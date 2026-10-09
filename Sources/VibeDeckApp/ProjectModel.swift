import Foundation
import Observation
import SwiftUI
import VibeDeckCore

enum SidebarSection: String, CaseIterable, Hashable {
    case docs, groups, topics, ideas, agents, commands, skills, workflows

    var title: String {
        switch self {
        case .docs: "Docs"
        case .groups: "Revisões"
        case .topics: "Regras"
        case .ideas: "Ideias"
        case .agents: "Agentes"
        case .commands: "Comandos"
        case .skills: "Skills"
        case .workflows: "Workflows"
        }
    }

    var symbol: String {
        switch self {
        case .docs: "doc.text"
        case .groups: "checklist"
        case .topics: "checkmark.shield"
        case .ideas: "sparkle"
        case .agents: "person.crop.rectangle.stack"
        case .commands: "command"
        case .skills: "wand.and.stars"
        case .workflows: "point.3.connected.trianglepath.dotted"
        }
    }

    var emptyMessage: String {
        switch self {
        case .docs: "Sem documentos"
        case .groups: "Sem grupos de revisão"
        case .topics: "Sem tópicos de regras"
        case .ideas: "Sem ideias"
        case .agents: "Sem agentes"
        case .commands: "Sem comandos"
        case .skills: "Sem skills"
        case .workflows: "Sem workflows"
        }
    }
}

enum SidebarItem: Hashable {
    case stack
    case patterns
    case links
    case graph
    case claude
    case terminal(UUID)
    case section(SidebarSection)
    case doc(String)
    case group(String)
    case topic(String)
    case idea(String)
    case agent(String)
    case command(String)
    case skill(String)
    case workflow(String)

    var storageKey: String {
        switch self {
        case .stack: "stack"
        case .patterns: "patterns"
        case .links: "links"
        case .graph: "graph"
        case .claude: "claude"
        case .terminal(let id): "terminal:\(id.uuidString)"
        case .section(let section): "section:\(section.rawValue)"
        case .doc(let slug): "doc:\(slug)"
        case .group(let slug): "group:\(slug)"
        case .topic(let slug): "topic:\(slug)"
        case .idea(let slug): "idea:\(slug)"
        case .agent(let slug): "agent:\(slug)"
        case .command(let slug): "command:\(slug)"
        case .skill(let slug): "skill:\(slug)"
        case .workflow(let slug): "workflow:\(slug)"
        }
    }

    init?(storageKey: String?) {
        guard let key = storageKey else { return nil }
        if key == "stack" { self = .stack }
        else if key == "patterns" { self = .patterns }
        else if key == "links" { self = .links }
        else if key == "graph" { self = .graph }
        else if key == "claude" { self = .claude }
        else if key.hasPrefix("terminal:") {
            guard let id = UUID(uuidString: String(key.dropFirst(9))) else { return nil }
            self = .terminal(id)
        }
        else if key.hasPrefix("section:") {
            guard let section = SidebarSection(rawValue: String(key.dropFirst(8))) else { return nil }
            self = .section(section)
        }
        else if key.hasPrefix("doc:") { self = .doc(String(key.dropFirst(4))) }
        else if key.hasPrefix("group:") { self = .group(String(key.dropFirst(6))) }
        else if key.hasPrefix("topic:") { self = .topic(String(key.dropFirst(6))) }
        else if key.hasPrefix("idea:") { self = .idea(String(key.dropFirst(5))) }
        else if key.hasPrefix("agent:") { self = .agent(String(key.dropFirst(6))) }
        else if key.hasPrefix("command:") { self = .command(String(key.dropFirst(8))) }
        else if key.hasPrefix("skill:") { self = .skill(String(key.dropFirst(6))) }
        else if key.hasPrefix("workflow:") { self = .workflow(String(key.dropFirst(9))) }
        else { return nil }
    }

    var isTerminal: Bool {
        if case .terminal = self { true } else { false }
    }

    /// The sidebar section this item lives in (expanded while it is selected).
    var section: SidebarSection? {
        switch self {
        case .stack, .patterns, .links, .graph, .claude, .terminal: nil
        case .section(let section): section
        case .doc: .docs
        case .group: .groups
        case .topic: .topics
        case .idea: .ideas
        case .agent: .agents
        case .command: .commands
        case .skill: .skills
        case .workflow: .workflows
        }
    }
}

/// One child of a sidebar section, as shown in the section's list page.
struct SectionRow: Identifiable, Hashable {
    var id: SidebarItem
    var title: String
    var symbol: String
    var detail: String
    var count: String
    var tags: [String]
    var dimmed = false
}

/// In-memory mirror of a project folder. Every mutation is written to disk immediately;
/// external changes (CLI, MCP, AI editing files) are picked up through FSEvents.
@MainActor
@Observable
final class ProjectModel {
    let store: ProjectStore
    var project: Project
    var docs: [DocInfo] = []
    var groups: [GroupEntry] = []
    var topics: [Entry<RuleTopic>] = []
    var ideas: [Entry<Idea>] = []
    var agents: [Entry<Agent>] = []
    var commands: [Entry<Command>] = []
    var skills: [Entry<Skill>] = []
    var workflows: [Entry<Workflow>] = []
    /// Workflow runs, newest first (`slug` = `<workflow>/<run>`).
    var runs: [Entry<WorkflowRun>] = []
    /// All recorded rule checks, newest first.
    var checks: [RuleCheck] = []
    /// Last "Rodar testes" outcome per rule (in memory only; checks are what gets recorded).
    var testRuns: [UUID: RuleTestOutcome] = [:]
    /// Topics whose scripts are running right now.
    var runningTests: Set<String> = []
    var ruleExecution: RuleExecutionModel?
    var errorMessage: String?

