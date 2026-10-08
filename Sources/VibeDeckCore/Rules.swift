import Foundation

// MARK: - Rules

public enum RuleSeverity: String, Codable, CaseIterable, Sendable {
    case must, should

    public var label: String {
        switch self {
        case .must: "Obrigatória"
        case .should: "Recomendada"
        }
    }
}

/// A behavior that a topic (or idea) must have, checked by agents before calling a task done.
public struct Rule: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var text: String
    public var details: String?
    public var severity: RuleSeverity
    public var author: Author
    public var createdAt: Date

    public init(text: String, details: String? = nil, severity: RuleSeverity = .must, author: Author = .human, now: Date = .now) {
        self.id = UUID()
        self.text = text
        self.details = details
        self.severity = severity
        self.author = author
        self.createdAt = now
    }

    enum CodingKeys: String, CodingKey { case id, text, details, severity, author, createdAt }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        text = try c.decode(String.self, forKey: .text)
        details = try c.decodeIfPresent(String.self, forKey: .details)
        severity = try c.decodeIfPresent(RuleSeverity.self, forKey: .severity) ?? .must
        author = try c.decodeIfPresent(Author.self, forKey: .author) ?? .human
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
    }
}

/// A file per topic in `.vibedeck/rules/`. Topics without `paths` apply to every task;
/// topics with `paths` (globs relative to the project root) apply when a touched file matches.
public struct RuleTopic: Codable, Equatable, Identifiable, Sendable {
    public var schema: String?
    public var id: UUID
    public var title: String
    public var description: String?
    public var tags: [String]
    public var paths: [String]
    public var rules: [Rule]
    public var sourceIdea: UUID?
    public var createdAt: Date

    public init(title: String, description: String? = nil, tags: [String] = [], paths: [String] = [], rules: [Rule] = [], sourceIdea: UUID? = nil, now: Date = .now) {
        self.schema = SchemaURL.ruleTopic
        self.id = UUID()
        self.title = title
        self.description = description
        self.tags = tags
        self.paths = paths
        self.rules = rules
        self.sourceIdea = sourceIdea
        self.createdAt = now
    }

    enum CodingKeys: String, CodingKey {
        case schema = "$schema", id, title, description, tags, paths, rules, sourceIdea, createdAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decodeIfPresent(String.self, forKey: .schema)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decode(String.self, forKey: .title)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        paths = try c.decodeIfPresent([String].self, forKey: .paths) ?? []
        rules = try c.decodeIfPresent([Rule].self, forKey: .rules) ?? []
        sourceIdea = try c.decodeIfPresent(UUID.self, forKey: .sourceIdea)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(schema, forKey: .schema)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(description, forKey: .description)
        if !tags.isEmpty { try c.encode(tags, forKey: .tags) }
        if !paths.isEmpty { try c.encode(paths, forKey: .paths) }
        try c.encode(rules, forKey: .rules)
        try c.encodeIfPresent(sourceIdea, forKey: .sourceIdea)
        try c.encode(createdAt, forKey: .createdAt)
    }

    /// True when the topic applies to every task (no path scope).
    public var isGlobal: Bool { paths.isEmpty }

    public func matches(file: String) -> Bool {
        paths.contains { Glob.matches($0, path: file) }
    }
}

// MARK: - Ideas

public enum IdeaStatus: String, Codable, CaseIterable, Sendable {
    case new, exploring, approved, discarded, done

    public var label: String {
        switch self {
        case .new: "Nova"
        case .exploring: "Explorando"
        case .approved: "Aprovada"
        case .discarded: "Descartada"
        case .done: "Implementada"
        }
    }

    public var symbol: String {
        switch self {
        case .new: "sparkle"
        case .exploring: "magnifyingglass"
        case .approved: "hand.thumbsup"
        case .discarded: "archivebox"
        case .done: "checkmark.seal"
        }
    }

