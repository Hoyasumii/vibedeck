#if canImport(CryptoKit)
import CryptoKit
#endif
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
    /// How the rule is verified: a script (decided by its exit code) or by the agent (`manual`).
    public var test: RuleTest?

    public init(text: String, details: String? = nil, severity: RuleSeverity = .must, author: Author = .human, now: Date = .now) {
        self.id = UUID()
        self.text = text
        self.details = details
        self.severity = severity
        self.author = author
        self.createdAt = now
    }

    enum CodingKeys: String, CodingKey { case id, text, details, severity, author, createdAt, test }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        text = try c.decode(String.self, forKey: .text)
        details = try c.decodeIfPresent(String.self, forKey: .details)
        severity = try c.decodeIfPresent(RuleSeverity.self, forKey: .severity) ?? .must
        author = try c.decodeIfPresent(Author.self, forKey: .author) ?? .human
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        test = try c.decodeIfPresent(RuleTest.self, forKey: .test)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(text, forKey: .text)
        try c.encodeIfPresent(details, forKey: .details)
        try c.encode(severity, forKey: .severity)
        try c.encode(author, forKey: .author)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(test, forKey: .test)
    }

    /// Fingerprint of what the rule asks (`text` + `details`): a test generated for another fingerprint is stale.
    public var contentHash: String {
        let data = Data((text + "\n" + (details ?? "")).utf8)
        #if canImport(CryptoKit)
        let digest = Array(SHA256.hash(data: data))
        #else
        let digest = PortableSHA256.hash(data)
        #endif
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    public var testState: RuleTestState {
        guard let test else { return .none }
        if test.ruleHash != contentHash { return .stale }
        return test.mode == .script && test.command?.trimmed.nonEmpty != nil ? .script : .manual
    }

    /// The command to run when the rule is decided by a script (nil when manual, untested or stale).
    public var scriptCommand: String? {
        testState == .script ? test?.command?.trimmed.nonEmpty : nil
    }
}

// MARK: - Rule tests

public enum RuleTestMode: String, Codable, CaseIterable, Sendable {
    case script, manual
}

/// A rule translated into a check: `script` runs `command` (exit 0 = pass, 77 = n/a, else fail);
/// `manual` means the rule isn't objectively testable and stays with the agent.
public struct RuleTest: Codable, Equatable, Hashable, Sendable {
    public var mode: RuleTestMode
    public var command: String?
    public var reason: String?
    /// `Rule.contentHash` when the test was written.
    public var ruleHash: String
    public var generatedAt: Date

    public init(mode: RuleTestMode, command: String? = nil, reason: String? = nil, ruleHash: String, now: Date = .now) {
        self.mode = mode
        self.command = command
        self.reason = reason
        self.ruleHash = ruleHash
        self.generatedAt = now
    }

    enum CodingKeys: String, CodingKey { case mode, command, reason, ruleHash, generatedAt }

    /// Hand-written tests: `mode` follows `command`; without `ruleHash` the test reads as stale until regenerated.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        command = try c.decodeIfPresent(String.self, forKey: .command)
        mode = try c.decodeIfPresent(RuleTestMode.self, forKey: .mode) ?? (command == nil ? .manual : .script)
        reason = try c.decodeIfPresent(String.self, forKey: .reason)
        ruleHash = try c.decodeIfPresent(String.self, forKey: .ruleHash) ?? ""
        generatedAt = try c.decodeIfPresent(Date.self, forKey: .generatedAt) ?? .now
    }
}

public enum RuleTestState: String, Sendable {
    case none, script, manual, stale

    public var label: String {
        switch self {
        case .none: "Sem teste"
        case .script: "Script"
        case .manual: "Manual"
        case .stale: "Desatualizado"
        }
    }

    /// True when the agent has to answer the rule in a check.
    public var needsAgent: Bool { self != .script }
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
    /// Id of the project pattern (`vibedeck.json` `patterns`) this topic enforces.
    public var sourcePattern: String?
    public var createdAt: Date

