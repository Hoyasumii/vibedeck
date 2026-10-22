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
