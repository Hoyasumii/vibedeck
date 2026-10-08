import Foundation

// MARK: - Skills

/// A file per skill in `.vibedeck/skills/`: instructions the AI loads when the task matches its description
/// (like a Claude Code skill's `SKILL.md`), plus the next steps that chain it into a flow, exactly like agents.
public struct Skill: Codable, Equatable, Identifiable, Sendable {
    public var schema: String?
    public var id: UUID
    public var title: String
    /// When to use the skill: it is what triggers it, so it should be specific.
    public var summary: String?
    public var model: String?
    public var tools: [String]
    public var prompt: String
    public var nextSteps: [NextStep]
    public var tags: [String]
    public var author: Author
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        title: String, summary: String? = nil, model: String? = nil, tools: [String] = [], prompt: String = "",
        tags: [String] = [], author: Author = .human, now: Date = .now
    ) {
        self.schema = SchemaURL.skill
        self.id = UUID()
        self.title = title
        self.summary = summary
        self.model = model
        self.tools = tools
        self.prompt = prompt
        self.nextSteps = []
        self.tags = tags
        self.author = author
        self.createdAt = now
        self.updatedAt = now
    }

    enum CodingKeys: String, CodingKey {
        case schema = "$schema", id, title, summary, model, tools, prompt, nextSteps, tags, author, createdAt, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decodeIfPresent(String.self, forKey: .schema)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decode(String.self, forKey: .title)
        summary = try c.decodeIfPresent(String.self, forKey: .summary)
        model = try c.decodeIfPresent(String.self, forKey: .model)
        tools = try c.decodeIfPresent([String].self, forKey: .tools) ?? []
        prompt = try c.decodeIfPresent(String.self, forKey: .prompt) ?? ""
        nextSteps = try c.decodeIfPresent([NextStep].self, forKey: .nextSteps) ?? []
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        author = try c.decodeIfPresent(Author.self, forKey: .author) ?? .human
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(schema, forKey: .schema)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(summary, forKey: .summary)
        try c.encodeIfPresent(model, forKey: .model)
        if !tools.isEmpty { try c.encode(tools, forKey: .tools) }
        try c.encode(prompt, forKey: .prompt)
        if !nextSteps.isEmpty { try c.encode(nextSteps, forKey: .nextSteps) }
        if !tags.isEmpty { try c.encode(tags, forKey: .tags) }
        try c.encode(author, forKey: .author)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
    }
}

// MARK: - Import from the AI provider (Claude Code)

/// Parses a Claude Code `SKILL.md`: Markdown whose frontmatter has `name`, `description`, `allowed-tools` and
/// `model`; the body is the instructions. The name falls back to the skill's folder.
public enum ClaudeSkillFile {
    public struct Parsed: Equatable, Sendable {
        public var name: String
        public var description: String?
        public var model: String?
        public var tools: [String]
        public var prompt: String
    }

    public static func parse(_ text: String, fallbackName: String) -> Parsed {
        let (fields, body) = Frontmatter.parse(text)
        return Parsed(
            name: Frontmatter.value(fields, "name") ?? fallbackName,
            description: Frontmatter.value(fields, "description"),
            model: Frontmatter.value(fields, "model"),
            tools: Frontmatter.list(fields, "allowed-tools"),
            prompt: body.trimmed
        )
    }
}
