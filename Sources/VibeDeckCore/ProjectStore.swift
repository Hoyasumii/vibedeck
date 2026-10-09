import Foundation

public enum VibeDeckError: LocalizedError, Equatable {
    case notAProject(String)
    case alreadyAProject(String)
    case docNotFound(String)
    case groupNotFound(String)
    case itemNotFound(String)
    case ambiguousItem(String)
    case topicNotFound(String)
    case ideaNotFound(String)
    case agentNotFound(String)
    case commandNotFound(String)
    case skillNotFound(String)
    case workflowNotFound(String)
    case runNotFound(String)
    case invalidWorkflow(String)
    case invalidNextStep(String)
    case ruleNotFound(String)
    case ambiguousRule(String)
    case incompleteCheck([String])
    case invalidRuleTest(String)
    case rulesNotVerified([String])
    case invalidName
    case invalidStatusLine
    case invalidClaudeSettings(String)
    case cloudNotSynced(CloudSync)
    case cloudDirty(CloudSync)
    case claudeNotInstalled
    case cloudSessionFailed(String)
    case discoverFailed(String)
    case discoverInvalidAnswer
    case discoverTimedOut
    case skillIconsUnavailable(String)
    case unknownStackIcons([String: [String]])
    case stackItemNotFound(String)
    case unknownPatterns([String: [String]])
    case patternNotFound(String)
    case graph(String)

    public var errorDescription: String? {
        switch self {
        case .notAProject(let p): "Nenhum vibedeck.json encontrado em \(p) ou diretórios acima. Rode `vibedeck init`."
        case .alreadyAProject(let p): "\(p) já contém um vibedeck.json."
        case .docNotFound(let s): "Doc não encontrado: \(s)"
        case .groupNotFound(let s): "Grupo de revisão não encontrado: \(s)"
        case .itemNotFound(let s): "Item de revisão não encontrado: \(s)"
        case .ambiguousItem(let s): "Prefixo de id ambíguo: \(s)"
        case .topicNotFound(let s): "Tópico de regras não encontrado: \(s)"
        case .ideaNotFound(let s): "Ideia não encontrada: \(s)"
        case .agentNotFound(let s): "Agente não encontrado: \(s)"
        case .commandNotFound(let s): "Comando não encontrado: \(s)"
        case .skillNotFound(let s): "Skill não encontrada: \(s)"
        case .workflowNotFound(let s): "Workflow não encontrado: \(s)"
        case .runNotFound(let s): "Execução de workflow não encontrada: \(s)"
        case .invalidWorkflow(let s): "Workflow inválido: \(s)"
        case .invalidNextStep(let s): "Próximo passo inválido: \(s)"
        case .ruleNotFound(let s): "Regra não encontrada entre as aplicáveis: \(s)"
        case .ambiguousRule(let s): "Prefixo de id de regra ambíguo: \(s)"
        case .incompleteCheck(let missing):
            "Check incompleto: responda todas as regras aplicáveis que não são decididas por script (pass, fail ou na). Faltando:\n" + missing.map { "- \($0)" }.joined(separator: "\n")
        case .invalidRuleTest(let s): "Teste de regra inválido: \(s)"
        case .rulesNotVerified(let problems):
            "O item não pode ser concluído sem passar pelas regras:\n" + problems.map { "- \($0)" }.joined(separator: "\n")
                + "\nUse rules_for / submit_rule_check (ou `vibedeck rules check`) com o id do item."
        case .invalidName: "Nome inválido."
        case .invalidStatusLine: "Entrada da statusline do Claude Code não é um objeto JSON."
        case .invalidClaudeSettings(let p): "\(p) não é um objeto JSON válido; corrija antes de ligar a statusline."
        case .cloudNotSynced(let sync): sync.message
        case .cloudDirty(let sync): sync.message + " Confirme (--allow-dirty / allow_dirty) para criar mesmo assim."
        case .claudeNotInstalled: "O Claude Code (`claude`) não foi encontrado. Instale-o para usar a nuvem."
        case .cloudSessionFailed(let output): "O Claude Code não criou a sessão na nuvem:\n\(output)"
        case .discoverFailed(let output):
            "O Claude Code não conseguiu descobrir; nada foi alterado." + (output.isEmpty ? "" : "\n\(output)")
        case .discoverInvalidAnswer: "O Claude Code respondeu num formato inesperado; nada foi alterado. Tente de novo."
        case .discoverTimedOut: "O Descubra demorou demais e foi interrompido; nada foi alterado. Tente de novo."
        case .skillIconsUnavailable(let s): "Skill Icons indisponível: \(s)"
        case .unknownStackIcons(let unknown):
            "Ícone(s) desconhecido(s) no Skill Icons; nada foi alterado:\n" + unknown.keys.sorted().map { name in
                let suggestions = unknown[name] ?? []
                return "- \(name)" + (suggestions.isEmpty ? "" : " (sugestões: \(suggestions.joined(separator: ", ")))")
            }.joined(separator: "\n")
        case .stackItemNotFound(let s): "Tecnologia não encontrada na stack: \(s)"
        case .unknownPatterns(let unknown):
            "Padrão(ões) desconhecido(s) no catálogo; nada foi alterado:\n" + unknown.keys.sorted().map { name in
                let suggestions = unknown[name] ?? []
                return "- \(name)" + (suggestions.isEmpty ? "" : " (sugestões: \(suggestions.joined(separator: ", ")))")
            }.joined(separator: "\n") + "\nVeja `pattern_catalog` / `vibedeck patterns catalog`, ou crie um padrão personalizado."
        case .graph(let s): "Grafo: \(s)"
        case .patternNotFound(let s): "Padrão não encontrado no projeto: \(s)"
        }
    }
}

/// File-based access to a VibeDeck project. Stateless: every call reads/writes disk,
/// so the app, the CLI, the MCP server and AI agents editing files by hand never diverge.
public struct ProjectStore: Sendable {
    public static let manifestName = "vibedeck.json"
    public static let dataDirName = ".vibedeck"

    public let root: URL

    public init(root: URL) {
        self.root = root.standardizedFileURL
    }

    public var manifestURL: URL { root.appending(path: Self.manifestName) }
    public var dataDir: URL { root.appending(path: Self.dataDirName, directoryHint: .isDirectory) }
    public var docsDir: URL { dataDir.appending(path: "docs", directoryHint: .isDirectory) }
    public var reviewsDir: URL { dataDir.appending(path: "reviews", directoryHint: .isDirectory) }
    public var rulesDir: URL { dataDir.appending(path: "rules", directoryHint: .isDirectory) }
    public var ideasDir: URL { dataDir.appending(path: "ideas", directoryHint: .isDirectory) }
    public var agentDefsDir: URL { dataDir.appending(path: "agents", directoryHint: .isDirectory) }
    public var commandsDir: URL { dataDir.appending(path: "commands", directoryHint: .isDirectory) }
    public var skillsDir: URL { dataDir.appending(path: "skills", directoryHint: .isDirectory) }
    public var workflowsDir: URL { dataDir.appending(path: "workflows", directoryHint: .isDirectory) }
    public var checksDir: URL { dataDir.appending(path: "checks", directoryHint: .isDirectory) }
    /// Scripts generated from rules (`tests/<topic>/<rule>.sh`); created on demand by whoever writes them.
    public var testsDir: URL { dataDir.appending(path: "tests", directoryHint: .isDirectory) }
    public var runsDir: URL { dataDir.appending(path: "runs", directoryHint: .isDirectory) }
    public var attachmentsDir: URL { dataDir.appending(path: "attachments", directoryHint: .isDirectory) }
    public var agentsURL: URL { dataDir.appending(path: "AGENTS.md") }

    // MARK: Detection / init

    public static func isProject(_ dir: URL) -> Bool {
        FileManager.default.fileExists(atPath: dir.appending(path: manifestName).path)
    }

    /// Walks up from `dir` looking for a vibedeck.json (like git does with .git).
    public static func find(from dir: URL) -> ProjectStore? {
        var current = dir.standardizedFileURL
        while true {
            if isProject(current) { return ProjectStore(root: current) }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { return nil }
            current = parent
        }
    }

    public static func locate(from dir: URL) throws -> ProjectStore {
        guard let store = find(from: dir) else { throw VibeDeckError.notAProject(dir.path) }
        return store
    }

    @discardableResult
    public static func initialize(at dir: URL, name: String? = nil, description: String? = nil) throws -> ProjectStore {
        let store = ProjectStore(root: dir)
        if isProject(store.root) { throw VibeDeckError.alreadyAProject(store.root.path) }
        let projectName = name?.trimmed.nonEmpty ?? store.root.lastPathComponent
        let project = Project(name: projectName, description: description)
        try store.ensureDirectories()
        try store.saveProject(project)
        try store.writeAgentsGuide()
        return store
    }

