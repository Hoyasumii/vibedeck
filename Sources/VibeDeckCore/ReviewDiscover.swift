import Foundation

/// "Descubra" in a review item: asks Claude Code, with read-only tools, where the item lives in the code and
/// which rule topics it touches, then turns the answer into a proposal the user accepts field by field.
/// Nothing here writes: `ReviewDiscoverProposal.apply` is the only way the answer reaches an item.
public enum ReviewDiscover {
    /// Tools the call may use. Anything else (Edit, Write, Bash, MCP servers) is unavailable.
    public static let tools = ["Read", "Grep", "Glob"]

    public static let timeout: Duration = .seconds(180)

    public enum Field: String, CaseIterable, Codable, Sendable {
        case file, route, component, selector

        public var label: String {
            switch self {
            case .file: "Arquivo"
            case .route: "Rota / tela"
            case .component: "Componente"
            case .selector: "Seletor"
            }
        }

        public var keyPath: WritableKeyPath<ReviewTarget, String?> {
            switch self {
            case .file: \.file
            case .route: \.route
            case .component: \.component
            case .selector: \.selector
            }
        }
    }

    /// What Claude answers, enforced by `--json-schema`.
    public struct Answer: Decodable, Equatable, Sendable {
        public struct FieldSuggestion: Decodable, Equatable, Sendable {
            public var field: Field
            public var value: String
            public var reason: String?
        }

        public struct TopicSuggestion: Decodable, Equatable, Sendable {
            public var slug: String
            public var reason: String?
        }

        public var fields: [FieldSuggestion]
        public var rules: [TopicSuggestion]

        public init(fields: [FieldSuggestion] = [], rules: [TopicSuggestion] = []) {
            self.fields = fields
            self.rules = rules
        }

