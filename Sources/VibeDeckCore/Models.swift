import Foundation

public enum SchemaURL {
    /// Base URL where the Cloudflare Worker serves the JSON Schemas.
    /// Run `scripts/set-schema-url.sh <url>` after deploying the worker to change it everywhere.
    public static let base = "https://vibedeck-schema.alanreisanjo.workers.dev/v1"
    public static let project = "\(base)/project.schema.json"
    public static let reviewGroup = "\(base)/review-group.schema.json"
    public static let ruleTopic = "\(base)/rule-topic.schema.json"
    public static let idea = "\(base)/idea.schema.json"
    public static let agent = "\(base)/agent.schema.json"
    public static let command = "\(base)/command.schema.json"
    public static let skill = "\(base)/skill.schema.json"
    public static let workflow = "\(base)/workflow.schema.json"
    public static let workflowRun = "\(base)/workflow-run.schema.json"
    public static let ruleCheck = "\(base)/rule-check.schema.json"
}

// MARK: - Project

public struct Project: Codable, Equatable, Sendable {
    public var schema: String?
    public var version: Int
    public var id: UUID
    public var name: String
    public var description: String?
    public var links: [Link]
    /// The project's highlighted technologies (Skill Icons ids), in display order.
    public var stack: [StackItem]
    /// Code patterns the AI must follow (TDD, hexagonal…), in display order; each one is enforced by its rule topic.
    public var patterns: [ProjectPattern]
    public var codexCloudEnvironment: String?
    public var reviewKinds: [ReviewKind]

    public init(name: String, description: String? = nil) {
        self.schema = SchemaURL.project
        self.version = 1
        self.id = UUID()
        self.name = name
        self.description = description
        self.links = []
        self.stack = []
        self.patterns = []
        self.codexCloudEnvironment = nil
        self.reviewKinds = ReviewKind.defaults
    }

    enum CodingKeys: String, CodingKey {
        case schema = "$schema", version, id, name, description, links, stack, patterns, codexCloudEnvironment, reviewKinds
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decodeIfPresent(String.self, forKey: .schema)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        links = try c.decodeIfPresent([Link].self, forKey: .links) ?? []
        stack = try c.decodeIfPresent([StackItem].self, forKey: .stack) ?? []
        patterns = try c.decodeIfPresent([ProjectPattern].self, forKey: .patterns) ?? []
        codexCloudEnvironment = try c.decodeIfPresent(String.self, forKey: .codexCloudEnvironment)
        let kinds = try c.decodeIfPresent([ReviewKind].self, forKey: .reviewKinds) ?? []
        reviewKinds = kinds.isEmpty ? ReviewKind.defaults : kinds
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(schema, forKey: .schema)
        try c.encode(version, forKey: .version)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encode(links, forKey: .links)
        if !stack.isEmpty { try c.encode(stack, forKey: .stack) }
        if !patterns.isEmpty { try c.encode(patterns, forKey: .patterns) }
        try c.encodeIfPresent(codexCloudEnvironment, forKey: .codexCloudEnvironment)
        try c.encode(reviewKinds, forKey: .reviewKinds)
    }

    public func kind(_ id: String) -> ReviewKind {
        reviewKinds.first { $0.id == id } ?? ReviewKind(id: id, label: id.capitalized, symbol: "tag")
    }
}

public struct Link: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var url: String
    public var tags: [String]

    public init(id: UUID = UUID(), title: String, url: String, tags: [String] = []) {
        self.id = id
        self.title = title
        self.url = url
        self.tags = tags
    }

    enum CodingKeys: String, CodingKey { case id, title, url, tags }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        url = try c.decode(String.self, forKey: .url)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? url
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(url, forKey: .url)
        if !tags.isEmpty { try c.encode(tags, forKey: .tags) }
    }
}

public struct ReviewKind: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: String
    public var label: String
    public var symbol: String?

    public init(id: String, label: String, symbol: String? = nil) {
        self.id = id
        self.label = label
        self.symbol = symbol
    }

    public static let defaults: [ReviewKind] = [
        .init(id: "disable", label: "Inativar", symbol: "nosign"),
        .init(id: "hide", label: "Ocultar", symbol: "eye.slash"),
        .init(id: "fix", label: "Corrigir", symbol: "wrench.and.screwdriver"),
        .init(id: "change", label: "Alterar", symbol: "pencil"),
        .init(id: "remove", label: "Remover", symbol: "trash"),
        .init(id: "note", label: "Nota", symbol: "note.text"),
    ]
}

// MARK: - Reviews