    public func ensureDirectories() throws {
        let fm = FileManager.default
        for dir in [docsDir, reviewsDir, rulesDir, ideasDir, agentDefsDir, commandsDir, skillsDir, workflowsDir, checksDir, attachmentsDir] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    public func writeAgentsGuide() throws {
        try ensureDirectories()
        try AtomicFile.write(Data(AgentsGuide.markdown.utf8), to: agentsURL)
        try AtomicFile.write(Data(AgentsGuide.referenceMarkdown.utf8), to: dataDir.appending(path: "guide.md"))
    }

    /// Rewrites AGENTS.md only when this build's guide differs from what's on disk.
    public func refreshAgentsGuideIfNeeded() throws {
        let current = FileManager.default.contents(atPath: agentsURL.path)
        if current != Data(AgentsGuide.markdown.utf8) || FileManager.default.contents(atPath: dataDir.appending(path: "guide.md").path) != Data(AgentsGuide.referenceMarkdown.utf8) { try writeAgentsGuide() }
    }

    // MARK: Project

    public func loadProject() throws -> Project {
        try VDJSON.decoder.decode(Project.self, from: Data(contentsOf: manifestURL))
    }

    public func saveProject(_ project: Project) throws {
        try AtomicFile.write(VDJSON.encode(project), to: manifestURL)
    }

    @discardableResult
    public func updateProject(_ change: (inout Project) throws -> Void) throws -> Project {
        var project = try loadProject()
        try change(&project)
        try saveProject(project)
        return project
    }

    // MARK: Docs

    public func docURL(_ slug: String) -> URL { docsDir.appending(path: "\(slug).md") }

    public func listDocs() throws -> [DocInfo] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: docsDir.path) else { return [] }
        let urls = try fm.contentsOfDirectory(
            at: docsDir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]
        )
        return urls
            .filter { $0.pathExtension.lowercased() == "md" }
            .map { url in
                let slug = url.deletingPathExtension().lastPathComponent
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                return DocInfo(slug: slug, title: Markdown.title(of: text) ?? slug, tags: Markdown.tags(of: text), modified: modified)
            }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    public func readDoc(_ slug: String) throws -> String {
        let url = docURL(slug)
        guard FileManager.default.fileExists(atPath: url.path) else { throw VibeDeckError.docNotFound(slug) }
        return try String(contentsOf: url, encoding: .utf8)
    }

    public func writeDoc(_ slug: String, _ text: String) throws {
        try ensureDirectories()
        try AtomicFile.write(Data(text.utf8), to: docURL(slug))
    }

    /// Creates a new doc with a unique slug derived from `title`. Returns the slug.
    public func createDoc(title: String, body: String = "") throws -> String {
        let slug = uniqueSlug(Slug.make(title), in: docsDir, ext: "md")
        try writeDoc(slug, "# \(title)\n\n\(body)")
        return slug
    }

    /// Rewrites the doc's frontmatter `tags:` line (removed when `tags` is empty).
    public func setDocTags(_ slug: String, _ tags: [String]) throws {
        try writeDoc(slug, Markdown.settingTags(tags, in: readDoc(slug)))
    }

    public func deleteDoc(_ slug: String) throws {
        try FileManager.default.removeItem(at: docURL(slug))
    }

    // MARK: Attachments

    /// Copies `url` into `.vibedeck/attachments/` as `<owner>-<name>.<ext>` (suffixed when taken).
    /// Returns the markdown link to insert, relative to `docs/` and `ideas/` (`../attachments/…`).
    public func importAttachment(from url: URL, owner: String) throws -> String {
        let dest = try attachmentDestination(name: url.lastPathComponent, owner: owner)
        try AtomicFile.write(Data(contentsOf: url), to: dest)
        return Self.attachmentMarkdown(path: "../attachments/" + dest.lastPathComponent, name: url.lastPathComponent)
    }

    /// Saves `data` (e.g. a pasted image) as an attachment named after `name`. Returns the markdown link.
    public func importAttachment(data: Data, name: String, owner: String) throws -> String {
        let dest = try attachmentDestination(name: name, owner: owner)
        try AtomicFile.write(data, to: dest)
        return Self.attachmentMarkdown(path: "../attachments/" + dest.lastPathComponent, name: name)
    }

    private func attachmentDestination(name: String, owner: String) throws -> URL {
        try ensureDirectories()
        let file = URL(fileURLWithPath: name)
        let ext = file.pathExtension.isEmpty ? "" : Slug.make(file.pathExtension)
        let slug = uniqueSlug(Slug.make(owner) + "-" + Slug.make(file.deletingPathExtension().lastPathComponent), in: attachmentsDir, ext: ext)
        return attachmentsDir.appending(path: ext.isEmpty ? slug : "\(slug).\(ext)")
    }

    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "svg", "tif", "tiff", "bmp"]

    /// `![name](path)` for images (rendered in the preview), `[name](path)` for anything else.
    public static func attachmentMarkdown(path: String, name: String) -> String {
        let label = name.replacingOccurrences(of: "[", with: "(").replacingOccurrences(of: "]", with: ")")
        let isImage = imageExtensions.contains(URL(fileURLWithPath: path).pathExtension.lowercased())
        return (isImage ? "!" : "") + "[\(label)](\(path))"
    }

    // MARK: Reviews

    public func groupURL(_ slug: String) -> URL { reviewsDir.appending(path: "\(slug).json") }

    public func listGroups() throws -> [(slug: String, group: ReviewGroup)] {
        try listRecords(ReviewGroup.self, in: reviewsDir).map { ($0.slug, $0.value) }
    }

    /// Resolves a group by slug, id (or prefix), or case-insensitive title.
    public func resolveGroupSlug(_ ref: String) throws -> String {
        try resolveSlug(ref, ReviewGroup.self, in: reviewsDir) { .groupNotFound($0) }
    }

    public func loadGroup(_ slug: String) throws -> ReviewGroup {
        try loadRecord(slug, in: reviewsDir) { .groupNotFound($0) }
    }

    public func saveGroup(_ group: ReviewGroup, slug: String) throws {
        try ensureDirectories()
        try AtomicFile.write(VDJSON.encode(group), to: groupURL(slug))
    }

    /// Creates a group with a unique slug. Returns the slug.
    @discardableResult
    public func createGroup(title: String, description: String? = nil, tags: [String] = []) throws -> (slug: String, group: ReviewGroup) {
        guard let title = title.trimmed.nonEmpty else { throw VibeDeckError.invalidName }
        let slug = uniqueSlug(Slug.make(title), in: reviewsDir, ext: "json")
        let group = ReviewGroup(title: title, description: description, tags: tags)
        try saveGroup(group, slug: slug)
        return (slug, group)
    }

    @discardableResult
    public func updateGroup(_ ref: String, _ change: (inout ReviewGroup) throws -> Void) throws -> (slug: String, group: ReviewGroup) {
        let slug = try resolveGroupSlug(ref)
        var group = try loadGroup(slug)
        try change(&group)
        try saveGroup(group, slug: slug)
        return (slug, group)
    }

    public func deleteGroup(_ slug: String) throws {
        try FileManager.default.removeItem(at: groupURL(slug))
    }

    /// Adds an item to a group (created on the fly if `groupRef` doesn't resolve).
    @discardableResult
    public func addItem(_ item: ReviewItem, toGroup groupRef: String) throws -> (slug: String, item: ReviewItem) {
        let slug: String
        if let existing = try? resolveGroupSlug(groupRef) { slug = existing } else { slug = try createGroup(title: groupRef).slug }
        var group = try loadGroup(slug)
        group.items.append(item)
        try saveGroup(group, slug: slug)
        return (slug, item)
    }

    /// Finds an item by full id or unique id prefix (min. 4 chars) across all groups.
    public func findItem(_ ref: String) throws -> (slug: String, group: ReviewGroup, index: Int) {
        let needle = ref.lowercased()
        var matches: [(String, ReviewGroup, Int)] = []
        for (slug, group) in try listGroups() {
            for (i, item) in group.items.enumerated() {
                let id = item.id.uuidString.lowercased()
                if id == needle { return (slug, group, i) }
                if needle.count >= 4, id.hasPrefix(needle) { matches.append((slug, group, i)) }
            }
        }
        guard !matches.isEmpty else { throw VibeDeckError.itemNotFound(ref) }
        guard matches.count == 1 else { throw VibeDeckError.ambiguousItem(ref) }
        return matches[0]
    }

    @discardableResult
    public func updateItem(_ ref: String, _ change: (inout ReviewItem) throws -> Void) throws -> ReviewItem {
        var (slug, group, index) = try findItem(ref)
        try change(&group.items[index])
        group.items[index].updatedAt = .now
        try saveGroup(group, slug: slug)
        return group.items[index]
    }

    public func deleteItem(_ ref: String) throws {
        var (slug, group, index) = try findItem(ref)
        group.items.remove(at: index)
        try saveGroup(group, slug: slug)
    }

    // MARK: Rules

    public func topicURL(_ slug: String) -> URL { rulesDir.appending(path: "\(slug).json") }

    public func listTopics() throws -> [(slug: String, topic: RuleTopic)] {
        try listRecords(RuleTopic.self, in: rulesDir).map { ($0.slug, $0.value) }
    }

    public func resolveTopicSlug(_ ref: String) throws -> String {
        try resolveSlug(ref, RuleTopic.self, in: rulesDir) { .topicNotFound($0) }
    }

    public func loadTopic(_ slug: String) throws -> RuleTopic {
        try loadRecord(slug, in: rulesDir) { .topicNotFound($0) }
    }

    public func saveTopic(_ topic: RuleTopic, slug: String) throws {
        try ensureDirectories()
        try AtomicFile.write(VDJSON.encode(topic), to: topicURL(slug))
    }

    @discardableResult
    public func createTopic(
        title: String, description: String? = nil, tags: [String] = [], paths: [String] = [], rules: [Rule] = [], sourceIdea: UUID? = nil,
        sourcePattern: String? = nil
    ) throws -> (slug: String, topic: RuleTopic) {
        guard let title = title.trimmed.nonEmpty else { throw VibeDeckError.invalidName }
        let slug = uniqueSlug(Slug.make(title), in: rulesDir, ext: "json")
        let topic = RuleTopic(title: title, description: description, tags: tags, paths: paths, rules: rules, sourceIdea: sourceIdea, sourcePattern: sourcePattern)
        try saveTopic(topic, slug: slug)
        return (slug, topic)
    }

    @discardableResult
    public func updateTopic(_ ref: String, _ change: (inout RuleTopic) throws -> Void) throws -> RuleTopic {
        let slug = try resolveTopicSlug(ref)
        var topic = try loadTopic(slug)
        try change(&topic)
        try saveTopic(topic, slug: slug)
        return topic
    }

    /// Deletes the topic, unpromotes any idea it came from and drops the pattern it enforced.
    public func deleteTopic(_ slug: String) throws {
        try FileManager.default.removeItem(at: topicURL(slug))
        try releaseOrphanedIdeas()
        try releaseOrphanedPatterns()
    }

    /// Adds a rule to a topic (created on the fly if `topicRef` doesn't resolve).
    @discardableResult
    public func addRule(_ rule: Rule, toTopic topicRef: String) throws -> (slug: String, rule: Rule) {
        let slug: String
        if let existing = try? resolveTopicSlug(topicRef) { slug = existing } else { slug = try createTopic(title: topicRef).slug }
        try updateTopic(slug) { $0.rules.append(rule) }
        return (slug, rule)
    }

    /// Finds a topic rule by full id or unique prefix (>= 4 chars).
    public func findRule(_ ref: String) throws -> (slug: String, topic: RuleTopic, index: Int) {
        let candidates = try listTopics().flatMap { t in t.topic.rules.indices.map { (t.slug, t.topic, $0) } }
        let (slug, topic, index) = try matchRule(ref, in: candidates) { $0.1.rules[$0.2] }
        return (slug, topic, index)
    }

    @discardableResult
    public func updateRule(_ ref: String, _ change: (inout Rule) throws -> Void) throws -> Rule {
        var (slug, topic, index) = try findRule(ref)
        try change(&topic.rules[index])
        try saveTopic(topic, slug: slug)
        return topic.rules[index]
    }

    public func deleteRule(_ ref: String) throws {
        var (slug, topic, index) = try findRule(ref)
        let removed = topic.rules.remove(at: index)
        try saveTopic(topic, slug: slug)
        removeGeneratedScript(of: removed)
    }

    /// Records how a rule is verified: a script `command` (run from the project root) or `manual`.
    @discardableResult
    public func setRuleTest(_ ref: String, mode: RuleTestMode, command: String? = nil, reason: String? = nil) throws -> Rule {
        let command = command?.trimmed.nonEmpty
        if mode == .script, command == nil { throw VibeDeckError.invalidRuleTest("Informe o comando do script.") }
        return try updateRule(ref) { rule in
            rule.test = RuleTest(mode: mode, command: mode == .script ? command : nil, reason: reason?.trimmed.nonEmpty, ruleHash: rule.contentHash)
        }
    }

    /// Forgets a rule's test (the generated script, if any, is deleted too).
    @discardableResult
    public func clearRuleTest(_ ref: String) throws -> Rule {
        var previous: Rule?
        let rule = try updateRule(ref) { previous = $0; $0.test = nil }
        if let previous { removeGeneratedScript(of: previous) }
        return rule
    }

    /// Deletes the rule's script when it lives in `.vibedeck/tests/` (hand-pointed commands elsewhere are left alone).
    private func removeGeneratedScript(of rule: Rule) {
        guard let command = rule.test?.command?.trimmed.nonEmpty, !command.contains(" ") else { return }
        let url = URL(fileURLWithPath: command, relativeTo: root).standardizedFileURL
        guard url.path.hasPrefix(testsDir.standardizedFileURL.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: Agents

    public func agentURL(_ slug: String) -> URL { agentDefsDir.appending(path: "\(slug).json") }

    public func listAgents() throws -> [(slug: String, agent: Agent)] {
        try listRecords(Agent.self, in: agentDefsDir).map { ($0.slug, $0.value) }
    }

    public func resolveAgentSlug(_ ref: String) throws -> String {
        try resolveSlug(ref, Agent.self, in: agentDefsDir) { .agentNotFound($0) }
    }

    public func loadAgent(_ slug: String) throws -> Agent {
        try loadRecord(slug, in: agentDefsDir) { .agentNotFound($0) }
    }

    public func saveAgent(_ agent: Agent, slug: String) throws {
        try ensureDirectories()
        try AtomicFile.write(VDJSON.encode(agent), to: agentURL(slug))
    }

    @discardableResult
    public func createAgent(
        title: String, summary: String? = nil, model: String? = nil, tools: [String] = [], prompt: String = "",
        tags: [String] = [], author: Author = .human
    ) throws -> (slug: String, agent: Agent) {
        guard let title = title.trimmed.nonEmpty else { throw VibeDeckError.invalidName }
        let slug = uniqueSlug(Slug.make(title), in: agentDefsDir, ext: "json")
        let agent = Agent(title: title, summary: summary, model: model, tools: tools, prompt: prompt, tags: tags, author: author)
        try saveAgent(agent, slug: slug)
        return (slug, agent)
    }

    @discardableResult
    public func updateAgent(_ ref: String, _ change: (inout Agent) throws -> Void) throws -> (slug: String, agent: Agent) {
        let slug = try resolveAgentSlug(ref)
        var agent = try loadAgent(slug)
        try change(&agent)
        agent.updatedAt = .now
        try saveAgent(agent, slug: slug)
        return (slug, agent)
    }

    public func deleteAgent(_ slug: String) throws {
        try FileManager.default.removeItem(at: agentURL(slug))
    }

    /// Appends a next step to an agent's flow. The target must be an existing VibeDeck agent or command (never the
    /// agent itself); it accepts the usual references (slug, UUID, prefix, title) and is stored as the slug.
    @discardableResult
    public func addNextStep(to ref: String, kind: NextStepKind = .agent, target: String, note: String? = nil) throws -> (slug: String, agent: Agent) {
        let from = try resolveAgentSlug(ref)
        let stored = try resolveNextStepTarget(kind: kind, target: target, excluding: (.agent, from))
        return try updateAgent(from) { agent in
            guard !agent.nextSteps.contains(where: { $0.kind == kind && $0.ref == stored }) else { return }
            agent.nextSteps.append(NextStep(kind: kind, ref: stored, note: note?.trimmed.nonEmpty))
        }
    }

    /// Resolves a next-step target to the slug of a VibeDeck agent/command/skill, rejecting the step's own owner.
    private func resolveNextStepTarget(kind: NextStepKind, target: String, excluding owner: (kind: NextStepKind, slug: String)) throws -> String {
        let stored = try resolveStepTarget(kind: kind, target: target)
        if kind == owner.kind, stored == owner.slug {
            let noun = switch kind {
            case .agent: "um agente"
            case .command: "um comando"
            case .skill: "uma skill"
            }
            throw VibeDeckError.invalidNextStep("\(noun) não pode ser o próximo passo de si mesmo.")
        }
        return stored
    }

    /// Slug of an existing VibeDeck agent, command or skill (usual references: slug, UUID, prefix, title).
    private func resolveStepTarget(kind: NextStepKind, target: String) throws -> String {
        switch kind {
        case .agent: try resolveAgentSlug(target)
        case .command: try resolveCommandSlug(target)
        case .skill: try resolveSkillSlug(target)
        }
    }

    /// Imports Claude Code agents (`~/.claude/agents` and `<project>/.claude/agents`) as VibeDeck agents.
    /// Existing agents (same slug) are skipped unless `overwrite`. Returns the slugs created/updated.
    @discardableResult
    public func importClaudeAgents(from dirs: [URL]? = nil, overwrite: Bool = false, author: Author = .human) throws -> [String] {
        let fm = FileManager.default
        let sources = dirs ?? [
            root.appending(path: ".claude/agents", directoryHint: .isDirectory),
            fm.homeDirectoryForCurrentUser.appending(path: ".claude/agents", directoryHint: .isDirectory),
        ]
        var imported: [String] = []
        var seen = Set<String>()
        for dir in sources {
            guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
            for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where file.pathExtension.lowercased() == "md" {
                guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
                let parsed = ClaudeAgentFile.parse(text, fallbackName: file.deletingPathExtension().lastPathComponent)
                let slug = Slug.make(parsed.name)
                guard seen.insert(slug).inserted else { continue }  // project dir wins over user dir
                if fm.fileExists(atPath: agentURL(slug).path) {
                    guard overwrite else { continue }
                    try updateAgent(slug) {
                        $0.summary = parsed.description; $0.model = parsed.model; $0.tools = parsed.tools; $0.prompt = parsed.prompt
                    }
                } else {
                    var agent = Agent(title: parsed.name, summary: parsed.description, model: parsed.model, tools: parsed.tools, prompt: parsed.prompt, author: author)
                    agent.tags = ["claude-code"]
                    try saveAgent(agent, slug: slug)
                }
                imported.append(slug)
            }
        }
        return imported
    }

    // MARK: Commands

    public func commandURL(_ slug: String) -> URL { commandsDir.appending(path: "\(slug).json") }

    public func listCommands() throws -> [(slug: String, command: Command)] {
        try listRecords(Command.self, in: commandsDir).map { ($0.slug, $0.value) }
    }

    public func resolveCommandSlug(_ ref: String) throws -> String {
        try resolveSlug(ref, Command.self, in: commandsDir) { .commandNotFound($0) }
    }

    public func loadCommand(_ slug: String) throws -> Command {
        try loadRecord(slug, in: commandsDir) { .commandNotFound($0) }
    }

    public func saveCommand(_ command: Command, slug: String) throws {
        try ensureDirectories()
        try AtomicFile.write(VDJSON.encode(command), to: commandURL(slug))
    }

    @discardableResult
    public func createCommand(
        title: String, summary: String? = nil, argumentHint: String? = nil, model: String? = nil, tools: [String] = [],
        prompt: String = "", tags: [String] = [], author: Author = .human
    ) throws -> (slug: String, command: Command) {
        guard let title = title.trimmed.nonEmpty else { throw VibeDeckError.invalidName }
        let slug = uniqueSlug(Slug.make(title), in: commandsDir, ext: "json")
        let command = Command(title: title, summary: summary, argumentHint: argumentHint, model: model, tools: tools, prompt: prompt, tags: tags, author: author)
        try saveCommand(command, slug: slug)
        return (slug, command)
    }

    @discardableResult
    public func updateCommand(_ ref: String, _ change: (inout Command) throws -> Void) throws -> (slug: String, command: Command) {
        let slug = try resolveCommandSlug(ref)
        var command = try loadCommand(slug)
        try change(&command)
        command.updatedAt = .now
        try saveCommand(command, slug: slug)
        return (slug, command)
    }

    public func deleteCommand(_ slug: String) throws {
        try FileManager.default.removeItem(at: commandURL(slug))
    }

    /// Appends a next step to a command's flow (same rules as `addNextStep(to:)` for agents).
    @discardableResult
    public func addCommandNextStep(to ref: String, kind: NextStepKind = .agent, target: String, note: String? = nil) throws -> (slug: String, command: Command) {
        let from = try resolveCommandSlug(ref)
        let stored = try resolveNextStepTarget(kind: kind, target: target, excluding: (.command, from))
        return try updateCommand(from) { command in
            guard !command.nextSteps.contains(where: { $0.kind == kind && $0.ref == stored }) else { return }
            command.nextSteps.append(NextStep(kind: kind, ref: stored, note: note?.trimmed.nonEmpty))
        }
    }

    /// Imports Claude Code slash commands (`<project>/.claude/commands` and `~/.claude/commands`, recursively) as
    /// VibeDeck commands. Subfolders are namespaces (`git/commit.md` → `git:commit`). Existing commands (same slug)
    /// are skipped unless `overwrite`. Returns the slugs created/updated.
    @discardableResult
    public func importClaudeCommands(from dirs: [URL]? = nil, overwrite: Bool = false, author: Author = .human) throws -> [String] {
        let fm = FileManager.default
        let sources = dirs ?? [
            root.appending(path: ".claude/commands", directoryHint: .isDirectory),
            fm.homeDirectoryForCurrentUser.appending(path: ".claude/commands", directoryHint: .isDirectory),
        ]
        var imported: [String] = []
        var seen = Set<String>()
        for dir in sources {
            guard let paths = try? fm.subpathsOfDirectory(atPath: dir.path) else { continue }
            let files = paths.filter { $0.lowercased().hasSuffix(".md") && !$0.split(separator: "/").contains { $0.hasPrefix(".") } }
            for path in files.sorted() {
                guard let text = try? String(contentsOf: dir.appending(path: path), encoding: .utf8) else { continue }
                let name = String(path.dropLast(3)).split(separator: "/").joined(separator: ":")
                let parsed = ClaudeCommandFile.parse(text, fallbackName: name)
                let slug = Slug.make(parsed.name)
                guard seen.insert(slug).inserted else { continue }  // project dir wins over user dir
                if fm.fileExists(atPath: commandURL(slug).path) {
                    guard overwrite else { continue }
                    try updateCommand(slug) {
                        $0.summary = parsed.description; $0.argumentHint = parsed.argumentHint; $0.model = parsed.model
                        $0.tools = parsed.tools; $0.prompt = parsed.prompt
                    }
                } else {
                    var command = Command(
                        title: parsed.name, summary: parsed.description, argumentHint: parsed.argumentHint, model: parsed.model,
                        tools: parsed.tools, prompt: parsed.prompt, author: author)
                    command.tags = ["claude-code"]
                    try saveCommand(command, slug: slug)
                }
                imported.append(slug)
            }
        }
        return imported
    }

    // MARK: Skills

    public func skillURL(_ slug: String) -> URL { skillsDir.appending(path: "\(slug).json") }

    public func listSkills() throws -> [(slug: String, skill: Skill)] {
        try listRecords(Skill.self, in: skillsDir).map { ($0.slug, $0.value) }
    }

    public func resolveSkillSlug(_ ref: String) throws -> String {
        try resolveSlug(ref, Skill.self, in: skillsDir) { .skillNotFound($0) }
    }

    public func loadSkill(_ slug: String) throws -> Skill {
        try loadRecord(slug, in: skillsDir) { .skillNotFound($0) }
    }

    public func saveSkill(_ skill: Skill, slug: String) throws {
        try ensureDirectories()
        try AtomicFile.write(VDJSON.encode(skill), to: skillURL(slug))
    }

    @discardableResult
    public func createSkill(
        title: String, summary: String? = nil, model: String? = nil, tools: [String] = [], prompt: String = "",
        tags: [String] = [], author: Author = .human
    ) throws -> (slug: String, skill: Skill) {
        guard let title = title.trimmed.nonEmpty else { throw VibeDeckError.invalidName }
        let slug = uniqueSlug(Slug.make(title), in: skillsDir, ext: "json")
        let skill = Skill(title: title, summary: summary, model: model, tools: tools, prompt: prompt, tags: tags, author: author)
        try saveSkill(skill, slug: slug)
        return (slug, skill)
    }

    @discardableResult
    public func updateSkill(_ ref: String, _ change: (inout Skill) throws -> Void) throws -> (slug: String, skill: Skill) {
        let slug = try resolveSkillSlug(ref)
        var skill = try loadSkill(slug)
        try change(&skill)
        skill.updatedAt = .now
        try saveSkill(skill, slug: slug)
        return (slug, skill)
    }

    public func deleteSkill(_ slug: String) throws {
        try FileManager.default.removeItem(at: skillURL(slug))
    }

    /// Appends a next step to a skill's flow (same rules as `addNextStep(to:)` for agents).
    @discardableResult
    public func addSkillNextStep(to ref: String, kind: NextStepKind = .agent, target: String, note: String? = nil) throws -> (slug: String, skill: Skill) {
        let from = try resolveSkillSlug(ref)
        let stored = try resolveNextStepTarget(kind: kind, target: target, excluding: (.skill, from))
        return try updateSkill(from) { skill in
            guard !skill.nextSteps.contains(where: { $0.kind == kind && $0.ref == stored }) else { return }
            skill.nextSteps.append(NextStep(kind: kind, ref: stored, note: note?.trimmed.nonEmpty))
        }
    }

    /// Imports Claude Code skills (`<project>/.claude/skills/<name>/SKILL.md` and `~/.claude/skills/<name>/SKILL.md`)
    /// as VibeDeck skills. Only `SKILL.md` is read; supporting files stay where they are. Existing skills (same slug)
    /// are skipped unless `overwrite`. Returns the slugs created/updated.
    @discardableResult
    public func importClaudeSkills(from dirs: [URL]? = nil, overwrite: Bool = false, author: Author = .human) throws -> [String] {
        let fm = FileManager.default
        let sources = dirs ?? [
            root.appending(path: ".claude/skills", directoryHint: .isDirectory),
            fm.homeDirectoryForCurrentUser.appending(path: ".claude/skills", directoryHint: .isDirectory),
        ]
        var imported: [String] = []
        var seen = Set<String>()
        for dir in sources {
            guard let folders = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
            for folder in folders.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                guard let text = try? String(contentsOf: folder.appending(path: "SKILL.md"), encoding: .utf8) else { continue }
                let parsed = ClaudeSkillFile.parse(text, fallbackName: folder.lastPathComponent)
                let slug = Slug.make(parsed.name)
                guard seen.insert(slug).inserted else { continue }  // project dir wins over user dir
                if fm.fileExists(atPath: skillURL(slug).path) {
                    guard overwrite else { continue }
                    try updateSkill(slug) {
                        $0.summary = parsed.description; $0.model = parsed.model; $0.tools = parsed.tools; $0.prompt = parsed.prompt
                        $0.sourcePath = folder.appending(path: "SKILL.md").path
                    }
                } else {
                    var skill = Skill(title: parsed.name, summary: parsed.description, model: parsed.model, tools: parsed.tools, prompt: parsed.prompt, author: author)
                    skill.tags = ["claude-code"]
                    skill.sourcePath = folder.appending(path: "SKILL.md").path
                    try saveSkill(skill, slug: slug)
                }
                imported.append(slug)
            }
        }
        return imported
    }


    // MARK: Workflows

    public func workflowURL(_ slug: String) -> URL { workflowsDir.appending(path: "\(slug).json") }

    public func listWorkflows() throws -> [(slug: String, workflow: Workflow)] {
        try listRecords(Workflow.self, in: workflowsDir).map { ($0.slug, $0.value) }
    }

    public func resolveWorkflowSlug(_ ref: String) throws -> String {
        try resolveSlug(ref, Workflow.self, in: workflowsDir) { .workflowNotFound($0) }
    }

    public func loadWorkflow(_ slug: String) throws -> Workflow {
        try loadRecord(slug, in: workflowsDir) { .workflowNotFound($0) }
    }

    public func saveWorkflow(_ workflow: Workflow, slug: String) throws {
        try ensureDirectories()
        try AtomicFile.write(VDJSON.encode(workflow), to: workflowURL(slug))
    }

    @discardableResult
    public func createWorkflow(
        title: String, summary: String? = nil, input: String? = nil, maxSteps: Int? = nil, tags: [String] = [],
        author: Author = .human
    ) throws -> (slug: String, workflow: Workflow) {
        guard let title = title.trimmed.nonEmpty else { throw VibeDeckError.invalidName }
        let slug = uniqueSlug(Slug.make(title), in: workflowsDir, ext: "json")
        let workflow = Workflow(title: title, summary: summary, input: input, maxSteps: maxSteps, tags: tags, author: author)
        try saveWorkflow(workflow, slug: slug)
        return (slug, workflow)
    }

    @discardableResult
    public func updateWorkflow(_ ref: String, _ change: (inout Workflow) throws -> Void) throws -> (slug: String, workflow: Workflow) {
        let slug = try resolveWorkflowSlug(ref)
        var workflow = try loadWorkflow(slug)
        try change(&workflow)
        workflow.updatedAt = .now
        try saveWorkflow(workflow, slug: slug)
        return (slug, workflow)
    }

    public func deleteWorkflow(_ slug: String) throws {
        try FileManager.default.removeItem(at: workflowURL(slug))
    }

    /// Appends a step running an existing VibeDeck agent/command/skill (the same one may appear more than once).
    /// Returns the new step's id, unique inside the workflow.
    @discardableResult
    public func addWorkflowStep(
        to ref: String, kind: NextStepKind = .agent, target: String, note: String? = nil
    ) throws -> (slug: String, workflow: Workflow, step: String) {
        let stored = try resolveStepTarget(kind: kind, target: target)
        var id = ""
        let (slug, workflow) = try updateWorkflow(ref) { workflow in
            id = workflow.newStepId(stored)
            workflow.steps.append(WorkflowStep(id: id, kind: kind, ref: stored, note: note?.trimmed.nonEmpty))
        }
        return (slug, workflow, id)
    }

    /// Removes a step (by id or 1-based position) and the transitions pointing to it.
    @discardableResult
    public func removeWorkflowStep(_ ref: String, step: String) throws -> (slug: String, workflow: Workflow) {
        try updateWorkflow(ref) { workflow in
            workflow.removeStep(at: try stepIndex(step, in: workflow))
        }
    }

    /// Moves a step to a 1-based `position` (position 1 makes it the start).
    @discardableResult
    public func moveWorkflowStep(_ ref: String, step: String, to position: Int) throws -> (slug: String, workflow: Workflow) {
        try updateWorkflow(ref) { workflow in
            let from = try stepIndex(step, in: workflow)
            let moved = workflow.steps.remove(at: from)
            workflow.steps.insert(moved, at: min(max(position - 1, 0), workflow.steps.count))
        }
    }

    /// Adds a transition `from` → `to` (both steps of the workflow; going back is allowed). `verdict` matches the
    /// exact last line of the step's result; `when` is a natural-language condition. With neither it is the fallback
    /// ("senão"); only one per step, and it stays last because the first matching transition wins.
    @discardableResult
    public func addWorkflowTransition(
        _ ref: String, from: String, to: String, when: String? = nil, verdict: String? = nil
    ) throws -> (slug: String, workflow: Workflow) {
        try updateWorkflow(ref) { workflow in
            let source = try stepIndex(from, in: workflow)
            let target = workflow.steps[try stepIndex(to, in: workflow)].id
            let transition = WorkflowTransition(verdict: verdict?.trimmed.nonEmpty, when: when?.trimmed.nonEmpty, to: target)
            if transition.isFallback, workflow.steps[source].transitions.contains(where: { $0.isFallback && $0.to != target }) {
                throw VibeDeckError.invalidWorkflow("a etapa \(workflow.steps[source].id) já tem uma transição sem condição (senão).")
            }
            workflow.addTransition(transition, toStepAt: source)
        }
    }

    /// Sets (or clears, with nil) the most runs of a step per execution.
    @discardableResult
    public func setWorkflowStepMaxVisits(_ ref: String, step: String, maxVisits: Int?) throws -> (slug: String, workflow: Workflow) {
        try updateWorkflow(ref) { workflow in
            workflow.steps[try stepIndex(step, in: workflow)].maxVisits = maxVisits.flatMap { $0 > 0 ? $0 : nil }
        }
    }

    /// Removes the transition at 1-based `index` of a step.
    @discardableResult
    public func removeWorkflowTransition(_ ref: String, from: String, index: Int) throws -> (slug: String, workflow: Workflow) {
        try updateWorkflow(ref) { workflow in
            let source = try stepIndex(from, in: workflow)
            guard workflow.steps[source].transitions.indices.contains(index - 1) else {
                throw VibeDeckError.invalidWorkflow("a etapa \(workflow.steps[source].id) não tem a transição \(index).")
            }
            workflow.steps[source].transitions.remove(at: index - 1)
        }
    }

    /// JSON plan that orchestrates the AI through the workflow.
    public func workflowPlan(_ ref: String, input: String? = nil) throws -> WorkflowPlan {
        let slug = try resolveWorkflowSlug(ref)
        return WorkflowPlan.build(
            slug: slug, workflow: try loadWorkflow(slug), input: input,
            agents: try listAgents(), commands: try listCommands(), skills: try listSkills()
        )
    }

    // MARK: Workflow runs

    public func runDir(workflow: String, run: String) -> URL {
        runsDir.appending(path: workflow, directoryHint: .isDirectory).appending(path: run, directoryHint: .isDirectory)
    }

    public func runURL(_ ref: String) -> URL {
        let (workflow, run) = Self.splitRunRef(ref)
        return runDir(workflow: workflow, run: run).appending(path: "run.json")
    }

    /// Every run, newest first, as `(ref: "<workflow>/<run>", run)`.
    public func listRuns(workflow: String? = nil) throws -> [(ref: String, run: WorkflowRun)] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: runsDir.path) else { return [] }
        let workflows = try workflow.map { [try resolveWorkflowSlug($0)] }
            ?? fm.contentsOfDirectory(atPath: runsDir.path).filter { !$0.hasPrefix(".") }
        var out: [(ref: String, run: WorkflowRun)] = []
        for wf in workflows {
            let dir = runsDir.appending(path: wf, directoryHint: .isDirectory)
            for name in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] where !name.hasPrefix(".") {
                let url = dir.appending(path: name, directoryHint: .isDirectory).appending(path: "run.json")
                guard let data = fm.contents(atPath: url.path), let run = try? VDJSON.decoder.decode(WorkflowRun.self, from: data) else { continue }
                out.append(("\(wf)/\(name)", run))
            }
        }
        return out.sorted { ($0.run.updatedAt, $0.ref) > ($1.run.updatedAt, $1.ref) }
    }

    /// Resolves `<workflow>/<run>`, a run name unique across workflows, or a run id (prefix >= 4 chars).
    public func resolveRunRef(_ ref: String) throws -> String {
        let ref = ref.trimmed
        let runs = try listRuns()
        if let exact = runs.first(where: { $0.ref == ref }) { return exact.ref }
        let needle = ref.lowercased()
        let matches = runs.filter {
            $0.ref.split(separator: "/").last.map(String.init) == ref || $0.run.id.uuidString.lowercased() == needle
                || (needle.count >= 4 && $0.run.id.uuidString.lowercased().hasPrefix(needle))
        }
        guard let first = matches.first else { throw VibeDeckError.runNotFound(ref) }
        guard matches.count == 1 else { throw VibeDeckError.invalidWorkflow("execução ambígua: \(ref); use <workflow>/<execução>.") }
        return first.ref
    }

    public func loadRun(_ ref: String) throws -> WorkflowRun {
        let url = runURL(ref)
        guard let data = FileManager.default.contents(atPath: url.path) else { throw VibeDeckError.runNotFound(ref) }
        return try VDJSON.decoder.decode(WorkflowRun.self, from: data)
    }

    public func saveRun(_ run: WorkflowRun, ref: String) throws {
        try AtomicFile.write(VDJSON.encode(run), to: runURL(ref))
    }

    /// Starts a run of a workflow. The run is named after the input, so starting again with the same input resumes
    /// it: an unfinished run stays where it is, a finished one starts a new cycle (from `from`, or the start).
    @discardableResult
    public func startRun(_ workflowRef: String, input: String? = nil, from: String? = nil, provider: AIProvider? = nil) throws -> (ref: String, run: WorkflowRun, action: WorkflowRunAction) {
        let slug = try resolveWorkflowSlug(workflowRef)
        let workflow = try loadWorkflow(slug)
        guard !workflow.steps.isEmpty else { throw VibeDeckError.invalidWorkflow("o workflow não tem etapas.") }
        let input = input?.trimmed.nonEmpty
        let name: String
        if let input {
            name = Slug.make(input)
        } else {
            let stamp = Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false).dateTimeSeparator(.standard))
            name = uniqueSlug("execucao-" + Slug.make(stamp), in: runsDir.appending(path: slug, directoryHint: .isDirectory), ext: "")
        }
        let ref = "\(slug)/\(name)"
        var run: WorkflowRun
        if FileManager.default.fileExists(atPath: runURL(ref).path) {
            run = try loadRun(ref)
            try WorkflowRunEngine.restart(&run, workflow: workflow, from: from)
        } else {
            run = WorkflowRun(workflow: slug, input: input, start: workflow.steps.first?.id, provider: provider ?? .claude)
            if let from { try WorkflowRunEngine.restart(&run, workflow: workflow, from: from) }
        }
        try saveRun(run, ref: ref)
        return (ref, run, nextRunAction(run, ref: ref, workflow: workflow))
    }

    /// What the orchestrator does now.
    public func nextRunAction(_ ref: String) throws -> WorkflowRunAction {
        let ref = try resolveRunRef(ref)
        let run = try loadRun(ref)
        return nextRunAction(run, ref: ref, workflow: try loadWorkflow(run.workflow))
    }

    private func nextRunAction(_ run: WorkflowRun, ref: String, workflow: Workflow) -> WorkflowRunAction {
        WorkflowRunEngine.next(run, ref: ref, workflow: workflow) { step in
            let r = resolvedStep(step, provider: run.provider)
            return (r.title, r.model)
        }
    }

    /// Records the current step's verdict and returns the next action (`decide` when conditions must be judged).
    @discardableResult
    public func recordRun(
        _ ref: String, verdict: String?, summary: String?, to: String? = nil, noneHolds: Bool = false
    ) throws -> WorkflowRunAction {
        let ref = try resolveRunRef(ref)
        var run = try loadRun(ref)
        let workflow = try loadWorkflow(run.workflow)
        if let decide = try WorkflowRunEngine.record(&run, workflow: workflow, verdict: verdict, summary: summary, to: to, noneHolds: noneHolds, ref: ref) {
            return decide
        }
        try saveRun(run, ref: ref)
        return nextRunAction(run, ref: ref, workflow: workflow)
    }

    @discardableResult
    public func askRun(_ ref: String, questions: [WorkflowQuestionDraft]) throws -> [WorkflowQuestion] {
        let ref = try resolveRunRef(ref)
        var run = try loadRun(ref)
        let added = try WorkflowRunEngine.ask(&run, drafts: questions)
        try saveRun(run, ref: ref)
        return added
    }

    @discardableResult
    public func answerRun(_ ref: String, number: Int, answer: String) throws -> WorkflowRunAction {
        let ref = try resolveRunRef(ref)
        var run = try loadRun(ref)
        try WorkflowRunEngine.answer(&run, number: number, text: answer)
        try saveRun(run, ref: ref)
        return nextRunAction(run, ref: ref, workflow: try loadWorkflow(run.workflow))
    }

    @discardableResult
    public func stopRun(_ ref: String, reason: String? = nil) throws -> WorkflowRun {
        let ref = try resolveRunRef(ref)
        var run = try loadRun(ref)
        WorkflowRunEngine.stop(&run, reason: reason)
        try saveRun(run, ref: ref)
        return run
    }

    public func deleteRun(_ ref: String) throws {
        let ref = try resolveRunRef(ref)
        try FileManager.default.removeItem(at: runURL(ref).deletingLastPathComponent())
    }

    /// The prompt of the run's current step, for the subagent that runs it.
    public func runStepPrompt(_ ref: String, cli: String = "vibedeck") throws -> String {
        let ref = try resolveRunRef(ref)
        let run = try loadRun(ref)
        let workflow = try loadWorkflow(run.workflow)
        guard !run.isFinished, let current = run.current, let step = workflow.steps.first(where: { $0.id == current }) else {
            throw VibeDeckError.invalidWorkflow("a execução \(ref) não tem etapa a rodar (\(run.status.rawValue)).")
        }
        let resolved = resolvedStep(step, provider: run.provider)
        let (wf, name) = Self.splitRunRef(ref)
        return WorkflowOrchestration.stepPrompt(
            run: run, ref: ref, workflow: workflow, step: step, title: resolved.title, instructions: resolved.prompt,
            runDir: runDir(workflow: wf, run: name), cli: cli
        )
    }

    private func resolvedStep(_ step: WorkflowStep, provider: AIProvider = .claude) -> (title: String?, model: String?, prompt: String?) {
        switch step.kind {
        case .agent: (try? loadAgent(step.ref)).map { ($0.title, $0.providerSettings?[provider.rawValue]?.model ?? $0.model, $0.prompt) } ?? (nil, nil, nil)
        case .command: (try? loadCommand(step.ref)).map { ($0.title, $0.providerSettings?[provider.rawValue]?.model ?? $0.model, $0.prompt) } ?? (nil, nil, nil)
        case .skill: (try? loadSkill(step.ref)).map { ($0.title, $0.providerSettings?[provider.rawValue]?.model ?? $0.model, $0.prompt + ($0.sourcePath.map { "\nRecursos da skill: \(URL(fileURLWithPath: $0).deletingLastPathComponent().path)" } ?? "")) } ?? (nil, nil, nil)
        }
    }

    static func splitRunRef(_ ref: String) -> (workflow: String, run: String) {
        let parts = ref.split(separator: "/", maxSplits: 1).map(String.init)
        return parts.count == 2 ? (parts[0], parts[1]) : ("", ref)
    }

    private func stepIndex(_ step: String, in workflow: Workflow) throws -> Int {
        guard let i = workflow.stepIndex(step) else { throw VibeDeckError.invalidWorkflow("etapa não encontrada: \(step).") }
        return i
    }

    // MARK: Ideas

    public func ideaURL(_ slug: String) -> URL { ideasDir.appending(path: "\(slug).json") }

    public func listIdeas() throws -> [(slug: String, idea: Idea)] {
        try listRecords(Idea.self, in: ideasDir).map { ($0.slug, $0.value) }
    }

    public func resolveIdeaSlug(_ ref: String) throws -> String {
        try resolveSlug(ref, Idea.self, in: ideasDir) { .ideaNotFound($0) }
    }

    public func loadIdea(_ slug: String) throws -> Idea {
        try loadRecord(slug, in: ideasDir) { .ideaNotFound($0) }
    }

    public func saveIdea(_ idea: Idea, slug: String) throws {
        try ensureDirectories()
        try AtomicFile.write(VDJSON.encode(idea), to: ideaURL(slug))
    }

    @discardableResult
    public func createIdea(title: String, body: String? = nil, tags: [String] = [], author: Author = .human) throws -> (slug: String, idea: Idea) {
        guard let title = title.trimmed.nonEmpty else { throw VibeDeckError.invalidName }
        let slug = uniqueSlug(Slug.make(title), in: ideasDir, ext: "json")
        let idea = Idea(title: title, body: body, tags: tags, author: author)
        try saveIdea(idea, slug: slug)
        return (slug, idea)
    }

    @discardableResult
    public func updateIdea(_ ref: String, _ change: (inout Idea) throws -> Void) throws -> (slug: String, idea: Idea) {
        let slug = try resolveIdeaSlug(ref)
        var idea = try loadIdea(slug)
        try change(&idea)
        idea.updatedAt = .now
        try saveIdea(idea, slug: slug)
        return (slug, idea)
    }

    public func deleteIdea(_ slug: String) throws {
        try FileManager.default.removeItem(at: ideaURL(slug))
    }

    /// Commits a removed idea on its own: `git commit -- <file>` records only that path, so anything else staged
    /// stays staged. Returns false (and does nothing) outside a git repo, when the idea was never tracked or when
    /// the commit fails (e.g. a pre-commit hook rejected it).
    @discardableResult
    public func commitIdeaRemoval(_ slug: String, title: String) -> Bool {
        let path = String(ideaURL(slug).path.dropFirst(root.path.count + 1))
        guard Git.run(["ls-files", "--error-unmatch", "--", path], in: root).ok else { return false }
        return Git.run(["commit", "--quiet", "-m", "chore(ideas): remove \"\(title)\"", "--", path], in: root).ok
    }

    @discardableResult
    public func addRule(_ rule: Rule, toIdea ideaRef: String) throws -> (slug: String, rule: Rule) {
        let (slug, _) = try updateIdea(ideaRef) { $0.rules.append(rule) }
        return (slug, rule)
    }

    /// Turns an idea's draft rules into a real (enforced) rule topic. Re-promoting syncs new rules
    /// into the existing topic instead of creating another one. The idea's `paths` become the topic's, or are
    /// added to them (none removed); `skippingPaths` leaves out globs the user chose not to copy.
    /// Returns the topic slug.
    @discardableResult
    public func promoteIdea(_ ref: String, skippingPaths: Set<String> = []) throws -> String {
        let ideaSlug = try resolveIdeaSlug(ref)
        let idea = try loadIdea(ideaSlug)
        let paths = idea.paths.filter { !skippingPaths.contains($0) }
        let topicSlug: String
        if let existing = idea.promotedTopic, let slug = try? resolveTopicSlug(existing) {
            try updateTopic(slug) { topic in
                let known = Set(topic.rules.map(\.id))
                topic.rules += idea.rules.filter { !known.contains($0.id) }
                topic.paths += paths.filter { !topic.paths.contains($0) }
            }
            topicSlug = slug
        } else {
            topicSlug = try createTopic(
                title: idea.title, description: "Regras vindas da ideia \"\(idea.title)\".", paths: paths, rules: idea.rules, sourceIdea: idea.id
            ).slug
        }
        try updateIdea(ideaSlug) { idea in
            idea.promotedTopic = topicSlug
            if !idea.status.isClosed { idea.status = .approved }
        }
        return topicSlug
    }

    /// Globs of the idea that no longer match any project file (renamed or deleted since they were suggested).
    public func unmatchedIdeaPaths(_ ref: String) throws -> [String] {
        let idea = try loadIdea(resolveIdeaSlug(ref))
        guard !idea.paths.isEmpty else { return [] }
        let files = ClaudeCompletion.projectFiles(root: root, limit: RuleDiscover.fileLimit).filter { !$0.hasSuffix("/") }
        return idea.paths.filter { glob in !files.contains { Glob.matches(glob, path: $0) } }
    }

    /// Undoes `promoteIdea`: deletes the idea's topic (if it still exists) and releases the idea.
    /// The draft rules stay in the idea. Returns the deleted topic slug, if any.
    @discardableResult
    public func unpromoteIdea(_ ref: String) throws -> String? {
        let ideaSlug = try resolveIdeaSlug(ref)
        guard let linked = try loadIdea(ideaSlug).promotedTopic else { return nil }
        let topicSlug = try? resolveTopicSlug(linked)
        if let topicSlug { try FileManager.default.removeItem(at: topicURL(topicSlug)) }
        try updateIdea(ideaSlug) { Self.release(&$0) }
        return topicSlug
    }

    /// Unpromotes ideas whose topic no longer exists (deleted by the app, the CLI or by hand).
    /// Idempotent. Returns the slugs of the ideas that changed.
    @discardableResult
    public func releaseOrphanedIdeas() throws -> [String] {
        var released: [String] = []
        for (slug, idea) in try listIdeas() {
            guard let linked = idea.promotedTopic, (try? resolveTopicSlug(linked)) == nil else { continue }
            try updateIdea(slug) { Self.release(&$0) }
            released.append(slug)
        }
        return released
    }

    /// Drops the topic link; an approved idea goes back to exploring, other statuses stay.
    private static func release(_ idea: inout Idea) {
        idea.promotedTopic = nil
        if idea.status == .approved { idea.status = .exploring }
    }

    // MARK: Checks

    /// Converts absolute paths inside the project to root-relative ones.
    public func relativePath(_ file: String) -> String {
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        var path = file.hasPrefix("/") ? URL(fileURLWithPath: file).standardizedFileURL.path : file
        if path.hasPrefix(rootPath) { path.removeFirst(rootPath.count) }
        if path.hasPrefix("./") { path.removeFirst(2) }
        return path
    }

    /// Topics that apply to a task: global ones (no `paths`), those whose globs match a touched file,
    /// and those named explicitly (slug, id or title).
    public func applicableTopics(files: [String], explicit: [String] = []) throws -> [(slug: String, topic: RuleTopic)] {
        let relative = files.map(relativePath)
        let named = Set(try explicit.map { try resolveTopicSlug($0) })
        return try listTopics().filter { entry in
            entry.topic.isGlobal || named.contains(entry.slug) || relative.contains { entry.topic.matches(file: $0) }
        }
    }

    /// Topics that gate a review item: its explicit `rules` plus topics matching its target file (and global ones).
    public func requiredTopics(for item: ReviewItem) throws -> [(slug: String, topic: RuleTopic)] {
        try applicableTopics(files: [item.target?.file].compactMap { $0 }, explicit: item.rules)
    }

    /// Files and topics of a task: the given ones plus the review item's target file and explicit topics.
    private func taskScope(files: [String], topics explicit: [String], reviewItem: String?) throws -> (files: [String], topics: [(slug: String, topic: RuleTopic)], item: UUID?) {
        var files = files.map(relativePath)
        var explicit = explicit
        var itemID: UUID?
        if let ref = reviewItem {
            let (_, group, index) = try findItem(ref)
            let item = group.items[index]
            itemID = item.id
            explicit += item.rules
            if let file = item.target?.file { files.append(relativePath(file)) }
        }
        return (Array(Set(files)).sorted(), try applicableTopics(files: files, explicit: explicit), itemID)
    }

    /// Runs the scripts of the applicable rules that are decided by a script (stale tests are skipped).
    /// `topics` alone (no files) runs exactly those topics.
    public func runRuleTests(
        files: [String] = [], topics explicit: [String] = [], reviewItem: String? = nil, onlyTopics: Bool = false,
        runner: RuleTestRunner = .live,
        onEvent: @Sendable (RuleScriptEvent) -> Void = { _ in }
    ) throws -> [RuleTestRun] {
        let scope = try taskScope(files: files, topics: explicit, reviewItem: reviewItem)
        let named = Set(try explicit.map { try resolveTopicSlug($0) })
        let topics = onlyTopics ? scope.topics.filter { named.contains($0.slug) } : scope.topics
        return runScripts(topics.flatMap { t in t.topic.rules.map { (t.slug, $0) } }, files: scope.files, runner: runner, onEvent: onEvent)
    }

    /// One at a time: scripts often share build directories (`swift test`, `npm test`) and would fight over locks.
    private func runScripts(_ rules: [(String, Rule)], files: [String], runner: RuleTestRunner, onEvent: @Sendable (RuleScriptEvent) -> Void = { _ in }) -> [RuleTestRun] {
        rules.compactMap { slug, rule in
            guard let command = rule.scriptCommand else { return nil }
            onEvent(.started(topic: slug, rule: rule, at: .now))
            let outcome = runner.run(command, .init(root: root, files: files, ruleId: rule.id))
            let run = RuleTestRun(topic: slug, rule: rule, command: command, outcome: outcome)
            onEvent(.finished(run, at: .now))
            return run
        }
    }

    /// Records a verification. Rules with a current script are decided by running it (answers for them are
    /// ignored). Every other applicable rule is verified only when answered; with `verifyManual` all of them must
    /// be answered, otherwise the unanswered ones are recorded as `pending`. The check passes when no `must`
    /// rule failed (`should` failures and stale tests become warnings).
    @discardableResult
    public func submitCheck(
        task: String, files: [String], topics explicit: [String] = [], reviewItem: String? = nil,
        answers: [RuleAnswer], verifyManual: Bool = false, author: Author = .ai, runner: RuleTestRunner = .live
    ) throws -> RuleCheck {
        let (files, topics, itemID) = try taskScope(files: files, topics: explicit, reviewItem: reviewItem)
        let candidates = topics.flatMap { t in t.topic.rules.map { (t.slug, $0) } }

        var answered: [UUID: RuleResult] = [:]
        for answer in answers {
            let (slug, rule) = try matchRule(answer.ruleId, in: candidates) { $0.1 }
            guard rule.testState.needsAgent else { continue }
            answered[rule.id] = RuleResult(topic: slug, ruleId: rule.id, verdict: answer.verdict, note: answer.note?.trimmed.nonEmpty)
        }
        let missing = candidates.filter { $0.1.testState.needsAgent && answered[$0.1.id] == nil }
        guard missing.isEmpty || !verifyManual else {
            throw VibeDeckError.incompleteCheck(missing.map { "[\($0.0)] \($0.1.id.uuidString.prefix(8)) \($0.1.text)" })
        }
        for run in runScripts(candidates, files: files, runner: runner) {
            answered[run.rule.id] = RuleResult(
                topic: run.topic, ruleId: run.rule.id, verdict: run.outcome.verdict,
                note: "\(run.command) (exit \(run.outcome.exitCode))\n\(run.outcome.output)".trimmed,
                source: .script, exitCode: run.outcome.exitCode
            )
        }

        return try saveRuleCheck(task: task, files: files, topics: topics, itemID: itemID, answered: answered, author: author)
    }

    /// Executes a fixed snapshot rather than reloading rules between phases.
    public func runRuleScripts(snapshot: [(slug: String, topic: RuleTopic)], runner: RuleTestRunner = .live,
                               onEvent: @Sendable (RuleScriptEvent) -> Void = { _ in }) -> [RuleTestRun] {
        runScripts(snapshot.flatMap { entry in entry.topic.rules.map { (entry.slug, $0) } }, files: [], runner: runner, onEvent: onEvent)
    }

    /// Saves a completed UI verification without executing its scripts again.
    @discardableResult
    public func completeRuleExecution(snapshot: [(slug: String, topic: RuleTopic)], results: [RuleResult]) throws -> RuleCheck {
        for entry in snapshot {
            guard try loadTopic(entry.slug) == entry.topic else {
                throw RuleExecutionError.changed
            }
        }
        let candidates = snapshot.flatMap { entry in entry.topic.rules.map { (entry.slug, $0) } }
        guard results.count == candidates.count, Set(results.map(\.ruleId)).count == results.count,
              candidates.allSatisfy({ slug, rule in
                  results.contains { $0.ruleId == rule.id && $0.topic == slug && $0.source == (rule.scriptCommand == nil ? .agent : .script) }
              }) else { throw RuleExecutionError.incomplete }
        return try saveRuleCheck(task: "Verificação de regras pelo aplicativo", files: [], topics: snapshot, itemID: nil,
                                 answered: Dictionary(uniqueKeysWithValues: results.map { ($0.ruleId, $0) }), author: .ai)
    }

    private func saveRuleCheck(task: String, files: [String], topics: [(slug: String, topic: RuleTopic)], itemID: UUID?,
                               answered: [UUID: RuleResult], author: Author) throws -> RuleCheck {
        let candidates = topics.flatMap { entry in entry.topic.rules.map { (entry.slug, $0) } }
        let failed = candidates.filter { answered[$0.1.id]?.verdict == .fail }
        let stale = candidates.filter { $0.1.testState == .stale }.map { "Teste desatualizado (a regra mudou): \($0.1.text)" }
        let pending = candidates.filter { $0.1.testState.needsAgent && answered[$0.1.id] == nil }.map(\.1.text)
        let check = RuleCheck(
            task: task, files: files, topics: topics.map(\.slug), reviewItem: itemID,
            results: candidates.compactMap { answered[$0.1.id] },
            passed: !failed.contains { $0.1.severity == .must },
            warnings: failed.filter { $0.1.severity == .should }.map(\.1.text) + stale,
            failures: failed.filter { $0.1.severity == .must }.map(\.1.text),
            pending: pending,
            author: author
        )
        try ensureDirectories()
        try AtomicFile.write(VDJSON.encode(check), to: checksDir.appending(path: Self.checkFileName(check)))
        return check
    }

    static func checkFileName(_ check: RuleCheck) -> String {
        var style = Date.VerbatimFormatStyle(
            format: "\(year: .defaultDigits)\(month: .twoDigits)\(day: .twoDigits)-\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased))\(minute: .twoDigits)\(second: .twoDigits)",
            timeZone: .gmt, calendar: Calendar(identifier: .gregorian)
        )
        style.locale = Locale(identifier: "en_US_POSIX")
        return "\(check.createdAt.formatted(style))-\(check.id.uuidString.prefix(8).lowercased()).json"
    }

    /// All recorded checks, newest first.
    public func listChecks() throws -> [RuleCheck] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: checksDir.path) else { return [] }
        return try fm.contentsOfDirectory(at: checksDir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
            .filter { $0.pathExtension.lowercased() == "json" }
            .compactMap { url -> (check: RuleCheck, modified: Date)? in
                guard let check = try? VDJSON.decoder.decode(RuleCheck.self, from: Data(contentsOf: url)) else { return nil }
                return (check, (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? check.createdAt)
            }
            // JSON timestamps have second precision. Preserve actual order for checks in the same second.
            .sorted { ($0.check.createdAt, $0.modified) > ($1.check.createdAt, $1.modified) }
            .map(\.check)
    }

    /// Why an item can't be marked done yet (empty = verified). The latest check for the item must
    /// have passed and answered every rule currently in its required topics.
    public func verificationProblems(for item: ReviewItem) throws -> [String] {
        let required = try requiredTopics(for: item)
        let rules = required.flatMap { t in t.topic.rules.map { (t.slug, $0) } }
        guard !rules.isEmpty else { return [] }
        guard let check = try listChecks().first(where: { $0.reviewItem == item.id }) else {
            return ["Nenhum check registrado para este item (tópicos: \(required.map(\.slug).joined(separator: ", ")))."]
        }
        if !check.passed {
            return check.failures.map { "Falhou no último check: \($0)" }
        }
        let answered = Set(check.results.map(\.ruleId))
        return rules.filter { !answered.contains($0.1.id) }.compactMap { slug, rule in
            guard rule.testState.needsAgent else { return "Regra nova desde o último check: [\(slug)] \(rule.text)" }
            // A scripts-only check leaves manual rules unverified: only the mandatory ones hold the item back.
            return rule.severity == .must ? "Regra manual obrigatória sem verificação: [\(slug)] \(rule.text) (envie o check com as regras manuais respondidas)" : nil
        }
    }

    /// Throws `rulesNotVerified` unless the item may be marked done.
    public func ensureVerified(_ itemRef: String) throws {
        let (_, group, index) = try findItem(itemRef)
        let problems = try verificationProblems(for: group.items[index])
        if !problems.isEmpty { throw VibeDeckError.rulesNotVerified(problems) }
    }

    // MARK: Helpers

    private func listRecords<T: SlugRecord>(_ type: T.Type, in dir: URL) throws -> [(slug: String, value: T)] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir.path) else { return [] }
        return try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            .filter { $0.pathExtension.lowercased() == "json" }
            .compactMap { url in
                guard let value = try? VDJSON.decoder.decode(T.self, from: Data(contentsOf: url)) else { return nil }
                return (url.deletingPathExtension().lastPathComponent, value)
            }
            .sorted { ($0.value.createdAt, $0.slug) < ($1.value.createdAt, $1.slug) }
    }

    /// Resolves a record by slug, id (or unique id prefix >= 4 chars), or case-insensitive title.
    private func resolveSlug<T: SlugRecord>(
        _ ref: String, _ type: T.Type, in dir: URL, notFound: (String) -> VibeDeckError
    ) throws -> String {
        let records = try listRecords(type, in: dir)
        let needle = ref.lowercased()
        if let match = records.first(where: {
            $0.slug == ref
                || $0.value.id.uuidString.lowercased() == needle
                || $0.value.title.caseInsensitiveCompare(ref) == .orderedSame
                || $0.slug == Slug.make(ref)
        }) { return match.slug }
        let prefixed = needle.count >= 4 ? records.filter { $0.value.id.uuidString.lowercased().hasPrefix(needle) } : []
        if prefixed.count == 1 { return prefixed[0].slug }
        // Undecodable file: return it so loading reports the real decoding error.
        if FileManager.default.fileExists(atPath: dir.appending(path: "\(ref).json").path) { return ref }
        throw notFound(ref)
    }

    private func loadRecord<T: Decodable>(_ slug: String, in dir: URL, notFound: (String) -> VibeDeckError) throws -> T {
        let url = dir.appending(path: "\(slug).json")
        guard FileManager.default.fileExists(atPath: url.path) else { throw notFound(slug) }
        return try VDJSON.decoder.decode(T.self, from: Data(contentsOf: url))
    }

    private func matchRule<C>(_ ref: String, in candidates: [C], rule: (C) -> Rule) throws -> C {
        let needle = ref.trimmed.lowercased()
        if let exact = candidates.first(where: { rule($0).id.uuidString.lowercased() == needle }) { return exact }
        let matches = needle.count >= 4 ? candidates.filter { rule($0).id.uuidString.lowercased().hasPrefix(needle) } : []
        guard !matches.isEmpty else { throw VibeDeckError.ruleNotFound(ref) }
        guard matches.count == 1 else { throw VibeDeckError.ambiguousRule(ref) }
        return matches[0]
    }

    private func uniqueSlug(_ base: String, in dir: URL, ext: String) -> String {
        let fm = FileManager.default
        var slug = base
        var n = 2
        while fm.fileExists(atPath: dir.appending(path: ext.isEmpty ? slug : "\(slug).\(ext)").path) {
            slug = "\(base)-\(n)"
            n += 1
        }
        return slug
    }
}