    public init(title: String, description: String? = nil, tags: [String] = [], paths: [String] = [], rules: [Rule] = [], sourceIdea: UUID? = nil, sourcePattern: String? = nil, now: Date = .now) {
        self.schema = SchemaURL.ruleTopic
        self.id = UUID()
        self.title = title
        self.description = description
        self.tags = tags
        self.paths = paths
        self.rules = rules
        self.sourceIdea = sourceIdea
        self.sourcePattern = sourcePattern
        self.createdAt = now
    }

    enum CodingKeys: String, CodingKey {
        case schema = "$schema", id, title, description, tags, paths, rules, sourceIdea, sourcePattern, createdAt
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
        sourcePattern = try c.decodeIfPresent(String.self, forKey: .sourcePattern)
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
        try c.encodeIfPresent(sourcePattern, forKey: .sourcePattern)
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
    /// Suggested globs (like `RuleTopic.paths`); promotion copies them into the topic.
    public var paths: [String]
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
        self.paths = []
        self.rules = []
        self.author = author
        self.createdAt = now
        self.updatedAt = now
    }

    enum CodingKeys: String, CodingKey {
        case schema = "$schema", id, title, body, status, tags, paths, rules, promotedTopic, author, createdAt, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decodeIfPresent(String.self, forKey: .schema)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decode(String.self, forKey: .title)
        body = try c.decodeIfPresent(String.self, forKey: .body)
        status = try c.decodeIfPresent(IdeaStatus.self, forKey: .status) ?? .new
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        paths = try c.decodeIfPresent([String].self, forKey: .paths) ?? []
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
        if !paths.isEmpty { try c.encode(paths, forKey: .paths) }
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

public enum RuleResultSource: String, Codable, Sendable {
    case agent, script
}

public struct RuleResult: Codable, Equatable, Hashable, Sendable {
    public var topic: String
    public var ruleId: UUID
    public var verdict: RuleVerdict
    public var note: String?
    public var source: RuleResultSource
    public var exitCode: Int32?

    public init(topic: String, ruleId: UUID, verdict: RuleVerdict, note: String? = nil, source: RuleResultSource = .agent, exitCode: Int32? = nil) {
        self.topic = topic
        self.ruleId = ruleId
        self.verdict = verdict
        self.note = note
        self.source = source
        self.exitCode = exitCode
    }

    enum CodingKeys: String, CodingKey { case topic, ruleId, verdict, note, source, exitCode }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        topic = try c.decode(String.self, forKey: .topic)
        ruleId = try c.decode(UUID.self, forKey: .ruleId)
        verdict = try c.decode(RuleVerdict.self, forKey: .verdict)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        source = try c.decodeIfPresent(RuleResultSource.self, forKey: .source) ?? .agent
        exitCode = try c.decodeIfPresent(Int32.self, forKey: .exitCode)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(topic, forKey: .topic)
        try c.encode(ruleId, forKey: .ruleId)
        try c.encode(verdict, forKey: .verdict)
        try c.encodeIfPresent(note, forKey: .note)
        if source != .agent { try c.encode(source, forKey: .source) }
        try c.encodeIfPresent(exitCode, forKey: .exitCode)
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
    /// Texts of manual rules this check left unverified (scripts-only check): `passed` doesn't cover them.
    public var pending: [String]
    public var author: Author
    public var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case schema = "$schema", id, task, files, topics, reviewItem, results, passed, warnings, failures, pending, author, createdAt
    }

    public init(task: String, files: [String], topics: [String], reviewItem: UUID?, results: [RuleResult],
                passed: Bool, warnings: [String], failures: [String], pending: [String] = [], author: Author, now: Date = .now) {
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
        self.pending = pending
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
        pending = try c.decodeIfPresent([String].self, forKey: .pending) ?? []
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
        if !pending.isEmpty { try c.encode(pending, forKey: .pending) }
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
