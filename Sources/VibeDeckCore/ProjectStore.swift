import Foundation

public enum VibeDeckError: LocalizedError, Equatable {
    case notAProject(String)
    case alreadyAProject(String)
    case docNotFound(String)
    case groupNotFound(String)
    case itemNotFound(String)
    case ambiguousItem(String)
    case invalidName

    public var errorDescription: String? {
        switch self {
        case .notAProject(let p): "Nenhum vibedeck.json encontrado em \(p) ou diretórios acima. Rode `vibedeck init`."
        case .alreadyAProject(let p): "\(p) já contém um vibedeck.json."
        case .docNotFound(let s): "Doc não encontrado: \(s)"
        case .groupNotFound(let s): "Grupo de revisão não encontrado: \(s)"
        case .itemNotFound(let s): "Item de revisão não encontrado: \(s)"
        case .ambiguousItem(let s): "Prefixo de id ambíguo: \(s)"
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
        for dir in [docsDir, reviewsDir] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    public func writeAgentsGuide() throws {
        try ensureDirectories()
        try AtomicFile.write(Data(AgentsGuide.markdown.utf8), to: agentsURL)
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
                return DocInfo(slug: slug, title: Markdown.title(of: text) ?? slug, modified: modified)
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

    public func deleteDoc(_ slug: String) throws {
        try FileManager.default.removeItem(at: docURL(slug))
    }

    // MARK: Reviews

    public func groupURL(_ slug: String) -> URL { reviewsDir.appending(path: "\(slug).json") }

    public func listGroups() throws -> [(slug: String, group: ReviewGroup)] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: reviewsDir.path) else { return [] }
        return try fm.contentsOfDirectory(at: reviewsDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            .filter { $0.pathExtension.lowercased() == "json" }
            .compactMap { url in
                guard let group = try? VDJSON.decoder.decode(ReviewGroup.self, from: Data(contentsOf: url)) else { return nil }
                return (url.deletingPathExtension().lastPathComponent, group)
            }
            .sorted { $0.group.createdAt < $1.group.createdAt }
    }

    /// Resolves a group by slug, id, or case-insensitive title.
    public func resolveGroupSlug(_ ref: String) throws -> String {
        if FileManager.default.fileExists(atPath: groupURL(ref).path) { return ref }
        let groups = try listGroups()
        if let match = groups.first(where: {
            $0.group.id.uuidString.caseInsensitiveCompare(ref) == .orderedSame
                || $0.group.title.caseInsensitiveCompare(ref) == .orderedSame
                || $0.slug == Slug.make(ref)
        }) { return match.slug }
        throw VibeDeckError.groupNotFound(ref)
    }

    public func loadGroup(_ slug: String) throws -> ReviewGroup {
        let url = groupURL(slug)
        guard FileManager.default.fileExists(atPath: url.path) else { throw VibeDeckError.groupNotFound(slug) }
        return try VDJSON.decoder.decode(ReviewGroup.self, from: Data(contentsOf: url))
    }

    public func saveGroup(_ group: ReviewGroup, slug: String) throws {
        try ensureDirectories()
        try AtomicFile.write(VDJSON.encode(group), to: groupURL(slug))
    }

    /// Creates a group with a unique slug. Returns the slug.
    @discardableResult
    public func createGroup(title: String, description: String? = nil) throws -> (slug: String, group: ReviewGroup) {
        guard let title = title.trimmed.nonEmpty else { throw VibeDeckError.invalidName }
        let slug = uniqueSlug(Slug.make(title), in: reviewsDir, ext: "json")
        let group = ReviewGroup(title: title, description: description)
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

    // MARK: Helpers

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
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false)[...]
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---" {
            lines = lines.dropFirst()
            while let line = lines.first, line.trimmingCharacters(in: .whitespaces) != "---" {
                if line.hasPrefix("title:") {
                    let value = line.dropFirst("title:".count).trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
                    if !value.isEmpty { return value }
                }
                lines = lines.dropFirst()
            }
            lines = lines.dropFirst()
        }
        for line in lines where line.hasPrefix("# ") {
            return line.dropFirst(2).trimmingCharacters(in: .whitespaces).nonEmpty
        }
        return nil
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nonEmpty: String? { isEmpty ? nil : self }
}