public enum ReviewStatus: String, Codable, CaseIterable, Sendable {
    case open, inProgress = "in_progress", done, wontfix

    public var label: String {
        switch self {
        case .open: "Aberto"
        case .inProgress: "Em andamento"
        case .done: "Feito"
        case .wontfix: "Não fazer"
        }
    }

    public var isClosed: Bool { self == .done || self == .wontfix }
}

public enum ReviewPriority: String, Codable, CaseIterable, Sendable {
    case low, normal, high

    public var label: String {
        switch self {
        case .low: "Baixa"
        case .normal: "Normal"
        case .high: "Alta"
        }
    }
}

public enum Author: String, Codable, Sendable {
    case human, ai
}

public struct ReviewTarget: Codable, Equatable, Hashable, Sendable {
    public var file: String?
    public var route: String?
    public var component: String?
    public var selector: String?

    public init(file: String? = nil, route: String? = nil, component: String? = nil, selector: String? = nil) {
        self.file = file
        self.route = route
        self.component = component
        self.selector = selector
    }

    public var isEmpty: Bool { file == nil && route == nil && component == nil && selector == nil }
}

public struct ReviewItem: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var kind: String
    public var title: String
    public var details: String?
    public var status: ReviewStatus
    public var priority: ReviewPriority
    public var target: ReviewTarget?
    /// Slugs of rule topics that must pass a check before the item can be marked done.
    public var rules: [String]
    public var author: Author
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        kind: String, title: String, details: String? = nil,
        status: ReviewStatus = .open, priority: ReviewPriority = .normal,
        target: ReviewTarget? = nil, rules: [String] = [], author: Author = .human, now: Date = .now
    ) {
        self.id = UUID()
        self.kind = kind
        self.title = title
        self.details = details
        self.status = status
        self.priority = priority
        self.target = (target?.isEmpty ?? true) ? nil : target
        self.rules = rules
        self.author = author
        self.createdAt = now
        self.updatedAt = now
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, title, details, status, priority, target, rules, author, createdAt, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "note"
        title = try c.decode(String.self, forKey: .title)
        details = try c.decodeIfPresent(String.self, forKey: .details)
        status = try c.decodeIfPresent(ReviewStatus.self, forKey: .status) ?? .open
        priority = try c.decodeIfPresent(ReviewPriority.self, forKey: .priority) ?? .normal
        target = try c.decodeIfPresent(ReviewTarget.self, forKey: .target)
        rules = try c.decodeIfPresent([String].self, forKey: .rules) ?? []
        author = try c.decodeIfPresent(Author.self, forKey: .author) ?? .human
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(details, forKey: .details)
        try c.encode(status, forKey: .status)
        try c.encode(priority, forKey: .priority)
        try c.encodeIfPresent(target, forKey: .target)
        if !rules.isEmpty { try c.encode(rules, forKey: .rules) }
        try c.encode(author, forKey: .author)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
    }
}

public struct ReviewGroup: Codable, Equatable, Identifiable, Sendable {
    public var schema: String?
    public var id: UUID
    public var title: String
    public var description: String?
    public var tags: [String]
    public var createdAt: Date
    public var items: [ReviewItem]

    public init(title: String, description: String? = nil, tags: [String] = [], now: Date = .now) {
        self.schema = SchemaURL.reviewGroup
        self.id = UUID()
        self.title = title
        self.description = description
        self.tags = tags
        self.createdAt = now
        self.items = []
    }

    enum CodingKeys: String, CodingKey {
        case schema = "$schema", id, title, description, tags, createdAt, items
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decodeIfPresent(String.self, forKey: .schema)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decode(String.self, forKey: .title)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        items = try c.decodeIfPresent([ReviewItem].self, forKey: .items) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(schema, forKey: .schema)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(description, forKey: .description)
        if !tags.isEmpty { try c.encode(tags, forKey: .tags) }
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(items, forKey: .items)
    }

    public var openCount: Int { items.filter { !$0.status.isClosed }.count }
}

// MARK: - Docs

public struct DocInfo: Equatable, Hashable, Identifiable, Sendable {
    public var slug: String
    public var title: String
    public var tags: [String] = []
    public var modified: Date
    public var id: String { slug }
}

// MARK: - JSON

public enum VDJSON {
    /// Single-line output for agents (`rules_for`): indentation is pure token cost there. Files use `encoder`.
    public static let compactEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)
            if let date = try? Date(s, strategy: .iso8601) { return date }
            if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(s) { return date }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid ISO 8601 date: \(s)")
        }
        return d
    }()

    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        var data = try encoder.encode(value)
        data.append(0x0A)
        return data
    }
}
