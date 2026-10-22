import Foundation

/// Isolated structured calls. Read-only by default; test generation explicitly requests workspace writes.
/// Read-only calls disable MCP; writing jobs get only the app's VibeDeck MCP for rule checks.
/// Approvals stay disabled; ephemeral threads do not enter chat history.
@MainActor final class CodexReadOnly {
    private let rpc = CodexRPC()
    private var waiter: CheckedContinuation<String, Error>?
    private var output = ""
    private var thread: String?
    private var timeoutTask: Task<Void, Never>?
    private(set) var tokens = AITokenUsage()
    private(set) var model: String?
    init() {}
    func run(root: URL, prompt: String, schema: JSONValue, timeout: Duration = .seconds(90), settings: AIProviderSettings = .init(), workspaceWrites: Bool = false, mcpCLI: String? = nil) async throws -> String {
        let prompt = try await RemoteExecution.prepareContext(prompt, root: root)
        output = ""; tokens = .init()
        defer { stop() }
        return try await withTaskCancellationHandler {
            try await rpc.start(root: root)
            let config = try await rpc.request("config/read", params: ["includeLayers": .bool(false)])
            let overrides = Self.overrides(config: config, workspaceWrites: workspaceWrites, root: root, cli: mcpCLI)
            var params: [String: JSONValue] = ["cwd": .string(RemoteExecution.path(for: root)), "ephemeral": .bool(true), "approvalPolicy": .string("never"), "sandbox": .string(workspaceWrites ? "workspace-write" : "read-only"), "config": .object(overrides), "developerInstructions": .string(AIPromptPolicy.instructions)]
            if !workspaceWrites { params["dynamicTools"] = CodexReadTools.specs }
            if let model = settings.model { params["model"] = .string(model) }
            params["allowProviderModelFallback"] = .bool(false)
            let response = try await rpc.request("thread/start", params: params)
            model = response["model"]?.string ?? settings.model
            if settings.model != nil || settings.effort != nil {
                var models: [CodexModel] = [], cursor: String?
                repeat {
                    var params: [String: JSONValue] = ["limit": .number(100)]
                    if let cursor { params["cursor"] = .string(cursor) }
                    let page = try await rpc.request("model/list", params: params)
                    models += CodexModel.list(page); cursor = page["nextCursor"]?.string
                } while cursor != nil
                _ = try AISettingsResolver.resolve(provider: .codex, resource: .init(model: model, effort: settings.effort),
                    availableModels: models.map(\.id), supportedEfforts: models.first(where: { $0.id == model })?.efforts)
            }
            guard let id = response["thread"]?["id"]?.string else { throw CodexRPCError.invalidResponse }
            thread = id
            rpc.onRequest = { [weak self] id, method, request in
                guard let self else { return }
                if method == "item/tool/call", !workspaceWrites, request["threadId"]?.string == self.thread {
                    let tool = request["tool"]?.string ?? ""
                    let arguments = request["arguments"] ?? .object([:])
                    let expectedThread = self.thread
                    Task { [weak self] in
                        let result = await VDLog.detached {
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
            var stream = CodexEventStream()
            rpc.onNotification = { [weak self] method, params in
                guard let self, params["threadId"]?.string == self.thread else { return }
                if method == "thread/tokenUsage/updated" { self.tokens = .codex(params["tokenUsage"]?["total"]) }
                if case .textDelta(let delta) = stream.event(method, params) { self.output += delta }
                if method == "item/completed", params["item"]?["type"]?.string == "agentMessage",
                   params["item"]?["phase"]?.string == "final_answer" { self.output = params["item"]?["text"]?.string ?? self.output }
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
    static func overrides(config: JSONValue, workspaceWrites: Bool, root: URL? = nil, cli: String? = nil) -> [String: JSONValue] {
        var overrides: [String: JSONValue] = [:]
        for name in config["config"]?["mcp_servers"]?.object?.keys ?? Dictionary<String, JSONValue>().keys {
            if workspaceWrites, root != nil, name == "vibedeck" { continue }
            overrides["mcp_servers.\(name).enabled"] = .bool(false)
        }
        if workspaceWrites, let root {
            // MCP runs as a child of app-server, outside the agent's command sandbox. Rule scripts
            // therefore run normally without relaxing workspace-write or accepting arbitrary approvals.
            // Replace any user-configured server of this name with the app's known CLI.
            let remote = RemoteWorkspace.existing(at: root) != nil
            let serverRoot = URL(fileURLWithPath: RemoteExecution.path(for: root))
            overrides.merge(CodexMCP.sessionConfig(root: serverRoot, cli: remote ? "vibedeck" : cli)) { _, new in new }
            overrides["mcp_servers.vibedeck.enabled"] = .bool(true)
        }
        if !workspaceWrites {
            overrides["features.shell_tool"] = .bool(false)
            overrides["features.unified_exec"] = .bool(false)
        }
        return overrides
    }
    private func finish(_ result: Result<String, Error>) { let saved = waiter; waiter = nil; saved?.resume(with: result) }
    private func stop() { thread = nil; timeoutTask?.cancel(); timeoutTask = nil; rpc.stop() }
    static func strictSchema(_ value: JSONValue) -> JSONValue {
        guard var object = value.object else {
            if let array = value.array { return .array(array.map(strictSchema)) }
            return value
        }
        for key in object.keys { object[key] = object[key].map(strictSchema) }
        if object["type"]?.string == "object" { object["additionalProperties"] = .bool(false) }
        return .object(object)
    }
}