/// A record stored as one JSON file per slug (review groups, rule topics, ideas).
protocol SlugRecord: Decodable {
    var id: UUID { get }
    var title: String { get }
    var createdAt: Date { get }
}

extension ReviewGroup: SlugRecord {}
extension RuleTopic: SlugRecord {}
extension Idea: SlugRecord {}
extension Agent: SlugRecord {}
extension Command: SlugRecord {}
extension Skill: SlugRecord {}
extension Workflow: SlugRecord {}

public enum AtomicFile {
    public static func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

public enum Slug {
    public static func make(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        var out = ""
        var lastDash = false
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar), scalar.isASCII {
                out.unicodeScalars.append(scalar)
                lastDash = false
            } else if !lastDash, !out.isEmpty {
                out.append("-")
                lastDash = true
            }
        }
        while out.hasSuffix("-") { out.removeLast() }
        return out.isEmpty ? "untitled" : String(out.prefix(60))
    }
}

public enum Markdown {
    /// Title from YAML frontmatter `title:` or the first `# ` heading.
    public static func title(of text: String) -> String? {
        let (front, body) = frontmatter(of: text)
        if let value = front?.first(where: { $0.hasPrefix("title:") })?
            .dropFirst("title:".count).trimmingCharacters(in: CharacterSet(charactersIn: " \"'")).nonEmpty {
            return value
        }
        for line in body where line.hasPrefix("# ") {
            return line.dropFirst(2).trimmingCharacters(in: .whitespaces).nonEmpty
        }
        return nil
    }

