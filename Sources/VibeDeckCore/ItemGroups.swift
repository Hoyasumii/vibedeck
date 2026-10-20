import Foundation

/// Directory groups are separate from review themes (one ReviewGroup JSON per theme).
public enum ItemConcept: String, Codable, CaseIterable, Sendable {
    case ideas, reviews, docs, skills
    public var fileExtension: String { self == .docs ? "md" : "json" }
}

public struct ItemDirectory: Codable, Equatable, Sendable, Identifiable {
    public var path: String
    public var id: String { path }
    public init(path: String) { self.path = path }
}

public struct GroupedRecord<Value: Encodable>: Encodable {
    public let slug: String
    public let value: Value
    public init(slug: String, value: Value) { self.slug = slug; self.value = value }
    public func encode(to encoder: Encoder) throws {
        try value.encode(to: encoder)
        var container = encoder.container(keyedBy: Keys.self)
        try container.encode(slug, forKey: .slug)
        try container.encode(ProjectStore.groupPath(of: slug), forKey: .group)
    }
    private enum Keys: String, CodingKey { case slug, group }
}

extension ProjectStore {
    public func directory(for concept: ItemConcept) -> URL {
        switch concept {
        case .ideas: ideasDir
        case .reviews: reviewsDir
        case .docs: docsDir
        case .skills: skillsDir
        }
    }

    public static func groupPath(of reference: String) -> String {
        reference.split(separator: "/").dropLast().joined(separator: "/")
    }

