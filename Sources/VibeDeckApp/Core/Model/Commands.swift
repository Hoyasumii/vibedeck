import Foundation

// MARK: - Commands

/// A file per command in `.vibedeck/commands/`: a reusable prompt (like a Claude Code slash command, with
/// `$ARGUMENTS`) plus the next steps that chain it into a flow, exactly like agents.
public struct Command: Codable, Equatable, Identifiable, Sendable {
    public var schema: String?
    public var id: UUID
    public var title: String
    public var summary: String?
    /// What goes in `$ARGUMENTS` (e.g. `<mensagem>`).
    public var argumentHint: String?
    public var model: String?
    public var providerSettings: [String: AIProviderSettings]?
    public var tools: [String]
    public var prompt: String
    public var nextSteps: [NextStep]
    public var tags: [String]
    public var author: Author
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        title: String, summary: String? = nil, argumentHint: String? = nil, model: String? = nil, tools: [String] = [],
        prompt: String = "", tags: [String] = [], author: Author = .human, now: Date = .now
    ) {
        self.schema = SchemaURL.command
        self.id = UUID()
        self.title = title
        self.summary = summary
        self.argumentHint = argumentHint
        self.model = model
        self.providerSettings = nil
        self.tools = tools
        self.prompt = prompt
        self.nextSteps = []
        self.tags = tags
        self.author = author
        self.createdAt = now
        self.updatedAt = now
    }

    enum CodingKeys: String, CodingKey {
        case schema = "$schema", id, title, summary, argumentHint, model, providerSettings, tools, prompt, nextSteps, tags, author, createdAt, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decodeIfPresent(String.self, forKey: .schema)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decode(String.self, forKey: .title)
        summary = try c.decodeIfPresent(String.self, forKey: .summary)
        argumentHint = try c.decodeIfPresent(String.self, forKey: .argumentHint)
        model = try c.decodeIfPresent(String.self, forKey: .model)
        providerSettings = try c.decodeIfPresent([String: AIProviderSettings].self, forKey: .providerSettings)
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
        try c.encodeIfPresent(argumentHint, forKey: .argumentHint)
        try c.encodeIfPresent(model, forKey: .model)
        try c.encodeIfPresent(providerSettings, forKey: .providerSettings)
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

/// Parses a Claude Code slash command file: Markdown whose optional frontmatter has `description`,
/// `argument-hint`, `allowed-tools` and `model`; the body is the prompt. The name comes from the file path.
public enum ClaudeCommandFile {
    public struct Parsed: Equatable, Sendable {
        public var name: String
        public var description: String?
        public var argumentHint: String?
        public var model: String?
        public var tools: [String]
        public var prompt: String
    }

    public static func parse(_ text: String, fallbackName: String) -> Parsed {
        let (fields, body) = Frontmatter.parse(text)
        return Parsed(
            name: Frontmatter.value(fields, "name") ?? fallbackName,
            description: Frontmatter.value(fields, "description"),
            argumentHint: Frontmatter.value(fields, "argument-hint"),
            model: Frontmatter.value(fields, "model"),
            tools: Frontmatter.list(fields, "allowed-tools"),
            prompt: body.trimmed
        )
    }
}
