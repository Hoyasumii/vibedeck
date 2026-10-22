import Foundation

/// "Descubra" in a rule topic or an idea: asks the AI provider, with read-only tools, for the globs of the subject,
/// interviews the user to draft rules and, last, rewrites the description and suggests tags. The user may give an
/// opening context first. Every answer becomes a proposal the user accepts item by item; nothing here writes. `RuleDiscoverScope.apply` / `RuleDiscoverDrafts.apply` are the only way in.
enum RuleDiscover {
    /// Same read-only tool set as the review Descubra (Read/Grep/Glob, no Edit/Write/Bash).
    static let tools = ReviewDiscover.tools
    /// Questions shown per interview round; extra ones are dropped.
    static let maxQuestions = 4
    /// Rounds of questions before the next call is forced to generate rules.
    static let maxRounds = 3
    /// Files scanned when checking that a glob matches something.
    static let fileLimit = 20000

    /// What the Descubra works on: a topic or an idea, read when the call starts.
    struct Subject: Equatable, Sendable {
        enum Kind: String, Sendable { case topic, idea }

        var kind: Kind
        var title: String
        var description: String?
        var paths: [String]
        var tags: [String]
        var rules: [Rule]
        /// Optional free text from the user, given before the Descubra starts. Not part of the stored subject.
        var context: String?

        init(topic: RuleTopic) {
            self.init(kind: .topic, title: topic.title, description: topic.description, paths: topic.paths, tags: topic.tags, rules: topic.rules)
        }

        init(idea: Idea) {
            self.init(kind: .idea, title: idea.title, description: idea.body, paths: idea.paths, tags: idea.tags, rules: idea.rules)
        }

        init(kind: Kind, title: String, description: String?, paths: [String], tags: [String], rules: [Rule], context: String? = nil) {
            self.context = context
            self.kind = kind
            self.title = title
            self.description = description
            self.paths = paths
            self.tags = tags
            self.rules = rules
        }

        /// Same content as the prompts see it. Ignores rule metadata (ids, dates, tests): a reload from disk
        /// truncates `createdAt` to whole seconds, which must not count as an edit.
        func hasSameContent(as other: Subject) -> Bool {
            func content(_ rules: [Rule]) -> [[String?]] { rules.map { [$0.text, $0.details, $0.severity.rawValue] } }
            return kind == other.kind && title == other.title && description == other.description
                && paths == other.paths && tags == other.tags && content(rules) == content(other.rules)
        }
    }

    /// Existing rules elsewhere in the project, to avoid duplicates and conflicts.
    struct KnownTopic: Equatable, Sendable {
        var slug: String
        var title: String
        var rules: [String]

        init(slug: String, title: String, rules: [String]) {
            self.slug = slug
            self.title = title
            self.rules = rules
        }
    }

    struct Suggestion: Decodable, Equatable, Sendable {
        var value: String
        var reason: String

        init(value: String, reason: String) {
            self.value = value
            self.reason = reason
        }
    }

    // MARK: Scope (globs)

    struct ScopeAnswer: Decodable, Equatable, Sendable {
        var paths: [Suggestion]
        var tags: [Suggestion]

        init(paths: [Suggestion] = [], tags: [Suggestion] = []) {
            self.paths = paths
            self.tags = tags
        }

        enum CodingKeys: String, CodingKey { case paths, tags }
        enum ItemKeys: String, CodingKey { case glob, tag, reason }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            paths = try Self.items(c, .paths, key: .glob)
            tags = c.contains(.tags) ? try Self.items(c, .tags, key: .tag) : []
        }