    /// Reject traversal before slug normalization; empty is only allowed for the root destination.
    public func normalizedGroupPath(_ path: String, allowRoot: Bool = false) throws -> String {
        if path.isEmpty, allowRoot { return "" }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"), parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.hasPrefix(".") }) else {
            throw VibeDeckError.invalidGroupPath(path)
        }
        return parts.map { Slug.make(String($0)) }.joined(separator: "/")
    }

    /// Foundation stops resolving when the final component does not exist. Resolve the longest existing
    /// ancestor first, then append missing components; this is essential for safe creates through symlinks.
    func canonicalURL(_ url: URL) -> URL {
        let fm = FileManager.default
        var ancestor = url.standardizedFileURL
        var missing: [String] = []
        var seen = Set<String>()
        while !fm.fileExists(atPath: ancestor.path), ancestor.path != "/" {
            if let target = try? fm.destinationOfSymbolicLink(atPath: ancestor.path), seen.insert(ancestor.path).inserted {
                ancestor = target.hasPrefix("/") ? URL(fileURLWithPath: target) : ancestor.deletingLastPathComponent().appending(path: target)
                ancestor = ancestor.standardizedFileURL
                continue
            }
            missing.append(ancestor.lastPathComponent)
            ancestor.deleteLastPathComponent()
        }
        var resolved = ancestor.resolvingSymlinksInPath()
        for component in missing.reversed() { resolved.append(path: component) }
        return resolved.standardizedFileURL
    }

    /// Resolving both the parent and the final path catches existing and dangling symlinks.
    func containedURL(_ path: String, in dir: URL) throws -> URL {
        let base = canonicalURL(dir)
        // A concept folder itself cannot redirect writes outside .vibedeck.
        let data = canonicalURL(dataDir).path
        guard base.path.hasPrefix(data + "/") else { throw VibeDeckError.invalidGroupPath(path) }
        let url = base.appending(path: path).standardizedFileURL
        let resolved = canonicalURL(url).path
        guard resolved == base.path || resolved.hasPrefix(base.path + "/") else { throw VibeDeckError.invalidGroupPath(path) }
        return url
    }

    func validatedRecordURL(_ reference: String, in dir: URL, extension ext: String) throws -> URL {
        _ = try normalizedGroupPath(reference)
        return try containedURL(reference + "." + ext, in: dir)
    }

    func relativeItemPath(_ url: URL, in dir: URL) -> String {
        let base = canonicalURL(dir).path
        let path = canonicalURL(url).path
        return String(path.dropFirst(base.count + 1))
    }

    func relativeRecordPath(_ url: URL, in dir: URL) -> String {
        relativeItemPath(canonicalURL(url).deletingPathExtension(), in: dir)
    }

    /// Never traverses symlink directories, and never reads a file escaping the concept folder.
    func recordFiles(in dir: URL, extension ext: String, recursive: Bool = true) throws -> [URL] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir.path) else { return [] }
        if !recursive {
            return try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]).filter {
                let values = try $0.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                return values.isRegularFile == true && values.isSymbolicLink != true && $0.pathExtension.lowercased() == ext
            }.map { canonicalURL($0) }.sorted { $0.path < $1.path }
        }
        guard let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]) else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            if values.isRegularFile == true, url.pathExtension.lowercased() == ext {
                _ = try containedURL(relativeItemPath(url, in: dir), in: dir)
                files.append(canonicalURL(url))
            }
        }
        return files.sorted { $0.path < $1.path }
    }

    public func itemDirectoryURL(_ concept: ItemConcept, path: String) throws -> URL {
        _ = try normalizedGroupPath(path)
        return try containedURL(path, in: directory(for: concept))
    }

    public func listItemDirectories(_ concept: ItemConcept) throws -> [ItemDirectory] {
        let dir = directory(for: concept)
        guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]) else { return [] }
        var result: [ItemDirectory] = []
        for case let url as URL in e {
            let v = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if v.isSymbolicLink == true { e.skipDescendants(); continue }
            if v.isDirectory == true {
                let path = relativeItemPath(url, in: dir)
                _ = try containedURL(path, in: dir)
                result.append(ItemDirectory(path: path))
            }
        }
        return result.sorted { $0.path < $1.path }
    }

    @discardableResult
    public func createItemDirectory(_ concept: ItemConcept, path: String) throws -> String {
        let path = try normalizedGroupPath(path)
        let url = try containedURL(path, in: directory(for: concept))
        guard !FileManager.default.fileExists(atPath: url.path) else { throw VibeDeckError.groupConflict(path) }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        VDLog.info("store.group_created", "Grupo criado", project: root, context: ["concept": concept.rawValue, "path": path])
        return path
    }

    /// `destination` is a full new path, for both rename and move. The source bytes are untouched.
    public func moveItemDirectory(_ concept: ItemConcept, from: String, to destination: String) throws {
        try moveDirectory(concept, from: from, to: destination, normalizeDestination: true)
    }

    private func moveDirectory(_ concept: ItemConcept, from: String, to destination: String, normalizeDestination: Bool) throws {
        _ = try normalizedGroupPath(from)
        let source = from
        let normalized = try normalizedGroupPath(destination)
        let target = normalizeDestination ? normalized : destination
        guard target != source, !target.hasPrefix(source + "/") else { throw VibeDeckError.invalidGroupPath(destination) }
        let dir = directory(for: concept)
        let fromURL = try containedURL(source, in: dir)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: fromURL.path, isDirectory: &isDir), isDir.boolValue else { throw VibeDeckError.groupNotFound(from) }
        // Validate every descendant before any mutation (including symlinks).
        try validateDescendants(fromURL, in: dir)
        let toURL = try containedURL(target, in: dir)
        let mapping = try recordFiles(in: fromURL, extension: concept.fileExtension).map {
            let old = relativeRecordPath($0, in: dir)
            return (old, target + String(old.dropFirst(source.count)))
        }
        try rename(concept, from: fromURL, to: toURL, mapping: mapping)
    }

    public func moveGroupedItem(_ concept: ItemConcept, reference: String, to destinationGroup: String) throws -> String {
        let ref = try resolveGroupedReference(concept, reference)
        let group = try normalizedGroupPath(destinationGroup, allowRoot: true)
        let target = (group.isEmpty ? "" : group + "/") + String(ref.split(separator: "/").last!)
        guard target != ref else { return ref }
        let dir = directory(for: concept)
        try rename(concept, from: validatedRecordURL(ref, in: dir, extension: concept.fileExtension),
                   to: validatedRecordURL(target, in: dir, extension: concept.fileExtension), mapping: [(ref, target)])
        return target
    }

    public func resolveGroupedReference(_ concept: ItemConcept, _ reference: String) throws -> String {
        switch concept {
        case .ideas: try resolveIdeaSlug(reference)
        case .reviews: try resolveGroupSlug(reference)
        case .skills: try resolveSkillSlug(reference)
        case .docs: try resolveDocSlug(reference)
        }
    }

    public func resolveDocSlug(_ reference: String) throws -> String {
        _ = try normalizedGroupPath(reference)
        let docs = try listDocs()
        let slugs = docs.filter { reference.contains("/") ? $0.slug == reference :
            ($0.slug.split(separator: "/").last.map(String.init) == reference || $0.slug.split(separator: "/").last.map(String.init) == Slug.make(reference)) }
        let candidates = slugs.isEmpty ? docs.filter { $0.title.caseInsensitiveCompare(reference) == .orderedSame } : slugs
        if candidates.count > 1 { throw VibeDeckError.ambiguousReference(reference, candidates.map(\.slug)) }
        guard let found = candidates.first else { throw VibeDeckError.docNotFound(reference) }
        return found.slug
    }

    public func deleteItemDirectory(_ concept: ItemConcept, path: String, confirmed: Bool = false) throws {
        _ = try normalizedGroupPath(path)
        let dir = directory(for: concept)
        let url = try containedURL(path, in: dir)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { throw VibeDeckError.groupNotFound(path) }
        try validateDescendants(url, in: dir)
        let contents = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
        guard confirmed || contents.isEmpty else { throw VibeDeckError.groupConfirmationRequired(path) }
        try ProjectFiles.remove(url)
        VDLog.info("store.group_deleted", "Grupo apagado", project: root, context: ["concept": concept.rawValue, "path": path])
    }

    private func validateDescendants(_ url: URL, in dir: URL) throws {
        if let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) {
            for case let child as URL in e {
                _ = try containedURL(relativeItemPath(child, in: dir), in: dir)
            }
        }
    }

    private func rename(_ concept: ItemConcept, from: URL, to: URL, mapping: [(String, String)]) throws {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: to.path), (try? to.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { throw VibeDeckError.groupConflict(to.path) }
        // Read/encode all affected references before moving anything. Failed updates roll back bytes and rename.
        let updates = try referenceUpdates(concept, mapping: mapping)
        try fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
        try ProjectFiles.move(from, to: to)
        var applied: [(URL, Data)] = []
        do {
            for (url, before, after) in updates {
                let movedURL = url.path == from.path || url.path.hasPrefix(from.path + "/") ? URL(fileURLWithPath: to.path + String(url.path.dropFirst(from.path.count))) : url
                applied.append((movedURL, before))
                try AtomicFile.write(after, to: movedURL)
            }
        } catch {
            for (url, bytes) in applied.reversed() { try? AtomicFile.write(bytes, to: url) }
            try? ProjectFiles.move(to, to: from)
            throw error
        }
        VDLog.info("store.group_moved", "Item ou grupo movido", project: root, context: ["concept": concept.rawValue, "from": from.path, "to": to.path])
    }

    /// Skills are referenced by nextSteps and workflow steps. Resolve before the move, so bare slugs,
    /// UUIDs and titles are updated only when they actually identify an item being moved.
    private func referenceUpdates(_ concept: ItemConcept, mapping: [(String, String)]) throws -> [(URL, Data, Data)] {
        guard concept == .skills else { return [] }
        let paths = Dictionary(uniqueKeysWithValues: mapping)
        var result: [(URL, Data, Data)] = []
        func rewrite(_ value: Any) throws -> Any {
            if let list = value as? [Any] { return try list.map(rewrite) }
            guard var object = value as? [String: Any] else { return value }
            if object["kind"] as? String == "skill", let ref = object["ref"] as? String,
               let old = try? resolveSkillSlug(ref), let target = paths[old] { object["ref"] = target }
            for key in object.keys { object[key] = try rewrite(object[key]!) }
            return object
        }
        for dir in [agentDefsDir, commandsDir, skillsDir, workflowsDir] {
            for url in try recordFiles(in: dir, extension: "json") {
                let before = try Data(contentsOf: url)
                let object = try JSONSerialization.jsonObject(with: before)
                let after = try rewrite(object)
                if !NSDictionary(dictionary: object as? [String: Any] ?? [:]).isEqual(to: after as? [String: Any] ?? [:]) {
                    result.append((url, before, try VDJSON.encodeObject(after)))
                }
            }
        }
        return result
    }
}

