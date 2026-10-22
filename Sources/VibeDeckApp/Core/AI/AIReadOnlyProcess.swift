import Foundation

/// Shared Claude process for app, CLI and MCP: only Read/Grep/Glob, cancellation and timeout.
enum AIReadOnlyProcess {
    static func run(executable: URL, root: URL, input: String, schema: String? = nil, settings: AIProviderSettings = .init()) async throws -> Data {
        let input = try await RemoteExecution.prepareContext(input, root: root)
        let path = ClaudeCode.childPATH()
        let process = Process()
        process.executableURL = executable
        process.currentDirectoryURL = root
        process.arguments = ReviewDiscover.arguments()
        if let model = settings.model { process.arguments?.append(contentsOf: ["--model", model]) }
        if let effort = settings.effort { process.arguments?.append(contentsOf: ["--effort", effort]) }
        if let schema, let index = process.arguments?.firstIndex(of: "--json-schema") {
            process.arguments?[index + 1] = schema
        }
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = path
        process.environment = environment
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        do { try RemoteExecution.configure(process, root: root, program: "claude"); try process.run() } catch { throw VibeDeckError.discoverFailed(error.localizedDescription) }
        try? stdin.fileHandleForWriting.write(contentsOf: Data(input.utf8))
        try? stdin.fileHandleForWriting.close()

        let timedOut = VDLog.detached {
            try? await Task.sleep(for: ReviewDiscover.timeout)
            guard !Task.isCancelled, process.isRunning else { return false }
            process.terminate()
            return true
        }
        defer { timedOut.cancel() }
        let output = await withTaskCancellationHandler {
            await VDLog.detached {
                // Drain stderr concurrently so a chatty hook can't fill the pipe and block the process.
                let errors = VDLog.detached { stderr.fileHandleForReading.readDataToEndOfFile() }
                let data = stdout.fileHandleForReading.readDataToEndOfFile()
                _ = await errors.value
                process.waitUntilExit()
                return data
            }.value
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
        try Task.checkCancellation()
        timedOut.cancel()
        if await timedOut.value { throw VibeDeckError.discoverTimedOut }
        return output
    }
}
