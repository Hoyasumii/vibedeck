import Foundation

/// "Descubra" in a rule topic or an idea: asks the AI provider, with read-only tools, for the globs and tags of the
/// subject and then interviews the user to draft rules. Every answer becomes a proposal the user accepts item by
/// item; nothing here writes. `RuleDiscoverScope.apply` / `RuleDiscoverDrafts.apply` are the only way in.
public enum RuleDiscover {
    /// Same read-only tool set as the review Descubra (Read/Grep/Glob, no Edit/Write/Bash).
    public static let tools = ReviewDiscover.tools
    /// Questions shown per interview round; extra ones are dropped.
    public static let maxQuestions = 4
    /// Rounds of questions before the next call is forced to generate rules.
    public static let maxRounds = 3
    /// Files scanned when checking that a glob matches something.
    public static let fileLimit = 20000

    /// What the Descubra works on: a topic or an idea, read when the call starts.
    public struct Subject: Equatable, Sendable {
        public enum Kind: String, Sendable { case topic, idea }

        public var kind: Kind
        public var title: String
        public var description: String?
        public var paths: [String]
        public var tags: [String]
        public var rules: [Rule]

        public init(topic: RuleTopic) {
            self.init(kind: .topic, title: topic.title, description: topic.description, paths: topic.paths, tags: topic.tags, rules: topic.rules)
        }

        public init(idea: Idea) {
            self.init(kind: .idea, title: idea.title, description: idea.body, paths: idea.paths, tags: idea.tags, rules: idea.rules)
        }

        public init(kind: Kind, title: String, description: String?, paths: [String], tags: [String], rules: [Rule]) {
            self.kind = kind
            self.title = title
            self.description = description
            self.paths = paths
            self.tags = tags
            self.rules = rules
        }
    }

    /// Existing rules elsewhere in the project, to avoid duplicates and conflicts.
    public struct KnownTopic: Equatable, Sendable {
        public var slug: String
        public var title: String
        public var rules: [String]

        public init(slug: String, title: String, rules: [String]) {
            self.slug = slug
            self.title = title
            self.rules = rules
        }
    }

    public struct Suggestion: Decodable, Equatable, Sendable {
        public var value: String
        public var reason: String

        public init(value: String, reason: String) {
            self.value = value
            self.reason = reason
        }
    }

    // MARK: Scope (globs + tags)

    public struct ScopeAnswer: Decodable, Equatable, Sendable {
        public var paths: [Suggestion]
        public var tags: [Suggestion]

        public init(paths: [Suggestion] = [], tags: [Suggestion] = []) {
            self.paths = paths
            self.tags = tags
        }

        enum CodingKeys: String, CodingKey { case paths, tags }
        enum ItemKeys: String, CodingKey { case glob, tag, reason }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            paths = try Self.items(c, .paths, key: .glob)
            tags = try Self.items(c, .tags, key: .tag)
        }

