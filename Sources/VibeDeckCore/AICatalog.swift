import Foundation

/// Compact discovery is opt-in; existing list APIs retain their wire format.
public struct AICatalogPage: Codable, Sendable {
    public struct Item: Codable, Sendable {
        public let ref: String
        public let title: String
        public let summary: String?
        public let paths: [String]?
    }
    public let items: [Item]
    public let nextOffset: Int?
    public let total: Int
}

extension ProjectStore {
    public func aiCatalog(kind: String, offset: Int = 0, limit: Int = 20) throws -> AICatalogPage {
        guard offset >= 0, (1...100).contains(limit) else { throw AIContextError.invalidRange }
        let all: [AICatalogPage.Item]
        switch kind {
        case "agents": all = try listAgents().map { .init(ref: $0.slug, title: $0.agent.title, summary: $0.agent.summary, paths: nil) }
        case "commands": all = try listCommands().map { .init(ref: $0.slug, title: $0.command.title, summary: $0.command.summary, paths: nil) }
        case "skills": all = try listSkills().map { .init(ref: $0.slug, title: $0.skill.title, summary: $0.skill.summary, paths: nil) }
        case "workflows": all = try listWorkflows().map { .init(ref: $0.slug, title: $0.workflow.title, summary: $0.workflow.summary, paths: nil) }
        case "rules": all = try listTopics().map { .init(ref: $0.slug, title: $0.topic.title, summary: $0.topic.description, paths: $0.topic.paths) }
        default: throw VibeDeckError.discoverFailed("Catálogo inválido: use agents, commands, skills, workflows ou rules.")
        }
        let sorted = all.sorted { $0.ref < $1.ref }
        guard offset <= sorted.count else { throw AIContextError.invalidRange }
        let items = Array(sorted.dropFirst(offset).prefix(limit))
        let end = offset + items.count
        return .init(items: items, nextOffset: end < sorted.count ? end : nil, total: sorted.count)
    }

    /// Full output travels with the workflow. History contains a reference, not a cut-off string.
    public func saveRunOutput(_ ref: String, output: String) throws -> String {
        let resolved = try resolveRunRef(ref)
        let directory = runURL(resolved).deletingLastPathComponent().appending(path: "outputs")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: UUID().uuidString + ".md")
        try AtomicFile.write(Data(output.utf8), to: file)
        return "Saída completa em `\(relativePath(file.path))` (\(output.count) caracteres). Leia quando necessário; não é um resumo do conteúdo."
    }
}
