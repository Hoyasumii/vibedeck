import Foundation

/// Short isolated exploration call for Descubra. MCP integrations are disabled, writes and
/// approvals are denied, and its ephemeral thread cannot pollute the project's chat history.
@MainActor public final class CodexReadOnly {
    private let rpc = CodexRPC()
    private var waiter: CheckedContinuation<String, Error>?
    private var output = ""
    private var thread: String?
    private var timeoutTask: Task<Void, Never>?
    public init() {}
    public func run(root: URL, prompt: String, schema: JSONValue, timeout: Duration = .seconds(90)) async throws -> String {
        defer { stop() }
        return try await withTaskCancellationHandler {
            try await rpc.start(root: root)
            let config = try await rpc.request("config/read", params: ["includeLayers": .bool(false)])
            var overrides: [String: JSONValue] = [:]
            for name in config["config"]?["mcp_servers"]?.object?.keys ?? Dictionary<String, JSONValue>().keys {
                overrides["mcp_servers.\(name).enabled"] = .bool(false)
            }
            let response = try await rpc.request("thread/start", params: ["cwd": .string(root.path), "ephemeral": .bool(true), "approvalPolicy": .string("never"), "sandbox": .string("read-only"), "config": .object(overrides)])
            guard let id = response["thread"]?["id"]?.string else { throw CodexRPCError.invalidResponse }
            thread = id
            rpc.onRequest = { [weak self] id, method, _ in
                guard let self else { return }
                if method == "item/permissions/requestApproval" { try? self.rpc.respond(id: id, result: .object(["permissions": .object([:]), "scope": .string("turn")])) }
                else if method.contains("requestApproval") { try? self.rpc.respond(id: id, result: .object(["decision": .string("decline")])) }
                else { self.rpc.reject(id: id, message: "Esta operação só permite exploração sem interação ou escrita.") }
            }
            rpc.onDisconnect = { [weak self] error in self?.finish(.failure(CodexRPCError.server(error))) }
            rpc.onNotification = { [weak self] method, params in
                guard let self, params["threadId"]?.string == self.thread else { return }
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
                        _ = try await rpc.request("turn/start", params: ["threadId": .string(id), "input": .array([.object(["type": .string("text"), "text": .string(prompt), "text_elements": .array([])])]), "outputSchema": Self.strictSchema(schema)])
                    } catch { finish(.failure(error)) }
                }
            }
        } onCancel: { Task { @MainActor [weak self] in self?.finish(.failure(CancellationError())); self?.stop() } }
    }
    private func finish(_ result: Result<String, Error>) { let saved = waiter; waiter = nil; saved?.resume(with: result) }
    private func stop() { timeoutTask?.cancel(); timeoutTask = nil; rpc.stop() }
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
