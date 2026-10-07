import Foundation
import Observation
import SwiftUI
import VibeDeckCore

enum SidebarItem: Hashable {
    case links
    case doc(String)
    case group(String)

    var storageKey: String {
        switch self {
        case .links: "links"
        case .doc(let slug): "doc:\(slug)"
        case .group(let slug): "group:\(slug)"
        }
    }

    init?(storageKey: String?) {
        guard let key = storageKey else { return nil }
        if key == "links" { self = .links }
        else if key.hasPrefix("doc:") { self = .doc(String(key.dropFirst(4))) }
        else if key.hasPrefix("group:") { self = .group(String(key.dropFirst(6))) }
        else { return nil }
    }
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
    var errorMessage: String?

    /// Bumped whenever a doc file changes on disk from outside the app.
    var externalDocChange: [String: Int] = [:]

    struct GroupEntry: Identifiable, Equatable {
        var slug: String
        var group: ReviewGroup
        var id: String { slug }
    }

    @ObservationIgnored private var watcher: FileWatcher?
    /// Last bytes the app wrote per file path, so our own writes don't trigger reloads.
    @ObservationIgnored private var lastWritten: [String: Data] = [:]

    init(store: ProjectStore) {
        self.store = store
        self.project = (try? store.loadProject()) ?? Project(name: store.root.lastPathComponent)
        try? store.ensureDirectories()
        reloadDocs()
        reloadGroups()
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
            }
        }
        if projectChanged, let p = try? store.loadProject(), p != project { project = p }
        if docsChanged { reloadDocs() }
        if groupsChanged { reloadGroups() }
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
}
