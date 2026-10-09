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
    static func run(root: URL, prompt: String) async throws {
        guard let executable = ClaudeCode.executable else { throw Failure(message: "Claude Code não encontrado.") }
        let path = await Task.detached { ClaudeCode.childPATH() }.value

        let process = Process()
        process.executableURL = executable
        process.currentDirectoryURL = root
        process.arguments = ClaudeLaunch.headlessArguments(prompt: prompt)
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
                if case .result(let r) = ClaudeStream.parse(line) { result = r }
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
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }
}
