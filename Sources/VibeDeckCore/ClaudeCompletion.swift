import Foundation

/// One entry of the composer's autocomplete list.
public struct ClaudeSuggestion: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case command, file, chat }

    public var kind: Kind
    /// Text shown and inserted (`/review`, `Sources/App.swift`).
    public var name: String
    public var detail: String?
    /// Chats only.
    public var chatId: UUID?

    public var id: String { "\(kind)-\(name)-\(chatId?.uuidString ?? "")" }

    public init(kind: Kind, name: String, detail: String? = nil, chatId: UUID? = nil) {
        self.kind = kind
        self.name = name
        self.detail = detail
        self.chatId = chatId
    }
}

/// What the cursor is completing: a `/command` at the start of the draft or an `@mention` of the last word.
public struct ClaudeTrigger: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case command, mention }

    public var kind: Kind
    public var query: String
    /// Characters of the draft the accepted suggestion replaces (the `/` or `@` included).
    public var range: Range<String.Index>
}

public enum ClaudeCompletion {
    /// Commands that work in headless mode, shown even before the session reports its own list.
    public static let builtinCommands: [(name: String, detail: String)] = [
        ("clear", "Apaga esta conversa e começa do zero"),
        ("compact", "Resume a conversa para liberar contexto"),
        ("context", "Mostra o uso da janela de contexto"),
        ("cost", "Mostra o custo da sessão"),
        ("init", "Cria um CLAUDE.md para o projeto"),
        ("review", "Revisa um pull request"),
        ("security-review", "Revisão de segurança das mudanças"),
    ]

    // MARK: Trigger

    /// `/` only counts while the draft is a single word; `@` counts on the last word, at the start or after a space.
    public static func trigger(in draft: String) -> ClaudeTrigger? {
        if draft.hasPrefix("/"), !draft.contains(where: \.isWhitespace) {
            return ClaudeTrigger(kind: .command, query: String(draft.dropFirst()), range: draft.startIndex..<draft.endIndex)
        }
        guard let at = draft.lastIndex(of: "@") else { return nil }
        if at != draft.startIndex, !draft[draft.index(before: at)].isWhitespace { return nil }
        let word = draft[draft.index(after: at)...]
        guard !word.contains(where: \.isWhitespace) else { return nil }
        return ClaudeTrigger(kind: .mention, query: String(word), range: at..<draft.endIndex)
    }

    // MARK: Ranking

    /// Case-insensitive match score (higher is better); nil when `query` doesn't match. Prefix and
    /// file-name matches beat plain subsequences.
    public static func score(_ candidate: String, query: String) -> Int? {
        if query.isEmpty { return 0 }
        let c = candidate.lowercased(), q = query.lowercased()
        let base = (c as NSString).lastPathComponent
        if base.hasPrefix(q) || c.hasPrefix(q) { return 1000 - c.count }
        if base.contains(q) { return 600 - c.count }
        if c.contains(q) { return 400 - c.count }
        var rest = c[...]
        for ch in q {
            guard let hit = rest.firstIndex(of: ch) else { return nil }
            rest = rest[rest.index(after: hit)...]
        }
        return 100 - c.count
    }

    public static func rank(_ items: [ClaudeSuggestion], query: String, limit: Int = 8) -> [ClaudeSuggestion] {
        let scored = items.compactMap { item in score(item.name, query: query).map { (item, $0) } }
        return scored.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }

    // MARK: Commands

    /// Built-ins, the session's reported commands (plugins included), and the custom commands and skills found on disk.
    public static func commands(root: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser, reported: [String] = []) -> [ClaudeSuggestion] {
        var found: [String: String?] = [:]
        for (name, detail) in builtinCommands { found[name] = detail }
        for name in reported where found[name] == nil { found[name] = .some(nil) }
        for base in [root.appending(path: ".claude"), home.appending(path: ".claude")] {
            for (name, detail) in customCommands(in: base.appending(path: "commands")) { found[name] = detail }
            for (name, detail) in skills(in: base.appending(path: "skills")) { found[name] = detail }
        }
        return found.keys.sorted().map { ClaudeSuggestion(kind: .command, name: "/" + $0, detail: found[$0] ?? nil) }
    }