extension ProjectStore {
    @discardableResult
    public func moveRuleToGroup(_ ref: String, group: String) throws -> Rule {
        let path = try normalizedGroupPath(group, allowRoot: true)
        return try updateRule(ref) { $0.group = path.isEmpty ? nil : path }
    }

    public func ruleGroupRenamed(_ rules: [Rule], from: String, to: String) throws -> [Rule] {
        _ = try normalizedGroupPath(from)
        let source = from
        let target = try normalizedGroupPath(to)
        guard target != source, !target.hasPrefix(source + "/") else { throw VibeDeckError.invalidGroupPath(to) }
        guard !rules.contains(where: { ($0.group ?? "") == target || ($0.group ?? "").hasPrefix(target + "/") }) else { throw VibeDeckError.groupConflict(target) }
        return rules.map { rule in
            var moved = rule
            if let group = rule.group, group == source || group.hasPrefix(source + "/") { moved.group = target + String(group.dropFirst(source.count)) }
            return moved
        }
    }

    public func renameRuleGroup(topic ref: String, from: String, to: String) throws {
        let topic = try loadTopic(resolveTopicSlug(ref))
        let moved = try ruleGroupRenamed(topic.rules, from: from, to: to)
        try updateTopic(ref) { $0.rules = moved }
    }
}

