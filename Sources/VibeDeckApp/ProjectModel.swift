import Foundation
import Observation
import SwiftUI
import VibeDeckCore

enum SidebarSection: String, CaseIterable, Hashable {
    case docs, groups, topics, ideas

    var title: String {
        switch self {
        case .docs: "Docs"
        case .groups: "Revisões"
        case .topics: "Regras"
        case .ideas: "Ideias"
        }
    }

    var symbol: String {
        switch self {
        case .docs: "doc.text"
        case .groups: "checklist"
        case .topics: "checkmark.shield"
        case .ideas: "sparkle"
        }
    }

    var emptyMessage: String {
        switch self {
        case .docs: "Sem documentos"
        case .groups: "Sem grupos de revisão"
        case .topics: "Sem tópicos de regras"
        case .ideas: "Sem ideias"
        }
    }
}

enum SidebarItem: Hashable {
    case links
    case section(SidebarSection)
    case doc(String)
    case group(String)
    case topic(String)
    case idea(String)

    var storageKey: String {
        switch self {
        case .links: "links"
        case .section(let section): "section:\(section.rawValue)"
        case .doc(let slug): "doc:\(slug)"
        case .group(let slug): "group:\(slug)"
        case .topic(let slug): "topic:\(slug)"
        case .idea(let slug): "idea:\(slug)"
        }
    }

    init?(storageKey: String?) {
        guard let key = storageKey else { return nil }
        if key == "links" { self = .links }
        else if key.hasPrefix("section:") {
            guard let section = SidebarSection(rawValue: String(key.dropFirst(8))) else { return nil }
            self = .section(section)
        }
        else if key.hasPrefix("doc:") { self = .doc(String(key.dropFirst(4))) }
        else if key.hasPrefix("group:") { self = .group(String(key.dropFirst(6))) }
        else if key.hasPrefix("topic:") { self = .topic(String(key.dropFirst(6))) }
        else if key.hasPrefix("idea:") { self = .idea(String(key.dropFirst(5))) }
        else { return nil }
    }

    /// The sidebar section this item lives in (expanded while it is selected).
    var section: SidebarSection? {
        switch self {
        case .links: nil
        case .section(let section): section
        case .doc: .docs
        case .group: .groups
        case .topic: .topics
        case .idea: .ideas
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
    /// All recorded rule checks, newest first.
    var checks: [RuleCheck] = []
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
        reloadDocs()
        reloadGroups()
        reloadTopics()
        reloadIdeas()
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
        var topicsChanged = false, ideasChanged = false, checksChanged = false
        for url in Set(urls.map { $0.resolvingSymlinksInPath().path }) {
            let current = FileManager.default.contents(atPath: url)
            if let current, current == lastWritten[url] { continue }
            if url.hasSuffix("/" + ProjectStore.manifestName) {
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
            } else if url.contains("/checks/") {
                checksChanged = true
            }
        }
        if projectChanged, let p = try? store.loadProject(), p != project { project = p }
        if docsChanged { reloadDocs() }
        if groupsChanged { reloadGroups() }
        if topicsChanged { reloadTopics() }
        if ideasChanged { reloadIdeas() }
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
        trash(store.topicURL(slug)) { reloadTopics() }
    }

    func mutateTopic(_ slug: String, _ actionName: String, undo: UndoManager?, _ change: @escaping (inout RuleTopic) -> Void) {
        mutate(\.topics, slug, url: store.topicURL(slug), actionName, undo: undo, change)
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

    // MARK: Ideas

    func idea(_ slug: String) -> Idea? {
        ideas.first { $0.slug == slug }?.value
    }

    func createIdea(title: String) -> String? {
        create { try store.createIdea(title: title) } url: { store.ideaURL($0) } reload: { reloadIdeas() }
    }

    func deleteIdea(_ slug: String) {
        trash(store.ideaURL(slug)) { reloadIdeas() }
    }

    func mutateIdea(_ slug: String, _ actionName: String, undo: UndoManager?, _ change: @escaping (inout Idea) -> Void) {
        mutate(\.ideas, slug, url: store.ideaURL(slug), actionName, undo: undo) { idea in
            let before = idea
            change(&idea)
            if idea != before { idea.updatedAt = .now }
        }
    }

    /// Promotes the idea's rules to an enforced topic. Returns the topic slug.
    func promoteIdea(_ slug: String) -> String? {
        do {
            let topic = try store.promoteIdea(slug)
            reloadTopics()
            reloadIdeas()
            return topic
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    // MARK: Sections

    func count(_ section: SidebarSection) -> Int {
        switch section {
        case .docs: docs.count
        case .groups: groups.count
        case .topics: topics.count
        case .ideas: ideas.count
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
        }
    }

    func fileURL(for item: SidebarItem) -> URL? {
        switch item {
        case .doc(let slug): store.docURL(slug)
        case .group(let slug): store.groupURL(slug)
        case .topic(let slug): store.topicURL(slug)
        case .idea(let slug): store.ideaURL(slug)
        case .links, .section: nil
        }
    }

    /// Display title for a tab showing `item`.
    func title(for item: SidebarItem) -> String {
        switch item {
        case .links: "Links"
        case .section(let section): section.title
        case .doc(let slug): docs.first { $0.slug == slug }?.title ?? slug
        case .group(let slug): group(slug)?.title ?? slug
        case .topic(let slug): topic(slug)?.title ?? slug
        case .idea(let slug): idea(slug)?.title ?? slug
        }
    }

    /// SF Symbol for a tab showing `item`.
    func symbol(for item: SidebarItem) -> String {
        switch item {
        case .links: "link"
        case .section(let section): section.symbol
        case .doc: "doc.text"
        case .group: "checklist"
        case .topic(let slug): topic(slug)?.isGlobal == false ? "scope" : "checkmark.shield"
        case .idea(let slug): idea(slug)?.status.symbol ?? "sparkle"
        }
    }

    /// Whether `item` still exists in the project (pages always do; files may have been deleted).
    func exists(_ item: SidebarItem) -> Bool {
        switch item {
        case .links, .section: true
        case .doc(let slug): docs.contains { $0.slug == slug }
        case .group(let slug): group(slug) != nil
        case .topic(let slug): topic(slug) != nil
        case .idea(let slug): idea(slug) != nil
        }
    }

    func delete(_ item: SidebarItem) {
        switch item {
        case .doc(let slug): deleteDoc(slug)
        case .group(let slug): deleteGroup(slug)
        case .topic(let slug): deleteTopic(slug)
        case .idea(let slug): deleteIdea(slug)
        case .links, .section: break
        }
    }

    func setTags(_ tags: [String], for item: SidebarItem, undo: UndoManager?) {
        switch item {
        case .doc(let slug): setDocTags(slug, tags)
        case .group(let slug): mutateGroup(slug, "Editar tags", undo: undo) { $0.tags = tags }
        case .topic(let slug): mutateTopic(slug, "Editar tags", undo: undo) { $0.tags = tags }
        case .idea(let slug): mutateIdea(slug, "Editar tags", undo: undo) { $0.tags = tags }
        case .links, .section: break
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
