import Foundation
import SwiftUI
import Testing
@testable import VibeDeckCore
@testable import VibeDeckApp

@Suite @MainActor struct GroupMoveTests {
    @Test func restoringDeletedGroupLogsUndoAndPreservesContents() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "restore-group-\(UUID())")
        let store = try ProjectStore.initialize(at: root)
        let logs = LogStore(dir: root.appending(path: "test-logs"))
        defer { try? FileManager.default.removeItem(at: root) }
        let (_, idea) = try store.createIdea(title: "Ideia privada", reference: "a/x")
        let original = try Data(contentsOf: store.ideaURL("a/x"))
        let model = ProjectModel(store: store)
        let undo = UndoManager()
        undo.groupsByEvent = false
        VDLog.$testStore.withValue(logs) {
            VDLog.withAction(control: "groups.delete", label: "Apagar grupo", project: root, id: "restore-group") {
                undo.beginUndoGrouping()
                model.deleteDirectoryGroup(.ideas, path: "a", confirmed: true, undo: undo)
                undo.endUndoGrouping()
                undo.undo()
            }
        }
        #expect(model.errorMessage == nil)
        #expect(try store.loadIdea("a/x").id == idea.id)
        #expect(try Data(contentsOf: store.ideaURL("a/x")) == original)
        VDLog.flush()
        let restored = try #require(logs.entries(LogFilter(action: "restore-group")).first { $0.event == "store.group_restored" })
        #expect(restored.project == root.path)
        #expect(restored.context["path"] == "a" && restored.context["undo"] == "Apagar grupo")
        #expect(!String(decoding: try Data(contentsOf: logs.fileURL(for: .now)), as: UTF8.self).contains(idea.title))
    }

    @Test func oneUndoMovesDiskAndKeepsSelectionMapping() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "app-groups-\(UUID())")
        let store = try ProjectStore.initialize(at: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let (_, idea) = try store.createIdea(title: "Ideia", reference: "a/x")
        let model = ProjectModel(store: store)
        let undo = UndoManager()
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        model.moveDirectoryGroup(.ideas, from: "a", to: "b", undo: undo)
        undo.endUndoGrouping()
        #expect(model.errorMessage == nil)
        #expect(try store.loadIdea("b/x").id == idea.id)
        #expect(model.latestPathMoves[.idea("a/x")] == .idea("b/x"))
        undo.undo()
        #expect(try store.loadIdea("a/x").id == idea.id)
        #expect(model.latestPathMoves[.idea("b/x")] == .idea("a/x"))
        #expect(!undo.canUndo)
        undo.redo()
        #expect(try store.loadIdea("b/x").id == idea.id)
    }

    @Test func externalRenameTracksIDsAndDocUndoManager() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "app-groups-\(UUID())")
        let store = try ProjectStore.initialize(at: root)
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try store.createIdea(title: "Ideia", reference: "a/x")
        _ = try store.createDoc(title: "Doc", reference: "a/doc")
        let model = ProjectModel(store: store)
        let manager = model.undoManager(forDoc: "a/doc")
        let viewID = model.contentIdentity(for: .doc("a/doc"))
        model.saveDoc("a/doc", text: "# Doc editado")
        #expect(model.contentIdentity(for: .doc("a/doc")) == viewID)
        try store.moveItemDirectory(.ideas, from: "a", to: "b")
        model.reloadIdeas()
        #expect(model.latestPathMoves[.idea("a/x")] == .idea("b/x"))
        try store.moveItemDirectory(.docs, from: "a", to: "b")
        model.reloadDocs()
        #expect(model.latestPathMoves[.doc("a/doc")] == .doc("b/doc"))
        #expect(model.undoManager(forDoc: "b/doc") === manager)
        #expect(model.contentIdentity(for: .doc("b/doc")) == viewID)
    }
}
