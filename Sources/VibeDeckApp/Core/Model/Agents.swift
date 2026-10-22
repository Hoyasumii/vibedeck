import Foundation

// MARK: - Agents

public enum NextStepKind: String, Codable, CaseIterable, Sendable {
    case agent, command, skill
}

/// Link in a flow: after this agent/command/skill runs, another VibeDeck agent, command or skill acts on its result.
public struct NextStep: Codable, Equatable, Sendable {
    public var kind: NextStepKind
    /// Slug of a VibeDeck agent, command or skill, never of the AI provider's.
    public var ref: String
    public var note: String?

    public init(kind: NextStepKind = .agent, ref: String, note: String? = nil) {
        self.kind = kind
        self.ref = ref
        self.note = note
    }

    enum CodingKeys: String, CodingKey { case kind, ref, note }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decodeIfPresent(NextStepKind.self, forKey: .kind) ?? .agent
        ref = try c.decode(String.self, forKey: .ref)
        note = try c.decodeIfPresent(String.self, forKey: .note)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        try c.encode(ref, forKey: .ref)
        try c.encodeIfPresent(note, forKey: .note)
    }
}

/// A file per agent in `.vibedeck/agents/`: name, model, prompt and the next steps that form a flow.
public struct Agent: Codable, Equatable, Identifiable, Sendable {
    public var schema: String?
    public var id: UUID
    public var title: String
    public var summary: String?
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
        title: String, summary: String? = nil, model: String? = nil, tools: [String] = [], prompt: String = "",
        tags: [String] = [], author: Author = .human, now: Date = .now
    ) {
        self.schema = SchemaURL.agent
        self.id = UUID()
        self.title = title
        self.summary = summary
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
        case schema = "$schema", id, title, summary, model, providerSettings, tools, prompt, nextSteps, tags, author, createdAt, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decodeIfPresent(String.self, forKey: .schema)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decode(String.self, forKey: .title)
        summary = try c.decodeIfPresent(String.self, forKey: .summary)
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

/// YAML frontmatter as Claude Code writes it in agent/command files: top-level `key: value` pairs, multi-line
/// `|`/`>` blocks and `- item` lists. Not a YAML parser; just tolerant enough for hand-written files.
enum Frontmatter {
    /// Lowercased keys → raw values, and the body after the closing `---` (the whole text when there's no frontmatter).
    static func parse(_ text: String) -> (fields: [String: String], body: String) {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var fields: [String: String] = [:]
        guard lines.first?.trimmed == "---", let end = lines.dropFirst().firstIndex(where: { $0.trimmed == "---" }) else {
            return (fields, text)
        }
        var key: String?
        var buffer: [String] = []
        var block = false
        func flush() {
            if let key { fields[key] = block ? buffer.joined(separator: "\n").trimmed : buffer.joined(separator: " ").trimmed }
            buffer = []
        }
        for line in lines[1..<end] {
            let isTop = !(line.first?.isWhitespace ?? true) && !line.hasPrefix("-")
            if isTop, let colon = line.firstIndex(of: ":") {
                flush()
                key = String(line[..<colon]).trimmed.lowercased()
                let rest = String(line[line.index(after: colon)...]).trimmed
                block = rest == "|" || rest == ">" || rest == "|-" || rest == ">-"
                buffer = rest.isEmpty || block ? [] : [rest]
            } else {
                buffer.append(line.trimmed)
            }
        }
        flush()
        return (fields, lines[(end + 1)...].joined(separator: "\n"))
    }

    static func unquote(_ s: String) -> String {
        var s = s.trimmed
        if s.count >= 2, let f = s.first, f == s.last, f == "\"" || f == "'" { s = String(s.dropFirst().dropLast()) }
        return s
    }

    /// Non-empty, unquoted scalar.
    static func value(_ fields: [String: String], _ key: String) -> String? {
        fields[key].map(unquote)?.nonEmpty
    }

    /// Comma-, newline- or `- item`-separated list (`tools: Read, Grep` or a YAML list).
    static func list(_ fields: [String: String], _ key: String) -> [String] {
        (fields[key] ?? "")
            .split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { unquote(String($0).trimmingCharacters(in: CharacterSet(charactersIn: "- []"))) }
            .filter { !$0.isEmpty }
    }
}

/// Parses a Claude Code agent file: Markdown with YAML frontmatter (`name`, `description`, `model`, `tools`)
/// whose body is the system prompt. Tolerant of multi-line `|`/`>` descriptions and comma/list `tools`.
public enum ClaudeAgentFile {
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
            tools: Frontmatter.list(fields, "tools"),
            prompt: body.trimmed
        )
    }
}

