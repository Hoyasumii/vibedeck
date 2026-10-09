import Foundation
import Testing
import VibeDeckCore
@testable import VibeDeckApp

@Suite(.serialized) @MainActor struct DocGenerateAppTests {
    private func fixture() throws -> ProjectModel {
        ProjectModel(store: try ProjectStore.initialize(at: FileManager.default.temporaryDirectory.appending(path: "doc-app-\(UUID())")))
    }
    private func wait(_ runner: DocGenerateRunner) async throws {
        for _ in 0..<300 {
            if !runner.isRunning { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Generation did not finish")
    }

    @Test func proposalEditingAndCancellationNeverWrite() async throws {
        let model = try fixture()
        defer { try? FileManager.default.removeItem(at: model.store.root) }
        let runner = model.docGenerator
        #expect(runner === ProjectModel(store: model.store).docGenerator)
        var calls = 0
        runner.start(store: model.store, provider: .codex, available: { _ in true }) { _, _ in
            calls += 1
            runner.start(store: model.store, provider: .claude, available: { _ in true }) { _, _ in
                Issue.record("Concurrent generation"); return Data()
            }
            return Data(#"{"documents":[{"title":"Rodar","content":"Fonte: Package.swift"}]}"#.utf8)
        }
        try await wait(runner)
        guard case .ready(var proposal) = runner.state else { Issue.record("No proposal"); return }
        #expect(calls == 1)
        proposal[0].title = "Editado"
        proposal[0].content = "Editado no rascunho"
        proposal.removeAll()
        #expect(try model.store.listDocs().isEmpty)
        runner.cancel()
        #expect(runner.state == .idle)
        #expect(try model.store.listDocs().isEmpty)
        var started = false
        runner.start(store: model.store, provider: .codex, available: { _ in true }) { _, _ in
            started = true
            try await Task.sleep(for: .seconds(30))
            return Data(#"{"documents":[]}"#.utf8)
        }
        while !started { await Task.yield() }
        runner.cancel()
        await Task.yield()
        #expect(try model.store.listDocs().isEmpty)
        #expect(runner.state == .idle)
    }

    @Test func invalidAnswerAndMissingProviderCreateNothing() async throws {
        let model = try fixture()
        defer { try? FileManager.default.removeItem(at: model.store.root) }
        let runner = model.docGenerator
        runner.start(store: model.store, provider: .codex, available: { _ in false }) { _, _ in
            Issue.record("Unavailable provider called"); return Data()
        }
        guard case .failed = runner.state else { Issue.record("Expected failure"); return }
        runner.cancel()
        var calls = 0
        runner.start(store: model.store, provider: .codex, available: { _ in true }) { _, _ in
            calls += 1; return Data("invalid".utf8)
        }
        try await wait(runner)
        #expect(calls == 2)
        guard case .failed(let message) = runner.state else { Issue.record("Expected invalid answer"); return }
        #expect(message.contains("Nenhum documento foi criado"))
        #expect(try model.store.listDocs().isEmpty)
        runner.cancel()
    }

    @Test func timeoutShowsErrorWithoutCreatingDocs() async throws {
        let model = try fixture()
        defer { try? FileManager.default.removeItem(at: model.store.root) }
        let runner = model.docGenerator
        var calls = 0
        runner.start(store: model.store, provider: .codex, available: { _ in true }) { _, _ in
            calls += 1
            throw VibeDeckError.discoverTimedOut
        }
        try await wait(runner)
        guard case .failed(let message) = runner.state else { Issue.record("Expected timeout"); return }
        #expect(message == VibeDeckError.discoverTimedOut.localizedDescription)
        #expect(calls == 1)
        #expect(try model.store.listDocs().isEmpty)
        runner.cancel()
    }

    @Test func acceptingBatchUpdatesListAndIsOneUndoWithRedo() throws {
        let model = try fixture()
        defer { try? FileManager.default.removeItem(at: model.store.root) }
        let original = try model.store.createDoc(title: "Rodar", body: "Original")
        let documents: [DocGenerate.Document] = [.init(title: "Rodar", content: "Editado"), .init(title: "Dependências", content: "Package.swift:1")]
        let undo = UndoManager()
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        #expect(model.acceptGeneratedDocs(documents, undo: undo))
        undo.endUndoGrouping()
        #expect(model.docs.count == 3)
        let created = model.docs.filter { $0.slug != original }
        #expect(created.count == 2)
        for doc in created { #expect(try model.store.readDoc(doc.slug).contains("author: ai")) }
        undo.undo()
        #expect(model.docs.map(\.slug) == [original])
        #expect(!undo.canUndo)
        undo.redo()
        #expect(model.docs.count == 3)
        #expect(try model.store.readDoc(original) == "# Rodar\n\nOriginal")
    }

    @Test func selectedAcceptanceAndInvalidEdits() throws {
        let model = try fixture()
        defer { try? FileManager.default.removeItem(at: model.store.root) }
        #expect(!model.acceptGeneratedDocs([.init(title: " ", content: "x")], undo: nil))
        #expect(try model.store.listDocs().isEmpty)
        #expect(model.acceptGeneratedDocs([.init(title: "Selecionado", content: "Novo conteúdo")], undo: nil))
        #expect(model.docs.map(\.title) == ["Selecionado"])
    }
}
