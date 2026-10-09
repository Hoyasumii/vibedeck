import Foundation

public enum CodexRPCError: LocalizedError, Sendable {
    case unavailable, disconnected, timeout(String), server(String), invalidResponse
    public var errorDescription: String? {
        switch self {
        case .unavailable: "Codex não encontrado. Instale o Codex CLI e reabra o VibeDeck."
        case .disconnected: "O Codex encerrou a conexão. Reabra a conversa para tentar novamente."
        case .timeout(let method): "O Codex não respondeu a \(method) a tempo."
        case .server(let message): "Codex: \(message)"
        case .invalidResponse: "Resposta inválida do Codex. Verifique a versão do CLI."
        }
    }
}

/// A single local app-server connection. No network listener or API key is needed.
/// Callbacks and continuations are isolated to the main actor; stdout/stderr drain concurrently.
@MainActor public final class CodexRPC {
    public var onNotification: ((String, JSONValue) -> Void)?
    public var onRequest: ((JSONValue, String, JSONValue) -> Void)?
    public var onDisconnect: ((String) -> Void)?
    private var process: Process?
    private var input: FileHandle?
    private var readers: [Task<Void, Never>] = []
    private var pending: [Int: CheckedContinuation<JSONValue, Error>] = [:]
    private var timeouts: [Int: Task<Void, Never>] = [:]
    private var sequence = 0
    private var stderrTail = ""
    public init() {}

    public func start(root: URL, executable: URL? = CodexCode.executable, arguments: [String] = ["app-server", "--stdio"]) async throws {
        if process != nil { return }
        guard let executable else { throw CodexRPCError.unavailable }
        let childPath = await Task.detached { ClaudeCode.childPATH() }.value
        try Task.checkCancellation()
        let p = Process(), stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        p.executableURL = executable; p.arguments = arguments; p.currentDirectoryURL = root
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = executable.deletingLastPathComponent().path + ":" + childPath
        p.environment = environment
        p.standardInput = stdin; p.standardOutput = stdout; p.standardError = stderr
        p.terminationHandler = { [weak self] ended in
            Task { @MainActor in self?.ended(ended) }
        }
        try p.run()
        process = p; input = stdin.fileHandleForWriting; stderrTail = ""
        readers = [
            Task.detached { [weak self] in
                for await line in ClaudeStream.lines(from: stdout.fileHandleForReading) {
                    await self?.receive(line)
                }
            },
            Task.detached { [weak self] in
                for await line in ClaudeStream.lines(from: stderr.fileHandleForReading) { await self?.appendError(line) }
            }
        ]
        do {
            _ = try await request("initialize", params: ["clientInfo": .object(["name": .string("vibedeck"), "title": .string("VibeDeck"), "version": .string("1.0")]), "capabilities": .object(["experimentalApi": .bool(true)])])
            try notify("initialized")
        } catch { stop(); throw error }
    }

    public func request(_ method: String, params: [String: JSONValue] = [:], timeout: Duration = .seconds(30)) async throws -> JSONValue {
        guard input != nil else { throw CodexRPCError.disconnected }
        sequence += 1; let id = sequence
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                pending[id] = continuation
                timeouts[id] = Task { [weak self] in
                    do { try await Task.sleep(for: timeout) } catch { return }
                    self?.finish(id, result: .failure(CodexRPCError.timeout(method)))
                }
                do { try write(.object(["id": .number(Double(id)), "method": .string(method), "params": .object(params)])) }
                catch { finish(id, result: .failure(error)) }
            }
        } onCancel: { Task { @MainActor [weak self] in self?.finish(id, result: .failure(CancellationError())) } }
    }

    public func notify(_ method: String, params: [String: JSONValue] = [:]) throws {
        try write(.object(["method": .string(method), "params": .object(params)]))
    }
    public func respond(id: JSONValue, result: JSONValue) throws { try write(.object(["id": id, "result": result])) }
    public func reject(id: JSONValue, message: String) {
        try? write(.object(["id": id, "error": .object(["code": .number(-32601), "message": .string(message)])]))
    }
    private func write(_ value: JSONValue) throws {
        guard let input else { throw CodexRPCError.disconnected }
        var data = try JSONEncoder().encode(value); data.append(10)
        try input.write(contentsOf: data)
    }
    private func receive(_ line: String) {
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: Data(line.utf8)) else { return }
        if let method = value["method"]?.string {
            if let id = value["id"] { onRequest?(id, method, value["params"] ?? .object([:])) }
            else { onNotification?(method, value["params"] ?? .object([:])) }
        } else if let id = value["id"]?.number {
            if let error = value["error"], error != .null {
                finish(Int(id), result: .failure(CodexRPCError.server(error["message"]?.string ?? String(describing: error))))
            } else { finish(Int(id), result: .success(value["result"] ?? .null)) }
        }
    }
    private func finish(_ id: Int, result: Result<JSONValue, Error>) {
        timeouts.removeValue(forKey: id)?.cancel()
        pending.removeValue(forKey: id)?.resume(with: result)
    }
    private func appendError(_ line: String) { stderrTail = String((stderrTail + line + "\n").suffix(4000)) }
    private func ended(_ p: Process) {
        guard p === process else { return }
        let detail = stderrTail.trimmingCharacters(in: .whitespacesAndNewlines)
        for id in Array(pending.keys) { finish(id, result: .failure(CodexRPCError.server(detail.isEmpty ? "Conexão encerrada (\(p.terminationStatus))." : detail))) }
        stop()
        onDisconnect?(detail.isEmpty ? "Codex encerrou a conexão (\(p.terminationStatus))." : detail)
    }
    public func stop() {
        let p = process; process = nil
        p?.terminationHandler = nil
        try? input?.close(); input = nil
        if p?.isRunning == true { p?.terminate() }
        readers.forEach { $0.cancel() }; readers = []
        for id in Array(pending.keys) { finish(id, result: .failure(CodexRPCError.disconnected)) }
    }
}

