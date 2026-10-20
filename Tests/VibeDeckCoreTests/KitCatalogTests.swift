import Foundation
import Testing
@testable import VibeDeckCore

@Suite struct KitCatalogTests {
    private func newStore() throws -> ProjectStore {
        try ProjectStore.initialize(at: FileManager.default.temporaryDirectory.appending(path: "vd-kits-\(UUID())"))
    }

    @Test func selectionMustBeExplicitAndCompleteBeforeWriting() throws {
        let store = try newStore()
        defer { try? FileManager.default.removeItem(at: store.root) }
        #expect(throws: VibeDeckError.self) { try store.addKitItems([]) }
        #expect(throws: VibeDeckError.self) { try store.addKitItems(["desconhecido"]) }
        for kit in KitCatalog.kits {
            let workflow = try #require(kit.items.first { $0.kind == .workflow })
            #expect(try KitCatalog.missingDependencies([workflow.id]) == workflow.dependencies)
            #expect(throws: VibeDeckError.missingKitDependencies(workflow.dependencies)) {
                try store.addKitItems([workflow.id])
            }
        }
        #expect(try store.listAgents().isEmpty)
        #expect(try store.listCommands().isEmpty)
        #expect(try store.listSkills().isEmpty)
        #expect(try store.listWorkflows().isEmpty)
        let item = KitCatalog.kits[0].items[0]
        let added = try store.addKitItems([item.id, item.id], author: .ai)
        #expect(added.count == 1)
        #expect(try store.loadAgent(added[0].slug).nextSteps.isEmpty)
        #expect(try store.loadAgent(added[0].slug).author == .ai)
    }

    @Test func duplicateKitsRemapReferencesAndPreserveEdits() throws {
        let store = try newStore()
        defer { try? FileManager.default.removeItem(at: store.root) }
        for kit in KitCatalog.kits {
            let first = try store.addKitItems([kit.id])
            let agent = try #require(first.first { $0.kind == .agent })
            let command = try #require(first.first { $0.kind == .command })
            let skill = try #require(first.first { $0.kind == .skill })
            let workflow = try #require(first.first { $0.kind == .workflow })
            try store.updateAgent(agent.slug) { $0.prompt = "Edição manual" }
            try store.updateCommand(command.slug) { $0.prompt = "Edição por IA" }
            try store.updateSkill(skill.slug) { $0.prompt = "Instruções locais" }
            try store.updateWorkflow(workflow.slug) { $0.summary = "Fluxo local" }
            let before = try first.map { try Data(contentsOf: url($0, store: store)) }
            let second = try store.addKitItems([kit.id], author: .ai)
            #expect(second.count == 4)
            for (old, new) in zip(first, second) {
                #expect(new.slug != old.slug)
                #expect(new.slug == old.slug + "-2")
            }
            #expect(try first.map { try Data(contentsOf: url($0, store: store)) } == before)
            for installation in [first, second] {
                let w = try #require(installation.first { $0.kind == .workflow })
                let value = try store.loadWorkflow(w.slug)
                #expect(value.schema == SchemaURL.workflow)
                #expect(value.maxSteps == 10)
                #expect(value.steps.count == 3)
                for step in value.steps {
                    #expect(installation.contains { $0.kind.rawValue == step.kind.rawValue && $0.slug == step.ref })
                    #expect(step.transitions.allSatisfy { t in value.steps.contains { $0.id == t.to } })
                    switch step.kind {
                    case .agent: #expect(try store.loadAgent(step.ref).schema == SchemaURL.agent)
                    case .command: #expect(try store.loadCommand(step.ref).schema == SchemaURL.command)
                    case .skill: #expect(try store.loadSkill(step.ref).schema == SchemaURL.skill)
                    }
                }
            }
        }
    }

    @Test func isolatedPromptsHaveNoPendingReferences() throws {
        let store = try newStore()
        defer { try? FileManager.default.removeItem(at: store.root) }
        for item in KitCatalog.kits.flatMap(\.items).filter({ $0.kind != .workflow }) {
            let installed = try #require(store.addKitItems([item.id]).first)
            switch item.kind {
            case .agent: #expect(try store.loadAgent(installed.slug).nextSteps.isEmpty)
            case .command: #expect(try store.loadCommand(installed.slug).nextSteps.isEmpty)
            case .skill: #expect(try store.loadSkill(installed.slug).nextSteps.isEmpty)
            case .workflow: break
            }
        }
    }

    private func url(_ item: InstalledKitItem, store: ProjectStore) -> URL {
        switch item.kind {
        case .agent: store.agentURL(item.slug)
        case .command: store.commandURL(item.slug)
        case .skill: store.skillURL(item.slug)
        case .workflow: store.workflowURL(item.slug)
        }
    }

    @Test func twoCompletePortableKits() throws {
        #expect(KitCatalog.kits.count == 2)
        let all = KitCatalog.kits.flatMap(\.items)
        #expect(Set(all.map(\.id)).count == all.count)
        for kit in KitCatalog.kits {
            for kind in KitItemKind.allCases {
                #expect(kit.items.contains { $0.kind == kind })
            }
            for item in kit.items {
                #expect(item.dependencies.allSatisfy { dep in kit.items.contains { $0.id == dep } })
                #expect(!item.prompt.contains("Sources/VibeDeck"))
                #expect(!item.prompt.contains(".swift"))
                #expect(item.prompt.contains("rules_for"))
                #expect(item.prompt.contains("submit_rule_check"))
                #expect(item.prompt.contains("código espaguete"))
                for step in item.steps {
                    #expect(step.transitions.allSatisfy { t in item.steps.contains { $0.id == t.to } })
                }
            }
        }
        #expect(try VDJSON.decoder.decode([CatalogKit].self, from: VDJSON.encode(KitCatalog.kits)).count == 2)
    }
}