        private static func items(_ c: KeyedDecodingContainer<CodingKeys>, _ field: CodingKeys, key: ItemKeys) throws -> [Suggestion] {
            var list = try c.nestedUnkeyedContainer(forKey: field)
            var out: [Suggestion] = []
            while !list.isAtEnd {
                let item = try list.nestedContainer(keyedBy: ItemKeys.self)
                out.append(Suggestion(value: try item.decode(String.self, forKey: key), reason: try item.decodeIfPresent(String.self, forKey: .reason) ?? ""))
            }
            return out
        }
    }

    public static let scopeSchema = #"""
    {"type":"object","properties":{"paths":{"type":"array","items":{"type":"object","properties":{"glob":{"type":"string"},"reason":{"type":"string"}},"required":["glob","reason"]}},"tags":{"type":"array","items":{"type":"object","properties":{"tag":{"type":"string"},"reason":{"type":"string"}},"required":["tag","reason"]}}},"required":["paths","tags"]}
    """#

    public static func scopePrompt(_ subject: Subject, vocabulary: [String], topics: [KnownTopic]) -> String {
        var lines = header(subject) + ["", "## Tags existentes no projeto", vocabulary.isEmpty ? "(nenhuma)" : vocabulary.joined(separator: ", ")]
        lines += known(topics)
        lines += [
            "",
            "## Tarefa",
            "Leia o repositório (o diretório atual) só com leitura e busca e sugira o escopo deste \(noun(subject)). Não altere nada.",
            "- paths: globs relativos à raiz que cobrem os arquivos onde estas regras valem. Cada glob precisa casar ao menos",
            "  um arquivo que existe. Nada de catch-all (`*`, `**`, `**/*`). Prefira poucos globs específicos. Omita os atuais.",
            "- tags: prefira as tags existentes acima; só invente uma tag nova se nenhuma servir. Omita as atuais.",
            "- reason: uma frase curta com a evidência (ex.: Sources/App/View.swift:42).",
            "Se não encontrar nada, devolva listas vazias.",
        ]
        return lines.joined(separator: "\n")
    }

    /// Keeps globs that aren't catch-all, aren't on the subject yet and match a project file; tags not on the
    /// subject, marking the ones outside the vocabulary as new.
    public static func scope(_ answer: ScopeAnswer, subject: Subject, vocabulary: [String], files: [String]) -> RuleDiscoverScope {
        var scope = RuleDiscoverScope()
        for suggestion in answer.paths {
            let glob = suggestion.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !glob.isEmpty, !subject.paths.contains(glob), !scope.paths.contains(where: { $0.glob == glob }) else { continue }
            if isCatchAll(glob) {
                scope.discarded.append("Glob amplo demais: \(glob)")
                continue
            }
            let matches = files.filter { Glob.matches(glob, path: $0) }.count
            guard matches > 0 else {
                scope.discarded.append("Glob não casa nenhum arquivo: \(glob)")
                continue
            }
            scope.paths.append(.init(glob: glob, matches: matches, reason: suggestion.reason.trimmed.nonEmpty))
        }
        let current = Set(subject.tags.map(normalizedTag))
        for suggestion in answer.tags {
            let tag = suggestion.value.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            guard !tag.isEmpty, !current.contains(normalizedTag(tag)), !scope.tags.contains(where: { normalizedTag($0.tag) == normalizedTag(tag) }) else { continue }
            let known = vocabulary.first { normalizedTag($0) == normalizedTag(tag) }
            scope.tags.append(.init(tag: known ?? tag, isNew: known == nil, reason: suggestion.reason.trimmed.nonEmpty))
        }
        return scope
    }

    /// A glob that covers (nearly) everything: only `*`, `/` and `.`.
    public static func isCatchAll(_ glob: String) -> Bool {
        glob.allSatisfy { "*/.".contains($0) }
    }

    /// Project files (no folders, build or dependency output) the globs are checked against.
    public static func projectFiles(root: URL) -> [String] {
        ClaudeCompletion.projectFiles(root: root, limit: fileLimit).filter { !$0.hasSuffix("/") }
    }

    // MARK: Interview (questions → rules)

    public struct Question: Equatable, Identifiable, Sendable {
        public var id: Int
        public var text: String
        public var options: [String]

        public init(id: Int, text: String, options: [String] = []) {
            self.id = id
            self.text = text
            self.options = options
        }
    }

    /// A question asked in an earlier round and what the user answered (empty = skipped).
    public struct Exchange: Equatable, Sendable {
        public var question: String
        public var answer: String

        public init(question: String, answer: String) {
            self.question = question
            self.answer = answer
        }
    }

    public enum Relation: String, Decodable, Sendable { case none, duplicate, conflict }

    public struct RuleSuggestion: Decodable, Equatable, Sendable {
        public var text: String
        public var details: String
        public var severity: RuleSeverity
        public var reason: String
        /// Existing rule this one duplicates or conflicts with (text), when `relation` isn't `none`.
        public var related: String
        public var relation: Relation

        public init(text: String, details: String = "", severity: RuleSeverity = .must, reason: String = "", related: String = "", relation: Relation = .none) {
            self.text = text
            self.details = details
            self.severity = severity
            self.reason = reason
            self.related = related
            self.relation = relation
        }
    }

    public struct InterviewAnswer: Decodable, Equatable, Sendable {
        struct RawQuestion: Decodable, Equatable, Sendable {
            var text: String
            var options: [String]
        }

        var rawQuestions: [RawQuestion]
        public var rules: [RuleSuggestion]

        enum CodingKeys: String, CodingKey { case rawQuestions = "questions", rules }

        public init(questions: [String] = [], rules: [RuleSuggestion] = []) {
            rawQuestions = questions.map { RawQuestion(text: $0, options: []) }
            self.rules = rules
        }

        /// Non-empty questions, at most `maxQuestions`.
        public var questions: [Question] {
            rawQuestions.compactMap { q in q.text.trimmed.nonEmpty.map { ($0, q.options.compactMap { $0.trimmed.nonEmpty }) } }
                .prefix(maxQuestions).enumerated().map { Question(id: $0.offset, text: $0.element.0, options: $0.element.1) }
        }
    }

    public static let interviewSchema = #"""
    {"type":"object","properties":{"questions":{"type":"array","items":{"type":"object","properties":{"text":{"type":"string"},"options":{"type":"array","items":{"type":"string"}}},"required":["text","options"]}},"rules":{"type":"array","items":{"type":"object","properties":{"text":{"type":"string"},"details":{"type":"string"},"severity":{"type":"string","enum":["must","should"]},"reason":{"type":"string"},"related":{"type":"string"},"relation":{"type":"string","enum":["none","duplicate","conflict"]}},"required":["text","details","severity","reason","related","relation"]}}},"required":["questions","rules"]}
    """#

    /// One interview call. `finish` (the user asked to generate, or the round limit was hit) forbids new questions.
    public static func interviewPrompt(_ subject: Subject, topics: [KnownTopic], history: [Exchange], finish: Bool) -> String {
        var lines = header(subject)
        lines.append("Regras atuais:" + (subject.rules.isEmpty ? " (nenhuma)" : ""))
        lines += subject.rules.map { "- [\($0.severity.rawValue)] \($0.text)" }
        lines += known(topics)
        if !history.isEmpty {
            lines += ["", "## Entrevista até agora"]
            for exchange in history {
                lines.append("P: \(exchange.question)")
                lines.append("R: \(exchange.answer.trimmed.nonEmpty ?? "(sem resposta)")")
            }
        }
        lines += [
            "",
            "## Tarefa",
            "Você está ajudando a escrever regras para este \(noun(subject)). Leia o repositório só com leitura e busca. Não altere nada.",
        ]
        if finish {
            lines.append("Não faça mais perguntas (questions vazio): gere as regras com o que já tem.")
        } else {
            lines += [
                "Se faltar informação para regras boas, faça até \(maxQuestions) perguntas curtas (questions), com opções de",
                "resposta quando fizer sentido, e deixe rules vazio. Se já der para escrever, devolva questions vazio e as regras.",
            ]
        }
        lines += [
            "- Cada regra é atômica e verificável: um comportamento por regra, sem termos vagos.",
            "- severity: must (bloqueia) ou should (só avisa). details: como verificar (pode ser vazio).",
            "- Não repita as regras atuais. Se uma regra duplica ou conflita com uma existente (deste \(noun(subject)) ou dos",
            "  tópicos acima), preencha relation (duplicate/conflict) e related com o texto da existente; senão relation none e related vazio.",
            "- reason: uma frase curta com a evidência (arquivo:linha ou a regra existente que motivou).",
        ]
        return lines.joined(separator: "\n")
    }

    /// Drops empty and repeated rules and flags duplicates of existing rules the AI didn't flag itself.
    public static func drafts(_ answer: InterviewAnswer, subject: Subject, topics: [KnownTopic]) -> RuleDiscoverDrafts {
        var drafts = RuleDiscoverDrafts()
        let existing = subject.rules.map(\.text) + topics.flatMap(\.rules)
        var seen = Set<String>()
        for suggestion in answer.rules {
            guard let text = suggestion.text.trimmed.nonEmpty, seen.insert(normalizedRule(text)).inserted else { continue }
            var relation = suggestion.relation
            var related = suggestion.related.trimmed.nonEmpty
            if relation == .none, let same = existing.first(where: { normalizedRule($0) == normalizedRule(text) }) {
                relation = .duplicate
                related = same
            }
            if relation == .none { related = nil }
            drafts.rules.append(.init(text: text, details: suggestion.details.trimmed.nonEmpty, severity: suggestion.severity,
                                      reason: suggestion.reason.trimmed.nonEmpty, relation: relation, related: related))
        }
        return drafts
    }

    // MARK: Description (+ viability for ideas)

    public struct DescriptionAnswer: Decodable, Equatable, Sendable {
        public var description: String
        public var reason: String
        public var viable: Bool
        public var missing: [String]

        public init(description: String, reason: String = "", viable: Bool = false, missing: [String] = []) {
            self.description = description
            self.reason = reason
            self.viable = viable
            self.missing = missing
        }

        enum CodingKeys: String, CodingKey { case description, reason, viable, missing }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
            reason = try c.decodeIfPresent(String.self, forKey: .reason) ?? ""
            viable = try c.decodeIfPresent(Bool.self, forKey: .viable) ?? false
            missing = try c.decodeIfPresent([String].self, forKey: .missing) ?? []
        }
    }

    public static let descriptionSchema = #"""
    {"type":"object","properties":{"description":{"type":"string"},"reason":{"type":"string"},"viable":{"type":"boolean"},"missing":{"type":"array","items":{"type":"string"}}},"required":["description","reason","viable","missing"]}
    """#

    /// Rewrites the description with what the Descubra gathered (globs, tags, rules, interview). For an idea it also
    /// judges whether it's ready to implement.
    public static func descriptionPrompt(_ subject: Subject, topics: [KnownTopic], history: [Exchange]) -> String {
        var lines = header(subject)
        lines.append("Regras atuais:" + (subject.rules.isEmpty ? " (nenhuma)" : ""))
        lines += subject.rules.map { rule in
            "- [\(rule.severity.rawValue)] \(rule.text)" + (rule.details?.trimmed.nonEmpty.map { " — \($0)" } ?? "")
        }
        lines += known(topics)
        if !history.isEmpty {
            lines += ["", "## Entrevista"]
            for exchange in history {
                lines.append("P: \(exchange.question)")
                lines.append("R: \(exchange.answer.trimmed.nonEmpty ?? "(sem resposta)")")
            }
        }
        lines += [
            "",
            "## Tarefa",
            "Leia o repositório só com leitura e busca. Não altere nada.",
        ]
        if subject.kind == .idea {
            lines += [
                "- description: reescreva a descrição desta ideia em markdown, pronta para pedir a uma IA que implemente.",
                "  Preserve tudo o que já está na descrição atual (inclusive links e imagens de anexos), sem inventar requisitos.",
                "  Incorpore as respostas da entrevista, os globs, as tags e as regras. Organize em seções curtas:",
                "  Problema, Proposta, Escopo (arquivos/telas afetados, com caminhos reais) e Critérios de aceite.",
                "- reason: uma frase curta dizendo o que mudou na descrição.",
                "- viable: true só se, depois de ler o código, a descrição nova + as regras bastam para um agente implementar",
                "  sem decisões de produto em aberto. Ideia vaga, sem regras ou com dúvidas fundamentais é false.",
                "- missing: as lacunas concretas que impedem implementar (vazio quando viable é true).",
            ]
        } else {
            lines += [
                "- description: uma ou duas frases, texto simples, dizendo quando este tópico se aplica, coerente com os",
                "  globs, as tags, as regras e a entrevista. Preserve o sentido da descrição atual.",
                "- reason: uma frase curta dizendo o que mudou na descrição.",
                "- viable: false e missing vazio (não se aplica a tópicos).",
            ]
        }
        return lines.joined(separator: "\n")
    }

    /// Normalizes the answer; `suggested` is nil when the text equals the current description.
    public static func description(_ answer: DescriptionAnswer, subject: Subject) -> RuleDiscoverDescription {
        let current = subject.description?.trimmed.nonEmpty
        let text = answer.description.trimmed.nonEmpty
        let isIdea = subject.kind == .idea
        return RuleDiscoverDescription(
            current: current,
            suggested: text == current ? nil : text,
            reason: answer.reason.trimmed.nonEmpty,
            viable: isIdea && answer.viable && !subject.rules.isEmpty,
            missing: isIdea ? answer.missing.compactMap { $0.trimmed.nonEmpty } : []
        )
    }

    // MARK: Prompt pieces

    private static func noun(_ subject: Subject) -> String {
        subject.kind == .topic ? "tópico de regras" : "rascunho de ideia"
    }

    private static func header(_ subject: Subject) -> [String] {
        var lines = [
            "Você está ajudando no VibeDeck, neste repositório (o diretório atual).",
            "",
            subject.kind == .topic ? "## Tópico de regras" : "## Ideia (regras rascunho, só valem depois de promovidas)",
            "Título: \(subject.title)",
        ]
        if let description = subject.description?.trimmed.nonEmpty { lines.append("Descrição: \(description)") }
        lines.append("Globs atuais: " + (subject.paths.isEmpty ? "(nenhum; vale para toda tarefa)" : subject.paths.joined(separator: ", ")))
        lines.append("Tags atuais: " + (subject.tags.isEmpty ? "(nenhuma)" : subject.tags.joined(separator: ", ")))
        return lines
    }

    private static func known(_ topics: [KnownTopic]) -> [String] {
        guard !topics.isEmpty else { return [] }
        var lines = ["", "## Outros tópicos de regras do projeto"]
        for topic in topics {
            lines.append("- \(topic.slug): \(topic.title)")
            lines += topic.rules.map { "  - \($0)" }
        }
        return lines
    }

    static func normalizedTag(_ tag: String) -> String {
        tag.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).trimmingCharacters(in: .whitespaces)
    }

    static func normalizedRule(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == " " }
            .map(String.init).joined()
            .split(separator: " ").joined(separator: " ")
    }
}

/// Validated globs and tags waiting for the user's choice.
public struct RuleDiscoverScope: Equatable, Sendable {
    public struct PathAddition: Equatable, Identifiable, Sendable {
        public var glob: String
        /// Project files the glob matches now.
        public var matches: Int
        public var reason: String?
        public var id: String { glob }
    }

    public struct TagAddition: Equatable, Identifiable, Sendable {
        public var tag: String
        /// Not in the project's vocabulary yet: starts unchecked.
        public var isNew: Bool
        public var reason: String?
        public var id: String { tag }
    }

    public var paths: [PathAddition] = []
    public var tags: [TagAddition] = []
    /// Suggestions dropped by validation, shown so the user knows they existed.
    public var discarded: [String] = []

    public init() {}

    public var isEmpty: Bool { paths.isEmpty && tags.isEmpty }

    /// Tags that start checked: the ones already in the vocabulary. A new tag needs an explicit check.
    public var defaultTags: Set<String> { Set(tags.filter { !$0.isNew }.map(\.tag)) }

    /// Appends the chosen globs and tags; existing ones are never removed.
    public func apply(paths chosenPaths: Set<String>, tags chosenTags: Set<String>, to current: inout [String], tags currentTags: inout [String]) {
        for path in paths where chosenPaths.contains(path.glob) && !current.contains(path.glob) { current.append(path.glob) }
        for tag in tags where chosenTags.contains(tag.tag) && !currentTags.contains(tag.tag) { currentTags.append(tag.tag) }
    }
}

/// Rules drafted by the interview waiting for the user's choice.
public struct RuleDiscoverDrafts: Equatable, Sendable {
    public struct Draft: Equatable, Identifiable, Sendable {
        public var id = UUID()
        public var text: String
        public var details: String?
        public var severity: RuleSeverity
        public var reason: String?
        public var relation: RuleDiscover.Relation
        /// Text of the existing rule it duplicates or conflicts with.
        public var related: String?

        public init(text: String, details: String? = nil, severity: RuleSeverity, reason: String? = nil, relation: RuleDiscover.Relation = .none, related: String? = nil) {
            self.text = text
            self.details = details
            self.severity = severity
            self.reason = reason
            self.relation = relation
            self.related = related
        }
    }

    public var rules: [Draft] = []

    public init() {}

    public var isEmpty: Bool { rules.isEmpty }

    /// Drafts that start checked: the ones not flagged as duplicate or conflict.
    public var defaultRules: Set<UUID> { Set(rules.filter { $0.relation == .none }.map(\.id)) }

    /// Appends the chosen drafts as AI-authored rules (to `idea.rules` they stay drafts until promotion).
    public func apply(_ chosen: Set<UUID>, to current: inout [Rule], now: Date = .now) {
        for draft in rules where chosen.contains(draft.id) {
            current.append(Rule(text: draft.text, details: draft.details, severity: draft.severity, author: .ai, now: now))
        }
    }
}

/// Rewritten description (and, for ideas, the viability verdict) waiting for the user's choice.
public struct RuleDiscoverDescription: Equatable, Sendable {
    public var current: String?
    /// New text; nil when the AI kept the current one.
    public var suggested: String?
    public var reason: String?
    public var viable: Bool
    public var missing: [String]

    public init(current: String? = nil, suggested: String? = nil, reason: String? = nil, viable: Bool = false, missing: [String] = []) {
        self.current = current
        self.suggested = suggested
        self.reason = reason
        self.viable = viable
        self.missing = missing
    }

    /// Replaces the description with the suggestion (no-op when there's none).
    public func apply(to description: inout String?) {
        if let suggested { description = suggested }
    }

    /// The verdict for `idea` as it is now (call after applying, or not, the description). The AI judged the new text:
    /// keeping the old one when there was a suggestion doesn't count as viable.
    public func readiness(for idea: Idea, acceptedDescription: Bool, now: Date = .now) -> IdeaReadiness {
        let rejected = suggested != nil && !acceptedDescription
        let missing = rejected && viable ? ["A descrição nova sugerida pela IA não foi aceita"] : missing
        return IdeaReadiness(viable: viable && !rejected && !idea.rules.isEmpty, missing: missing, checkedAt: now, fingerprint: idea.contentFingerprint)
    }
}
