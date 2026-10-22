import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Stack

/// A highlighted technology of the project, kept in `vibedeck.json` under `stack`. `icon` is a Skill Icons id:
/// it identifies the item, and the array order is the display order.
struct StackItem: Codable, Equatable, Hashable, Identifiable, Sendable {
    var icon: String
    var name: String
    var category: String?
    /// How the project uses it ("Swift 6, strict concurrency"); handed to the AI with the stack.
    var note: String?
    var tags: [String]
    var author: Author

    var id: String { icon }

    init(icon: String, name: String, category: String? = nil, note: String? = nil, tags: [String] = [], author: Author = .human) {
        self.icon = icon
        self.name = name
        self.category = category
        self.note = note
        self.tags = tags
        self.author = author
    }

    init(_ icon: SkillIcon, note: String? = nil, author: Author = .human) {
        self.init(icon: icon.id, name: icon.name, category: icon.category, note: note, author: author)
    }

    enum CodingKeys: String, CodingKey { case icon, name, category, note, tags, author }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        icon = try c.decode(String.self, forKey: .icon)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? icon
        category = try c.decodeIfPresent(String.self, forKey: .category)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        author = try c.decodeIfPresent(Author.self, forKey: .author) ?? .human
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(icon, forKey: .icon)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(category, forKey: .category)
        if let note, !note.isEmpty { try c.encode(note, forKey: .note) }
        if !tags.isEmpty { try c.encode(tags, forKey: .tags) }
        try c.encode(author, forKey: .author)
    }
}

// MARK: - Skill Icons

/// An icon of the Skill Icons catalog, as `skill_icons_search` returns it.
struct SkillIcon: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var category: String?
    /// Has dark and light variants.
    var themed: Bool
    var aliases: [String]

    init(id: String, name: String, category: String? = nil, themed: Bool = false, aliases: [String] = []) {
        self.id = id
        self.name = name
        self.category = category
        self.themed = themed
        self.aliases = aliases
    }

    enum CodingKeys: String, CodingKey { case id, name, category, themed, aliases }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? id
        category = try c.decodeIfPresent(String.self, forKey: .category)
        themed = try c.decodeIfPresent(Bool.self, forKey: .themed) ?? false
        aliases = try c.decodeIfPresent([String].self, forKey: .aliases) ?? []
    }

    /// True when `text` names this icon: its id, brand name or an alias (case- and accent-insensitive).
    func matches(exactly text: String) -> Bool {
        let key = SkillIcon.normalize(text)
        return ([id, name] + aliases).contains { SkillIcon.normalize($0) == key }
    }

    /// True when `text` is part of the id, brand name or an alias.
    func matches(containing text: String) -> Bool {
        let key = SkillIcon.normalize(text)
        guard !key.isEmpty else { return true }
        return ([id, name] + aliases).contains { SkillIcon.normalize($0).contains(key) }
    }

    static func normalize(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .filter { $0.isLetter || $0.isNumber || $0 == "+" || $0 == "#" }
    }
}

enum SkillIconTheme: String, CaseIterable, Sendable {
    case dark, light
}

/// What `skill_icons_badge` returns: the image URL plus Markdown/HTML ready to paste.
struct SkillBadge: Codable, Equatable, Sendable {
    struct Unknown: Codable, Equatable, Sendable {
        var name: String
        var suggestions: [String]

        enum CodingKeys: String, CodingKey { case name, suggestions }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decode(String.self, forKey: .name)
            suggestions = try c.decodeIfPresent([String].self, forKey: .suggestions) ?? []
        }
    }

    var url: String
    var markdown: String
    var html: String
    var icons: [String]
    var unknown: [Unknown]

    enum CodingKeys: String, CodingKey { case url, markdown, html, icons, unknown }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url = try c.decode(String.self, forKey: .url)
        markdown = try c.decodeIfPresent(String.self, forKey: .markdown) ?? "![Stack](\(url))"
        html = try c.decodeIfPresent(String.self, forKey: .html) ?? "<img src=\"\(url)\" />"
        icons = try c.decodeIfPresent([String].self, forKey: .icons) ?? []
        unknown = try c.decodeIfPresent([Unknown].self, forKey: .unknown) ?? []
    }
}

/// The Skill Icons MCP server; a protocol so tests can swap the network for a fake.
protocol SkillIconsAPI: Sendable {
    func search(query: String?, category: String?, limit: Int?) async throws -> [SkillIcon]
    func badge(icons: [String], theme: SkillIconTheme?, perLine: Int?) async throws -> SkillBadge
    func image(url: String) async throws -> Data
}

extension SkillIconsAPI {
    /// The whole catalog (one call).
    func catalog() async throws -> [SkillIcon] {
        try await search(query: nil, category: nil, limit: SkillIcons.catalogLimit)
    }
}

/// Client for the Skill Icons MCP server (stateless JSON-RPC over HTTP): the catalog and the rendered icons
/// both come from it, never from hand-written URLs.
struct SkillIcons: SkillIconsAPI {
    static let endpoint = URL(string: "https://skill-icons.alanreisanjo.workers.dev/mcp")!
    static let categories = [
        "language", "frontend", "backend", "database", "cloud", "devops", "tooling", "testing", "observability",
        "auth", "ide", "ai", "design", "game", "payments", "os", "social", "productivity",
    ]
    static let catalogLimit = 631

    var endpoint: URL
    var session: URLSession

    init(endpoint: URL = SkillIcons.endpoint, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.session = session
    }

    func search(query: String?, category: String?, limit: Int?) async throws -> [SkillIcon] {
        var args: [String: Any] = [:]
        if let query, !query.isEmpty { args["query"] = query }
        if let category, !category.isEmpty { args["category"] = category }
        if let limit { args["limit"] = limit }
        struct Result: Decodable { var icons: [SkillIcon] }
        return try Self.decodeToolText(Result.self, from: await callTool("skill_icons_search", args)).icons
    }

    func badge(icons: [String], theme: SkillIconTheme?, perLine: Int?) async throws -> SkillBadge {
        var args: [String: Any] = ["icons": icons]
        if let theme { args["theme"] = theme.rawValue }
        if let perLine { args["perLine"] = perLine }
        return try Self.decodeToolText(SkillBadge.self, from: await callTool("skill_icons_badge", args))
    }

    func image(url: String) async throws -> Data {
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
    static func resolve(_ refs: [String], in catalog: [SkillIcon]) throws -> [SkillIcon] {
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
enum ReadmeStack {
    static let start = "<!-- vibedeck:stack:start -->"
    static let end = "<!-- vibedeck:stack:end -->"

    /// `text` with the block set to `badge` (nil removes it). A new block goes right after the first `# ` heading,
    /// or at the top when there is none.
    static func apply(_ badge: String?, to text: String) -> String {
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