    /// Bumped whenever a doc file changes on disk from outside the app.
    var externalDocChange: [String: Int] = [:]

    struct GroupEntry: Identifiable, Equatable {
        var slug: String
        var group: ReviewGroup
        var id: String { slug }
    }

    struct Entry<Value: Equatable>: Identifiable, Equatable {
        var slug: String
        var value: Value
        var id: String { slug }
    }

    @ObservationIgnored private var watcher: FileWatcher?
    /// Last bytes the app wrote per file path, so our own writes don't trigger reloads.
    @ObservationIgnored private var lastWritten: [String: Data] = [:]

    init(store: ProjectStore) {
        self.store = store
        self.project = (try? store.loadProject()) ?? Project(name: store.root.lastPathComponent)
        try? store.ensureDirectories()
        try? store.refreshAgentsGuideIfNeeded()
        // Topics deleted while the app was closed unpromote their ideas.
        _ = try? store.releaseOrphanedIdeas()
        _ = try? store.releaseOrphanedPatterns()
        reloadDocs()
        reloadGroups()
        reloadTopics()
        reloadIdeas()
        reloadAgents()
        reloadCommands()
        reloadSkills()
        reloadWorkflows()
        reloadRuns()
        reloadChecks()
    }

    func startWatching() {
        guard watcher == nil else { return }
        let watcher = FileWatcher(root: store.root) { [weak self] urls in
            Task { @MainActor in self?.handleExternalChanges(urls) }
        }
        watcher.start()
        self.watcher = watcher
    }

    func stopWatching() {
        watcher?.stop()
        watcher = nil
    }

    // MARK: Disk sync

    private func handleExternalChanges(_ urls: [URL]) {
        var docsChanged = false, groupsChanged = false, projectChanged = false
        var topicsChanged = false, ideasChanged = false, agentsChanged = false, commandsChanged = false, skillsChanged = false, workflowsChanged = false, runsChanged = false, checksChanged = false
        for url in Set(urls.map { $0.resolvingSymlinksInPath().path }) {
            let current = FileManager.default.contents(atPath: url)
            if let current, current == lastWritten[url] { continue }
            if url.contains("/\(ProjectStore.dataDirName)/runs/") {
                // Before the others: the steps' artifacts inside a run may have any name.
                runsChanged = true
            } else if url.hasSuffix("/" + ProjectStore.manifestName) {
                projectChanged = true
            } else if url.contains("/docs/") {
                docsChanged = true
                let slug = URL(fileURLWithPath: url).deletingPathExtension().lastPathComponent
                externalDocChange[slug, default: 0] += 1
            } else if url.contains("/reviews/") {
                groupsChanged = true
            } else if url.contains("/rules/") {
                topicsChanged = true
            } else if url.contains("/ideas/") {
                ideasChanged = true
            } else if url.contains("/agents/") {
                agentsChanged = true
            } else if url.contains("/commands/") {
                commandsChanged = true
            } else if url.contains("/skills/") {
                skillsChanged = true
            } else if url.contains("/workflows/") {
                workflowsChanged = true

            } else if url.contains("/checks/") {
                checksChanged = true
            }
        }
        // A topic deleted outside the app (Finder, rm, CLI) unpromotes the idea it came from.
        if topicsChanged, let released = try? store.releaseOrphanedIdeas(), !released.isEmpty { ideasChanged = true }
        // ...and drops the pattern it enforced.
        if topicsChanged, let dropped = try? store.releaseOrphanedPatterns(), !dropped.isEmpty { projectChanged = true }
        if projectChanged, let p = try? store.loadProject(), p != project { project = p }
        if docsChanged { reloadDocs() }
        if groupsChanged { reloadGroups() }
        if topicsChanged { reloadTopics() }
        if ideasChanged { reloadIdeas() }
        if agentsChanged { reloadAgents() }
        if commandsChanged { reloadCommands() }
        if skillsChanged { reloadSkills() }
        if workflowsChanged { reloadWorkflows() }
        if runsChanged { reloadRuns() }
        if checksChanged { reloadChecks() }
    }

    func reloadTopics() {
        let list = ((try? store.listTopics()) ?? []).map { Entry(slug: $0.slug, value: $0.topic) }
        if list != topics { topics = list }
    }

    func reloadIdeas() {
        let list = ((try? store.listIdeas()) ?? []).map { Entry(slug: $0.slug, value: $0.idea) }
        if list != ideas { ideas = list }
    }

    func reloadAgents() {
        let list = ((try? store.listAgents()) ?? []).map { Entry(slug: $0.slug, value: $0.agent) }
        if list != agents { agents = list }
    }

