import Foundation

// Compatibility aliases keep existing clients and persisted chat formats unchanged.
typealias AIEvent = ClaudeEvent
typealias AIPermissionRequest = ClaudePermissionRequest
typealias AIResult = ClaudeResult

struct AIConversationConfiguration: Sendable {
    var root: URL
    var sessionID: String?
    var settings: AIProviderSettings
    var mode: ClaudePermissionMode
    var instructions: String
    var config: [String: JSONValue]
    var autoReview: Bool
    init(root: URL, sessionID: String? = nil, settings: AIProviderSettings = .init(), mode: ClaudePermissionMode = .default,
                instructions: String = AIPromptPolicy.instructions, config: [String: JSONValue] = [:], autoReview: Bool = false) {
        self.root = root; self.sessionID = sessionID; self.settings = settings; self.mode = mode
        self.instructions = instructions; self.config = config; self.autoReview = autoReview
    }
}

/// Provider-specific wire formats stay behind these lifecycle operations.
@MainActor protocol AIConversationTransport: AnyObject {
    var provider: AIProvider { get }
    var onEvent: ((AIEvent) -> Void)? { get set }
    var onDisconnect: ((String) -> Void)? { get set }
    func prepare(_ configuration: AIConversationConfiguration) async throws -> String?
    func send(_ text: String, configuration: AIConversationConfiguration, schema: JSONValue?) async throws -> String?
    func interrupt() async throws
    func decisions(for request: AIPermissionRequest) -> [AIPermissionDecision]
    func respond(to request: AIPermissionRequest, decision: AIPermissionDecision) throws
    func answer(_ request: AIPermissionRequest, answers: [String: [String]]) throws
    func stop()
}

@MainActor final class ClaudeConversationTransport: AIConversationTransport {
    let provider = AIProvider.claude
    var onEvent: ((AIEvent) -> Void)?
    var onDisconnect: ((String) -> Void)?
    var isConnected: Bool { process != nil }
    private(set) var resumeFailed = false
    private var initialized = false
    private var process: Process?
    private var input: FileHandle?
    private var readers: [Task<Void, Never>] = []
    private var stderrTail = ""
    private var configuration: AIConversationConfiguration?
    private let executable: URL?
    private let launchArguments: [String]?
    init(executable: URL? = ClaudeCode.executable, launchArguments: [String]? = nil) {
        self.executable = executable; self.launchArguments = launchArguments
    }

    func prepare(_ configuration: AIConversationConfiguration) async throws -> String? {
        if process != nil { return self.configuration?.sessionID }
        guard let executable = (RemoteWorkspace.existing(at: configuration.root) != nil ? RemoteExecution.executable(provider, root: configuration.root) : executable) else { throw AIIntegrationError.unavailable(provider) }
        let path = await Task.detached { ClaudeCode.childPATH() }.value
        try Task.checkCancellation()
        let p = Process(), stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        p.executableURL = executable; p.currentDirectoryURL = configuration.root
        p.arguments = launchArguments ?? ClaudeLaunch.arguments(mode: configuration.mode, settings: configuration.settings,
                                             resume: configuration.sessionID, instructions: configuration.instructions)
        var environment = ProcessInfo.processInfo.environment; environment["PATH"] = path; p.environment = environment
        p.standardInput = stdin; p.standardOutput = stdout; p.standardError = stderr
        p.terminationHandler = { [weak self] ended in Task { @MainActor in self?.ended(ended) } }
        try RemoteExecution.configure(p, root: configuration.root, program: "claude")
        try p.run()
        self.configuration = configuration; process = p; input = stdin.fileHandleForWriting; stderrTail = ""
        initialized = false; resumeFailed = false
        readers = [
            VDLog.detached { [weak self] in
                for await line in ClaudeStream.lines(from: stdout.fileHandleForReading) {
                    await self?.receive(line, process: p)
                }
            },
            VDLog.detached { [weak self] in
                for await line in ClaudeStream.lines(from: stderr.fileHandleForReading) {
                    await self?.appendError(line, process: p)
                }
            }
        ]
        return configuration.sessionID
    }
    private func receive(_ line: String, process: Process) {
        guard process === self.process else { return }
        let event = ClaudeStream.parse(line)
        if case .initialized = event { initialized = true }
        onEvent?(event)
    }
    private func appendError(_ line: String, process: Process) {
        guard process === self.process else { return }
        stderrTail = String((stderrTail + line + "\n").suffix(2000))
    }
    func send(_ text: String, configuration: AIConversationConfiguration, schema: JSONValue? = nil) async throws -> String? {
        try Task.checkCancellation()
        try write(ClaudeInput.userMessage(try await RemoteExecution.prepareContext(text, root: configuration.root))); return nil
    }
    func write(_ data: Data) throws {
        guard let input else { throw AIIntegrationError.disconnected(provider) }
        try input.write(contentsOf: data)
    }
    func interrupt() async throws { try write(ClaudeInput.interrupt()) }
    func decisions(for request: AIPermissionRequest) -> [AIPermissionDecision] { [.allowOnce, .allowSession, .allowAlways, .deny] }
    func respond(to request: AIPermissionRequest, decision: AIPermissionDecision) throws {
        switch decision {
        case .allowOnce: try write(ClaudeInput.allow(request))
        case .allowSession: try write(ClaudeInput.allow(request, always: .session))
        case .allowAlways: try write(ClaudeInput.allow(request, always: .localSettings))
        case .deny: try write(ClaudeInput.deny(request, message: "O usuário negou esta ação no VibeDeck."))
        }
    }
    func answer(_ request: AIPermissionRequest, answers: [String: [String]]) throws { try write(ClaudeInput.answer(request, answers)) }
    private func ended(_ ended: Process) {
        guard ended === process else { return }
        resumeFailed = !initialized && configuration?.sessionID != nil
        let detail = stderrTail.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = "Claude encerrou a conexão (\(ended.terminationStatus))." + (detail.isEmpty ? "" : "\n" + detail)
        stop(); onDisconnect?(message)
    }
    func stop() {
        let p = process; process = nil; p?.terminationHandler = nil
        try? input?.close(); input = nil
        if p?.isRunning == true { p?.terminate() }
        readers.forEach { $0.cancel() }; readers = []; configuration = nil
    }
}

