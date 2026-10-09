import Foundation

// MARK: - Stack

/// A highlighted technology of the project, kept in `vibedeck.json` under `stack`. `icon` is a Skill Icons id:
/// it identifies the item, and the array order is the display order.
public struct StackItem: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var icon: String
    public var name: String
    public var category: String?
    /// How the project uses it ("Swift 6, strict concurrency"); handed to the AI with the stack.
    public var note: String?
    public var author: Author

    public var id: String { icon }

    public init(icon: String, name: String, category: String? = nil, note: String? = nil, author: Author = .human) {
        self.icon = icon
        self.name = name
        self.category = category
        self.note = note
        self.author = author
    }

    public init(_ icon: SkillIcon, note: String? = nil, author: Author = .human) {
        self.init(icon: icon.id, name: icon.name, category: icon.category, note: note, author: author)
    }

    enum CodingKeys: String, CodingKey { case icon, name, category, note, author }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        icon = try c.decode(String.self, forKey: .icon)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? icon
        category = try c.decodeIfPresent(String.self, forKey: .category)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        author = try c.decodeIfPresent(Author.self, forKey: .author) ?? .human
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(icon, forKey: .icon)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(category, forKey: .category)
        if let note, !note.isEmpty { try c.encode(note, forKey: .note) }
        try c.encode(author, forKey: .author)
    }
}

// MARK: - Skill Icons

/// An icon of the Skill Icons catalog, as `skill_icons_search` returns it.
public struct SkillIcon: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var category: String?
    /// Has dark and light variants.
    public var themed: Bool
    public var aliases: [String]

    public init(id: String, name: String, category: String? = nil, themed: Bool = false, aliases: [String] = []) {
        self.id = id
        self.name = name
        self.category = category
        self.themed = themed
        self.aliases = aliases
    }

    enum CodingKeys: String, CodingKey { case id, name, category, themed, aliases }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? id
        category = try c.decodeIfPresent(String.self, forKey: .category)
        themed = try c.decodeIfPresent(Bool.self, forKey: .themed) ?? false
        aliases = try c.decodeIfPresent([String].self, forKey: .aliases) ?? []
    }

    /// True when `text` names this icon: its id, brand name or an alias (case- and accent-insensitive).
    public func matches(exactly text: String) -> Bool {
        let key = SkillIcon.normalize(text)
        return ([id, name] + aliases).contains { SkillIcon.normalize($0) == key }
    }

    /// True when `text` is part of the id, brand name or an alias.
    public func matches(containing text: String) -> Bool {
        let key = SkillIcon.normalize(text)
        guard !key.isEmpty else { return true }
        return ([id, name] + aliases).contains { SkillIcon.normalize($0).contains(key) }
    }

    static func normalize(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .filter { $0.isLetter || $0.isNumber || $0 == "+" || $0 == "#" }
    }
}

public enum SkillIconTheme: String, CaseIterable, Sendable {
    case dark, light
}

/// What `skill_icons_badge` returns: the image URL plus Markdown/HTML ready to paste.
public struct SkillBadge: Codable, Equatable, Sendable {
    public struct Unknown: Codable, Equatable, Sendable {
        public var name: String
        public var suggestions: [String]

        enum CodingKeys: String, CodingKey { case name, suggestions }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decode(String.self, forKey: .name)
            suggestions = try c.decodeIfPresent([String].self, forKey: .suggestions) ?? []
        }
    }

    public var url: String
    public var markdown: String
    public var html: String
    public var icons: [String]
    public var unknown: [Unknown]

    enum CodingKeys: String, CodingKey { case url, markdown, html, icons, unknown }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url = try c.decode(String.self, forKey: .url)
        markdown = try c.decodeIfPresent(String.self, forKey: .markdown) ?? "![Stack](\(url))"
        html = try c.decodeIfPresent(String.self, forKey: .html) ?? "<img src=\"\(url)\" />"
        icons = try c.decodeIfPresent([String].self, forKey: .icons) ?? []
        unknown = try c.decodeIfPresent([Unknown].self, forKey: .unknown) ?? []
    }
}

/// The Skill Icons MCP server; a protocol so tests can swap the network for a fake.
public protocol SkillIconsAPI: Sendable {
    func search(query: String?, category: String?, limit: Int?) async throws -> [SkillIcon]
    func badge(icons: [String], theme: SkillIconTheme?, perLine: Int?) async throws -> SkillBadge
    func image(url: String) async throws -> Data
}

public extension SkillIconsAPI {
    /// The whole catalog (one call).
    func catalog() async throws -> [SkillIcon] {
        try await search(query: nil, category: nil, limit: SkillIcons.catalogLimit)
    }
}

