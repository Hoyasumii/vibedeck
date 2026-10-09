import Foundation
import VibeDeckCore

/// Runs one background `claude -p` job that writes and registers the test scripts of a topic's rules.
/// Several run side by side (see `ProjectModel.generateAllTests`); the chat panel stays free.
enum RuleTestGenerator {
    struct Failure: LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }

    /// Runs the job to the end. Cancelling the task terminates the process.
    @MainActor static func run(root: URL, prompt: String, provider: AIProvider = .claude, operation: String = "Gerar testes", topic: String? = nil, expectedRules: [Rule] = []) async throws {
        let settings = AIReadOnlyOperation.settings(provider)
        var usage = AIUsageRecord(operation: operation, provider: provider, model: settings.model, prompt: prompt)
        usage.status = "failed"
        defer {
            usage.finish(Task.isCancelled ? "cancelled" : usage.status)
            try? AIUsageStore(root: root).save(usage)
        }
        if provider == .codex {
            let runner = CodexReadOnly()
            defer { usage.tokens = runner.tokens; usage.model = runner.model ?? settings.model }
            let schema: JSONValue = .object(["type": .string("object"), "properties": .object([
                "completed": .object(["type": .string("boolean")]), "summary": .object(["type": .string("string")])]),
                "required": .array([.string("completed"), .string("summary")])])
            let output = try await runner.run(root: root,
                prompt: prompt + "\nRetorne completed=true somente se todos os testes solicitados foram gerados, executados e registrados; caso contrário false e explique em summary.",
                schema: schema, timeout: .seconds(600), settings: settings, workspaceWrites: true)
            let answer = try JSONDecoder().decode(JSONValue.self, from: Data(output.utf8))
            guard answer["completed"]?.bool == true else { throw Failure(message: answer["summary"]?.string ?? AIPromptPolicy.incomplete) }
            try validateGeneration(root: root, topic: topic, expected: expectedRules)
            usage.status = "completed"
            return
        }
        guard let executable = ClaudeCode.executable else { throw Failure(message: "Claude Code não encontrado.") }
        let path = await Task.detached { ClaudeCode.childPATH() }.value

        let process = Process()
        process.executableURL = executable
        process.currentDirectoryURL = root
        process.arguments = ClaudeLaunch.headlessArguments(prompt: prompt, model: ClaudeModel(rawValue: settings.model ?? "") ?? .automatic, effort: ClaudeEffort(rawValue: settings.effort ?? "") ?? .automatic)
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = path
        process.environment = environment
        let output = Pipe(), errors = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = errors

        let exited = AsyncStream<Int32> { continuation in
            process.terminationHandler = { continuation.yield($0.terminationStatus); continuation.finish() }
        }
        do {
            try process.run()
        } catch {
            throw Failure(message: "Não foi possível iniciar o Claude Code: \(error.localizedDescription)")
        }

        try await withTaskCancellationHandler {
            async let stderrTail: String = {
                var tail = ""
                for await line in ClaudeStream.lines(from: errors.fileHandleForReading) { tail = String((tail + line + "\n").suffix(2000)) }
                return tail
            }()
            var result: ClaudeResult?
            for await line in ClaudeStream.lines(from: output.fileHandleForReading) {
                if case .result(let r) = ClaudeStream.parse(line) { result = r; usage.tokens = r.tokens; usage.costUSD = r.costUSD }
            }
            var status: Int32 = 0
            for await s in exited { status = s }
            let detail = await stderrTail.trimmingCharacters(in: .whitespacesAndNewlines)
            try Task.checkCancellation()

            if let result, result.isError {
                let text = result.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                throw Failure(message: text.isEmpty ? "O Claude Code terminou com erro." : text)
            }
            if status != 0 || result == nil {
                throw Failure(message: "O Claude Code terminou com erro (\(status))." + (detail.isEmpty ? "" : "\n\(detail)"))
            }
            try validateGeneration(root: root, topic: topic, expected: expectedRules)
            usage.status = "completed"
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }
    static func validateGeneration(root: URL, topic: String?, expected: [Rule]) throws {
        guard let topic else { return }
        let store = ProjectStore(root: root)
        let updated = try store.loadTopic(topic)
        for original in expected {
            guard let rule = updated.rules.first(where: { $0.id == original.id }),
                  rule.contentHash == original.contentHash,
                  rule.testState == .script || rule.testState == .manual else {
                throw Failure(message: "Regra alterada ou sem teste válido após a geração. " + AIPromptPolicy.incomplete)
            }
            if let command = rule.scriptCommand,
               command.hasPrefix(".vibedeck/tests/"), !FileManager.default.isExecutableFile(atPath: root.appending(path: command).path) {
                throw Failure(message: "Script registrado não existe ou não é executável: " + command)
            }
        }
    }

}