@MainActor final class CodexConversationTransport: AIConversationTransport {
    let provider = AIProvider.codex
    let rpc: CodexRPC
    var onEvent: ((AIEvent) -> Void)?
    var onDisconnect: ((String) -> Void)?
    var onNotification: ((String, JSONValue) -> Void)?
    private var thread: String?
    private var turn: String?
    private var stream = CodexEventStream()
    private var finishedDuringSend = false
    private var requests: [String: (id: JSONValue, method: String, params: JSONValue)] = [:]
    private var items: [String: JSONValue] = [:]
    private var completedTurns = Set<String>()
    init(rpc: CodexRPC = CodexRPC()) {
        self.rpc = rpc
        rpc.onNotification = { [weak self] method, params in
            guard let self else { return }
            guard params["threadId"] != nil else { self.onNotification?(method, params); return }
            guard params["threadId"]?.string == self.thread else { return }
            let incomingTurn = params["turnId"]?.string ?? params["turn"]?["id"]?.string
            if let id = incomingTurn {
                guard !self.completedTurns.contains(id) else { return }
                if let turn = self.turn, id != turn { return }
            }
            self.onNotification?(method, params)
            if method == "item/started", let id = params["item"]?["id"]?.string { self.items[id] = params["item"] }
            if method == "serverRequest/resolved", let id = params["requestId"] { self.requests[CodexProtocol.key(id)] = nil }
            if method == "turn/started" { self.turn = params["turn"]?["id"]?.string }
            self.onEvent?(self.stream.event(method, params))
            if method == "turn/completed" {
                if let id = incomingTurn { self.completedTurns.insert(id) }
                self.turn = nil; self.finishedDuringSend = true; self.requests = [:]
            }
        }
        rpc.onRequest = { [weak self, weak rpc] id, method, params in
            guard let self, params["threadId"]?.string == self.thread,
                  params["turnId"]?.string == nil || self.turn == nil || params["turnId"]?.string == self.turn else {
                rpc?.reject(id: id, message: "Solicitação fora da conversa ativa"); return
            }
            var detail = params.object ?? [:]
            if let itemID = params["itemId"]?.string { detail["changes"] = self.items[itemID]?["changes"] }
            guard let request = CodexProtocol.permission(id: id, method: method, params: .object(detail)) else {
                rpc?.reject(id: id, message: "Solicitação não suportada pelo VibeDeck"); return
            }
            self.requests[request.id] = (id, method, params)
            self.onEvent?(.permission(request))
        }
        rpc.onDisconnect = { [weak self] message in self?.onDisconnect?(message) }
    }
    func prepare(_ configuration: AIConversationConfiguration) async throws -> String? {
        try await rpc.start(root: configuration.root)
        var params = CodexProtocol.threadParameters(root: configuration.root, mode: configuration.mode,
                                                   model: configuration.settings.model, autoReview: configuration.autoReview)
        params["developerInstructions"] = .string(configuration.instructions)
        params["config"] = .object(configuration.config)
        let method = configuration.sessionID == nil ? "thread/start" : "thread/resume"
        if let id = configuration.sessionID { params["threadId"] = .string(id) }
        else { params["allowProviderModelFallback"] = .bool(false) }
        let result = try await rpc.request(method, params: params)
        guard let id = result["thread"]?["id"]?.string else { throw CodexRPCError.invalidResponse }
        thread = id; turn = nil; stream = CodexEventStream()
        onEvent?(.initialized(sessionId: id, model: result["model"]?.string))
        return id
    }
    func send(_ text: String, configuration: AIConversationConfiguration, schema: JSONValue? = nil) async throws -> String? {
        guard let thread else { throw AIIntegrationError.disconnected(provider) }
        stream = CodexEventStream(); turn = nil; finishedDuringSend = false
        var params = CodexProtocol.turnParameters(thread: thread, text: try await RemoteExecution.prepareContext(text, root: configuration.root), mode: configuration.mode,
            model: configuration.settings.model, effort: configuration.settings.effort, autoReview: configuration.autoReview)
        if let schema { params["outputSchema"] = CodexReadOnly.strictSchema(schema) }
        let response = try await rpc.request("turn/start", params: params)
        if !finishedDuringSend { turn = response["turn"]?["id"]?.string }
        return turn
    }
    func interrupt() async throws {
        guard let thread, let turn else { stop(); return }
        _ = try await rpc.request("turn/interrupt", params: ["threadId": .string(thread), "turnId": .string(turn)])
    }
    func decisions(for request: AIPermissionRequest) -> [AIPermissionDecision] {
        guard let original = requests[request.id] else { return [] }
        return CodexProtocol.decisions(method: original.method, params: original.params)
    }
    func respond(to request: AIPermissionRequest, decision: AIPermissionDecision) throws {
        guard let original = requests[request.id] else { throw CodexRPCError.invalidResponse }
        let result = try CodexProtocol.approval(method: original.method, params: original.params, decision: decision)
        try rpc.respond(id: original.id, result: result); requests[request.id] = nil
    }
    func answer(_ request: AIPermissionRequest, answers: [String: [String]]) throws {
        guard let original = requests[request.id] else { throw CodexRPCError.invalidResponse }
        try rpc.respond(id: original.id, result: CodexProtocol.answer(params: original.params, answers: answers))
        requests[request.id] = nil
    }
    func stop() { rpc.stop(); thread = nil; turn = nil; requests = [:]; items = [:]; stream = CodexEventStream() }

}