/// Client for the Skill Icons MCP server (stateless JSON-RPC over HTTP): the catalog and the rendered icons
/// both come from it, never from hand-written URLs.
public struct SkillIcons: SkillIconsAPI {
    public static let endpoint = URL(string: "https://skill-icons.alanreisanjo.workers.dev/mcp")!
    public static let categories = [
        "language", "frontend", "backend", "database", "cloud", "devops", "tooling", "testing", "observability",
        "auth", "ide", "ai", "design", "game", "payments", "os", "social", "productivity",
    ]
    static let catalogLimit = 631

    public var endpoint: URL
    public var session: URLSession

    public init(endpoint: URL = SkillIcons.endpoint, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.session = session
    }

    public func search(query: String?, category: String?, limit: Int?) async throws -> [SkillIcon] {
        var args: [String: Any] = [:]
        if let query, !query.isEmpty { args["query"] = query }
        if let category, !category.isEmpty { args["category"] = category }
        if let limit { args["limit"] = limit }
        struct Result: Decodable { var icons: [SkillIcon] }
        return try Self.decodeToolText(Result.self, from: await callTool("skill_icons_search", args)).icons
    }

    public func badge(icons: [String], theme: SkillIconTheme?, perLine: Int?) async throws -> SkillBadge {
        var args: [String: Any] = ["icons": icons]
        if let theme { args["theme"] = theme.rawValue }
        if let perLine { args["perLine"] = perLine }
        return try Self.decodeToolText(SkillBadge.self, from: await callTool("skill_icons_badge", args))
    }

    public func image(url: String) async throws -> Data {
        guard let url = URL(string: url) else { throw VibeDeckError.skillIconsUnavailable("URL inválida: \(url)") }
        do {
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw VibeDeckError.skillIconsUnavailable("HTTP \(http.statusCode) ao baixar o ícone.")
            }
            return data
        } catch let error as VibeDeckError {
            throw error
        } catch {
            throw VibeDeckError.skillIconsUnavailable(error.localizedDescription)
        }
    }

    private func callTool(_ name: String, _ arguments: [String: Any]) async throws -> Data {
        var request = URLRequest(url: endpoint, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "accept")
        let body: [String: Any] = [
            "jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": ["name": name, "arguments": arguments],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw VibeDeckError.skillIconsUnavailable("HTTP \(http.statusCode) em \(name).")
            }
            return data
        } catch let error as VibeDeckError {
            throw error
        } catch {
            throw VibeDeckError.skillIconsUnavailable(error.localizedDescription)
        }
    }

    /// Unwraps a JSON-RPC `tools/call` response (plain JSON or a single SSE `data:` event) and decodes the
    /// JSON inside its first text content.
    static func decodeToolText<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        var payload = data
        if let text = String(data: data, encoding: .utf8), !text.hasPrefix("{"),
           let line = text.split(separator: "\n").last(where: { $0.hasPrefix("data:") }) {
            payload = Data(line.dropFirst(5).trimmingCharacters(in: .whitespaces).utf8)
        }
        guard let envelope = try? JSONDecoder().decode(ToolEnvelope.self, from: payload) else {
            throw VibeDeckError.skillIconsUnavailable("resposta inesperada do servidor.")
        }
        if let error = envelope.error { throw VibeDeckError.skillIconsUnavailable(error.message) }
        guard let result = envelope.result, let text = result.content.first(where: { $0.type == "text" })?.text else {
            throw VibeDeckError.skillIconsUnavailable("resposta sem conteúdo.")
        }
        if result.isError == true { throw VibeDeckError.skillIconsUnavailable(text) }
        do {
            return try JSONDecoder().decode(T.self, from: Data(text.utf8))
        } catch {
            throw VibeDeckError.skillIconsUnavailable("resposta inesperada do servidor.")
        }
    }

    private struct ToolEnvelope: Decodable {
        struct Content: Decodable { var type: String; var text: String? }
        struct Result: Decodable { var content: [Content]; var isError: Bool? }
        struct Failure: Decodable { var message: String }
        var result: Result?
        var error: Failure?
    }

    /// Resolves ids, brand names or aliases ("k8s", "Next.js") against the catalog, in order and without
    /// duplicates. Throws `unknownStackIcons` with suggestions when any name matches nothing.
    public static func resolve(_ refs: [String], in catalog: [SkillIcon]) throws -> [SkillIcon] {
        var resolved: [SkillIcon] = []
        var unknown: [String: [String]] = [:]
        for ref in refs.map({ $0.trimmingCharacters(in: .whitespaces) }) where !ref.isEmpty {
            if let icon = catalog.first(where: { $0.id == ref }) ?? catalog.first(where: { $0.matches(exactly: ref) }) {
                if !resolved.contains(icon) { resolved.append(icon) }
            } else {
                unknown[ref] = Array(catalog.filter { $0.matches(containing: ref) }.prefix(5).map(\.id))
            }
        }
        if !unknown.isEmpty { throw VibeDeckError.unknownStackIcons(unknown) }
        return resolved
    }
}

