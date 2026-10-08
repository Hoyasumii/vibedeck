import Foundation

// MARK: - Agents

public enum NextStepKind: String, Codable, CaseIterable, Sendable {
    case agent, command
}

/// Link in a flow: after this agent runs, another VibeDeck agent (or, later, command) acts on its result.
public struct NextStep: Codable, Equatable, Sendable {
    public var kind: NextStepKind
    /// Slug of a VibeDeck agent (or command), never of the AI provider's.
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
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var fields: [String: String] = [:]
        var body = text

        if lines.first?.trimmed == "---", let end = lines.dropFirst().firstIndex(where: { $0.trimmed == "---" }) {
            body = lines[(end + 1)...].joined(separator: "\n")
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
        }

        func unquote(_ s: String) -> String {
            var s = s.trimmed
            if s.count >= 2, let f = s.first, f == s.last, f == "\"" || f == "'" { s = String(s.dropFirst().dropLast()) }
            return s
        }
        let tools = (fields["tools"] ?? "")
            .split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { unquote(String($0).trimmingCharacters(in: CharacterSet(charactersIn: "- []"))) }
            .filter { !$0.isEmpty }
        return Parsed(
            name: fields["name"].map(unquote)?.nonEmpty ?? fallbackName,
            description: fields["description"].map(unquote)?.nonEmpty,
            model: fields["model"].map(unquote)?.nonEmpty,
            tools: tools,
            prompt: body.trimmed
        )
    }
}

// MARK: - Flow (JSON that orchestrates the AI)

public struct AgentFlowNode: Codable, Equatable, Sendable {
    public var agent: String
    public var title: String
    public var model: String?
    public var prompt: String
    public var next: [AgentFlowStep]
}

public struct AgentFlowStep: Codable, Equatable, Sendable {
    public var kind: NextStepKind
    public var ref: String
    public var note: String?
    /// Resolved agent (nil for commands, cycles already expanded above, or missing refs).
    public var node: AgentFlowNode?
    public var warning: String?
}

public enum AgentFlow {
    public static func build(from slug: String, agents: [(slug: String, agent: Agent)]) -> AgentFlowNode? {
        let index = Dictionary(uniqueKeysWithValues: agents.map { ($0.slug, $0.agent) })
        func node(_ slug: String, path: [String]) -> AgentFlowNode? {
            guard let a = index[slug] else { return nil }
            let steps = a.nextSteps.map { step -> AgentFlowStep in
                var out = AgentFlowStep(kind: step.kind, ref: step.ref, note: step.note, node: nil, warning: nil)
                switch step.kind {
                case .command: out.warning = "Comandos ainda não são executáveis."
                case .agent:
                    if path.contains(step.ref) || step.ref == slug { out.warning = "Ciclo: \(step.ref) já está neste fluxo." }
                    else if let n = node(step.ref, path: path + [slug]) { out.node = n }
                    else { out.warning = "Agente não encontrado: \(step.ref)" }
                }
                return out
            }
            return AgentFlowNode(agent: slug, title: a.title, model: a.model, prompt: a.prompt, next: steps)
        }
        return node(slug, path: [])
    }

    /// Pretty JSON of the flow, meant to be pasted into / sent in a prompt.
    public static func json(from slug: String, agents: [(slug: String, agent: Agent)]) throws -> String? {
        guard let node = build(from: slug, agents: agents) else { return nil }
        return String(decoding: try VDJSON.encode(node), as: UTF8.self)
    }
}