    public var isClosed: Bool { self == .discarded || self == .done }
}

/// A file per idea in `.vibedeck/ideas/`: brainstorm for the project's future, with its own draft rules.
public struct Idea: Codable, Equatable, Identifiable, Sendable {
    public var schema: String?
    public var id: UUID
    public var title: String
    public var body: String?
    public var status: IdeaStatus
    public var tags: [String]
    public var rules: [Rule]
    /// Slug of the rule topic created when the idea was promoted.
    public var promotedTopic: String?
    public var author: Author
    public var createdAt: Date
    public var updatedAt: Date

    public init(title: String, body: String? = nil, tags: [String] = [], author: Author = .human, now: Date = .now) {
        self.schema = SchemaURL.idea
        self.id = UUID()
        self.title = title
        self.body = body
        self.status = .new
        self.tags = tags
        self.rules = []
        self.author = author
        self.createdAt = now
        self.updatedAt = now
    }

    enum CodingKeys: String, CodingKey {
        case schema = "$schema", id, title, body, status, tags, rules, promotedTopic, author, createdAt, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decodeIfPresent(String.self, forKey: .schema)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decode(String.self, forKey: .title)
        body = try c.decodeIfPresent(String.self, forKey: .body)
        status = try c.decodeIfPresent(IdeaStatus.self, forKey: .status) ?? .new
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        rules = try c.decodeIfPresent([Rule].self, forKey: .rules) ?? []
        promotedTopic = try c.decodeIfPresent(String.self, forKey: .promotedTopic)
        author = try c.decodeIfPresent(Author.self, forKey: .author) ?? .human
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(schema, forKey: .schema)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(body, forKey: .body)
        try c.encode(status, forKey: .status)
        if !tags.isEmpty { try c.encode(tags, forKey: .tags) }
        try c.encode(rules, forKey: .rules)
        try c.encodeIfPresent(promotedTopic, forKey: .promotedTopic)
        try c.encode(author, forKey: .author)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
    }
}

// MARK: - Checks

public enum RuleVerdict: String, Codable, CaseIterable, Sendable {
    case pass, fail, na
}

public struct RuleResult: Codable, Equatable, Hashable, Sendable {
    public var topic: String
    public var ruleId: UUID
    public var verdict: RuleVerdict
    public var note: String?

    public init(topic: String, ruleId: UUID, verdict: RuleVerdict, note: String? = nil) {
        self.topic = topic
        self.ruleId = ruleId
        self.verdict = verdict
        self.note = note
    }
}

/// A verification an agent submitted against the applicable rules, kept in `.vibedeck/checks/`.
public struct RuleCheck: Codable, Equatable, Identifiable, Sendable {
    public var schema: String?
    public var id: UUID
    public var task: String
    public var files: [String]
    public var topics: [String]
    public var reviewItem: UUID?
    public var results: [RuleResult]
    public var passed: Bool
    /// Texts of `should` rules that failed (don't block, but are reported).
    public var warnings: [String]
    /// Texts of `must` rules that failed.
    public var failures: [String]
    public var author: Author
    public var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case schema = "$schema", id, task, files, topics, reviewItem, results, passed, warnings, failures, author, createdAt
    }

    public init(task: String, files: [String], topics: [String], reviewItem: UUID?, results: [RuleResult],
                passed: Bool, warnings: [String], failures: [String], author: Author, now: Date = .now) {
        self.schema = SchemaURL.ruleCheck
        self.id = UUID()
        self.task = task
        self.files = files
        self.topics = topics
        self.reviewItem = reviewItem
        self.results = results
        self.passed = passed
        self.warnings = warnings
        self.failures = failures
        self.author = author
        self.createdAt = now
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decodeIfPresent(String.self, forKey: .schema)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        task = try c.decodeIfPresent(String.self, forKey: .task) ?? ""
        files = try c.decodeIfPresent([String].self, forKey: .files) ?? []
        topics = try c.decodeIfPresent([String].self, forKey: .topics) ?? []
        reviewItem = try c.decodeIfPresent(UUID.self, forKey: .reviewItem)
        results = try c.decodeIfPresent([RuleResult].self, forKey: .results) ?? []
        passed = try c.decodeIfPresent(Bool.self, forKey: .passed) ?? false
        warnings = try c.decodeIfPresent([String].self, forKey: .warnings) ?? []
        failures = try c.decodeIfPresent([String].self, forKey: .failures) ?? []
        author = try c.decodeIfPresent(Author.self, forKey: .author) ?? .ai
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
    }

    /// `createdAt` keeps fractional seconds: "latest check" must be unambiguous even when an agent
    /// resubmits within the same second.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(schema, forKey: .schema)
        try c.encode(id, forKey: .id)
        try c.encode(task, forKey: .task)
        try c.encode(files, forKey: .files)
        try c.encode(topics, forKey: .topics)
        try c.encodeIfPresent(reviewItem, forKey: .reviewItem)
        try c.encode(results, forKey: .results)
        try c.encode(passed, forKey: .passed)
        try c.encode(warnings, forKey: .warnings)
        try c.encode(failures, forKey: .failures)
        try c.encode(author, forKey: .author)
        try c.encode(createdAt.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true)), forKey: .createdAt)
    }
}

