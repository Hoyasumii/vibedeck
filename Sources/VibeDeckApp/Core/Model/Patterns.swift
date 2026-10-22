import Foundation

// MARK: - Patterns

/// A code pattern the project follows (TDD, hexagonal architecture, CQRS…), kept in `vibedeck.json` under `patterns`.
/// Its rules live in a real rule topic (`topic`, with `sourcePattern` pointing back), so `rules_for` enforces them.
struct ProjectPattern: Codable, Equatable, Hashable, Identifiable, Sendable {
    /// Catalog id (`tdd`, `hexagonal`) or the slug of a custom pattern's name.
    var id: String
    var name: String
    var category: String?
    var summary: String?
    /// How the project applies it ("hexagonal só no Core; a UI fala com casos de uso"); goes into the topic description.
    var note: String?
    /// Slug of the rule topic that enforces the pattern.
    var topic: String?
    var tags: [String]
    var author: Author

    init(id: String, name: String, category: String? = nil, summary: String? = nil, note: String? = nil, topic: String? = nil, tags: [String] = [], author: Author = .human) {
        self.id = id
        self.name = name
        self.category = category
        self.summary = summary
        self.note = note
        self.topic = topic
        self.tags = tags
        self.author = author
    }

    enum CodingKeys: String, CodingKey { case id, name, category, summary, note, topic, tags, author }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? id
        category = try c.decodeIfPresent(String.self, forKey: .category)
        summary = try c.decodeIfPresent(String.self, forKey: .summary)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        topic = try c.decodeIfPresent(String.self, forKey: .topic)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        author = try c.decodeIfPresent(Author.self, forKey: .author) ?? .human
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(category, forKey: .category)
        if let summary, !summary.isEmpty { try c.encode(summary, forKey: .summary) }
        if let note, !note.isEmpty { try c.encode(note, forKey: .note) }
        try c.encodeIfPresent(topic, forKey: .topic)
        if !tags.isEmpty { try c.encode(tags, forKey: .tags) }
        try c.encode(author, forKey: .author)
    }

    /// Description of the pattern's rule topic: what the pattern is, plus the project's note.
    var topicDescription: String {
        let parts = [summary?.trimmed.nonEmpty, note?.trimmed.nonEmpty.map { "No projeto: \($0)" }].compactMap { $0 }
        return (parts.isEmpty ? ["Padrão de projeto \(name)."] : parts).joined(separator: "\n\n")
    }
}

enum PatternCategory {
    static let all = ["practices", "architecture", "domain", "design", "custom"]

    static func label(_ id: String?) -> String {
        switch id {
        case "practices": "Práticas"
        case "architecture": "Arquitetura"
        case "domain": "Domínio"
        case "design": "Design"
        case "custom": "Personalizados"
        case let other?: other.capitalized
        case nil: "Outros"
        }
    }
}
