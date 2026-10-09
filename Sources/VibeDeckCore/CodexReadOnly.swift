import Foundation

/// Isolated structured calls. Read-only by default; test generation explicitly requests workspace writes.
/// MCP integrations and approvals stay disabled; ephemeral threads do not enter chat history.
@MainActor public final class CodexReadOnly {
    private let rpc = CodexRPC()
    private var waiter: CheckedContinuation<String, Error>?
    private var output = ""
    private var thread: String?
    private var timeoutTask: Task<Void, Never>?
    public private(set) var tokens = AITokenUsage()
    public private(set) var model: String?
    public init() {}
    public func run(root: URL, prompt: String, schema: JSONValue, timeout: Duration = .seconds(90), settings: AIProviderSettings = .init(), workspaceWrites: Bool = false) async throws -> String {
        output = ""; tokens = .init()
        defer { stop() }
        return try await withTaskCancellationHandler {
            try await rpc.start(root: root)
            let config = try await rpc.request("config/read", params: ["includeLayers": .bool(false)])
            let overrides = Self.overrides(config: config, workspaceWrites: workspaceWrites)
            var params: [String: JSONValue] = ["cwd": .string(root.path), "ephemeral": .bool(true), "approvalPolicy": .string("never"), "sandbox": .string(workspaceWrites ? "workspace-write" : "read-only"), "config": .object(overrides), "developerInstructions": .string(AIPromptPolicy.instructions)]
            if !workspaceWrites { params["dynamicTools"] = CodexReadTools.specs }
            if let model = settings.model { params["model"] = .string(model) }
            let response = try await rpc.request("thread/start", params: params)
            model = response["model"]?.string ?? settings.model
            guard let id = response["thread"]?["id"]?.string else { throw CodexRPCError.invalidResponse }
            thread = id
            rpc.onRequest = { [weak self] id, method, request in
                guard let self else { return }
                if method == "item/tool/call", !workspaceWrites, request["threadId"]?.string == self.thread {
                    let tool = request["tool"]?.string ?? ""
                    let arguments = request["arguments"] ?? .object([:])
                    let expectedThread = self.thread
                    Task { [weak self] in
                        let result = await Task.detached {
                            CodexReadTools.response(root: root, tool: tool, arguments: arguments)
                        }.value
                        guard let self, self.thread == expectedThread else { return }
                        try? self.rpc.respond(id: id, result: result)
                    }
                } else if method == "item/permissions/requestApproval" { try? self.rpc.respond(id: id, result: .object(["permissions": .object([:]), "scope": .string("turn")])) }
                else if method.contains("requestApproval") { try? self.rpc.respond(id: id, result: .object(["decision": .string("decline")])) }
                else { self.rpc.reject(id: id, message: "Esta operação só permite exploração sem interação ou escrita.") }
            }
            rpc.onDisconnect = { [weak self] error in self?.finish(.failure(CodexRPCError.server(error))) }
            rpc.onNotification = { [weak self] method, params in
                guard let self, params["threadId"]?.string == self.thread else { return }
                if method == "thread/tokenUsage/updated" { self.tokens = .codex(params["tokenUsage"]?["total"]) }
                if method == "item/agentMessage/delta" { self.output += params["delta"]?.string ?? "" }
                if method == "item/completed", params["item"]?["type"]?.string == "agentMessage", self.output.isEmpty { self.output = params["item"]?["text"]?.string ?? "" }
                if method == "turn/completed" {
                    let turn = params["turn"]
                    if turn?["status"]?.string == "completed" { self.finish(.success(self.output)) }
                    else { self.finish(.failure(CodexRPCError.server(turn?["error"]?["message"]?.string ?? "Exploração interrompida"))) }
                }
            }
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                waiter = continuation
                timeoutTask = Task {
                    do { try await Task.sleep(for: timeout) } catch { return }
                    finish(.failure(VibeDeckError.discoverTimedOut))
                }
                Task {
                    do {
                        var turn: [String: JSONValue] = ["threadId": .string(id), "input": .array([.object(["type": .string("text"), "text": .string(prompt), "text_elements": .array([])])]), "outputSchema": Self.strictSchema(schema)]
                        if let effort = settings.effort { turn["effort"] = .string(effort) }
                        _ = try await rpc.request("turn/start", params: turn)
                    } catch { finish(.failure(error)) }
                }
            }
        } onCancel: { Task { @MainActor [weak self] in self?.finish(.failure(CancellationError())); self?.stop() } }
    }
    /// Read-only calls keep file tools but remove command execution; test generation keeps its write mode.
    static func overrides(config: JSONValue, workspaceWrites: Bool) -> [String: JSONValue] {
        var overrides: [String: JSONValue] = [:]
        for name in config["config"]?["mcp_servers"]?.object?.keys ?? Dictionary<String, JSONValue>().keys {
            overrides["mcp_servers.\(name).enabled"] = .bool(false)
        }
        if !workspaceWrites {
            overrides["features.shell_tool"] = .bool(false)
            overrides["features.unified_exec"] = .bool(false)
        }
        return overrides
    }
    private func finish(_ result: Result<String, Error>) { let saved = waiter; waiter = nil; saved?.resume(with: result) }
    private func stop() { thread = nil; timeoutTask?.cancel(); timeoutTask = nil; rpc.stop() }
    public static func strictSchema(_ value: JSONValue) -> JSONValue {
        guard var object = value.object else {
            if let array = value.array { return .array(array.map(strictSchema)) }
            return value
        }
        for key in object.keys { object[key] = object[key].map(strictSchema) }
        if object["type"]?.string == "object" { object["additionalProperties"] = .bool(false) }
        return .object(object)
    }
}