extension ProjectStore {
    /// Attachments retain their identity when a Markdown record moves. Rebase the known attachment convention
    /// for rendering only; move operations never rewrite the stored Markdown or JSON.
    public static func markdownForGroupedRecord(_ text: String, reference: String) -> String {
        let prefix = String(repeating: "../", count: reference.split(separator: "/").count)
        guard let regex = try? NSRegularExpression(pattern: #"(?<=\()(?:(?:\.\./)+)attachments/"#) else { return text }
        return regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: prefix + "attachments/")
    }
    public static func attachmentPath(name: String, owner: String) -> String {
        String(repeating: "../", count: owner.split(separator: "/").count) + "attachments/" + name
    }
}

public struct GroupMoveReceipt: Sendable {
    public struct ReferenceChange: Sendable {
        public let beforeURL: URL
        public let afterURL: URL
        public let before: Data
        public let after: Data
    }
    public let concept: ItemConcept
    public let source: String
    public let destination: String
    public let isDirectory: Bool
    public let references: [ReferenceChange]
}

extension ProjectStore {
    /// Captures only changed reference files so undo restores bare slugs, UUIDs and titles byte for byte.
    public func moveWithReceipt(_ concept: ItemConcept, from reference: String, to destination: String, directory: Bool) throws -> GroupMoveReceipt {
        _ = try normalizedGroupPath(reference)
        let source = directory ? reference : try resolveGroupedReference(concept, reference)
        let dir = self.directory(for: concept)
        let sourceURL = directory ? try containedURL(source, in: dir) : try validatedRecordURL(source, in: dir, extension: concept.fileExtension)
        let before = try skillReferenceBytes(concept)
        let target: String
        if directory { try moveItemDirectory(concept, from: source, to: destination); target = try normalizedGroupPath(destination) }
        else { target = try moveGroupedItem(concept, reference: source, to: destination) }
        let targetURL = directory ? try containedURL(target, in: dir) : try validatedRecordURL(target, in: dir, extension: concept.fileExtension)
        let changed = try before.compactMap { url, bytes -> GroupMoveReceipt.ReferenceChange? in
            let moved = url.path == sourceURL.path || url.path.hasPrefix(sourceURL.path + "/")
            let afterURL = moved ? URL(fileURLWithPath: targetURL.path + String(url.path.dropFirst(sourceURL.path.count))) : url
            let after = try Data(contentsOf: afterURL)
            guard after != bytes else { return nil }
            return .init(beforeURL: url, afterURL: afterURL, before: bytes, after: after)
        }
        return GroupMoveReceipt(concept: concept, source: source, destination: target, isDirectory: directory, references: changed)
    }

