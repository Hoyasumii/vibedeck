import Foundation

// MARK: - Chats

/// One line of a saved Claude conversation, as shown in the panel.
struct ClaudeChatMessage: Codable, Equatable, Sendable {
    enum Role: String, Codable, Sendable {
        case user, assistant, tool, notice, error
    }

    var role: Role
    var text: String
    var toolName: String?
    /// Tool calls: the one-line description (command, path…).
    var summary: String?
    var result: String?
    var isError: Bool?
    /// User messages: other chats mentioned (sent to Claude as JSON, not resumed).
    var mentions: [UUID]?
    /// User messages: absolute paths of files attached (referenced in the prompt, never copied).
    var attachments: [String]?

    init(
        role: Role, text: String, toolName: String? = nil, summary: String? = nil, result: String? = nil,
        isError: Bool? = nil, mentions: [UUID]? = nil, attachments: [String]? = nil
    ) {
        self.role = role
        self.text = text
        self.toolName = toolName
        self.summary = summary
        self.result = result
        self.isError = isError
        self.mentions = mentions
        self.attachments = attachments
    }

    private enum CodingKeys: String, CodingKey {
        case role, text, toolName, summary, result, isError, mentions, attachments
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decode(String.self, forKey: .text)
        role = (try? c.decodeIfPresent(Role.self, forKey: .role)) ?? .notice
        toolName = try c.decodeIfPresent(String.self, forKey: .toolName)
        summary = try c.decodeIfPresent(String.self, forKey: .summary)
        result = try c.decodeIfPresent(String.self, forKey: .result)
        isError = try c.decodeIfPresent(Bool.self, forKey: .isError)
        mentions = try c.decodeIfPresent([UUID].self, forKey: .mentions)
        attachments = try c.decodeIfPresent([String].self, forKey: .attachments)
    }
}

/// A Claude Code conversation of a project: its transcript plus the Claude Code session that resumes it.
struct ClaudeChat: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var title: String
    var provider: AIProvider
    var sessionId: String?
    var pendingPlan: String? = nil
    /// Workflow run this conversation executes (`<workflow>/<run>`), independent of title and messages.
    var workflowRun: String? = nil
    /// Agents and subagents seen in the conversation, as last reported by the provider.
    var agentProcesses: [AgentProcess] = []
    var createdAt: Date
    var updatedAt: Date
    var messages: [ClaudeChatMessage]

    init(id: UUID = UUID(), title: String, provider: AIProvider = .claude, sessionId: String? = nil, createdAt: Date = .now, updatedAt: Date = .now, messages: [ClaudeChatMessage] = []) {
        self.id = id
        self.title = title
        self.provider = provider
        self.sessionId = sessionId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, provider, sessionId, pendingPlan, workflowRun, agentProcesses, createdAt, updatedAt, messages
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decode(String.self, forKey: .title)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        provider = try c.decodeIfPresent(AIProvider.self, forKey: .provider) ?? .claude
        sessionId = try c.decodeIfPresent(String.self, forKey: .sessionId)
        pendingPlan = try c.decodeIfPresent(String.self, forKey: .pendingPlan)
        workflowRun = try c.decodeIfPresent(String.self, forKey: .workflowRun)
        agentProcesses = (try? c.decodeIfPresent([AgentProcess].self, forKey: .agentProcesses)) ?? []
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        messages = try c.decodeIfPresent([ClaudeChatMessage].self, forKey: .messages) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(provider, forKey: .provider)
        try c.encodeIfPresent(sessionId, forKey: .sessionId)
        try c.encodeIfPresent(pendingPlan, forKey: .pendingPlan)
        try c.encodeIfPresent(workflowRun, forKey: .workflowRun)
        if !agentProcesses.isEmpty { try c.encode(agentProcesses, forKey: .agentProcesses) }
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(messages, forKey: .messages)
    }

    static let untitled = "Nova conversa"

    /// Automatic title: the first line of the first message, shortened.
    static func title(from message: String, limit: Int = 40) -> String {
        let line = message.split(whereSeparator: \.isNewline).first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !line.isEmpty else { return untitled }
        return line.count > limit ? String(line.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…" : line
    }

    /// The whole conversation as JSON, for mentioning it in another chat.
    func contextJSON() -> String {
        struct Context: Encodable {
            var title: String
            var createdAt: Date
            var messages: [ClaudeChatMessage]
        }
        let context = Context(title: title, createdAt: createdAt, messages: messages.map { var m = $0; m.mentions = nil; return m })
        let data = (try? VDJSON.encoder.encode(context)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// What is written to Claude for a user message: the text, followed by each mentioned chat as JSON.
    static func wireText(_ text: String, mentioning chats: [ClaudeChat], attachments: [String] = [], provider: AIProvider = .claude, contextStore: AIContextStore? = nil, includeFullChats: Bool = false) -> String {
        var out = text
        if !attachments.isEmpty {
            out += provider == .claude ? "\n\nArquivos anexados pelo usuário (leia com Read se precisar):" : "\n\nArquivos anexados pelo usuário (leia se precisar):"
            out += attachments.map { "\n- " + $0 }.joined()
        }
        guard !chats.isEmpty else { return out }
        out += "\n\n"
        out += "As conversas mencionadas abaixo são só referência (outras conversas deste projeto, em JSON); não fazem parte desta conversa."
        for chat in chats {
            let title = chat.title.replacingOccurrences(of: "\"", with: "'")
            if !includeFullChats, chat.contextJSON().count > 2000, let contextStore,
               let reference = try? contextStore.save(chat.contextJSON(), title: title) {
                out += "\n\n" + reference.instruction
                out += "\nLeia os trechos relevantes antes de usar esta conversa; decisões antigas também podem ser necessárias."
            } else {
                // A failed snapshot must never silently discard the user's reference.
                out += "\n\n<conversa-mencionada titulo=\"\(title)\">\n\(chat.contextJSON())\n</conversa-mencionada>"
            }
        }
        return out
    }
}

// MARK: - Store

/// Chats of one project, one JSON file each, kept outside the project (Application Support).
struct ClaudeChatStore: Sendable {
    let dir: URL

    init(dir: URL) {
        self.dir = dir
    }

    /// `~/Library/Application Support/VibeDeck/chats/<projectId>/`.
    static func forProject(_ projectId: UUID) -> ClaudeChatStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")
        return ClaudeChatStore(dir: base.appending(path: "VibeDeck/chats/\(projectId.uuidString)", directoryHint: .isDirectory))
    }

    func url(_ id: UUID) -> URL { dir.appending(path: "\(id.uuidString).json") }

    /// Most recently updated first; unreadable files are skipped.
    func list() -> [ClaudeChat] {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return files.filter { $0.pathExtension == "json" }
            .compactMap { try? VDJSON.decoder.decode(ClaudeChat.self, from: Data(contentsOf: $0)) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func load(_ id: UUID) -> ClaudeChat? {
        try? VDJSON.decoder.decode(ClaudeChat.self, from: Data(contentsOf: url(id)))
    }

    func save(_ chat: ClaudeChat) throws {
        try AtomicFile.write(VDJSON.encode(chat), to: url(chat.id))
    }

    func delete(_ id: UUID) throws {
        let url = url(id)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    func deleteAll() throws {
        if FileManager.default.fileExists(atPath: dir.path) { try FileManager.default.removeItem(at: dir) }
    }
}
