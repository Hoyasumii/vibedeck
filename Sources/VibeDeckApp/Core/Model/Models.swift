import Foundation

enum SchemaURL {
    /// Base URL where the Cloudflare Worker serves the JSON Schemas.
    /// Run `scripts/set-schema-url.sh <url>` after deploying the worker to change it everywhere.
    static let base = "https://vibedeck-schema.alanreisanjo.workers.dev/v1"
    static let project = "\(base)/project.schema.json"
    static let reviewGroup = "\(base)/review-group.schema.json"
    static let ruleTopic = "\(base)/rule-topic.schema.json"
    static let idea = "\(base)/idea.schema.json"
    static let agent = "\(base)/agent.schema.json"
    static let command = "\(base)/command.schema.json"
    static let skill = "\(base)/skill.schema.json"
    static let workflow = "\(base)/workflow.schema.json"
    static let workflowRun = "\(base)/workflow-run.schema.json"
    static let ruleCheck = "\(base)/rule-check.schema.json"
}

// MARK: - Project

struct Project: Codable, Equatable, Sendable {
    var schema: String?
    var version: Int
    var id: UUID
    var name: String
    var description: String?
    var links: [ProjectLink]
    var claude: [ClaudeItem]
    /// The project's highlighted technologies (Skill Icons ids), in display order.
    var stack: [StackItem]
    /// Code patterns the AI must follow (TDD, hexagonal…), in display order; each one is enforced by its rule topic.
    var patterns: [ProjectPattern]
    var reviewKinds: [ReviewKind]

    init(name: String, description: String? = nil) {
        self.schema = SchemaURL.project
        self.version = 1
        self.id = UUID()
        self.name = name
        self.description = description
        self.links = []
        self.claude = []
        self.stack = []
        self.patterns = []
        self.reviewKinds = ReviewKind.defaults
    }

    enum CodingKeys: String, CodingKey {
        case schema = "$schema", version, id, name, description, links, claude, stack, patterns, reviewKinds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decodeIfPresent(String.self, forKey: .schema)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        links = try c.decodeIfPresent([ProjectLink].self, forKey: .links) ?? []
        claude = try c.decodeIfPresent([ClaudeItem].self, forKey: .claude) ?? []
        stack = try c.decodeIfPresent([StackItem].self, forKey: .stack) ?? []
        patterns = try c.decodeIfPresent([ProjectPattern].self, forKey: .patterns) ?? []
        let kinds = try c.decodeIfPresent([ReviewKind].self, forKey: .reviewKinds) ?? []
        reviewKinds = kinds.isEmpty ? ReviewKind.defaults : kinds
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(schema, forKey: .schema)
        try c.encode(version, forKey: .version)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encode(links, forKey: .links)
        if !claude.isEmpty { try c.encode(claude, forKey: .claude) }
        if !stack.isEmpty { try c.encode(stack, forKey: .stack) }
        if !patterns.isEmpty { try c.encode(patterns, forKey: .patterns) }
        try c.encode(reviewKinds, forKey: .reviewKinds)
    }

    func kind(_ id: String) -> ReviewKind {
        reviewKinds.first { $0.id == id } ?? ReviewKind(id: id, label: id.capitalized, symbol: "tag")
    }
}

struct ProjectLink: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id: UUID
    var title: String
    var url: String
    var tags: [String]

    init(id: UUID = UUID(), title: String, url: String, tags: [String] = []) {
        self.id = id
        self.title = title
        self.url = url
        self.tags = tags
    }

    enum CodingKeys: String, CodingKey { case id, title, url, tags }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        url = try c.decode(String.self, forKey: .url)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? url
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(url, forKey: .url)
        if !tags.isEmpty { try c.encode(tags, forKey: .tags) }
    }
}

struct ReviewKind: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id: String
    var label: String
    var symbol: String?

    init(id: String, label: String, symbol: String? = nil) {
        self.id = id
        self.label = label
        self.symbol = symbol
    }

    static let defaults: [ReviewKind] = [
        .init(id: "disable", label: "Inativar", symbol: "nosign"),
        .init(id: "hide", label: "Ocultar", symbol: "eye.slash"),
        .init(id: "fix", label: "Corrigir", symbol: "wrench.and.screwdriver"),
        .init(id: "change", label: "Alterar", symbol: "pencil"),
        .init(id: "remove", label: "Remover", symbol: "trash"),
        .init(id: "note", label: "Nota", symbol: "note.text"),
    ]
}

// MARK: - Reviews

enum ReviewStatus: String, Codable, CaseIterable, Sendable {
    case open, inProgress = "in_progress", done, wontfix

    var label: String {
        switch self {
        case .open: "Aberto"
        case .inProgress: "Em andamento"
        case .done: "Feito"
        case .wontfix: "Não fazer"
        }
    }

    var isClosed: Bool { self == .done || self == .wontfix }
}

enum ReviewPriority: String, Codable, CaseIterable, Sendable {
    case low, normal, high

    var label: String {
        switch self {
        case .low: "Baixa"
        case .normal: "Normal"
        case .high: "Alta"
        }
    }
}

enum Author: String, Codable, Sendable {
    case human, ai
}

struct ReviewTarget: Codable, Equatable, Hashable, Sendable {
    var file: String?
    var route: String?
    var component: String?
    var selector: String?

    init(file: String? = nil, route: String? = nil, component: String? = nil, selector: String? = nil) {
        self.file = file
        self.route = route
        self.component = component
        self.selector = selector
    }

    var isEmpty: Bool { file == nil && route == nil && component == nil && selector == nil }
}

struct ReviewItem: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id: UUID
    var kind: String
    var title: String
    var details: String?
    var status: ReviewStatus
    var priority: ReviewPriority
    var target: ReviewTarget?
    /// Slugs of rule topics that must pass a check before the item can be marked done.
    var rules: [String]
    var author: Author
    var createdAt: Date
    var updatedAt: Date

    init(
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

    init(from decoder: Decoder) throws {
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

    func encode(to encoder: Encoder) throws {
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

struct ReviewGroup: Codable, Equatable, Identifiable, Sendable {
    var schema: String?
    var id: UUID
    var title: String
    var description: String?
    var tags: [String]
    var createdAt: Date
    var items: [ReviewItem]

    init(title: String, description: String? = nil, tags: [String] = [], now: Date = .now) {
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

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decodeIfPresent(String.self, forKey: .schema)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decode(String.self, forKey: .title)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        items = try c.decodeIfPresent([ReviewItem].self, forKey: .items) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(schema, forKey: .schema)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(description, forKey: .description)
        if !tags.isEmpty { try c.encode(tags, forKey: .tags) }
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(items, forKey: .items)
    }

    var openCount: Int { items.filter { !$0.status.isClosed }.count }
}

// MARK: - Docs

struct DocInfo: Equatable, Hashable, Identifiable, Codable, Sendable {
    var slug: String
    var title: String
    var tags: [String] = []
    var modified: Date
    var id: String { slug }
    var group: String { CoreStore.groupPath(of: slug) }
}

// MARK: - JSON

enum VDJSON {
    /// Reference updates retain unknown JSON fields rather than round-tripping through a narrower model.
    static func encodeObject(_ object: Any) throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        data.append(0x0A)
        return data
    }

    /// Single-line output for agents (`rules_for`): indentation is pure token cost there. Files use `encoder`.
    static let compactEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
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

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        var data = try encoder.encode(value)
        data.append(0x0A)
        return data
    }
}