        enum CodingKeys: String, CodingKey { case fields, rules }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            fields = try c.decodeIfPresent([FieldSuggestion].self, forKey: .fields) ?? []
            rules = try c.decodeIfPresent([TopicSuggestion].self, forKey: .rules) ?? []
        }
    }

    public static let schema = #"""
    {"type":"object","properties":{"fields":{"type":"array","items":{"type":"object","properties":{"field":{"type":"string","enum":["file","route","component","selector"]},"value":{"type":"string"},"reason":{"type":"string"}},"required":["field","value","reason"]}},"rules":{"type":"array","items":{"type":"object","properties":{"slug":{"type":"string"},"reason":{"type":"string"}},"required":["slug","reason"]}}},"required":["fields","rules"]}
    """#

    // MARK: Launch

    /// `claude -p` arguments; the prompt goes on stdin (the variadic `--tools` would swallow a trailing one).
    /// `--strict-mcp-config` without a config leaves out every MCP server, the project's own included.
    public static func arguments() -> [String] {
        let tools = tools.joined(separator: ",")
        return [
            "-p", "--output-format", "json", "--json-schema", schema,
            "--tools", tools, "--allowedTools", tools,
            "--strict-mcp-config", "--no-session-persistence",
        ]
    }

    /// Topics worth suggesting: global ones, linked ones and those matching the item's file already apply.
    public static func candidateTopics(_ topics: [(slug: String, topic: RuleTopic)], item: ReviewItem) -> [(slug: String, topic: RuleTopic)] {
        topics.filter { slug, topic in
            !topic.isGlobal && !item.rules.contains(slug) && !(item.target?.file.map(topic.matches(file:)) ?? false)
        }
    }

    public static func prompt(item: ReviewItem, kind: String, topics: [(slug: String, topic: RuleTopic)]) -> String {
        var lines = [
            "Você está preenchendo um item de revisão do VibeDeck neste repositório (o diretório atual).",
            "Use Read, Grep e Glob para encontrar no código onde o item se aplica. Não altere nada.",
            "",
            "## Item",
            "Título: \(item.title)",
            "Tipo: \(kind)",
        ]
        if let details = item.details, !details.isEmpty { lines.append("Detalhes: \(details)") }
        let current = Field.allCases.compactMap { field in item.target?[keyPath: field.keyPath].map { "\(field.rawValue) = \($0)" } }
        lines.append("Onde atual: " + (current.isEmpty ? "(vazio)" : current.joined(separator: "; ")))
        lines += ["", "## Tópicos de regras disponíveis"]
        if topics.isEmpty { lines.append("(nenhum)") }
        for (slug, topic) in topics {
            var line = "- \(slug): \(topic.title)"
            if let description = topic.description, !description.isEmpty { line += " — \(description)" }
            line += " (paths: \(topic.paths.joined(separator: ", ")))"
            lines.append(line)
        }
        lines += [
            "",
            "## Resposta",
            "- fields: só os campos que você encontrou de verdade (file, route, component, selector).",
            "  file é um caminho relativo à raiz de um arquivo que existe. Não invente; se não achou, omita.",
            "- rules: slugs da lista acima que o item deve seguir. Só slugs da lista.",
            "- reason: uma frase curta dizendo onde encontrou (ex.: Sources/App/View.swift:42).",
        ]
        return lines.joined(separator: "\n")
    }

    // MARK: Output

    /// Reads the `--output-format json` result from stdout. Throws without touching anything when the call
    /// failed or the answer doesn't decode.
    public static func parse(_ output: Data) throws -> Answer {
        let text = String(decoding: output, as: UTF8.self)
        let result = text.split(whereSeparator: \.isNewline).reversed().lazy
            .compactMap { try? JSONDecoder().decode(JSONValue.self, from: Data($0.utf8)) }
            .first { $0["type"]?.string == "result" }
        guard let result else { throw VibeDeckError.discoverInvalidAnswer }
        if result["is_error"]?.bool == true || result["subtype"]?.string != "success" {
            let message = [result["result"]?.string, result["subtype"]?.string].compactMap { $0 }.first { !$0.isEmpty } ?? ""
            throw VibeDeckError.discoverFailed(message)
        }
        let structured: Data? = if let value = result["structured_output"], value != .null {
            try? JSONEncoder().encode(value)
        } else {
            result["result"]?.string.map { Data($0.utf8) }
        }
        guard let structured, let answer = try? JSONDecoder().decode(Answer.self, from: structured) else {
            throw VibeDeckError.discoverInvalidAnswer
        }
        return answer
    }

    /// Keeps only what can be applied safely: existing files inside the project, known topic slugs not
    /// already on the item, and values that differ from the current ones.
    public static func proposal(
        _ answer: Answer, item: ReviewItem, topics: [(slug: String, topic: RuleTopic)], store: ProjectStore
    ) -> ReviewDiscoverProposal {
        var proposal = ReviewDiscoverProposal()
        var seen = Set<Field>()
        for suggestion in answer.fields {
            var value = suggestion.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, !seen.contains(suggestion.field) else { continue }
            if suggestion.field == .file {
                guard let file = existingFile(value, store: store) else {
                    proposal.discarded.append("Arquivo não encontrado no projeto: \(value)")
                    continue
                }
                value = file
            }
            let current = item.target?[keyPath: suggestion.field.keyPath]
            seen.insert(suggestion.field)
            guard value != current else { continue }
            proposal.fields.append(.init(field: suggestion.field, current: current, suggested: value, reason: suggestion.reason))
        }
        let candidates = candidateTopics(topics, item: item)
        var added = Set<String>()
        for suggestion in answer.rules {
            guard let match = candidates.first(where: { $0.slug == suggestion.slug }) else {
                if !item.rules.contains(suggestion.slug), !topics.contains(where: { $0.slug == suggestion.slug }) {
                    proposal.discarded.append("Tópico de regras inexistente: \(suggestion.slug)")
                }
                continue
            }
            guard added.insert(match.slug).inserted else { continue }
            proposal.topics.append(.init(slug: match.slug, title: match.topic.title, reason: suggestion.reason))
        }
        return proposal
    }

    /// Project-relative path of a regular file inside the project, or nil.
    static func existingFile(_ path: String, store: ProjectStore) -> String? {
        let relative = store.relativePath(path)
        guard !relative.hasPrefix("/") else { return nil }
        let url = store.root.appending(path: relative).standardizedFileURL
        let rootPath = store.root.path.hasSuffix("/") ? store.root.path : store.root.path + "/"
        guard url.path.hasPrefix(rootPath) else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else { return nil }
        return String(url.path.dropFirst(rootPath.count))
    }
}

/// Validated suggestions waiting for the user's choice.
public struct ReviewDiscoverProposal: Equatable, Sendable {
    public struct FieldChange: Equatable, Identifiable, Sendable {
        public var field: ReviewDiscover.Field
        /// Value the item has now; non-nil means accepting replaces it.
        public var current: String?
        public var suggested: String
        public var reason: String?
        public var id: ReviewDiscover.Field { field }
        public var replaces: Bool { current != nil }
    }

    public struct TopicAddition: Equatable, Identifiable, Sendable {
        public var slug: String
        public var title: String
        public var reason: String?
        public var id: String { slug }
    }

    public var fields: [FieldChange] = []
    public var topics: [TopicAddition] = []
    /// Suggestions dropped by validation, shown so the user knows they existed.
    public var discarded: [String] = []

    public init() {}

    public var isEmpty: Bool { fields.isEmpty && topics.isEmpty }

    /// Fields that start checked: empty ones. Replacing a value is opt-in.
    public var defaultFields: Set<ReviewDiscover.Field> { Set(fields.filter { !$0.replaces }.map(\.field)) }

    /// Writes the chosen fields and appends the chosen topics. Topics are only ever added.
    public func apply(fields chosen: Set<ReviewDiscover.Field>, topics chosenTopics: Set<String>, to item: inout ReviewItem) {
        var target = item.target ?? ReviewTarget()
        for change in fields where chosen.contains(change.field) {
            target[keyPath: change.field.keyPath] = change.suggested
        }
        item.target = target.isEmpty ? nil : target
        for topic in topics where chosenTopics.contains(topic.slug) && !item.rules.contains(topic.slug) {
            item.rules.append(topic.slug)
        }
    }
}
