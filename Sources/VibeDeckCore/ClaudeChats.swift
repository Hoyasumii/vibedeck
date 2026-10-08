import Foundation

// MARK: - Chats

/// One line of a saved Claude conversation, as shown in the panel.
public struct ClaudeChatMessage: Codable, Equatable, Sendable {
    public enum Role: String, Codable, Sendable {
        case user, assistant, tool, notice, error
    }

    public var role: Role
    public var text: String
    public var toolName: String?
    /// Tool calls: the one-line description (command, path…).
    public var summary: String?
    public var result: String?
    public var isError: Bool?
    /// User messages: other chats mentioned (sent to Claude as JSON, not resumed).
    public var mentions: [UUID]?
    /// User messages: absolute paths of files attached (referenced in the prompt, never copied).
    public var attachments: [String]?

    public init(
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

    public init(from decoder: Decoder) throws {
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
public struct ClaudeChat: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var sessionId: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var messages: [ClaudeChatMessage]

    public init(id: UUID = UUID(), title: String, sessionId: String? = nil, createdAt: Date = .now, updatedAt: Date = .now, messages: [ClaudeChatMessage] = []) {
        self.id = id
        self.title = title
        self.sessionId = sessionId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, sessionId, createdAt, updatedAt, messages
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decode(String.self, forKey: .title)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        sessionId = try c.decodeIfPresent(String.self, forKey: .sessionId)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        messages = try c.decodeIfPresent([ClaudeChatMessage].self, forKey: .messages) ?? []
    }

    public static let untitled = "Nova conversa"

    /// Automatic title: the first line of the first message, shortened.
    public static func title(from message: String, limit: Int = 40) -> String {
        let line = message.split(whereSeparator: \.isNewline).first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !line.isEmpty else { return untitled }
        return line.count > limit ? String(line.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…" : line
    }

    /// The whole conversation as JSON, for mentioning it in another chat.
    public func contextJSON() -> String {
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
    public static func wireText(_ text: String, mentioning chats: [ClaudeChat], attachments: [String] = []) -> String {
        var out = text
        if !attachments.isEmpty {
            out += "\n\nArquivos anexados pelo usuário (leia com Read se precisar):"
            out += attachments.map { "\n- " + $0 }.joined()
        }
        guard !chats.isEmpty else { return out }
        out += "\n\n"
        out += "As conversas mencionadas abaixo são só referência (outras conversas deste projeto, em JSON); não fazem parte desta conversa."
        for chat in chats {
            let title = chat.title.replacingOccurrences(of: "\"", with: "'")
            out += "\n\n<conversa-mencionada titulo=\"\(title)\">\n\(chat.contextJSON())\n</conversa-mencionada>"
        }
        return out
    }
}

// MARK: - Store

/// Chats of one project, one JSON file each, kept outside the project (Application Support).
public struct ClaudeChatStore: Sendable {
    public let dir: URL

    public init(dir: URL) {
        self.dir = dir
    }

    /// `~/Library/Application Support/VibeDeck/chats/<projectId>/`.
    public static func forProject(_ projectId: UUID) -> ClaudeChatStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")
        return ClaudeChatStore(dir: base.appending(path: "VibeDeck/chats/\(projectId.uuidString)", directoryHint: .isDirectory))
    }

    public func url(_ id: UUID) -> URL { dir.appending(path: "\(id.uuidString).json") }

    /// Most recently updated first; unreadable files are skipped.
    public func list() -> [ClaudeChat] {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return files.filter { $0.pathExtension == "json" }
            .compactMap { try? VDJSON.decoder.decode(ClaudeChat.self, from: Data(contentsOf: $0)) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    public func load(_ id: UUID) -> ClaudeChat? {
        try? VDJSON.decoder.decode(ClaudeChat.self, from: Data(contentsOf: url(id)))
    }

    public func save(_ chat: ClaudeChat) throws {
        try AtomicFile.write(VDJSON.encode(chat), to: url(chat.id))
    }

    public func delete(_ id: UUID) throws {
        let url = url(id)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    public func deleteAll() throws {
        if FileManager.default.fileExists(atPath: dir.path) { try FileManager.default.removeItem(at: dir) }
    }
}
