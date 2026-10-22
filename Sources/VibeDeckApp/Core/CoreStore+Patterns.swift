import Foundation

// Padrões do projeto (add_pattern / remove_pattern / update_pattern / set_tags). O Core cria e remove o tópico de regras de cada padrão.
// O app cria padrões como `human` (argumento `author` do modo --app).
extension CoreStore {
    @discardableResult
    func addPatterns(_ ids: [String], note: String?, paths: [String], author: Author = .human) async throws -> String {
        var args: [String: Any] = ["patterns": ids, "paths": paths, "author": author.rawValue]
        if let note = note, !note.isEmpty { args["note"] = note }
        return try await call("add_pattern", args)
    }

    @discardableResult
    func addCustomPattern(name: String, summary: String?, rules: [String], note: String?, paths: [String], author: Author = .human) async throws -> String {
        var args: [String: Any] = ["name": name, "rules": rules, "paths": paths, "author": author.rawValue]
        if let summary = summary, !summary.isEmpty { args["summary"] = summary }
        if let note = note, !note.isEmpty { args["note"] = note }
        return try await call("add_pattern", args)
    }

    @discardableResult
    func removePatterns(_ ids: [String]) async throws -> String {
        try await call("remove_pattern", ["patterns": ids])
    }

    @discardableResult
    func setPatternNote(_ id: String, _ note: String) async throws -> String {
        try await call("update_pattern", ["pattern": id, "note": note])
    }

    @discardableResult
    func setPatternPaths(_ id: String, _ paths: [String]) async throws -> String {
        try await call("update_pattern", ["pattern": id, "paths": paths])
    }

    func setPatternTags(_ id: String, _ tags: [String]) async throws {
        try await setTags(kind: "pattern", ref: id, tags: tags)
    }
}

/// Uma linha do catálogo de padrões do Core (`pattern_catalog`). O catálogo vive só no Core.
struct PatternCatalogEntry: Decodable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var category: String
    var summary: String
    var rules: [String]
    var inProject: Bool
    var aliases: [String]?
}

extension CoreStore {
    func patternCatalog(query: String? = nil) async throws -> [PatternCatalogEntry] {
        var args: [String: Any] = [:]
        if let query = query, !query.isEmpty { args["query"] = query }
        return try await callJSON("pattern_catalog", args, as: [PatternCatalogEntry].self, idempotent: true)
    }
}
