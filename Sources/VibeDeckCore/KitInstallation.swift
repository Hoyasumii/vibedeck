import Foundation

public struct InstalledKitItem: Codable, Equatable, Sendable {
    public let catalogID: String
    public let kind: KitItemKind
    public let slug: String
}

extension ProjectStore {
    /// Validate the entire explicit selection before writing. References are remapped to the newly
    /// created slugs, including when a previous copy of the kit is already in the project.
    public func addKitItems(_ refs: [String], author: Author = .human) throws -> [InstalledKitItem] {
        let items = try KitCatalog.selection(refs)
        guard !items.isEmpty else { throw VibeDeckError.invalidKitSelection("nenhum item") }
        let missing = try KitCatalog.missingDependencies(refs)
        guard missing.isEmpty else { throw VibeDeckError.missingKitDependencies(missing) }
        var created: [InstalledKitItem] = []
        do {
            for item in items {
                let slug: String
                switch item.kind {
                case .agent:
                    slug = try createAgent(title: item.title, summary: item.summary, prompt: item.prompt, tags: ["kit"], author: author).slug
                case .command:
                    slug = try createCommand(title: item.title, summary: item.summary, argumentHint: "<objetivo>", prompt: item.prompt, tags: ["kit"], author: author).slug
                case .skill:
                    slug = try createSkill(title: item.title, summary: item.summary, prompt: item.prompt, tags: ["kit"], author: author).slug
                case .workflow:
                    slug = try createWorkflow(title: item.title, summary: item.summary, input: "<objetivo e critérios de aceite>", maxSteps: 10, tags: ["kit"], author: author).slug
                }
                created.append(.init(catalogID: item.id, kind: item.kind, slug: slug))
            }
            let mapping = Dictionary(uniqueKeysWithValues: created.map { ($0.catalogID, $0.slug) })
            func target(_ ref: String) throws -> String {
                guard let slug = mapping[ref] else { throw VibeDeckError.missingKitDependencies([ref]) }
                return slug
            }
            for (item, installed) in zip(items, created) {
                let next = try item.nextSteps.map { NextStep(kind: $0.kind, ref: try target($0.ref), note: $0.note) }
                switch item.kind {
                case .agent: if !next.isEmpty { try updateAgent(installed.slug) { $0.nextSteps = next } }
                case .command: if !next.isEmpty { try updateCommand(installed.slug) { $0.nextSteps = next } }
                case .skill: if !next.isEmpty { try updateSkill(installed.slug) { $0.nextSteps = next } }
                case .workflow:
                    let steps = try item.steps.map { step -> WorkflowStep in
                        var step = step
                        step.ref = try target(step.ref)
                        return step
                    }
                    try updateWorkflow(installed.slug) { $0.steps = steps }
                }
            }
            return created
        } catch {
            // Roll back only this operation's creations, never a previous item or kit copy.
            for item in created.reversed() {
                switch item.kind {
                case .agent: try? deleteAgent(item.slug)
                case .command: try? deleteCommand(item.slug)
                case .skill: try? deleteSkill(item.slug)
                case .workflow: try? deleteWorkflow(item.slug)
                }
            }
            throw error
        }
    }
}