    public func undoGroupedMove(_ receipt: GroupMoveReceipt) throws -> GroupMoveReceipt {
        // An external edit is never overwritten by undo.
        for change in receipt.references {
            try validateReferenceURL(change.beforeURL)
            try validateReferenceURL(change.afterURL)
            guard try Data(contentsOf: change.afterURL) == change.after else { throw VibeDeckError.groupConflict(change.afterURL.path) }
        }
        if receipt.isDirectory {
            try moveDirectory(receipt.concept, from: receipt.destination, to: receipt.source, normalizeDestination: false)
        } else {
            let dir = directory(for: receipt.concept)
            try rename(receipt.concept, from: validatedRecordURL(receipt.destination, in: dir, extension: receipt.concept.fileExtension),
                       to: validatedRecordURL(receipt.source, in: dir, extension: receipt.concept.fileExtension), mapping: [(receipt.destination, receipt.source)])
        }
        for change in receipt.references { try AtomicFile.write(change.before, to: change.beforeURL) }
        return GroupMoveReceipt(concept: receipt.concept, source: receipt.destination, destination: receipt.source, isDirectory: receipt.isDirectory,
                                references: receipt.references.map { .init(beforeURL: $0.afterURL, afterURL: $0.beforeURL, before: $0.after, after: $0.before) })
    }

    private func validateReferenceURL(_ url: URL) throws {
        for dir in [agentDefsDir, commandsDir, skillsDir, workflowsDir] {
            let base = canonicalURL(dir).path
            if url.standardizedFileURL.path.hasPrefix(base + "/") {
                _ = try containedURL(String(url.path.dropFirst(base.count + 1)), in: dir)
                return
            }
        }
        throw VibeDeckError.invalidGroupPath(url.path)
    }

    private func skillReferenceBytes(_ concept: ItemConcept) throws -> [URL: Data] {
        guard concept == .skills else { return [:] }
        return try Dictionary(uniqueKeysWithValues: [agentDefsDir, commandsDir, skillsDir, workflowsDir].flatMap { dir in
            try recordFiles(in: dir, extension: "json").map { ($0, try Data(contentsOf: $0)) }
        })
    }
}

// Preserve the pre-grouping flow builders for callers with flat fixtures, while accepting grouped lists.
extension AgentFlow {
    public static func build(kind: NextStepKind = .agent, from slug: String,
                             agents: [(slug: String, agent: Agent)], commands: [(slug: String, command: Command)] = [],
                             skills: [(slug: String, skill: Skill, group: String)]) -> AgentFlowNode? {
        build(kind: kind, from: slug, agents: agents, commands: commands, skills: skills.map { ($0.slug, $0.skill) })
    }
    public static func json(kind: NextStepKind = .agent, from slug: String,
                            agents: [(slug: String, agent: Agent)], commands: [(slug: String, command: Command)] = [],
                            skills: [(slug: String, skill: Skill, group: String)]) throws -> String? {
        try json(kind: kind, from: slug, agents: agents, commands: commands, skills: skills.map { ($0.slug, $0.skill) })
    }
}

extension WorkflowPlan {
    public static func build(slug: String, workflow: Workflow, input: String? = nil,
                             agents: [(slug: String, agent: Agent)], commands: [(slug: String, command: Command)] = [],
                             skills: [(slug: String, skill: Skill, group: String)]) -> WorkflowPlan {
        build(slug: slug, workflow: workflow, input: input, agents: agents, commands: commands, skills: skills.map { ($0.slug, $0.skill) })
    }
}
