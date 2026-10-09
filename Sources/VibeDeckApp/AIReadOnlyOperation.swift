import Foundation
import VibeDeckCore

/// Shared structured read-only calls. Only invalid answers receive one recovery, on the same model.
@MainActor enum AIReadOnlyOperation {
    static func settings(_ provider: AIProvider) -> AIProviderSettings {
        let defaults = UserDefaults.standard
        let model = defaults.string(forKey: provider == .codex ? "codexModel" : "claudeModel")
        let effort = defaults.string(forKey: provider == .codex ? "codexEffort" : "claudeEffort")
        return .init(model: model.flatMap { $0.isEmpty ? nil : $0 }, effort: effort.flatMap { $0.isEmpty ? nil : $0 })
    }

    static func run<T>(root: URL, provider: AIProvider, operation: String, prompt: String, schema: String,
                       request: ((String, AIProviderSettings) async throws -> Data)? = nil,
                       parse: (Data) throws -> T) async throws -> T {
        let taskID = UUID().uuidString
        let settings = settings(provider)
        var nextPrompt = prompt
        for attempt in 1...2 {
            try Task.checkCancellation()
            var usage = AIUsageRecord(taskID: taskID, operation: operation, provider: provider,
                                      model: settings.model, attempt: attempt, prompt: nextPrompt)
            var reply: Data
            do {
                if let request {
                    reply = try await request(nextPrompt, settings)
                } else if provider == .codex {
                    let runner = CodexReadOnly()
                    do {
                        reply = Data(try await runner.run(root: root, prompt: nextPrompt,
                            schema: JSONDecoder().decode(JSONValue.self, from: Data(schema.utf8)),
                            timeout: .seconds(180), settings: settings, workspaceWrites: false).utf8)
                    } catch {
                        usage.tokens = runner.tokens; usage.model = runner.model ?? settings.model
                        throw error
                    }
                    usage.tokens = runner.tokens; usage.model = runner.model ?? settings.model
                } else {
                    guard let executable = provider.executable else { throw VibeDeckError.discoverFailed("Claude não está instalado.") }
                    let data = try await ReviewDiscoverRunner.run(executable: executable, root: root, input: nextPrompt,
                                                                 schema: schema, settings: settings)
                    let envelope = String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).reversed()
                        .compactMap { try? JSONDecoder().decode(JSONValue.self, from: Data($0.utf8)) }
                        .first { $0["type"]?.string == "result" }
                    usage.tokens = .claude(envelope?["usage"]); usage.costUSD = envelope?["total_cost_usd"]?.number
                    guard let envelope, envelope["is_error"]?.bool != true, envelope["subtype"]?.string == "success" else {
                        throw VibeDeckError.discoverFailed(envelope?["result"]?.string ?? "A chamada de IA falhou.")
                    }
                    if let value = envelope["structured_output"], value != .null { reply = try JSONEncoder().encode(value) }
                    else { reply = Data((envelope["result"]?.string ?? "").utf8) }
                }
            } catch {
                usage.finish(error is CancellationError ? "cancelled" : "failed")
                try? AIUsageStore(root: root).save(usage)
                throw error
            }
            let result: T
            do {
                try Task.checkCancellation()
                result = try parse(reply)
            } catch is CancellationError {
                usage.finish("cancelled"); try? AIUsageStore(root: root).save(usage)
                throw CancellationError()
            } catch {
                usage.finish("invalid-answer"); try AIUsageStore(root: root).save(usage)
                guard attempt == 1 else { throw VibeDeckError.discoverFailed(AIPromptPolicy.incomplete) }
                nextPrompt = AIPromptPolicy.recovery(prompt, diagnosis: error.localizedDescription)
                continue
            }
            usage.finish("completed")
            try AIUsageStore(root: root).save(usage)
            return result
        }
        throw VibeDeckError.discoverFailed(AIPromptPolicy.incomplete)
    }
}