// MARK: - README block

/// The `<!-- vibedeck:stack -->` block VibeDeck keeps in the repo's README.md with the stack badge.
public enum ReadmeStack {
    public static let start = "<!-- vibedeck:stack:start -->"
    public static let end = "<!-- vibedeck:stack:end -->"

    /// `text` with the block set to `badge` (nil removes it). A new block goes right after the first `# ` heading,
    /// or at the top when there is none.
    public static func apply(_ badge: String?, to text: String) -> String {
        var text = text
        if let s = markerLine(start, in: text, from: text.startIndex),
           let e = markerLine(end, in: text, from: s.upperBound) {
            var removeEnd = e.upperBound
            if removeEnd < text.endIndex, text[removeEnd] == "\n" { removeEnd = text.index(after: removeEnd) }
            guard let badge else {
                text.removeSubrange(s.lowerBound..<removeEnd)
                // Drop the blank line the block leaves behind.
                if text[..<s.lowerBound].hasSuffix("\n\n"), text[s.lowerBound...].hasPrefix("\n") {
                    text.remove(at: s.lowerBound)
                }
                return text
            }
            text.replaceSubrange(s.lowerBound..<removeEnd, with: block(badge) + "\n")
            return text
        }
        guard let badge else { return text }
        var lines = text.components(separatedBy: "\n")
        if let heading = lines.firstIndex(where: { $0.hasPrefix("# ") }) {
            lines.insert(contentsOf: ["", block(badge)], at: heading + 1)
            return lines.joined(separator: "\n")
        }
        return block(badge) + "\n" + (text.isEmpty ? "" : "\n" + text)
    }

    /// The first occurrence of `marker` that fills a whole line, so a marker quoted in prose is left alone.
    static func markerLine(_ marker: String, in text: String, from: String.Index) -> Range<String.Index>? {
        var from = from
        while let r = text.range(of: marker, range: from..<text.endIndex) {
            let atStart = r.lowerBound == text.startIndex || text[text.index(before: r.lowerBound)] == "\n"
            let atEnd = r.upperBound == text.endIndex || text[r.upperBound] == "\n"
            if atStart, atEnd { return r }
            from = r.upperBound
        }
        return nil
    }

    static func block(_ badge: String) -> String { "\(start)\n\(badge)\n\(end)" }
}

extension ProjectStore {
    public var readmeURL: URL { root.appending(path: "README.md") }

    /// Writes `badge` (Skill Icons markdown) into README.md's stack block; nil removes the block.
    /// Creates README.md only when there is something to show. Returns whether the file changed.
    @discardableResult
    public func syncReadmeStack(badge: String?) throws -> Bool {
        let current = (try? String(contentsOf: readmeURL, encoding: .utf8))
        if current == nil, badge == nil { return false }
        let base = try current ?? "# \(loadProject().name)\n"
        let updated = ReadmeStack.apply(badge, to: base)
        guard updated != current else { return false }
        try AtomicFile.write(Data(updated.utf8), to: readmeURL)
        return true
    }

    /// Index of the stack item `ref` names: exact id, then name (case-insensitive), then a unique id prefix.
    public func stackIndex(_ ref: String, in stack: [StackItem]) throws -> Int {
        let key = ref.trimmingCharacters(in: .whitespaces)
        if let i = stack.firstIndex(where: { $0.icon == key }) { return i }
        if let i = stack.firstIndex(where: { $0.name.caseInsensitiveCompare(key) == .orderedSame }) { return i }
        let prefixed = stack.indices.filter { stack[$0].icon.lowercased().hasPrefix(key.lowercased()) }
        if prefixed.count == 1, !key.isEmpty { return prefixed[0] }
        throw VibeDeckError.stackItemNotFound(ref)
    }