// MARK: - Flow (JSON that orchestrates the AI)

/// A VibeDeck agent, command or skill resolved inside a flow.
public struct AgentFlowNode: Codable, Equatable, Sendable {
    public var kind: NextStepKind
    /// Slug of the VibeDeck agent/command/skill.
    public var ref: String
    public var title: String
    public var model: String?
    public var providerSettings: [String: AIProviderSettings]?
    /// Commands only: what goes in `$ARGUMENTS`.
    public var argumentHint: String?
    public var prompt: String
    public var next: [AgentFlowStep]
}

public struct AgentFlowStep: Codable, Equatable, Sendable {
    public var kind: NextStepKind
    public var ref: String
    public var note: String?
    /// Resolved agent/command/skill (nil for cycles already expanded above or missing refs).
    public var node: AgentFlowNode?
    public var warning: String?
}

public enum AgentFlow {
    public static func build(
        kind: NextStepKind = .agent, from slug: String,
        agents: [(slug: String, agent: Agent)], commands: [(slug: String, command: Command)] = [],
        skills: [(slug: String, skill: Skill)] = []
    ) -> AgentFlowNode? {
        let agentIndex = Dictionary(agents.map { ($0.slug, $0.agent) }, uniquingKeysWith: { a, _ in a })
        let commandIndex = Dictionary(commands.map { ($0.slug, $0.command) }, uniquingKeysWith: { a, _ in a })
        let skillIndex = Dictionary(skills.map { ($0.slug, $0.skill) }, uniquingKeysWith: { a, _ in a })
        func key(_ kind: NextStepKind, _ ref: String) -> String { "\(kind.rawValue):\(ref)" }
        func node(_ kind: NextStepKind, _ slug: String, path: Set<String>) -> AgentFlowNode? {
            let base: (title: String, model: String?, settings: [String: AIProviderSettings]?, hint: String?, prompt: String, next: [NextStep])
            switch kind {
            case .agent:
                guard let a = agentIndex[slug] else { return nil }
                base = (a.title, a.model, a.providerSettings, nil, a.prompt, a.nextSteps)
            case .command:
                guard let c = commandIndex[slug] else { return nil }
                base = (c.title, c.model, c.providerSettings, c.argumentHint, c.prompt, c.nextSteps)
            case .skill:
                guard let s = skillIndex[slug] else { return nil }
                base = (s.title, s.model, s.providerSettings, nil, s.prompt, s.nextSteps)
            }
            let here = path.union([key(kind, slug)])
            let steps = base.next.map { step -> AgentFlowStep in
                var out = AgentFlowStep(kind: step.kind, ref: step.ref, note: step.note, node: nil, warning: nil)
                if here.contains(key(step.kind, step.ref)) {
                    out.warning = "Ciclo: \(step.ref) já está neste fluxo."
                } else if let n = node(step.kind, step.ref, path: here) {
                    out.node = n
                } else {
                    out.warning = switch step.kind {
                    case .agent: "Agente não encontrado: \(step.ref)"
                    case .command: "Comando não encontrado: \(step.ref)"
                    case .skill: "Skill não encontrada: \(step.ref)"
                    }
                }
                return out
            }
            return AgentFlowNode(kind: kind, ref: slug, title: base.title, model: base.model, providerSettings: base.settings, argumentHint: base.hint, prompt: base.prompt, next: steps)
        }
        return node(kind, slug, path: [])
    }

    /// Pretty JSON of the flow, meant to be pasted into / sent in a prompt.
    public static func json(
        kind: NextStepKind = .agent, from slug: String,
        agents: [(slug: String, agent: Agent)], commands: [(slug: String, command: Command)] = [],
        skills: [(slug: String, skill: Skill)] = []
    ) throws -> String? {
        guard let node = build(kind: kind, from: slug, agents: agents, commands: commands, skills: skills) else { return nil }
        return String(decoding: try VDJSON.encode(node), as: UTF8.self)
    }
}
