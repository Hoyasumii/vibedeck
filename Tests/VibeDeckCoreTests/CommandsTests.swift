import Foundation
import Testing
@testable import VibeDeckCore

@Suite struct CommandsTests {
    private func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "vd-commands-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func crudAndResolve() throws {
        let store = try ProjectStore.initialize(at: tempDir())
        let (slug, command) = try store.createCommand(title: "Commit", argumentHint: "<mensagem>", prompt: "Commite: $ARGUMENTS", author: .ai)
        #expect(slug == "commit")
        #expect(command.author == .ai && command.schema == SchemaURL.command)
        #expect(try store.resolveCommandSlug(String(command.id.uuidString.prefix(6))) == slug)
        #expect(try store.resolveCommandSlug("Commit") == slug)
        try store.updateCommand(slug) { $0.model = "haiku" }
        #expect(try store.loadCommand(slug).model == "haiku")
        #expect(try store.listCommands().count == 1)
        try store.deleteCommand(slug)
        #expect(throws: VibeDeckError.commandNotFound(slug)) { try store.loadCommand(slug) }
    }

    @Test func lenientDecodeAndOmitEmpty() throws {
        let store = try ProjectStore.initialize(at: tempDir())
        try Data(#"{"title":"Mínimo"}"#.utf8).write(to: store.commandURL("minimo"))
        let c = try store.loadCommand("minimo")
        #expect(c.prompt == "" && c.argumentHint == nil && c.nextSteps.isEmpty && c.author == .human)
        let text = String(decoding: try VDJSON.encode(c), as: UTF8.self)
        #expect(!text.contains("nextSteps") && !text.contains("tools") && !text.contains("tags") && !text.contains("argumentHint"))
    }

    @Test func nextStepsValidate() throws {
        let store = try ProjectStore.initialize(at: tempDir())
        let c = try store.createCommand(title: "Testar").slug
        let a = try store.createAgent(title: "Revisor").slug
        try store.addCommandNextStep(to: c, target: a, note: "revisar")
        try store.addCommandNextStep(to: c, target: a)  // duplicate ignored
        #expect(try store.loadCommand(c).nextSteps == [NextStep(kind: .agent, ref: a, note: "revisar")])
        #expect(throws: VibeDeckError.self) { try store.addCommandNextStep(to: c, kind: .command, target: c) }
        #expect(throws: VibeDeckError.commandNotFound("nao-existe")) { try store.addCommandNextStep(to: c, kind: .command, target: "nao-existe") }
        // An agent may point to a command with the same slug as itself (different kinds).
        let same = try store.createCommand(title: "Revisor").slug
        try store.addNextStep(to: a, kind: .command, target: same)
        #expect(try store.loadAgent(a).nextSteps.first?.kind == .command)
    }

    @Test func flowMixesAgentsAndCommands() throws {
        let store = try ProjectStore.initialize(at: tempDir())
        let a = try store.createAgent(title: "Autor").slug
        let c = try store.createCommand(title: "Testar", argumentHint: "<alvo>").slug
        let b = try store.createAgent(title: "Revisor").slug
        try store.addNextStep(to: a, kind: .command, target: c)
        try store.addCommandNextStep(to: c, target: b)
        try store.addNextStep(to: b, target: a)  // cycle back to the start
        try store.updateAgent(b) { $0.nextSteps.append(NextStep(kind: .command, ref: "sumiu")) }

        let flow = try #require(AgentFlow.build(from: a, agents: store.listAgents(), commands: store.listCommands()))
        let cmd = try #require(flow.next.first?.node)
        #expect(cmd.kind == .command && cmd.ref == c && cmd.argumentHint == "<alvo>")
        let rev = try #require(cmd.next.first?.node)
        #expect(rev.kind == .agent && rev.ref == b)
        #expect(rev.next[0].warning?.hasPrefix("Ciclo") == true)
        #expect(rev.next[1].warning == "Comando não encontrado: sumiu")

        let fromCommand = try #require(AgentFlow.build(kind: .command, from: c, agents: store.listAgents(), commands: store.listCommands()))
        #expect(fromCommand.next.first?.node?.next.first?.node?.ref == a)
        #expect(try AgentFlow.json(kind: .command, from: c, agents: store.listAgents(), commands: store.listCommands())?.contains("\"kind\" : \"command\"") == true)
    }

    @Test func parsesClaudeCommandFile() {
        let text = """
        ---
        description: Cria um commit
        argument-hint: [mensagem]
        allowed-tools: Bash(git add:*), Bash(git commit:*)
        model: haiku
        ---

        Faça o commit: $ARGUMENTS
        """
        let p = ClaudeCommandFile.parse(text, fallbackName: "commit")
        #expect(p.name == "commit")
        #expect(p.description == "Cria um commit")
        #expect(p.argumentHint == "[mensagem]")
        #expect(p.tools == ["Bash(git add:*)", "Bash(git commit:*)"])
        #expect(p.model == "haiku")
        #expect(p.prompt == "Faça o commit: $ARGUMENTS")
        let bare = ClaudeCommandFile.parse("Só o prompt", fallbackName: "fb")
        #expect(bare.name == "fb" && bare.prompt == "Só o prompt" && bare.description == nil)
    }

    @Test func importsRecursivelyWithNamespaces() throws {
        let store = try ProjectStore.initialize(at: tempDir())
        let src = tempDir()
        try FileManager.default.createDirectory(at: src.appending(path: "git"), withIntermediateDirectories: true)
        try Data("---\nargument-hint: <msg>\n---\nCommit $ARGUMENTS".utf8).write(to: src.appending(path: "git/commit.md"))
        try Data("Revise o PR".utf8).write(to: src.appending(path: "review.md"))
        try Data("ignorado".utf8).write(to: src.appending(path: "notas.txt"))
        #expect(try Set(store.importClaudeCommands(from: [src])) == ["git-commit", "review"])
        #expect(try store.importClaudeCommands(from: [src]).isEmpty)  // skipped, exists
        let c = try store.loadCommand("git-commit")
        #expect(c.title == "git:commit" && c.argumentHint == "<msg>" && c.prompt == "Commit $ARGUMENTS" && c.tags == ["claude-code"])
        #expect(try store.importClaudeCommands(from: [src], overwrite: true).count == 2)
    }
}