    func reloadCommands() {
        let list = ((try? store.listCommands()) ?? []).map { Entry(slug: $0.slug, value: $0.command) }
        if list != commands { commands = list }
    }

    func reloadSkills() {
        let list = ((try? store.listSkills()) ?? []).map { Entry(slug: $0.slug, value: $0.skill) }
        if list != skills { skills = list }
    }

    func reloadWorkflows() {
        let list = ((try? store.listWorkflows()) ?? []).map { Entry(slug: $0.slug, value: $0.workflow) }
        if list != workflows { workflows = list }
    }

    func reloadRuns() {
        let list = ((try? store.listRuns()) ?? []).map { Entry(slug: $0.ref, value: $0.run) }
        if list != runs { runs = list }
    }

    func reloadChecks() {
        let list = (try? store.listChecks()) ?? []
        if list != checks { checks = list }
    }

    func reloadDocs() {
        let list = (try? store.listDocs()) ?? []
        if list != docs { docs = list }
    }

    func reloadGroups() {
        let list = ((try? store.listGroups()) ?? []).map { GroupEntry(slug: $0.slug, group: $0.group) }
        if list != groups { groups = list }
    }

    private func write(_ data: Data, to url: URL) {
        do {
            lastWritten[url.resolvingSymlinksInPath().path] = data
            try AtomicFile.write(data, to: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Project / links

    func mutateProject(_ actionName: String, undo: UndoManager?, _ change: (inout Project) -> Void) {
        let old = project
        change(&project)
        guard project != old else { return }
        saveProject()
        undo?.registerUndo(withTarget: self) { model in
            model.mutateProject(actionName, undo: undo) { $0 = old }
        }
        undo?.setActionName(actionName)
    }

    /// Changes the stack like `mutateProject`, then rewrites README.md's stack badge in the background.
    func mutateStack(_ actionName: String, undo: UndoManager?, _ change: (inout [StackItem]) -> Void) {
        let old = project.stack
        var new = old
        change(&new)
        guard new != old else { return }
        project.stack = new
        saveProject()
        syncReadmeStack()
        undo?.registerUndo(withTarget: self) { model in
            model.mutateStack(actionName, undo: undo) { $0 = old }
        }
        undo?.setActionName(actionName)
    }

    // MARK: Patterns

    /// The patterns plus the files of their rule topics: what a pattern change touches, so undo can put it back.
    struct PatternsSnapshot {
        var patterns: [ProjectPattern]
        var topics: [String: Data]
    }

    private func patternsSnapshot() -> PatternsSnapshot {
        let topics = ((try? store.listTopics()) ?? []).filter { $0.topic.sourcePattern != nil }
        var files: [String: Data] = [:]
        for (slug, _) in topics { files[slug] = FileManager.default.contents(atPath: store.topicURL(slug).path) }
        return PatternsSnapshot(patterns: (try? store.loadProject().patterns) ?? project.patterns, topics: files)
    }

    /// Writes a snapshot back: pattern topics not in it are deleted, the others rewritten, the patterns restored.
    private func restorePatterns(_ snapshot: PatternsSnapshot, _ actionName: String, undo: UndoManager?) {
        let current = patternsSnapshot()
        for slug in current.topics.keys where snapshot.topics[slug] == nil {
            try? FileManager.default.removeItem(at: store.topicURL(slug))
        }
        for (slug, data) in snapshot.topics where current.topics[slug] != data { write(data, to: store.topicURL(slug)) }
        project.patterns = snapshot.patterns
        saveProject()
        reloadTopics()
        undo?.registerUndo(withTarget: self) { model in model.restorePatterns(current, actionName, undo: undo) }
        undo?.setActionName(actionName)
    }

    /// Runs a pattern change through the store (it also writes the pattern's rule topic), then refreshes both.
    /// Undo restores the patterns and their topic files as they were.
    @discardableResult
    func changePatterns<T>(_ actionName: String, undo: UndoManager?, _ change: (ProjectStore) throws -> T) -> T? {
        let before = patternsSnapshot()
        do {
            let result = try change(store)
            reloadProject()
            reloadTopics()
            undo?.registerUndo(withTarget: self) { model in model.restorePatterns(before, actionName, undo: undo) }
            undo?.setActionName(actionName)
            return result
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Moves a pattern (order only lives in vibedeck.json, so it can be undone).
    func movePatterns(from source: IndexSet, to destination: Int, undo: UndoManager?) {
        mutateProject("Reordenar padrões", undo: undo) { $0.patterns.move(fromOffsets: source, toOffset: destination) }
    }

    private func reloadProject() {
        if let p = try? store.loadProject(), p != project { project = p }
    }

    @ObservationIgnored private var readmeSync: Task<Void, Never>?
    /// Last README.md sync problem (offline Skill Icons, unwritable file); shown in the Stack page.
    var readmeWarning: String?

    private func syncReadmeStack() {
        readmeSync?.cancel()
        let service = StackService(store: store)
        readmeSync = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            let warning = await service.syncReadme()
            guard !Task.isCancelled else { return }
            self?.readmeWarning = warning
        }
    }

    private func saveProject() {
        guard let data = try? VDJSON.encode(project) else { return }
        write(data, to: store.manifestURL)
    }

    // MARK: Docs

    func createDoc(title: String) -> String? {
        do {
            let slug = try store.createDoc(title: title)
            reloadDocs()
            return slug
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// One undo history per doc, so Cmd+Z never crosses documents and survives switching between them.
    @ObservationIgnored private var docUndoManagers: [String: UndoManager] = [:]

    func undoManager(forDoc slug: String) -> UndoManager {
        if let existing = docUndoManagers[slug] { return existing }
        let manager = UndoManager()
        docUndoManagers[slug] = manager
        return manager
    }

    func readDoc(_ slug: String) -> String {
        (try? store.readDoc(slug)) ?? ""
    }

    func saveDoc(_ slug: String, text: String) {
        write(Data(text.utf8), to: store.docURL(slug))
        let title = Markdown.title(of: text) ?? slug
        if let i = docs.firstIndex(where: { $0.slug == slug }), docs[i].title != title {
            docs[i].title = title
        }
    }

    /// Copies files dropped/picked into a doc or idea to `.vibedeck/attachments/`; returns their markdown links.
    func importAttachments(_ urls: [URL], owner: String) -> [String] {
        urls.compactMap { url in
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do { return try store.importAttachment(from: url, owner: owner) } catch {
                errorMessage = error.localizedDescription
                return nil
            }
        }
    }

    /// Saves pasted image data as an attachment; returns its markdown link.
    func importAttachment(data: Data, name: String, owner: String) -> String? {
        do { return try store.importAttachment(data: data, name: name, owner: owner) } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func setDocTags(_ slug: String, _ tags: [String]) {
        let text = Markdown.settingTags(tags, in: readDoc(slug))
        write(Data(text.utf8), to: store.docURL(slug))
        externalDocChange[slug, default: 0] += 1
        reloadDocs()
    }

    func deleteDoc(_ slug: String) {
        do {
            try FileManager.default.trashItem(at: store.docURL(slug), resultingItemURL: nil)
            reloadDocs()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Review groups

    func group(_ slug: String) -> ReviewGroup? {
        groups.first { $0.slug == slug }?.group
    }

    func createGroup(title: String) -> String? {
        do {
            let (slug, group) = try store.createGroup(title: title)
            if let data = try? VDJSON.encode(group) { lastWritten[store.groupURL(slug).resolvingSymlinksInPath().path] = data }
            reloadGroups()
            return slug
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func deleteGroup(_ slug: String) {
        do {
            try FileManager.default.trashItem(at: store.groupURL(slug), resultingItemURL: nil)
            reloadGroups()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Mutates a group, saves it, and registers an undo that restores the previous value
    /// (undoing registers the inverse, so Cmd+Shift+Z redoes).
    func mutateGroup(_ slug: String, _ actionName: String, undo: UndoManager?, _ change: (inout ReviewGroup) -> Void) {
        guard let index = groups.firstIndex(where: { $0.slug == slug }) else { return }
        let old = groups[index].group
        var new = old
        change(&new)
        guard new != old else { return }
        groups[index].group = new
        if let data = try? VDJSON.encode(new) { write(data, to: store.groupURL(slug)) }
        undo?.registerUndo(withTarget: self) { model in
            model.mutateGroup(slug, actionName, undo: undo) { $0 = old }
        }
        undo?.setActionName(actionName)
    }

    func mutateItem(_ slug: String, _ id: ReviewItem.ID, _ actionName: String, undo: UndoManager?, _ change: @escaping (inout ReviewItem) -> Void) {
        mutateGroup(slug, actionName, undo: undo) { group in
            guard let i = group.items.firstIndex(where: { $0.id == id }) else { return }
            var item = group.items[i]
            change(&item)
            if item != group.items[i] {
                item.updatedAt = .now
                group.items[i] = item
            }
        }
    }

    // MARK: Rules

    func topic(_ slug: String) -> RuleTopic? {
        topics.first { $0.slug == slug }?.value
    }

    func createTopic(title: String) -> String? {
        create { try store.createTopic(title: title) } url: { store.topicURL($0) } reload: { reloadTopics() }
    }

    func deleteTopic(_ slug: String) {
        trash(store.topicURL(slug)) {
            reloadTopics()
            releaseOrphanedIdeas()
            releaseOrphanedPatterns()
        }
    }

    /// Drops patterns whose topic is gone and refreshes the project.
    private func releaseOrphanedPatterns() {
        do {
            if try !store.releaseOrphanedPatterns().isEmpty { reloadProject() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Unpromotes ideas whose topic is gone and refreshes them.
    private func releaseOrphanedIdeas() {
        do {
            if try !store.releaseOrphanedIdeas().isEmpty { reloadIdeas() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func mutateTopic(_ slug: String, _ actionName: String, undo: UndoManager?, _ change: @escaping (inout RuleTopic) -> Void) {
        mutate(\.topics, slug, url: store.topicURL(slug), actionName, undo: undo, change)
    }

    /// Runs the scripts of a topic's rules off the main thread and keeps each outcome in `testRuns`.
    func runTests(topic slug: String) {
        startRuleExecution(topic: slug)
    }

    func runAllTests() {
        startRuleExecution()
    }

    enum TestGeneration: Equatable {
        case queued, running, done
        case failed(String)
        var isActive: Bool { self == .queued || self == .running }
    }

    /// Background test generation per topic (see `generateAllTests`); finished entries stay until the next batch.
    var generatingTests: [String: TestGeneration] = [:]
    private var generationTask: Task<Void, Never>?
    var isGeneratingTests: Bool { generatingTests.values.contains(where: \.isActive) }

    /// Writes the tests of `selection` for every topic that has such rules, one background `claude -p` per
    /// topic, at most `maxConcurrent` at a time. The scripts register themselves through the CLI, so the
    /// topics reload from disk as each job ends.
    func generateAllTests(_ selection: RuleTestPrompt.Selection, provider: AIProvider = .claude, maxConcurrent: Int = 3) {
        guard !isGeneratingTests, ruleExecution?.active != true else { return }
        let cli = ClaudeUsageView.cliPath ?? "vibedeck"
        let jobs = topics.compactMap { entry -> (slug: String, prompt: String, rules: [Rule])? in
            guard !RuleTestPrompt.rules(entry.value, selection).isEmpty else { return nil }
            return (entry.slug, RuleTestPrompt.generate(slug: entry.slug, topic: entry.value, selection: selection, headless: cli), RuleTestPrompt.rules(entry.value, selection))
        }
        guard !jobs.isEmpty else { return }
        generatingTests = Dictionary(uniqueKeysWithValues: jobs.map { ($0.slug, .queued) })
        let root = store.root
        generationTask = Task {
            await withTaskGroup(of: (String, String?).self) { group in
                var queue = jobs[...]
                var active = 0
                while true {
                    while active < maxConcurrent, !Task.isCancelled, let job = queue.popFirst() {
                        generatingTests[job.slug] = .running
                        active += 1
                        group.addTask {
                            do {
                                try await RuleTestGenerator.run(root: root, prompt: job.prompt, provider: provider,
                                    operation: "Gerar testes · " + job.slug, topic: job.slug, expectedRules: job.rules)
                                return (job.slug, nil)
                            }
                            catch { return (job.slug, error.localizedDescription) }
                        }
                    }
                    guard let (slug, failure) = await group.next() else { break }
                    active -= 1
                    reloadTopics()
                    guard !Task.isCancelled else { continue }
                    generatingTests[slug] = failure.map(TestGeneration.failed) ?? .done
                    if let failure, let title = topic(slug)?.title { errorMessage = "Testes de \"\(title)\": \(failure)" }
                }
            }
            generationTask = nil
        }
    }

    /// Stops the batch: running `claude` processes are terminated and queued topics dropped.
    func cancelTestGeneration() {
        generationTask?.cancel()
        generatingTests = generatingTests.filter { !$0.value.isActive }
    }

    /// Checks that verified at least one rule of the topic, newest first.
    func checks(forTopic slug: String) -> [RuleCheck] {
        checks.filter { $0.topics.contains(slug) }
    }

    /// Why a review item can't be considered verified yet (empty = verified or not gated).
    /// Reads disk through the store; touching `checks`/`topics` keeps SwiftUI observing them.
    func verificationProblems(for item: ReviewItem) -> [String] {
        _ = (checks, topics)
        return (try? store.verificationProblems(for: item)) ?? []
    }

    func requiredTopics(for item: ReviewItem) -> [String] {
        _ = topics
        return ((try? store.requiredTopics(for: item)) ?? []).map(\.slug)
    }

    /// Tags already used by docs, review groups, topics and ideas: the vocabulary the rules Descubra prefers.
    var tagVocabulary: [String] {
        let all = docs.flatMap(\.tags) + groups.flatMap(\.group.tags) + topics.flatMap(\.value.tags) + ideas.flatMap(\.value.tags)
        return Array(Set(all)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Rules of the other topics, so the Descubra can flag duplicates and conflicts.
    func knownTopics(excluding slug: String? = nil) -> [RuleDiscover.KnownTopic] {
        topics.filter { $0.slug != slug }.map { .init(slug: $0.slug, title: $0.value.title, rules: $0.value.rules.map(\.text)) }
    }

    // MARK: Ideas

    func idea(_ slug: String) -> Idea? {
        ideas.first { $0.slug == slug }?.value
    }

    func createIdea(title: String) -> String? {
        create { try store.createIdea(title: title) } url: { store.ideaURL($0) } reload: { reloadIdeas() }
    }

    /// Trashes the idea and, in a git repo, commits just that removal in the background.
    func deleteIdea(_ slug: String) {
        let title = idea(slug)?.title ?? slug
        trash(store.ideaURL(slug)) { reloadIdeas() }
        guard !FileManager.default.fileExists(atPath: store.ideaURL(slug).path) else { return }
        let store = store
        Task.detached { store.commitIdeaRemoval(slug, title: title) }
    }

    func mutateIdea(_ slug: String, _ actionName: String, undo: UndoManager?, _ change: @escaping (inout Idea) -> Void) {
        mutate(\.ideas, slug, url: store.ideaURL(slug), actionName, undo: undo) { idea in
            let before = idea
            change(&idea)
            if idea != before { idea.updatedAt = .now }
        }
    }

    // MARK: Agents

    func agent(_ slug: String) -> Agent? {
        agents.first { $0.slug == slug }?.value
    }

    func createAgent(title: String) -> String? {
        create { try store.createAgent(title: title) } url: { store.agentURL($0) } reload: { reloadAgents() }
    }

    func deleteAgent(_ slug: String) {
        trash(store.agentURL(slug)) { reloadAgents() }
    }

    func mutateAgent(_ slug: String, _ actionName: String, undo: UndoManager?, _ change: @escaping (inout Agent) -> Void) {
        mutate(\.agents, slug, url: store.agentURL(slug), actionName, undo: undo) { agent in
            let before = agent
            change(&agent)
            if agent != before { agent.updatedAt = .now }
        }
    }

    /// Imports Claude Code agents as VibeDeck agents. Returns how many were created.
    func importClaudeAgents() -> Int {
        do {
            let slugs = try store.importClaudeAgents()
            reloadAgents()
            return slugs.count
        } catch {
            errorMessage = error.localizedDescription
            return 0
        }
    }

    // MARK: Commands

    func command(_ slug: String) -> Command? {
        commands.first { $0.slug == slug }?.value
    }

    func createCommand(title: String) -> String? {
        create { try store.createCommand(title: title) } url: { store.commandURL($0) } reload: { reloadCommands() }
    }

    func deleteCommand(_ slug: String) {
        trash(store.commandURL(slug)) { reloadCommands() }
    }

    func mutateCommand(_ slug: String, _ actionName: String, undo: UndoManager?, _ change: @escaping (inout Command) -> Void) {
        mutate(\.commands, slug, url: store.commandURL(slug), actionName, undo: undo) { command in
            let before = command
            change(&command)
            if command != before { command.updatedAt = .now }
        }
    }

    /// Imports Claude Code slash commands as VibeDeck commands. Returns how many were created.
    func importClaudeCommands() -> Int {
        do {
            let slugs = try store.importClaudeCommands()
            reloadCommands()
            return slugs.count
        } catch {
            errorMessage = error.localizedDescription
            return 0
        }
    }

    // MARK: Skills

    func skill(_ slug: String) -> Skill? {
        skills.first { $0.slug == slug }?.value
    }

    func createSkill(title: String) -> String? {
        create { try store.createSkill(title: title) } url: { store.skillURL($0) } reload: { reloadSkills() }
    }

    func deleteSkill(_ slug: String) {
        trash(store.skillURL(slug)) { reloadSkills() }
    }

    func mutateSkill(_ slug: String, _ actionName: String, undo: UndoManager?, _ change: @escaping (inout Skill) -> Void) {
        mutate(\.skills, slug, url: store.skillURL(slug), actionName, undo: undo) { skill in
            let before = skill
            change(&skill)
            if skill != before { skill.updatedAt = .now }
        }
    }

    /// Imports Claude Code skills (`SKILL.md`) as VibeDeck skills. Returns how many were created.
    func importClaudeSkills() -> Int {
        do {
            let slugs = try store.importClaudeSkills()
            reloadSkills()
            return slugs.count
        } catch {
            errorMessage = error.localizedDescription
            return 0
        }
    }

    // MARK: Workflows

    func workflow(_ slug: String) -> Workflow? {
        workflows.first { $0.slug == slug }?.value
    }

    func createWorkflow(title: String) -> String? {
        create { try store.createWorkflow(title: title) } url: { store.workflowURL($0) } reload: { reloadWorkflows() }
    }

    func deleteWorkflow(_ slug: String) {
        trash(store.workflowURL(slug)) { reloadWorkflows() }
    }

    func mutateWorkflow(_ slug: String, _ actionName: String, undo: UndoManager?, _ change: @escaping (inout Workflow) -> Void) {
        mutate(\.workflows, slug, url: store.workflowURL(slug), actionName, undo: undo) { workflow in
            let before = workflow
            change(&workflow)
            if workflow != before { workflow.updatedAt = .now }
        }
    }

    func runs(of workflow: String) -> [Entry<WorkflowRun>] {
        runs.filter { $0.value.workflow == workflow }
    }

    /// Starts (or resumes, with the same input) a run and returns the orchestrator prompt for the chat.
    func startRun(_ workflow: String, input: String?, from: String? = nil) -> String? {
        do {
            let (ref, run, _) = try store.startRun(workflow, input: input, from: from)
            reloadRuns()
            return orchestratorPrompt(ref, run)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Prompt that makes the chat continue orchestrating an existing run.
    func orchestratorPrompt(_ ref: String, _ run: WorkflowRun) -> String {
        WorkflowOrchestration.orchestratorPrompt(
            ref: ref, title: workflow(run.workflow)?.title ?? run.workflow, input: run.input, cli: ClaudeUsageView.cliPath ?? "vibedeck", provider: run.provider
        )
    }

    func stopRun(_ ref: String) {
        do {
            try store.stopRun(ref)
            reloadRuns()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteRun(_ ref: String) {
        trash(store.runURL(ref).deletingLastPathComponent()) { reloadRuns() }
    }

    /// The workflow's plan with the agents, commands and skills currently loaded.
    func workflowPlan(_ slug: String, input: String? = nil) -> WorkflowPlan? {
        workflow(slug).map {
            WorkflowPlan.build(
                slug: slug, workflow: $0, input: input, agents: agents.map { ($0.slug, $0.value) },
                commands: commands.map { ($0.slug, $0.value) }, skills: skills.map { ($0.slug, $0.value) }
            )
        }
    }

    /// Promotes the idea's rules to an enforced topic. Returns the topic slug.
    func promoteIdea(_ slug: String, skippingPaths: Set<String> = []) -> String? {
        do {
            let topic = try store.promoteIdea(slug, skippingPaths: skippingPaths)
            reloadTopics()
            reloadIdeas()
            return topic
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Deletes the idea's topic and releases the idea (draft rules stay). Undo restores both files.
    func unpromoteIdea(_ slug: String, undo: UndoManager?) {
        do {
            let idea = try store.loadIdea(slug)
            let topicSlug = idea.promotedTopic.flatMap { try? store.resolveTopicSlug($0) }
            let topic = try topicSlug.map { try store.loadTopic($0) }
            try store.unpromoteIdea(slug)
            reloadTopics()
            reloadIdeas()
            undo?.registerUndo(withTarget: self) { model in
                do {
                    if let topicSlug, let topic { try model.store.saveTopic(topic, slug: topicSlug) }
                    try model.store.saveIdea(idea, slug: slug)
                } catch {
                    model.errorMessage = error.localizedDescription
                }
                model.reloadTopics()
                model.reloadIdeas()
                undo?.registerUndo(withTarget: model) { $0.unpromoteIdea(slug, undo: undo) }
                undo?.setActionName("Despromover ideia")
            }
            undo?.setActionName("Despromover ideia")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Sections

    func count(_ section: SidebarSection) -> Int {
        switch section {
        case .docs: docs.count
        case .groups: groups.count
        case .topics: topics.count
        case .ideas: ideas.count
        case .agents: agents.count
        case .commands: commands.count
        case .skills: skills.count
        case .workflows: workflows.count
        }
    }

    func rows(for section: SidebarSection) -> [SectionRow] {
        switch section {
        case .docs:
            docs.map {
                SectionRow(id: .doc($0.slug), title: $0.title, symbol: "doc.text",
                           detail: $0.modified.formatted(.relative(presentation: .named)), count: "", tags: $0.tags)
            }
        case .groups:
            groups.map {
                SectionRow(id: .group($0.slug), title: $0.group.title, symbol: "checklist",
                           detail: $0.group.description ?? "",
                           count: "\($0.group.openCount) de \($0.group.items.count) abertos", tags: $0.group.tags)
            }
        case .topics:
            topics.map {
                SectionRow(id: .topic($0.slug), title: $0.value.title, symbol: $0.value.isGlobal ? "checkmark.shield" : "scope",
                           detail: $0.value.isGlobal ? "Global" : $0.value.paths.joined(separator: ", "),
                           count: "\($0.value.rules.count) regra(s)", tags: $0.value.tags)
            }
        case .ideas:
            ideas.map {
                SectionRow(id: .idea($0.slug), title: $0.value.title, symbol: $0.value.status.symbol,
                           detail: $0.value.status.label, count: "\($0.value.rules.count) regra(s)",
                           tags: $0.value.tags, dimmed: $0.value.status.isClosed)
            }
        case .agents:
            agents.map {
                SectionRow(id: .agent($0.slug), title: $0.value.title, symbol: "person.crop.rectangle",
                           detail: $0.value.model ?? "Modelo herdado",
                           count: $0.value.nextSteps.isEmpty ? "" : "\($0.value.nextSteps.count) próximo(s) passo(s)", tags: $0.value.tags)
            }
        case .commands:
            commands.map {
                SectionRow(id: .command($0.slug), title: $0.value.title, symbol: "command",
                           detail: $0.value.summary ?? $0.value.argumentHint ?? "",
                           count: $0.value.nextSteps.isEmpty ? "" : "\($0.value.nextSteps.count) próximo(s) passo(s)", tags: $0.value.tags)
            }
        case .skills:
            skills.map {
                SectionRow(id: .skill($0.slug), title: $0.value.title, symbol: "wand.and.stars",
                           detail: $0.value.summary ?? "",
                           count: $0.value.nextSteps.isEmpty ? "" : "\($0.value.nextSteps.count) próximo(s) passo(s)", tags: $0.value.tags)
            }
        case .workflows:
            workflows.map {
                SectionRow(id: .workflow($0.slug), title: $0.value.title, symbol: "point.3.connected.trianglepath.dotted",
                           detail: $0.value.summary ?? "", count: "\($0.value.steps.count) etapa(s)", tags: $0.value.tags)
            }
        }
    }

    func fileURL(for item: SidebarItem) -> URL? {
        switch item {
        case .doc(let slug): store.docURL(slug)
        case .group(let slug): store.groupURL(slug)
        case .topic(let slug): store.topicURL(slug)
        case .idea(let slug): store.ideaURL(slug)
        case .agent(let slug): store.agentURL(slug)
        case .command(let slug): store.commandURL(slug)
        case .skill(let slug): store.skillURL(slug)
        case .workflow(let slug): store.workflowURL(slug)
        case .stack, .patterns, .links, .graph, .claude, .terminal, .section: nil
        }
    }

    /// Display title for a tab showing `item`.
    func title(for item: SidebarItem) -> String {
        switch item {
        case .stack: "Stack"
        case .patterns: "Padrões"
        case .links: "Links"
        case .graph: "Grafo"
        case .claude: "IA"
        case .terminal: "Terminal"
        case .section(let section): section.title
        case .doc(let slug): docs.first { $0.slug == slug }?.title ?? slug
        case .group(let slug): group(slug)?.title ?? slug
        case .topic(let slug): topic(slug)?.title ?? slug
        case .idea(let slug): idea(slug)?.title ?? slug
        case .agent(let slug): agent(slug)?.title ?? slug
        case .command(let slug): command(slug)?.title ?? slug
        case .skill(let slug): skill(slug)?.title ?? slug
        case .workflow(let slug): workflow(slug)?.title ?? slug
        }
    }

    /// SF Symbol for a tab showing `item`.
    func symbol(for item: SidebarItem) -> String {
        switch item {
        case .stack: "square.stack.3d.up"
        case .patterns: "building.columns"
        case .links: "link"
        case .graph: "point.3.connected.trianglepath.dotted"
        case .claude: "sparkles"
        case .terminal: "terminal"
        case .section(let section): section.symbol
        case .doc: "doc.text"
        case .group: "checklist"
        case .topic(let slug): topic(slug)?.isGlobal == false ? "scope" : "checkmark.shield"
        case .idea(let slug): idea(slug)?.status.symbol ?? "sparkle"
        case .agent: "person.crop.rectangle"
        case .command: "command"
        case .skill: "wand.and.stars"
        case .workflow: "point.3.connected.trianglepath.dotted"
        }
    }

    /// Whether `item` still exists in the project (pages always do; files may have been deleted).
    func exists(_ item: SidebarItem) -> Bool {
        switch item {
        case .stack, .patterns, .links, .graph, .terminal, .section: true
        case .claude: !AIProvider.installed.isEmpty
        case .doc(let slug): docs.contains { $0.slug == slug }
        case .group(let slug): group(slug) != nil
        case .topic(let slug): topic(slug) != nil
        case .idea(let slug): idea(slug) != nil
        case .agent(let slug): agent(slug) != nil
        case .command(let slug): command(slug) != nil
        case .skill(let slug): skill(slug) != nil
        case .workflow(let slug): workflow(slug) != nil
        }
    }

    func delete(_ item: SidebarItem) {
        switch item {
        case .doc(let slug): deleteDoc(slug)
        case .group(let slug): deleteGroup(slug)
        case .topic(let slug): deleteTopic(slug)
        case .idea(let slug): deleteIdea(slug)
        case .agent(let slug): deleteAgent(slug)
        case .command(let slug): deleteCommand(slug)
        case .skill(let slug): deleteSkill(slug)
        case .workflow(let slug): deleteWorkflow(slug)
        case .stack, .patterns, .links, .graph, .claude, .terminal, .section: break
        }
    }

    func setTags(_ tags: [String], for item: SidebarItem, undo: UndoManager?) {
        switch item {
        case .doc(let slug): setDocTags(slug, tags)
        case .group(let slug): mutateGroup(slug, "Editar tags", undo: undo) { $0.tags = tags }
        case .topic(let slug): mutateTopic(slug, "Editar tags", undo: undo) { $0.tags = tags }
        case .idea(let slug): mutateIdea(slug, "Editar tags", undo: undo) { $0.tags = tags }
        case .agent(let slug): mutateAgent(slug, "Editar tags", undo: undo) { $0.tags = tags }
        case .command(let slug): mutateCommand(slug, "Editar tags", undo: undo) { $0.tags = tags }
        case .skill(let slug): mutateSkill(slug, "Editar tags", undo: undo) { $0.tags = tags }
        case .workflow(let slug): mutateWorkflow(slug, "Editar tags", undo: undo) { $0.tags = tags }
        case .stack, .patterns, .links, .graph, .claude, .terminal, .section: break
        }
    }

    // MARK: Generic helpers

    private func create<V: Encodable>(_ make: () throws -> (String, V), url: (String) -> URL, reload: () -> Void) -> String? {
        do {
            let (slug, value) = try make()
            if let data = try? VDJSON.encode(value) { lastWritten[url(slug).resolvingSymlinksInPath().path] = data }
            reload()
            return slug
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func trash(_ url: URL, reload: () -> Void) {
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Same contract as `mutateGroup`: write through, undo restores the previous value.
    private func mutate<V: Equatable & Encodable>(
        _ entries: ReferenceWritableKeyPath<ProjectModel, [Entry<V>]>, _ slug: String, url: URL,
        _ actionName: String, undo: UndoManager?, _ change: @escaping (inout V) -> Void
    ) {
        guard let index = self[keyPath: entries].firstIndex(where: { $0.slug == slug }) else { return }
        let old = self[keyPath: entries][index].value
        var new = old
        change(&new)
        guard new != old else { return }
        self[keyPath: entries][index].value = new
        if let data = try? VDJSON.encode(new) { write(data, to: url) }
        undo?.registerUndo(withTarget: self) { model in
            model.mutate(entries, slug, url: url, actionName, undo: undo) { $0 = old }
        }
        undo?.setActionName(actionName)
    }
}
