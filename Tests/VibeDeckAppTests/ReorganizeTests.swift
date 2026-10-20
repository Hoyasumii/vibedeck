import Foundation
import Testing
import VibeDeckCore
@testable import VibeDeckApp

@Suite(.serialized) @MainActor struct ReorganizeAppTests {
    private func fixture() throws -> ProjectModel {
        ProjectModel(store: try ProjectStore.initialize(at: FileManager.default.temporaryDirectory.appending(path: "reorganize-app-\(UUID())")))
    }
    private func wait(_ runner: ReorganizeRunner) async throws {
        for _ in 0..<300 {
            if !runner.isRunning { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Reorganização não terminou")
    }
    @Test func readOnlySharedRunnerInvalidJSONTimeoutAndCancellation() async throws {
        let model = try fixture(); defer { try? FileManager.default.removeItem(at: model.store.root) }
        let runner = ReorganizeRunner.shared(root: model.store.root)
        #expect(runner === ReorganizeRunner.shared(root: model.store.root.appending(path: ".")))
        let before = try model.store.reorganizeFingerprint()
        var calls = 0
        runner.start(store: model.store, provider: .codex, available: { _ in true }) { _, _ in
            calls += 1
            runner.start(store: model.store, provider: .claude, available: { _ in true }) { _, _ in
                Issue.record("Chamada concorrente"); return Data()
            }
            return Data("invalid".utf8)
        }
        try await wait(runner)
        #expect(calls == 2)
        if case .failed(let message) = runner.state { #expect(message.contains("Nenhum arquivo")) }
        else { Issue.record("Erro esperado") }
        #expect(try model.store.reorganizeFingerprint() == before)
        runner.cancel()
        runner.start(store: model.store, provider: .codex, available: { _ in true }) { _, _ in throw VibeDeckError.discoverTimedOut }
        try await wait(runner)
        if case .failed(let message) = runner.state { #expect(message == VibeDeckError.discoverTimedOut.localizedDescription) }
        else { Issue.record("Timeout esperado") }
        runner.cancel()
        var started = false
        runner.start(store: model.store, provider: .codex, available: { _ in true }) { _, _ in
            started = true; try await Task.sleep(for: .seconds(30)); return Data("{\"actions\":[]}".utf8)
        }
        while !started { await Task.yield() }
        runner.cancel()
        await Task.yield()
        #expect(runner.state == .idle)
        #expect(try model.store.reorganizeFingerprint() == before)
    }
    @Test func projectChangeDiscardsAnswerWithoutRetry() async throws {
        let model = try fixture(); defer { try? FileManager.default.removeItem(at: model.store.root) }
        let runner = ReorganizeRunner.shared(root: model.store.root)
        var calls = 0
        runner.start(store: model.store, provider: .codex, available: { _ in true }) { _, _ in
            calls += 1
            _ = try model.store.createDoc(title: "Mudança externa")
            return Data("{\"actions\":[]}".utf8)
        }
        try await wait(runner)
        #expect(calls == 1)
        if case .failed(let message) = runner.state { #expect(message.contains("projeto mudou")) }
        else { Issue.record("Proposta desatualizada deveria ser descartada") }
        runner.cancel()
    }
    @Test func acceptanceUpdatesListsWithOneUndoAndRedo() throws {
        let model = try fixture(); defer { try? FileManager.default.removeItem(at: model.store.root) }
        let doc = try model.store.createDoc(title: "Doc")
        let move = ReorganizeDiscover.Action(kind: .move, item: .init(.docs, doc), reason: "Agrupar Doc", destination: "grupo")
        let flow = ReorganizeDiscover.Action(kind: .flow, item: .init(.docs, doc), reason: "Melhorar fluxo", title: "Melhoria", content: "Proposta")
        let proposal = try ReorganizeDiscover.parse(VDJSON.encode(ReorganizeDiscover.Answer(actions: [move, flow])), store: model.store, fingerprint: model.store.reorganizeFingerprint())
        let undo = UndoManager(); undo.groupsByEvent = false; undo.beginUndoGrouping()
        #expect(model.acceptReorganization(proposal, acceptance: .init(selected: proposal.actions.map(\.id)), undo: undo))
        undo.endUndoGrouping()
        #expect(model.docs.map(\.slug) == ["grupo/" + doc])
        #expect(model.ideas.count == 1)
        #expect(model.ideas.first?.value.author == .ai)
        undo.undo()
        #expect(model.docs.map(\.slug) == [doc])
        #expect(model.ideas.isEmpty)
        #expect(!undo.canUndo)
        undo.redo()
        #expect(model.docs.map(\.slug) == ["grupo/" + doc])
        #expect(model.ideas.count == 1)
    }
}