/// Complete messages can arrive without deltas, or repeat text already streamed.
struct CodexEventStream: Sendable {
    private var texts: [String: String] = [:]
    private var completed = Set<String>()
    private(set) var finalText: String?
    init() {}
    mutating func event(_ method: String, _ params: JSONValue) -> AIEvent {
        let item = params["item"] ?? .null
        let id = params["itemId"]?.string ?? item["id"]?.string ?? ""
        if method == "item/agentMessage/delta" {
            guard !completed.contains(id) else { return .ignored }
            let delta = params["delta"]?.string ?? ""; texts[id, default: ""] += delta
            return .textDelta(delta)
        }
        if method == "item/completed", item["type"]?.string == "agentMessage" {
            guard completed.insert(id).inserted else { return .ignored }
            let text = item["text"]?.string ?? "", previous = texts[id] ?? ""
            if item["phase"]?.string == "final_answer" { finalText = text }
            texts[id] = text
            guard text.hasPrefix(previous) else { return .ignored }
            let suffix = String(text.dropFirst(previous.count))
            return suffix.isEmpty ? .ignored : .textDelta(suffix)
        }
        let event = CodexProtocol.event(method, params)
        if case .result(var result) = event, !result.isError { result.text = finalText; return .result(result) }
        return event
    }
}