    /// Appends icons not yet in the stack (existing ones keep their place; a given `note` replaces theirs).
    /// Returns the items added or updated.
    @discardableResult
    public func addStackItems(_ icons: [SkillIcon], note: String? = nil, author: Author) throws -> [StackItem] {
        var touched: [StackItem] = []
        try updateProject { project in
            for icon in icons {
                if let i = project.stack.firstIndex(where: { $0.icon == icon.id }) {
                    if let note { project.stack[i].note = note.isEmpty ? nil : note }
                    touched.append(project.stack[i])
                } else {
                    let item = StackItem(icon, note: note?.isEmpty == true ? nil : note, author: author)
                    project.stack.append(item)
                    touched.append(item)
                }
            }
        }
        return touched
    }

    /// Removes the items `refs` name. Throws (removing nothing) if any is not in the stack.
    @discardableResult
    public func removeStackItems(_ refs: [String]) throws -> [StackItem] {
        var removed: [StackItem] = []
        try updateProject { project in
            let indices = Set(try refs.map { try stackIndex($0, in: project.stack) })
            removed = indices.sorted().map { project.stack[$0] }
            project.stack = project.stack.enumerated().filter { !indices.contains($0.offset) }.map(\.element)
        }
        return removed
    }

    /// Sets (or, with nil/empty, clears) an item's note.
    @discardableResult
    public func setStackNote(_ ref: String, _ note: String?) throws -> StackItem {
        var item: StackItem!
        try updateProject { project in
            let i = try stackIndex(ref, in: project.stack)
            project.stack[i].note = note?.isEmpty == true ? nil : note
            item = project.stack[i]
        }
        return item
    }

    /// Moves an item to `position` (0-based, clamped).
    public func moveStackItem(_ ref: String, to position: Int) throws {
        try updateProject { project in
            let item = project.stack.remove(at: try stackIndex(ref, in: project.stack))
            project.stack.insert(item, at: max(0, min(position, project.stack.count)))
        }
    }
}

/// Stack operations that also talk to Skill Icons: resolving names and keeping README.md's badge in sync.
public struct StackService: Sendable {
    public let store: ProjectStore
    public let icons: any SkillIconsAPI

    public init(store: ProjectStore, icons: any SkillIconsAPI = SkillIcons()) {
        self.store = store
        self.icons = icons
    }

    /// Result of a change: the items touched, plus a warning when README.md could not be updated.
    public struct Change: Encodable, Sendable {
        public var items: [StackItem]
        public var stack: [StackItem]
        public var readmeWarning: String?
    }

    public func add(_ refs: [String], note: String? = nil, author: Author) async throws -> Change {
        let resolved = try SkillIcons.resolve(refs, in: try await icons.catalog())
        let items = try store.addStackItems(resolved, note: note, author: author)
        return try await change(items)
    }

    public func remove(_ refs: [String]) async throws -> Change {
        var ids: [String] = []
        for ref in refs { ids.append(try await stackID(ref)) }
        return try await change(store.removeStackItems(ids))
    }

    public func setNote(_ ref: String, _ note: String?) async throws -> Change {
        try await change([store.setStackNote(stackID(ref), note)])
    }

    public func move(_ ref: String, to position: Int) async throws -> Change {
        let id = try await stackID(ref)
        try store.moveStackItem(id, to: position)
        let stack = try store.loadProject().stack
        return try await change([stack[try store.stackIndex(id, in: stack)]])
    }

    /// The id of the stack item `ref` names; aliases ("k8s") go through the catalog only when nothing matches locally.
    func stackID(_ ref: String) async throws -> String {
        let stack = try store.loadProject().stack
        if let i = try? store.stackIndex(ref, in: stack) { return stack[i].icon }
        if let catalog = try? await icons.catalog(),
           let icon = catalog.first(where: { $0.matches(exactly: ref) }), stack.contains(where: { $0.icon == icon.id }) {
            return icon.id
        }
        throw VibeDeckError.stackItemNotFound(ref)
    }

    /// The badge for the current stack (nil when empty).
    public func badge(theme: SkillIconTheme? = nil) async throws -> SkillBadge? {
        let stack = try store.loadProject().stack
        guard !stack.isEmpty else { return nil }
        return try await icons.badge(icons: stack.map(\.icon), theme: theme, perLine: nil)
    }

    /// Rewrites README.md's stack block. Returns a warning instead of throwing: the stack itself is already saved.
    public func syncReadme() async -> String? {
        do {
            try store.syncReadmeStack(badge: try await badge()?.markdown)
            return nil
        } catch {
            return "A stack foi salva, mas o README.md não foi atualizado: \(error.localizedDescription)"
        }
    }

    private func change(_ items: [StackItem]) async throws -> Change {
        let warning = await syncReadme()
        return Change(items: items, stack: try store.loadProject().stack, readmeWarning: warning)
    }
}
