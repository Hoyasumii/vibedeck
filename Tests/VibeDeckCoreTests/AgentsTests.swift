import Foundation
import Testing
@testable import VibeDeckCore

@Suite struct AgentsTests {
    private func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "vd-agents-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func crudAndResolve() throws {
        let store = try ProjectStore.initialize(at: tempDir())
        let (slug, agent) = try store.createAgent(title: "Revisor de código", model: "sonnet", prompt: "Revise.", tags: ["qa"], author: .ai)
        #expect(slug == "revisor-de-codigo")
        #expect(agent.author == .ai)
        #expect(try store.resolveAgentSlug(String(agent.id.uuidString.prefix(6))) == slug)
        #expect(try store.resolveAgentSlug("Revisor de código") == slug)
        try store.updateAgent(slug) { $0.model = "opus" }
        #expect(try store.loadAgent(slug).model == "opus")
        #expect(try store.listAgents().count == 1)
        try store.deleteAgent(slug)
        #expect(throws: VibeDeckError.self) { try store.loadAgent(slug) }
    }

    @Test func lenientDecodeAndOmitEmpty() throws {
        let store = try ProjectStore.initialize(at: tempDir())
        try store.ensureDirectories()
        try Data(#"{"title":"Mínimo"}"#.utf8).write(to: store.agentURL("minimo"))
        let a = try store.loadAgent("minimo")
        #expect(a.prompt == "" && a.tools.isEmpty && a.nextSteps.isEmpty && a.author == .human)
        let text = String(decoding: try VDJSON.encode(a), as: UTF8.self)
        #expect(!text.contains("nextSteps") && !text.contains("tools") && !text.contains("tags"))
    }

    @Test func nextStepsValidateAndFlowDetectsCycles() throws {
        let store = try ProjectStore.initialize(at: tempDir())
        let a = try store.createAgent(title: "A").slug
        let b = try store.createAgent(title: "B").slug
        try store.addNextStep(to: a, target: b, note: "revisar")
        try store.addNextStep(to: a, target: b)  // duplicate ignored
        #expect(try store.loadAgent(a).nextSteps.count == 1)
        #expect(throws: VibeDeckError.self) { try store.addNextStep(to: a, target: a) }
        #expect(throws: VibeDeckError.self) { try store.addNextStep(to: a, target: "nao-existe") }
        try store.addNextStep(to: b, target: a)  // cycle
        let flow = try #require(AgentFlow.build(from: a, agents: store.listAgents()))
        #expect(flow.next.first?.node?.ref == b)
        #expect(flow.next.first?.node?.next.first?.warning?.hasPrefix("Ciclo") == true)
        #expect(throws: VibeDeckError.self) { try store.addNextStep(to: a, kind: .command, target: "deploy") }
        try store.createCommand(title: "Deploy")
        try store.addNextStep(to: a, kind: .command, target: "Deploy")
        #expect(try store.loadAgent(a).nextSteps.last == NextStep(kind: .command, ref: "deploy"))
    }

    @Test func parsesClaudeAgentFile() {
        let text = """
        ---
        name: code-explorer
        description: |
          Analisa features.
          Segunda linha.
        tools: Glob, Grep, Read
        model: sonnet
        color: yellow
        ---

        Você é um analista.
        """
        let p = ClaudeAgentFile.parse(text, fallbackName: "x")
        #expect(p.name == "code-explorer")
        #expect(p.description == "Analisa features.\nSegunda linha.")
        #expect(p.tools == ["Glob", "Grep", "Read"])
        #expect(p.model == "sonnet")
        #expect(p.prompt == "Você é um analista.")
        #expect(ClaudeAgentFile.parse("só prompt", fallbackName: "fb").name == "fb")
    }

    @Test func importsFromDirectory() throws {
        let store = try ProjectStore.initialize(at: tempDir())
        let src = tempDir()
        try Data("---\nname: helper\nmodel: opus\n---\nOlá".utf8).write(to: src.appending(path: "helper.md"))
        #expect(try store.importClaudeAgents(from: [src]) == ["helper"])
        #expect(try store.importClaudeAgents(from: [src]).isEmpty)  // skipped, exists
        let a = try store.loadAgent("helper")
        #expect(a.prompt == "Olá" && a.model == "opus" && a.tags == ["claude-code"])
    }
}
