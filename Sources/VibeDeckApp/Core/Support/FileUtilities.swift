import Foundation

/// Lock for the app's own files (chats, caches, logs). Project data is written by the Rust Core, never here.
final class FilesLock: @unchecked Sendable {
    static let shared = FilesLock()
    let lock = NSRecursiveLock()
}

enum AtomicFile {
    static func write(_ data: Data, to url: URL) throws {
        try FilesLock.shared.lock.withLock {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }
        VDLog.fileWritten(url, bytes: data.count)
    }
}

enum Slug {
    static func make(_ text: String) -> String {
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

enum Markdown {
    /// Title from YAML frontmatter `title:` or the first `# ` heading.
    static func title(of text: String) -> String? {
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
    static func tags(of text: String) -> [String] {
        guard let line = frontmatter(of: text).front?.first(where: { $0.hasPrefix("tags:") }) else { return [] }
        return line.dropFirst("tags:".count)
            .trimmingCharacters(in: CharacterSet(charactersIn: " []"))
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \"'")) }
            .filter { !$0.isEmpty }
    }

    /// Returns `text` with the frontmatter `tags:` line replaced, added (creating the frontmatter
    /// if needed) or removed when `tags` is empty. Everything else is preserved.
    static func settingTags(_ tags: [String], in text: String) -> String {
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

enum ProjectFiles {
    static func remove(_ url: URL) throws { try FilesLock.shared.lock.withLock { try FileManager.default.removeItem(at: url) } }
    static func move(_ source: URL, to target: URL) throws { try FilesLock.shared.lock.withLock { try FileManager.default.moveItem(at: source, to: target) } }
}
