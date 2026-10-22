import Foundation
import Testing
@testable import VibeDeckApp

@Suite @MainActor struct KitCatalogAppTests {
    @Test func entireSelectionIsLiveAndHasOneUndoWithRedo() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "vd-kit-app-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try CoreStore.initialize(at: root)
        let original = try store.createAgent(title: "Revisor de manutenção", prompt: "Preservar")
        let model = ProjectModel(store: store)
        let undo = UndoManager()
        undo.beginUndoGrouping()
        #expect(model.addKitItems(["manutencao", "novas-ferramentas"], undo: undo))
        undo.endUndoGrouping()
        #expect(model.agents.count == 3 && model.commands.count == 2 && model.skills.count == 2 && model.workflows.count == 2)
        let slugs = model.agents.map(\.slug)
        let identities = model.workflows.map { $0.value.id }
        undo.undo()
        #expect(model.agents.count == 1 && model.commands.isEmpty && model.skills.isEmpty && model.workflows.isEmpty)
        #expect(try store.listCommands().isEmpty && store.listWorkflows().isEmpty)
        #expect(try store.loadAgent(original.slug).prompt == "Preservar")
        #expect(!undo.canUndo)
        undo.redo()
        #expect(model.agents.map(\.slug) == slugs)
        #expect(model.workflows.map { $0.value.id } == identities)
        #expect(try store.listSkills().count == 2)
        #expect(model.errorMessage == nil)
    }

    @Test func invalidSelectionDoesNotCreateOrRegisterUndo() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "vd-kit-app-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try CoreStore.initialize(at: root)
        let model = ProjectModel(store: store)
        let undo = UndoManager()
        #expect(!model.addKitItems(["manutencao:workflow"], undo: undo))
        #expect(model.agents.isEmpty && model.workflows.isEmpty)
        #expect(model.errorMessage?.contains("dependências") == true)
        #expect(!undo.canUndo)
    }

    @Test func redoPreservesAnExternalItemAtTheSameSlug() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "vd-kit-app-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try CoreStore.initialize(at: root)
        let model = ProjectModel(store: store)
        let undo = UndoManager()
        undo.beginUndoGrouping()
        #expect(model.addKitItems(["manutencao"], undo: undo))
        undo.endUndoGrouping()
        undo.undo()
        let human = try store.createAgent(title: "Revisor de manutenção", prompt: "Item externo")
        undo.redo()
        #expect(try store.loadAgent(human.slug).id == human.agent.id)
        #expect(try store.loadAgent(human.slug).prompt == "Item externo")
        #expect(try store.listCommands().isEmpty)
        #expect(model.errorMessage?.contains("já existe") == true)
    }
}
