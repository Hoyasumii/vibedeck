import Foundation
import Testing
import VibeDeckCore
@testable import VibeDeckApp

@Suite(.serialized) @MainActor struct GraphRunnerTests {
    private let emptySemantic: JSONValue = .object(["nodes": .array([]), "links": .array([])])
    private var fixtureGraph: JSONValue { .object(["nodes": .array([.object(["id": .string("a"), "label": .string("A")])]), "links": .array([])]) }
    private func root() throws -> URL {
        try ProjectStore.initialize(at: FileManager.default.temporaryDirectory.appending(path: "graph-runner-\(UUID())")).root
    }
    private func writeGraph(_ root: URL) throws {
        try AtomicFile.write(VDJSON.encode(fixtureGraph), to: root.appending(path: "graphify-out/graph.json"))
    }
    private func wait(_ runner: GraphRunner) async throws {
        for _ in 0..<200 {
            if runner.state != .running { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Graph runner did not finish")
    }

    @Test func sharedRunnerPreventsConcurrentWorkAndPublishesCompletePair() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeGraph(root)
        try AtomicFile.write(Data("old HTML".utf8), to: root.appending(path: "graphify-out/graph.html"))
        let runner = GraphRunner.shared(root: root)
        #expect(runner === GraphRunner.shared(root: root.appending(path: ".")))
        #expect(ProjectModel(store: ProjectStore(root: root)).graphRunner === runner)
        var analyses = 0
        runner.start(root: root, provider: .codex, available: { _ in true }, extract: { _ in }, analyze: { _, stage, provider in
            analyses += 1
            #expect(stage != root)
            #expect(provider == .codex)
            let previousHTML = try String(contentsOf: root.appending(path: "graphify-out/graph.html"), encoding: .utf8)
            #expect(previousHTML == "old HTML")
            runner.start(root: root, provider: .claude, available: { _ in true }, extract: { _ in Issue.record("Concurrent extraction") })
            return emptySemantic
        })
        try await wait(runner)
        #expect(runner.state == .idle)
        #expect(runner.generation == 1)
        #expect(analyses == 1)
        #expect(try ProjectGraph.load(root: root).summary["provider"]?.string == "codex")
        #expect(try String(contentsOf: root.appending(path: "graphify-out/graph.html"), encoding: .utf8).contains("vibedeck-graph-renderer"))
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).allSatisfy { !$0.hasPrefix(".graphify-staging-") })
    }

    @Test func failureAndCancellationPreserveOldArtifacts() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeGraph(root)
        let json = try Data(contentsOf: root.appending(path: "graphify-out/graph.json"))
        try AtomicFile.write(Data("old HTML".utf8), to: root.appending(path: "graphify-out/graph.html"))
        let runner = GraphRunner.shared(root: root)
        runner.start(root: root, provider: .codex, available: { _ in true }, extract: { stage in
            try AtomicFile.write(Data("invalid JSON".utf8), to: stage.appending(path: "graphify-out/graph.json"))
        }, analyze: { _, _, _ in Issue.record("Invalid graph reached semantic analysis"); return emptySemantic })
        try await wait(runner)
        guard case .failed = runner.state else { Issue.record("Invalid graph must fail"); return }
        #expect(runner.generation == 0)
        runner.start(root: root, provider: .codex, available: { _ in true }, extract: { _ in }, analyze: { _, _, _ in
            runner.cancel(); try Task.checkCancellation(); return emptySemantic
        })
        try await wait(runner)
        #expect(runner.state == .idle)
        #expect(runner.generation == 0)
        #expect(try Data(contentsOf: root.appending(path: "graphify-out/graph.json")) == json)
        #expect(try String(contentsOf: root.appending(path: "graphify-out/graph.html"), encoding: .utf8) == "old HTML")
        runner.start(root: root, provider: .codex, available: { _ in false })
        guard case .failed(let message) = runner.state else { Issue.record("Missing provider must fail"); return }
        #expect(message.contains("não está disponível"))
    }

    @Test func documentDistinguishesStatesAndIgnoresUntrustedHTML() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(await GraphDocument.load(root: root) == .missing)
        let json = root.appending(path: "graphify-out/graph.json")
        try AtomicFile.write(Data("{}".utf8), to: json)
        guard case .incompatible = await GraphDocument.load(root: root) else { Issue.record("Expected incompatible"); return }
        try AtomicFile.write(Data("bad".utf8), to: json)
        guard case .invalid = await GraphDocument.load(root: root) else { Issue.record("Expected invalid"); return }
        try AtomicFile.write(Data("{\"nodes\":[],\"links\":[]}".utf8), to: json)
        #expect(await GraphDocument.load(root: root) == .empty)
        try writeGraph(root)
        try AtomicFile.write(Data("<script>untrusted()</script>".utf8), to: root.appending(path: "graphify-out/graph.html"))
        guard case .ready(let file, let summary) = await GraphDocument.load(root: root) else { Issue.record("Expected ready"); return }
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        #expect(!summary.contains("1970"))
        #expect(summary.contains("não registrada"))
        #expect(try !String(contentsOf: file, encoding: .utf8).contains("untrusted()"))
        #expect(GraphWebView.Coordinator.permits(file, file: file, readAccess: file.deletingLastPathComponent()))
        #expect(!GraphWebView.Coordinator.permits(URL(fileURLWithPath: "/etc/passwd"), file: file, readAccess: file.deletingLastPathComponent()))
        #expect(!GraphWebView.Coordinator.permits(URL(string: "https://example.com")!, file: file, readAccess: file.deletingLastPathComponent()))
    }
}
