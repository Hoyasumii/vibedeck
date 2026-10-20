import Foundation
import Testing
@testable import VibeDeckCore
@testable import VibeDeckApp

@Suite @MainActor struct ClaudeCollectionTests {
    @Test func collectionMutationsPersistAndUndoIncludingLastRemoval() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "claude-app-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ProjectStore.initialize(at: root)
        let model = ProjectModel(store: store)
        let undo = UndoManager()
        undo.groupsByEvent = false
        let item = try ClaudeItem.make(url: "https://claude.ai/public/artifacts/x", kind: .doc, title: "Meu doc")
        undo.beginUndoGrouping()
        model.mutateProject("Adicionar do Claude", undo: undo) { $0.claude.append(item) }
        undo.endUndoGrouping()
        #expect(try store.loadProject().claude.map(\.id) == [item.id])
        undo.undo()
        #expect(model.project.claude.isEmpty)
        #expect(try store.loadProject().claude.isEmpty)
        undo.redo()
        #expect(try store.loadProject().claude.map(\.id) == [item.id])

        undo.beginUndoGrouping()
        model.mutateProject("Remover da coleção", undo: undo) { $0.claude.removeAll() }
        undo.endUndoGrouping()
        #expect(try store.loadProject().claude.isEmpty)
        // The open page survives last removal and can show its empty state/add action.
        #expect(model.exists(.claudeItems))
        undo.undo()
        #expect(try store.loadProject().claude.map(\.id) == [item.id])
        #expect(model.errorMessage == nil)
    }
}
