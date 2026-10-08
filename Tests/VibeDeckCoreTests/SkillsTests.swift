import Foundation
import Testing
@testable import VibeDeckCore

@Suite struct SkillsTests {
    private func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "vd-skills-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeSkill(_ text: String, named name: String, in dir: URL) throws {
        let folder = dir.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: folder.appending(path: "SKILL.md"))
    }

    @Test func crudAndResolve() throws {
        let store = try ProjectStore.initialize(at: tempDir())
        let (slug, skill) = try store.createSkill(title: "Revisar PR", summary: "Use ao revisar um PR", prompt: "Leia o diff.", author: .ai)
        #expect(slug == "revisar-pr")
        #expect(skill.author == .ai && skill.schema == SchemaURL.skill)
        #expect(try store.resolveSkillSlug(String(skill.id.uuidString.prefix(6))) == slug)
        #expect(try store.resolveSkillSlug("Revisar PR") == slug)
        try store.updateSkill(slug) { $0.model = "haiku" }
        #expect(try store.loadSkill(slug).model == "haiku")
        #expect(try store.listSkills().count == 1)
        try store.deleteSkill(slug)
        #expect(throws: VibeDeckError.skillNotFound(slug)) { try store.loadSkill(slug) }
    }

    @Test func lenientDecodeAndOmitEmpty() throws {
        let store = try ProjectStore.initialize(at: tempDir())
        try Data(#"{"title":"Mínima"}"#.utf8).write(to: store.skillURL("minima"))
        let s = try store.loadSkill("minima")
        #expect(s.prompt == "" && s.summary == nil && s.nextSteps.isEmpty && s.author == .human)
        let text = String(decoding: try VDJSON.encode(s), as: UTF8.self)
        #expect(!text.contains("nextSteps") && !text.contains("tools") && !text.contains("tags"))
    }

    @Test func nextStepsValidate() throws {
        let store = try ProjectStore.initialize(at: tempDir())
        let s = try store.createSkill(title: "Revisar").slug
        let c = try store.createCommand(title: "Commit").slug
        try store.addSkillNextStep(to: s, kind: .command, target: c, note: "commitar")
        try store.addSkillNextStep(to: s, kind: .command, target: c)  // duplicate ignored
        #expect(try store.loadSkill(s).nextSteps == [NextStep(kind: .command, ref: c, note: "commitar")])
        #expect(throws: VibeDeckError.self) { try store.addSkillNextStep(to: s, kind: .skill, target: s) }
        #expect(throws: VibeDeckError.skillNotFound("nao-existe")) { try store.addSkillNextStep(to: s, kind: .skill, target: "nao-existe") }
        // Agents and commands may point to skills.
        let a = try store.createAgent(title: "Autor").slug
        try store.addNextStep(to: a, kind: .skill, target: s)
        try store.addCommandNextStep(to: c, kind: .skill, target: s)
        #expect(try store.loadAgent(a).nextSteps.first == NextStep(kind: .skill, ref: s))
        #expect(try store.loadCommand(c).nextSteps.first?.kind == .skill)
    }

    @Test func flowMixesAgentsCommandsAndSkills() throws {
        let store = try ProjectStore.initialize(at: tempDir())
        let a = try store.createAgent(title: "Autor").slug
        let s = try store.createSkill(title: "Revisar", prompt: "Revise.").slug
        let c = try store.createCommand(title: "Commit").slug
        try store.addNextStep(to: a, kind: .skill, target: s)
        try store.addSkillNextStep(to: s, kind: .command, target: c)
        try store.addCommandNextStep(to: c, kind: .skill, target: s)  // cycle back to the skill
        try store.updateSkill(s) { $0.nextSteps.append(NextStep(kind: .skill, ref: "sumiu")) }

        let flow = try #require(AgentFlow.build(from: a, agents: store.listAgents(), commands: store.listCommands(), skills: store.listSkills()))
        let skill = try #require(flow.next.first?.node)
        #expect(skill.kind == .skill && skill.ref == s && skill.prompt == "Revise.")
        #expect(skill.next[0].node?.kind == .command)
        #expect(skill.next[0].node?.next.first?.warning?.hasPrefix("Ciclo") == true)
        #expect(skill.next[1].warning == "Skill não encontrada: sumiu")

        let json = try AgentFlow.json(kind: .skill, from: s, agents: store.listAgents(), commands: store.listCommands(), skills: store.listSkills())
        #expect(json?.contains("\"kind\" : \"skill\"") == true)
    }

    @Test func parsesClaudeSkillFile() {
        let text = """
        ---
        name: revisar-pr
        description: Use ao revisar um pull request
        allowed-tools: Read, Grep, Bash(gh pr diff:*)
        model: sonnet
        ---

        # Revisar PR

        Leia o diff.
        """
        let p = ClaudeSkillFile.parse(text, fallbackName: "pasta")
        #expect(p.name == "revisar-pr")
        #expect(p.description == "Use ao revisar um pull request")
        #expect(p.tools == ["Read", "Grep", "Bash(gh pr diff:*)"])
        #expect(p.model == "sonnet")
        #expect(p.prompt == "# Revisar PR\n\nLeia o diff.")
        let bare = ClaudeSkillFile.parse("Só as instruções", fallbackName: "pasta")
        #expect(bare.name == "pasta" && bare.prompt == "Só as instruções" && bare.description == nil)
    }

    @Test func importsSkillFolders() throws {
        let store = try ProjectStore.initialize(at: tempDir())
        let project = tempDir(), user = tempDir()
        try writeSkill("---\ndescription: Do projeto\n---\nProjeto", named: "revisar", in: project)
        try writeSkill("---\ndescription: Do usuário\n---\nUsuário", named: "revisar", in: user)
        try writeSkill("---\nname: grafo\ndescription: Gera o grafo\n---\nGrafo", named: "graphify", in: user)
        try FileManager.default.createDirectory(at: user.appending(path: "sem-skill"), withIntermediateDirectories: true)
        try Data("solto".utf8).write(to: user.appending(path: "SKILL.md"))  // not inside a folder

        #expect(try store.importClaudeSkills(from: [project, user]) == ["revisar", "grafo"])
        let s = try store.loadSkill("revisar")
        #expect(s.summary == "Do projeto" && s.prompt == "Projeto" && s.tags == ["claude-code"])  // project wins
        #expect(try store.loadSkill("grafo").summary == "Gera o grafo")
        #expect(try store.importClaudeSkills(from: [project, user]).isEmpty)  // skipped, exists

        try writeSkill("---\ndescription: Nova\n---\nNovo texto", named: "revisar", in: project)
        #expect(try store.importClaudeSkills(from: [project], overwrite: true) == ["revisar"])
        #expect(try store.loadSkill("revisar").prompt == "Novo texto")
    }
}