    /// `commands/a/b.md` → `a:b`, described by its frontmatter or first line.
    static func customCommands(in dir: URL) -> [(String, String?)] {
        let fm = FileManager.default
        guard let walker = fm.enumerator(atPath: dir.path) else { return [] }
        var out: [(String, String?)] = []
        for case let relative as String in walker where relative.hasSuffix(".md") && !relative.split(separator: "/").contains(where: { $0.hasPrefix(".") }) {
            let name = String(relative.dropLast(3)).replacingOccurrences(of: "/", with: ":")
            out.append((name, describe(dir.appending(path: relative))))
        }
        return out
    }

    /// `skills/<name>/SKILL.md`.
    static func skills(in dir: URL) -> [(String, String?)] {
        let entries = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return entries.compactMap { entry in
            let file = entry.appending(path: "SKILL.md")
            guard FileManager.default.fileExists(atPath: file.path) else { return nil }
            return (entry.lastPathComponent, describe(file))
        }
    }

    /// `description:` from the frontmatter, else the first non-empty body line.
    static func describe(_ url: URL) -> String? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        var body = lines[...]
        if lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") {
            if let d = lines[1..<end].first(where: { $0.hasPrefix("description:") }) {
                let value = d.dropFirst("description:".count).trimmingCharacters(in: CharacterSet.whitespaces.union(["\"", "'"]))
                if !value.isEmpty { return value }
            }
            body = lines[(end + 1)...]
        }
        return body.first { !$0.isEmpty }.map { String($0.drop(while: { $0 == "#" || $0 == " " }).prefix(120)) }
    }

    // MARK: Files

    static let skippedDirectories: Set<String> = [".git", "node_modules", ".build", "build", "DerivedData", ".swiftpm", "dist", ".next", "Pods", "__pycache__", ".venv", "target"]

    /// Relative paths of the project's files (and folders, with a trailing `/`), without build/dependency output.
    public static func projectFiles(root: URL, limit: Int = 8000) -> [String] {
        let fm = FileManager.default
        guard let walker = fm.enumerator(atPath: root.path) else { return [] }
        var out: [String] = []
        for case let relative as String in walker {
            let parts = relative.split(separator: "/")
            let name = String(parts.last ?? "")
            let isDirectory = walker.fileAttributes?[.type] as? FileAttributeType == .typeDirectory
            if name.hasPrefix(".") || skippedDirectories.contains(name) {
                if isDirectory { walker.skipDescendants() }
                continue
            }
            out.append(isDirectory ? relative + "/" : relative)
            if out.count >= limit { break }
        }
        return out
    }
}

// MARK: - Terminal commands

public enum ShellCommand {
    /// Programs that take over the screen or wait for keyboard input, so `!` can't capture their output.
    static let interactivePrograms: Set<String> = [
        "vi", "vim", "nvim", "nano", "emacs", "pico", "micro", "hx",
        "top", "htop", "btop", "less", "more", "man", "watch", "tig", "lazygit",
        "ssh", "mosh", "telnet", "ftp", "sftp", "tmux", "screen", "claude", "codex",
    ]
    /// REPLs: interactive only when started without a script or command.
    static let repls: Set<String> = ["python", "python3", "node", "irb", "ruby", "swift", "bash", "zsh", "sh", "fish", "psql", "mysql", "sqlite3", "redis-cli"]

    /// Whether `command` needs a real terminal (pty) instead of having its output captured.
    public static func isInteractive(_ command: String) -> Bool {
        let words = command.split(whereSeparator: \.isWhitespace).map(String.init)
        // Skip env assignments and wrappers like `sudo`.
        guard let index = words.firstIndex(where: { !$0.contains("=") && $0 != "sudo" && $0 != "env" && $0 != "exec" }) else { return false }
        let program = (words[index] as NSString).lastPathComponent
        let args = words[(index + 1)...]
        if interactivePrograms.contains(program) { return true }
        if repls.contains(program) { return args.isEmpty }
        if program == "git", let sub = args.first {
            // Commands that open an editor or a pager-driven prompt.
            if sub == "commit" { return !args.contains { $0 == "-m" || $0.hasPrefix("--message") || $0 == "--no-edit" || $0.hasPrefix("-am") } }
            if sub == "rebase" { return args.contains { $0 == "-i" || $0 == "--interactive" } }
            if sub == "add" { return args.contains { $0 == "-p" || $0 == "-i" || $0 == "--patch" || $0 == "--interactive" } }
        }
        return false
    }
}