public enum CodexProtocol {
    public static func threadParameters(root: URL, mode: ClaudePermissionMode, model: String? = nil, autoReview: Bool = false) -> [String: JSONValue] {
        var params: [String: JSONValue] = ["cwd": .string(root.path), "approvalPolicy": .string("on-request"), "sandbox": .string(mode == .plan ? "read-only" : "workspace-write")]
        params["approvalsReviewer"] = .string(autoReview ? "auto_review" : "user")
        if let model, !model.isEmpty { params["model"] = .string(model) }
        return params
    }
    public static func turnParameters(thread: String, text: String, mode: ClaudePermissionMode, model: String?, effort: String?, autoReview: Bool = false) -> [String: JSONValue] {
        var params: [String: JSONValue] = ["threadId": .string(thread), "input": .array([.object(["type": .string("text"), "text": .string(text), "text_elements": .array([])])]),
            "approvalPolicy": .string("on-request"),
            "sandboxPolicy": .object(["type": .string(mode == .plan ? "readOnly" : "workspaceWrite")])]
        params["approvalsReviewer"] = .string(autoReview ? "auto_review" : "user")
        if let model, !model.isEmpty { params["model"] = .string(model) }
        if let effort, !effort.isEmpty { params["effort"] = .string(effort) }
        if let model, !model.isEmpty {
            params["collaborationMode"] = .object(["mode": .string(mode == .plan ? "plan" : "default"), "settings": .object(["model": .string(model), "reasoning_effort": effort.map(JSONValue.string) ?? .null, "developer_instructions": .null])])
        }
        return params
    }
    public static func key(_ id: JSONValue) -> String { String(decoding: (try? JSONEncoder().encode(id)) ?? Data(), as: UTF8.self) }
    public static func permission(id: JSONValue, method: String, params: JSONValue) -> ClaudePermissionRequest? {
        var input = params.object ?? [:]
        let name: String
        switch method {
        case "item/commandExecution/requestApproval": name = "Bash"
        case "item/fileChange/requestApproval": name = "Edit"; input["file_path"] = params["grantRoot"]
        case "item/tool/requestUserInput":
            name = "AskUserQuestion"
            input["questions"] = .array((params["questions"]?.array ?? []).map { q in
                var value = q.object ?? [:]; value["multiSelect"] = .bool(false); return .object(value)
            })
        case "item/permissions/requestApproval": name = "Permissions"
        case "item/tool/requestApproval": name = "MCP"
        default: return nil
        }
        return ClaudePermissionRequest(requestId: key(id), toolName: name, input: input, description: params["reason"]?.string, suggestions: [])
    }
    public static func answer(params: JSONValue, answers: [String: [String]]) -> JSONValue {
        var result: [String: JSONValue] = [:]
        for q in params["questions"]?.array ?? [] {
            if let id = q["id"]?.string, let text = q["question"]?.string {
                result[id] = .object(["answers": .array((answers[text] ?? []).map(JSONValue.string))])
            }
        }
        return .object(["answers": .object(result)])
    }
    public static func event(_ method: String, _ params: JSONValue) -> ClaudeEvent {
        let item = params["item"] ?? .null
        switch method {
        case "item/agentMessage/delta": return .textDelta(params["delta"]?.string ?? "")
        case "item/reasoning/summaryTextDelta", "item/reasoning/textDelta": return .thinking
        case "item/started":
            switch item["type"]?.string {
            case "agentMessage": return .textStarted
            case "commandExecution", "fileChange", "mcpToolCall", "webSearch", "dynamicToolCall":
                return .toolUse(ClaudeToolUse(id: item["id"]?.string ?? UUID().uuidString, name: item["tool"]?.string ?? item["type"]?.string ?? "Tool", input: item.object ?? [:]))
            default: return .ignored
            }
        case "item/completed":
            guard ["commandExecution", "fileChange", "mcpToolCall", "dynamicToolCall", "webSearch"].contains(item["type"]?.string ?? "") else { return .ignored }
            let output = item["aggregatedOutput"]?.string ?? item["result"]?.string ?? String(decoding: (try? JSONEncoder().encode(item["result"] ?? item["changes"] ?? .null)) ?? Data(), as: UTF8.self)
            return .toolResult(toolUseId: item["id"]?.string ?? "", content: output, isError: item["status"]?.string == "failed" || (item["exitCode"]?.number ?? 0) != 0)
        case "turn/completed":
            let turn = params["turn"] ?? .null
            return .result(ClaudeResult(isError: turn["status"]?.string == "failed", text: turn["error"]?["message"]?.string, costUSD: nil))
        default: return .ignored
        }
    }
}