    /// Tags from YAML frontmatter: `tags: [a, b]` or `tags: a, b`.
    public static func tags(of text: String) -> [String] {
        guard let line = frontmatter(of: text).front?.first(where: { $0.hasPrefix("tags:") }) else { return [] }
        return line.dropFirst("tags:".count)
            .trimmingCharacters(in: CharacterSet(charactersIn: " []"))
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \"'")) }
            .filter { !$0.isEmpty }
    }

    /// Returns `text` with the frontmatter `tags:` line replaced, added (creating the frontmatter
    /// if needed) or removed when `tags` is empty. Everything else is preserved.
    public static func settingTags(_ tags: [String], in text: String) -> String {
        let tagLine = tags.isEmpty ? nil : "tags: [\(tags.joined(separator: ", "))]"
        let (front, body) = frontmatter(of: text)
        var lines = (front ?? []).filter { !$0.hasPrefix("tags:") }
        if let tagLine { lines.append(Substring(tagLine)) }
        let bodyText = body.joined(separator: "\n")
        guard !lines.isEmpty else { return bodyText }
        return (["---"] + lines + ["---"]).joined(separator: "\n") + "\n" + bodyText
    }

    /// Splits off YAML frontmatter (`front` is nil when there is none).
    private static func frontmatter(of text: String) -> (front: [Substring]?, body: ArraySlice<Substring>) {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)[...]
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" })
        else { return (nil, lines) }
        return (Array(lines[lines.startIndex + 1 ..< end]), lines[(end + 1)...])
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nonEmpty: String? { isEmpty ? nil : self }
}