/// An answer to one rule, as sent by an agent: `ruleId` may be a full id or a unique prefix (>= 4 chars).
public struct RuleAnswer: Decodable, Sendable {
    public var ruleId: String
    public var verdict: RuleVerdict
    public var note: String?

    public init(ruleId: String, verdict: RuleVerdict, note: String? = nil) {
        self.ruleId = ruleId
        self.verdict = verdict
        self.note = note
    }

    enum CodingKeys: String, CodingKey { case ruleId, rule_id, verdict, note }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = try c.decodeIfPresent(String.self, forKey: .ruleId) ?? c.decodeIfPresent(String.self, forKey: .rule_id) else {
            throw DecodingError.keyNotFound(CodingKeys.ruleId, .init(codingPath: c.codingPath, debugDescription: "ruleId ausente"))
        }
        ruleId = id
        verdict = try c.decode(RuleVerdict.self, forKey: .verdict)
        note = try c.decodeIfPresent(String.self, forKey: .note)
    }
}

// MARK: - Glob

/// Minimal gitignore-like globs: `*` (within a segment), `?`, `**` (any depth).
/// A pattern without `/` matches the file name at any depth; a trailing `/` matches everything below.
public enum Glob {
    public static func matches(_ pattern: String, path: String) -> Bool {
        var pattern = pattern.trimmingCharacters(in: .whitespaces)
        guard !pattern.isEmpty else { return false }
        if pattern.hasPrefix("./") { pattern.removeFirst(2) }
        if pattern.hasPrefix("/") { pattern.removeFirst() } else if !pattern.contains("/") { pattern = "**/" + pattern }
        if pattern.hasSuffix("/") { pattern += "**" }
        let path = path.hasPrefix("./") ? String(path.dropFirst(2)) : path
        return path.range(of: regex(pattern), options: .regularExpression) != nil
    }

    static func regex(_ pattern: String) -> String {
        var out = "^"
        var chars = Array(pattern)[...]
        while let ch = chars.popFirst() {
            switch ch {
            case "*":
                if chars.first == "*" {
                    chars.removeFirst()
                    if chars.first == "/" {
                        chars.removeFirst()
                        out += "(?:.*/)?"
                    } else {
                        out += ".*"
                    }
                } else {
                    out += "[^/]*"
                }
            case "?": out += "[^/]"
            case ".", "+", "(", ")", "^", "$", "|", "[", "]", "{", "}", "\\": out += "\\\(ch)"
            default: out.append(ch)
            }
        }
        return out + "$"
    }
}