        fileprivate static func items<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ field: K, key: ItemKeys) throws -> [Suggestion] {
            var list = try c.nestedUnkeyedContainer(forKey: field)
            var out: [Suggestion] = []
            while !list.isAtEnd {
                let item = try list.nestedContainer(keyedBy: ItemKeys.self)
                out.append(Suggestion(value: try item.decode(String.self, forKey: key), reason: try item.decodeIfPresent(String.self, forKey: .reason) ?? ""))
            }
            return out
        }
    }

    static let scopeSchema = #"""
    {"type":"object","properties":{"paths":{"type":"array","items":{"type":"object","properties":{"glob":{"type":"string"},"reason":{"type":"string"}},"required":["glob","reason"]}}},"required":["paths"]}
    """#

    static func scopePrompt(_ subject: Subject, topics: [KnownTopic]) -> String {
        var lines = header(subject)
        lines += known(topics)
        lines += [
            "",
            "## Tarefa",
            "Leia o repositório (o diretório atual) só com leitura e busca e sugira os globs deste \(noun(subject)). Não altere nada.",
            "- paths: globs relativos à raiz que cobrem os arquivos onde estas regras valem. Cada glob precisa casar ao menos",
            "  um arquivo que existe. Nada de catch-all (`*`, `**`, `**/*`). Prefira poucos globs específicos. Omita os atuais.",
            "- reason: uma frase curta com a evidência (ex.: Sources/App/View.swift:42).",
            "Se não encontrar nada, devolva a lista vazia.",
        ]
        return lines.joined(separator: "\n")
    }

    /// Keeps globs that aren't catch-all, aren't on the subject yet and match a project file; tags not on the
    /// subject, marking the ones outside the vocabulary as new.
    static func scope(_ answer: ScopeAnswer, subject: Subject, vocabulary: [String], files: [String]) -> RuleDiscoverScope {
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
    static func isCatchAll(_ glob: String) -> Bool {
        glob.allSatisfy { "*/.".contains($0) }
    }

    /// Project files (no folders, build or dependency output) the globs are checked against.
    static func projectFiles(root: URL) -> [String] {
        ClaudeCompletion.projectFiles(root: root, limit: fileLimit).filter { !$0.hasSuffix("/") }
    }

    // MARK: Interview (questions → rules)

    struct Question: Equatable, Identifiable, Sendable {
        var id: Int
        var text: String
        var options: [String]

        init(id: Int, text: String, options: [String] = []) {
            self.id = id
            self.text = text
            self.options = options
        }
    }

    /// A question asked in an earlier round and what the user answered (empty = skipped).
    struct Exchange: Equatable, Sendable {
        var question: String
        var answer: String

        init(question: String, answer: String) {
            self.question = question
            self.answer = answer
        }
    }

    enum Relation: String, Decodable, Sendable { case none, duplicate, conflict }

    struct RuleSuggestion: Decodable, Equatable, Sendable {
        var text: String
        var details: String
        var severity: RuleSeverity
        var reason: String
        /// Existing rule this one duplicates or conflicts with (text), when `relation` isn't `none`.
        var related: String
        var relation: Relation

        init(text: String, details: String = "", severity: RuleSeverity = .must, reason: String = "", related: String = "", relation: Relation = .none) {
            self.text = text
            self.details = details
            self.severity = severity
            self.reason = reason
            self.related = related
            self.relation = relation
        }
    }

    struct InterviewAnswer: Decodable, Equatable, Sendable {
        struct RawQuestion: Decodable, Equatable, Sendable {
            var text: String
            var options: [String]
        }

        var rawQuestions: [RawQuestion]
        var rules: [RuleSuggestion]

        enum CodingKeys: String, CodingKey { case rawQuestions = "questions", rules }

        init(questions: [String] = [], rules: [RuleSuggestion] = []) {
            rawQuestions = questions.map { RawQuestion(text: $0, options: []) }
            self.rules = rules
        }

        /// Non-empty questions, at most `maxQuestions`; repeated options are dropped (they'd be duplicate picker tags).
        var questions: [Question] {
            rawQuestions.compactMap { q in q.text.trimmed.nonEmpty.map { ($0, q.options.compactMap { $0.trimmed.nonEmpty }) } }
                .prefix(maxQuestions).enumerated().map { Question(id: $0.offset, text: $0.element.0, options: $0.element.1.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }) }
        }
    }

    static let interviewSchema = #"""
    {"type":"object","properties":{"questions":{"type":"array","items":{"type":"object","properties":{"text":{"type":"string"},"options":{"type":"array","items":{"type":"string"}}},"required":["text","options"]}},"rules":{"type":"array","items":{"type":"object","properties":{"text":{"type":"string"},"details":{"type":"string"},"severity":{"type":"string","enum":["must","should"]},"reason":{"type":"string"},"related":{"type":"string"},"relation":{"type":"string","enum":["none","duplicate","conflict"]}},"required":["text","details","severity","reason","related","relation"]}}},"required":["questions","rules"]}
    """#

    /// One interview call. `finish` (the user asked to generate, or the round limit was hit) forbids new questions.
    static func interviewPrompt(_ subject: Subject, topics: [KnownTopic], history: [Exchange], finish: Bool) -> String {
        var lines = header(subject)
        lines.append("Regras atuais:" + (subject.rules.isEmpty ? " (nenhuma)" : ""))
        lines += subject.rules.map { "- [\($0.severity.rawValue)] \($0.text)" }
        lines += known(topics)
        lines += interviewLines(history, title: "Entrevista até agora")
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
    static func drafts(_ answer: InterviewAnswer, subject: Subject, topics: [KnownTopic]) -> RuleDiscoverDrafts {
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

    // MARK: Details (description + tags)

    struct DetailsAnswer: Decodable, Equatable, Sendable {
        var description: String
        var reason: String
        var tags: [Suggestion]

        init(description: String, reason: String = "", tags: [Suggestion] = []) {
            self.description = description
            self.reason = reason
            self.tags = tags
        }

        enum CodingKeys: String, CodingKey { case description, reason, tags }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
            reason = try c.decodeIfPresent(String.self, forKey: .reason) ?? ""
            tags = c.contains(.tags) ? try ScopeAnswer.items(c, .tags, key: .tag) : []
        }
    }

    static let detailsSchema = #"""
    {"type":"object","properties":{"description":{"type":"string"},"reason":{"type":"string"},"tags":{"type":"array","items":{"type":"object","properties":{"tag":{"type":"string"},"reason":{"type":"string"}},"required":["tag","reason"]}}},"required":["description","reason","tags"]}
    """#

    /// Rewrites the description and suggests tags with what the Descubra gathered (globs, rules, interview).
    static func detailsPrompt(_ subject: Subject, vocabulary: [String], topics: [KnownTopic], history: [Exchange]) -> String {
        var lines = header(subject)
        lines += ["", "## Tags existentes no projeto", vocabulary.isEmpty ? "(nenhuma)" : vocabulary.joined(separator: ", ")]
        lines.append("Regras atuais:" + (subject.rules.isEmpty ? " (nenhuma)" : ""))
        lines += subject.rules.map { rule in
            "- [\(rule.severity.rawValue)] \(rule.text)" + (rule.details?.trimmed.nonEmpty.map { " — \($0)" } ?? "")
        }
        lines += known(topics)
        lines += interviewLines(history, title: "Entrevista")
        lines += [
            "",
            "## Tarefa",
            "Leia o repositório só com leitura e busca. Não altere nada.",
        ]
        if subject.kind == .idea {
            lines += [
                "- description: reescreva a descrição desta ideia em markdown, pronta para pedir a uma IA que implemente.",
                "  Preserve tudo o que já está na descrição atual (inclusive links e imagens de anexos), sem inventar requisitos.",
                "  Incorpore o contexto do usuário, as respostas da entrevista, os globs e as regras. Organize em seções curtas:",
                "  Problema, Proposta, Escopo (arquivos/telas afetados, com caminhos reais) e Critérios de aceite.",
            ]
        } else {
            lines += [
                "- description: uma ou duas frases, texto simples, dizendo quando este tópico se aplica, coerente com os",
                "  globs, as regras e a entrevista. Preserve o sentido da descrição atual.",
            ]
        }
        lines += [
            "- reason: uma frase curta dizendo o que mudou na descrição.",
            "- tags: prefira as tags existentes acima; só invente uma tag nova se nenhuma servir. Omita as atuais.",
            "  Cada tag com uma frase curta de motivo.",
        ]
        return lines.joined(separator: "\n")
    }

    /// Normalizes the answer; `suggested` is nil when the text equals the current description, tags follow `scope`'s rules.
    static func details(_ answer: DetailsAnswer, subject: Subject, vocabulary: [String]) -> RuleDiscoverDetails {
        let current = subject.description?.trimmed.nonEmpty
        let text = answer.description.trimmed.nonEmpty
        return RuleDiscoverDetails(
            current: current,
            suggested: text == current ? nil : text,
            reason: answer.reason.trimmed.nonEmpty,
            tags: scope(ScopeAnswer(tags: answer.tags), subject: subject, vocabulary: vocabulary, files: []).tags
        )
    }

    // MARK: Verdict (viability of an idea)

    struct VerdictAnswer: Decodable, Equatable, Sendable {
        var viable: Bool
        var missing: [String]

        init(viable: Bool = false, missing: [String] = []) {
            self.viable = viable
            self.missing = missing
        }

        enum CodingKeys: String, CodingKey { case viable, missing }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            viable = try c.decodeIfPresent(Bool.self, forKey: .viable) ?? false
            missing = try c.decodeIfPresent([String].self, forKey: .missing) ?? []
        }
    }

    static let verdictSchema = #"""
    {"type":"object","properties":{"viable":{"type":"boolean"},"missing":{"type":"array","items":{"type":"string"}}},"required":["viable","missing"]}
    """#

    /// Judges whether the idea, as written, is ready for an agent to implement. Doesn't rewrite anything.
    static func verdictPrompt(_ subject: Subject, topics: [KnownTopic]) -> String {
        var lines = header(subject)
        lines.append("Regras atuais:" + (subject.rules.isEmpty ? " (nenhuma)" : ""))
        lines += subject.rules.map { rule in
            "- [\(rule.severity.rawValue)] \(rule.text)" + (rule.details?.trimmed.nonEmpty.map { " — \($0)" } ?? "")
        }
        lines += known(topics)
        lines += [
            "",
            "## Tarefa",
            "Leia o repositório só com leitura e busca. Não altere nada, nem sugira nova descrição.",
            "- viable: true só se, depois de ler o código, a descrição + as regras bastam para um agente implementar",
            "  sem decisões de produto em aberto. Ideia vaga, sem regras ou com dúvidas fundamentais é false.",
            "- missing: as lacunas concretas que impedem implementar (vazio quando viable é true).",
            "Avalie somente a descrição e as regras atuais. Avaliações salvas anteriores podem estar desatualizadas.",
            "Escolhas técnicas usuais (nomes de APIs, tipos internos, organização de código) não são lacunas de produto.",
            "Não exija decisões que a descrição já tomou; leia a especificação inteira antes do veredito.",
        ]
        return lines.joined(separator: "\n")
    }

    static func verdict(_ answer: VerdictAnswer, subject: Subject) -> RuleDiscoverVerdict {
        RuleDiscoverVerdict(viable: answer.viable && !subject.rules.isEmpty, missing: answer.missing.compactMap { $0.trimmed.nonEmpty })
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
        if let context = subject.context?.trimmed.nonEmpty {
            lines += ["", "## Contexto do usuário (o que ele quer fazer; vale mais que suposições)", context]
        }
        return lines
    }

    private static func interviewLines(_ history: [Exchange], title: String) -> [String] {
        guard !history.isEmpty else { return [] }
        return ["", "## \(title)"] + history.flatMap { ["P: \($0.question)", "R: \($0.answer.trimmed.nonEmpty ?? "(sem resposta)")"] }
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
struct RuleDiscoverScope: Equatable, Sendable {
    struct PathAddition: Equatable, Identifiable, Sendable {
        var glob: String
        /// Project files the glob matches now.
        var matches: Int
        var reason: String?
        var id: String { glob }
    }

    struct TagAddition: Equatable, Identifiable, Sendable {
        var tag: String
        /// Not in the project's vocabulary yet: starts unchecked.
        var isNew: Bool
        var reason: String?
        var id: String { tag }
    }

    var paths: [PathAddition] = []
    var tags: [TagAddition] = []
    /// Suggestions dropped by validation, shown so the user knows they existed.
    var discarded: [String] = []

    init() {}

    var isEmpty: Bool { paths.isEmpty && tags.isEmpty }

    /// Tags that start checked: the ones already in the vocabulary. A new tag needs an explicit check.
    var defaultTags: Set<String> { Set(tags.filter { !$0.isNew }.map(\.tag)) }

    /// Appends the chosen globs and tags; existing ones are never removed.
    func apply(paths chosenPaths: Set<String>, tags chosenTags: Set<String>, to current: inout [String], tags currentTags: inout [String]) {
        for path in paths where chosenPaths.contains(path.glob) && !current.contains(path.glob) { current.append(path.glob) }
        for tag in tags where chosenTags.contains(tag.tag) && !currentTags.contains(tag.tag) { currentTags.append(tag.tag) }
    }
}

/// Rules drafted by the interview waiting for the user's choice.
struct RuleDiscoverDrafts: Equatable, Sendable {
    struct Draft: Equatable, Identifiable, Sendable {
        var id = UUID()
        var text: String
        var details: String?
        var severity: RuleSeverity
        var reason: String?
        var relation: RuleDiscover.Relation
        /// Text of the existing rule it duplicates or conflicts with.
        var related: String?

        init(text: String, details: String? = nil, severity: RuleSeverity, reason: String? = nil, relation: RuleDiscover.Relation = .none, related: String? = nil) {
            self.text = text
            self.details = details
            self.severity = severity
            self.reason = reason
            self.relation = relation
            self.related = related
        }
    }

    var rules: [Draft] = []

    init() {}

    var isEmpty: Bool { rules.isEmpty }

    /// Drafts that start checked: the ones not flagged as duplicate or conflict.
    var defaultRules: Set<UUID> { Set(rules.filter { $0.relation == .none }.map(\.id)) }

    /// Appends the chosen drafts as AI-authored rules (to `idea.rules` they stay drafts until promotion).
    func apply(_ chosen: Set<UUID>, to current: inout [Rule], now: Date = .now) {
        for draft in rules where chosen.contains(draft.id) {
            current.append(Rule(text: draft.text, details: draft.details, severity: draft.severity, author: .ai, now: now))
        }
    }
}

/// Rewritten description and suggested tags waiting for the user's choice.
struct RuleDiscoverDetails: Equatable, Sendable {
    var current: String?
    /// New text; nil when the AI kept the current one.
    var suggested: String?
    var reason: String?
    var tags: [RuleDiscoverScope.TagAddition]

    init(current: String? = nil, suggested: String? = nil, reason: String? = nil, tags: [RuleDiscoverScope.TagAddition] = []) {
        self.current = current
        self.suggested = suggested
        self.reason = reason
        self.tags = tags
    }

    /// Tags that start checked: the ones already in the vocabulary. A new tag needs an explicit check.
    var defaultTags: Set<String> { Set(tags.filter { !$0.isNew }.map(\.tag)) }

    var isEmpty: Bool { suggested == nil && tags.isEmpty }

    /// Replaces the description with the suggestion when `acceptDescription`, and appends the chosen tags.
    func apply(acceptDescription: Bool, tags chosen: Set<String>, description: inout String?, tags current: inout [String]) {
        if acceptDescription, let suggested { description = suggested }
        for tag in tags where chosen.contains(tag.tag) && !current.contains(tag.tag) { current.append(tag.tag) }
    }
}

/// Whether an idea is ready to implement, waiting to be saved on it.
struct RuleDiscoverVerdict: Equatable, Sendable {
    var viable: Bool
    var missing: [String]

    init(viable: Bool = false, missing: [String] = []) {
        self.viable = viable
        self.missing = missing
    }

    /// The verdict for `idea` as it is now.
    func readiness(for idea: Idea, now: Date = .now) -> IdeaReadiness {
        IdeaReadiness(viable: viable && !idea.rules.isEmpty, missing: missing, checkedAt: now, fingerprint: idea.contentFingerprint)
    }

    /// Saves the evaluation and approves eligible ideas without promoting their draft rules.
    func apply(to idea: inout Idea, now: Date = .now) {
        let readiness = readiness(for: idea, now: now)
        idea.readiness = readiness
        if readiness.viable, !idea.status.isClosed, idea.promotedTopic == nil {
            idea.status = .approved
        }
    }
}
