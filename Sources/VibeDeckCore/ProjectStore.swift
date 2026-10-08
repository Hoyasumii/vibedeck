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
    case ruleNotFound(String)
    case ambiguousRule(String)
    case incompleteCheck([String])
    case rulesNotVerified([String])
    case invalidName

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
        case .ruleNotFound(let s): "Regra não encontrada entre as aplicáveis: \(s)"
        case .ambiguousRule(let s): "Prefixo de id de regra ambíguo: \(s)"
        case .incompleteCheck(let missing):
            "Check incompleto: responda todas as regras aplicáveis (pass, fail ou na). Faltando:\n" + missing.map { "- \($0)" }.joined(separator: "\n")
        case .rulesNotVerified(let problems):
            "O item não pode ser concluído sem passar pelas regras:\n" + problems.map { "- \($0)" }.joined(separator: "\n")
                + "\nUse rules_for / submit_rule_check (ou `vibedeck rules check`) com o id do item."
        case .invalidName: "Nome inválido."
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
    public var checksDir: URL { dataDir.appending(path: "checks", directoryHint: .isDirectory) }
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
        for dir in [docsDir, reviewsDir, rulesDir, ideasDir, checksDir] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    public func writeAgentsGuide() throws {
        try ensureDirectories()
        try AtomicFile.write(Data(AgentsGuide.markdown.utf8), to: agentsURL)
    }

    /// Rewrites AGENTS.md only when this build's guide differs from what's on disk.
    public func refreshAgentsGuideIfNeeded() throws {
        let current = FileManager.default.contents(atPath: agentsURL.path)
        if current != Data(AgentsGuide.markdown.utf8) { try writeAgentsGuide() }
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
        title: String, description: String? = nil, tags: [String] = [], paths: [String] = [], rules: [Rule] = [], sourceIdea: UUID? = nil
    ) throws -> (slug: String, topic: RuleTopic) {
        guard let title = title.trimmed.nonEmpty else { throw VibeDeckError.invalidName }
        let slug = uniqueSlug(Slug.make(title), in: rulesDir, ext: "json")
        let topic = RuleTopic(title: title, description: description, tags: tags, paths: paths, rules: rules, sourceIdea: sourceIdea)
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

    public func deleteTopic(_ slug: String) throws {
        try FileManager.default.removeItem(at: topicURL(slug))
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
        topic.rules.remove(at: index)
        try saveTopic(topic, slug: slug)
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

    @discardableResult
    public func addRule(_ rule: Rule, toIdea ideaRef: String) throws -> (slug: String, rule: Rule) {
        let (slug, _) = try updateIdea(ideaRef) { $0.rules.append(rule) }
        return (slug, rule)
    }

    /// Turns an idea's draft rules into a real (enforced) rule topic. Re-promoting syncs new rules
    /// into the existing topic instead of creating another one. Returns the topic slug.
    @discardableResult
    public func promoteIdea(_ ref: String) throws -> String {
        let ideaSlug = try resolveIdeaSlug(ref)
        let idea = try loadIdea(ideaSlug)
        let topicSlug: String
        if let existing = idea.promotedTopic, let slug = try? resolveTopicSlug(existing) {
            try updateTopic(slug) { topic in
                let known = Set(topic.rules.map(\.id))
                topic.rules += idea.rules.filter { !known.contains($0.id) }
            }
            topicSlug = slug
        } else {
            topicSlug = try createTopic(
                title: idea.title, description: "Regras vindas da ideia \"\(idea.title)\".", rules: idea.rules, sourceIdea: idea.id
            ).slug
        }
        try updateIdea(ideaSlug) { idea in
            idea.promotedTopic = topicSlug
            if !idea.status.isClosed { idea.status = .approved }
        }
        return topicSlug
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

    /// Records an agent's verification. Every applicable rule must be answered; the check passes
    /// when no `must` rule failed (`should` failures become warnings).
    @discardableResult
    public func submitCheck(
        task: String, files: [String], topics explicit: [String] = [], reviewItem: String? = nil,
        answers: [RuleAnswer], author: Author = .ai
    ) throws -> RuleCheck {
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
        let topics = try applicableTopics(files: files, explicit: explicit)
        let candidates = topics.flatMap { t in t.topic.rules.map { (t.slug, $0) } }

        var answered: [UUID: RuleResult] = [:]
        for answer in answers {
            let (slug, rule) = try matchRule(answer.ruleId, in: candidates) { $0.1 }
            answered[rule.id] = RuleResult(topic: slug, ruleId: rule.id, verdict: answer.verdict, note: answer.note?.trimmed.nonEmpty)
        }
        let missing = candidates.filter { answered[$0.1.id] == nil }
        guard missing.isEmpty else {
            throw VibeDeckError.incompleteCheck(missing.map { "[\($0.0)] \($0.1.id.uuidString.prefix(8)) \($0.1.text)" })
        }

        let failed = candidates.filter { answered[$0.1.id]?.verdict == .fail }
        let check = RuleCheck(
            task: task, files: Array(Set(files)).sorted(), topics: topics.map(\.slug), reviewItem: itemID,
            results: candidates.compactMap { answered[$0.1.id] },
            passed: !failed.contains { $0.1.severity == .must },
            warnings: failed.filter { $0.1.severity == .should }.map(\.1.text),
            failures: failed.filter { $0.1.severity == .must }.map(\.1.text),
            author: author
        )
        try ensureDirectories()
        try AtomicFile.write(VDJSON.encode(check), to: checksDir.appending(path: Self.checkFileName(check)))
        return check
    }

    private static func checkFileName(_ check: RuleCheck) -> String {
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
        return try fm.contentsOfDirectory(at: checksDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            .filter { $0.pathExtension.lowercased() == "json" }
            .compactMap { try? VDJSON.decoder.decode(RuleCheck.self, from: Data(contentsOf: $0)) }
            .sorted { $0.createdAt > $1.createdAt }
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
        return rules.filter { !answered.contains($0.1.id) }.map { "Regra nova desde o último check: [\($0.0)] \($0.1.text)" }
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
        while fm.fileExists(atPath: dir.appending(path: "\(slug).\(ext)").path) {
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
