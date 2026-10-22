import Foundation

// Reorganizar com IA e criar/editar itens com IA: prompts, validação e gravação são do Core (`reorganize_*`, `item_ai_*`).
extension CoreStore {
    struct AIPromptPackage: Decodable {
        var prompt: String
        var schema: String
        var fingerprint: String?
    }

    /// Analisa o projeto com a IA escolhida (o Core roda `claude`/`codex` no mesmo lado do projeto, inclusive por SSH).
    func reorganizeAnalyze(provider: AIProvider, settings: AIProviderSettings = AIProviderSettings()) async throws -> ReorganizeDiscover.Proposal {
        var args: [String: Any] = ["provider": provider.rawValue]
        if let model = settings.model, !model.isEmpty { args["model"] = model }
        if let effort = settings.effort, !effort.isEmpty { args["effort"] = effort }
        return try await callJSON("reorganize_analyze", args, timeout: 900)
    }

    /// Aplica as ações aceitas; devolve o recibo (arquivos antes/depois, pastas criadas, movimentos de caminho).
    func reorganizeApply(_ proposal: ReorganizeDiscover.Proposal, acceptance: ReorganizeDiscover.Acceptance) async throws -> ReorganizeReceipt {
        let reply = try await call("reorganize_apply", [
            "proposal": try CoreStore.encodeString(proposal),
            "acceptance": try CoreStore.encodeString(acceptance),
        ])
        return try CoreStore.decode(ReorganizeReceipt.self, from: reply, what: "reorganize_apply")
    }

    /// PEDIDO-CORE (reorganize_restore): desfazer/refazer uma reorganização a partir do recibo.
    func reorganizeRestore(_ receipt: ReorganizeReceipt, forward: Bool) async throws {
        _ = try await call("reorganize_restore", ["receipt": try CoreStore.encodeString(receipt), "forward": forward])
    }

    func itemAIPrompt(kind: String, request: String, item: String?) async throws -> AIPromptPackage {
        var args: [String: Any] = ["kind": kind, "request": request]
        if let item = item, !item.isEmpty { args["item"] = item }
        return try await callJSON("item_ai_prompt", args)
    }

    /// Valida (contra o schema do tipo) e grava a proposta da IA; devolve o slug gravado.
    func itemAIApply(kind: String, proposal: String, item: String?) async throws -> String {
        var args: [String: Any] = ["kind": kind, "proposal": proposal]
        if let item = item, !item.isEmpty { args["item"] = item }
        let reply = try await call("item_ai_apply", args)
        let prefix = "Gravado: "
        return reply.hasPrefix(prefix) ? String(reply.dropFirst(prefix.count)) : reply
    }
}

// Comandos `/nome`, agentes `/agent:nome` e skills digitados no chat: resolvidos pelas tools `get_*` do Core.
extension CoreStore {
    private func record<T: Decodable>(_ tool: String, _ key: String, _ ref: String, as type: T.Type) async -> T? {
        guard let text = try? await call(tool, [key: ref], idempotent: true) else { return nil }
        return try? CoreStore.decode(type, from: text, what: tool)
    }

    /// Expande um comando/agente/skill registrado sem fingir que é um slash command nativo do TUI.
    func expandAICommand(_ text: String) async throws -> String {
        guard text.hasPrefix("/") else { return text }
        let words = text.split(maxSplits: 1, whereSeparator: \.isWhitespace)
        let name = String(words[0].dropFirst()), args = words.count > 1 ? String(words[1]) : ""
        if name.hasPrefix("agent:") {
            let agent: Agent = try await callJSON("get_agent", ["agent": String(name.dropFirst(6))], idempotent: true)
            return agent.prompt + "\n\nEntrada: " + args
        }
        if let command = await record("get_command", "command", name, as: Command.self) {
            return command.prompt.replacingOccurrences(of: "$ARGUMENTS", with: args)
        }
        if let skill = await record("get_skill", "skill", name, as: Skill.self) {
            let resources = skill.sourcePath.map { "\n\nRecursos da skill: \(URL(fileURLWithPath: $0).deletingLastPathComponent().path)" } ?? ""
            return skill.prompt + resources + "\n\nEntrada: " + args
        }
        return text
    }

    /// Modelo/esforço configurados no comando, agente ou skill chamado em `text`; nil se não for um deles.
    func commandProviderSettings(_ text: String, provider: AIProvider, availableModels: [String], fallback: String?) async throws
        -> (settings: AIProviderSettings, warning: String?)? {
        guard text.hasPrefix("/"), let token = text.split(whereSeparator: \.isWhitespace).first else { return nil }
        let name = String(token.dropFirst())
        let legacy: String?
        let all: [String: AIProviderSettings]?
        if name.hasPrefix("agent:") {
            let agent: Agent = try await callJSON("get_agent", ["agent": String(name.dropFirst(6))], idempotent: true)
            legacy = agent.model
            all = agent.providerSettings
        } else if let command = await record("get_command", "command", name, as: Command.self) {
            legacy = command.model
            all = command.providerSettings
        } else if let skill = await record("get_skill", "skill", name, as: Skill.self) {
            legacy = skill.model
            all = skill.providerSettings
        } else {
            return nil
        }
        let settings = try AISettingsResolver.resolve(provider: provider, resource: all?[provider.rawValue],
            legacyModel: legacy, session: AIProviderSettings(model: fallback), availableModels: availableModels.isEmpty ? nil : availableModels)
        return (settings, nil)
    }

    /// Configurações do provedor para a etapa atual de uma execução.
    func runProviderSettings(_ ref: String, availableModels: [String], fallback: String?) async throws -> (settings: AIProviderSettings, warning: String?) {
        let run = try await loadRun(ref)
        let workflow: Workflow = try await callJSON("get_workflow", ["workflow": run.workflow], idempotent: true)
        guard let current = run.current, let step = workflow.steps.first(where: { $0.id == current }) else {
            throw VibeDeckError.invalidWorkflow("Etapa inexistente")
        }
        let legacy: String?
        let overrides: [String: AIProviderSettings]?
        switch step.kind {
        case .agent:
            let record: Agent = try await callJSON("get_agent", ["agent": step.ref], idempotent: true)
            legacy = record.model
            overrides = record.providerSettings
        case .command:
            let record: Command = try await callJSON("get_command", ["command": step.ref], idempotent: true)
            legacy = record.model
            overrides = record.providerSettings
        case .skill:
            let record: Skill = try await callJSON("get_skill", ["skill": step.ref], idempotent: true)
            legacy = record.model
            overrides = record.providerSettings
        }
        let settings = try AISettingsResolver.resolve(provider: run.provider, resource: overrides?[run.provider.rawValue],
            legacyModel: legacy, session: AIProviderSettings(model: fallback), availableModels: availableModels.isEmpty ? nil : availableModels)
        return (settings, nil)
    }

    /// `import_agents` / `import_commands` / `import_skills`: lê `.claude`/`.codex` do lado do projeto (inclusive SSH).
    func importRecords(_ tool: String, provider: AIProvider, overwrite: Bool = false) async throws -> AIImportResult {
        let text = try await call(tool, ["provider": provider.rawValue, "overwrite": overwrite], timeout: 300)
        var result = AIImportResult()
        guard let data = text.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) else { return result }
        if let list = object as? [String] {
            result.slugs = list
        } else if let dictionary = object as? [String: Any] {
            result.slugs = dictionary["slugs"] as? [String] ?? []
            result.warnings = dictionary["warnings"] as? [String] ?? []
        }
        return result
    }
}
