import Foundation

enum ClaudeItemKind: String, Codable, CaseIterable, Sendable {
    case artifact, doc

    var title: String { self == .artifact ? "Artefato" : "Doc" }
}

/// A curated reference, stored only in the project's manifest. No Claude API is involved.
struct ClaudeItem: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id: UUID
    var title: String
    var url: String
    var kind: ClaudeItemKind
    var tags: [String]
    var addedAt: Date

    init(id: UUID = UUID(), title: String, url: String, kind: ClaudeItemKind,
                tags: [String] = [], addedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.url = url
        self.kind = kind
        self.tags = tags
        self.addedAt = addedAt
    }

    static func accepts(_ text: String) -> Bool {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              url.host?.lowercased() == "claude.ai", url.user == nil, url.password == nil else { return false }
        return true
    }

    static func suggestedTitle(for text: String) -> String {
        let url = URL(string: text)
        let last = url?.lastPathComponent.removingPercentEncoding ?? ""
        return last.isEmpty || last == "/" ? "claude.ai" : last
    }

    static func make(url: String, kind: ClaudeItemKind, title: String? = nil, tags: [String] = []) throws -> Self {
        let url = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard accepts(url) else { throw VibeDeckError.invalidClaudeURL }
        let title = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return Self(title: title.isEmpty ? suggestedTitle(for: url) : title, url: url, kind: kind, tags: tags)
    }

    enum CodingKeys: String, CodingKey { case id, title, url, kind, tags, addedAt }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        url = try c.decode(String.self, forKey: .url)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? Self.suggestedTitle(for: url)
        kind = try c.decodeIfPresent(ClaudeItemKind.self, forKey: .kind) ?? .artifact
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        addedAt = try c.decodeIfPresent(Date.self, forKey: .addedAt) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(url, forKey: .url)
        try c.encode(kind, forKey: .kind)
        if !tags.isEmpty { try c.encode(tags, forKey: .tags) }
        try c.encode(addedAt, forKey: .addedAt)
    }
}

