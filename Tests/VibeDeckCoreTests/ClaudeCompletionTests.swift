import Foundation
import Testing
@testable import VibeDeckCore

@Suite struct ClaudeCompletionTests {
    @Test func slashTriggersOnlyOnFirstWord() {
        #expect(ClaudeCompletion.trigger(in: "/rev")?.query == "rev")
        #expect(ClaudeCompletion.trigger(in: "/rev now") == nil)
        #expect(ClaudeCompletion.trigger(in: "oi /rev") == nil)
    }

    @Test func mentionTriggersOnLastWord() {
        let t = ClaudeCompletion.trigger(in: "veja @Sources/Ap")
        #expect(t?.kind == .mention)
        #expect(t?.query == "Sources/Ap")
        #expect(ClaudeCompletion.trigger(in: "a@b") == nil)
        #expect(ClaudeCompletion.trigger(in: "@x depois") == nil)
    }

    @Test func rankingPrefersFileNamePrefix() {
        let items = ["Docs/readme.md", "Sources/App.swift", "Sources/Core/Apple.swift"].map { ClaudeSuggestion(kind: .file, name: $0) }
        #expect(ClaudeCompletion.rank(items, query: "app").first?.name == "Sources/App.swift")
        #expect(ClaudeCompletion.rank(items, query: "zzz").isEmpty)
        #expect(ClaudeCompletion.rank(items, query: "srcapp").count == 2)
    }

    @Test func findsCustomCommandsAndSkills() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let commands = root.appending(path: ".claude/commands/git")
        let skill = root.appending(path: ".claude/skills/deploy")
        try FileManager.default.createDirectory(at: commands, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: skill, withIntermediateDirectories: true)
        try "---\ndescription: Faz commit\n---\nbody".write(to: commands.appending(path: "commit.md"), atomically: true, encoding: .utf8)
        try "# Deploy\n".write(to: skill.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root) }

        let found = ClaudeCompletion.commands(root: root, home: root.appending(path: "home"), reported: ["plug:x"])
        let names = found.map(\.name)
        #expect(names.contains("/git:commit"))
        #expect(names.contains("/deploy"))
        #expect(names.contains("/plug:x"))
        #expect(names.contains("/compact"))
        #expect(found.first { $0.name == "/git:commit" }?.detail == "Faz commit")
    }

    @Test func projectFilesSkipDependencies() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appending(path: "node_modules/x"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appending(path: "src"), withIntermediateDirectories: true)
        try "".write(to: root.appending(path: "src/a.swift"), atomically: true, encoding: .utf8)
        try "".write(to: root.appending(path: "node_modules/x/b.js"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root) }

        let files = ClaudeCompletion.projectFiles(root: root)
        #expect(files.contains("src/a.swift"))
        #expect(!files.contains { $0.contains("node_modules") })
    }
}

@Suite struct ShellCommandTests {
    @Test func detectsInteractivePrograms() {
        #expect(ShellCommand.isInteractive("vim README.md"))
        #expect(ShellCommand.isInteractive("sudo top"))
        #expect(ShellCommand.isInteractive("FOO=1 /usr/bin/less x"))
        #expect(ShellCommand.isInteractive("python3"))
        #expect(!ShellCommand.isInteractive("python3 script.py"))
        #expect(ShellCommand.isInteractive("git commit"))
        #expect(!ShellCommand.isInteractive("git commit -m 'x'"))
        #expect(ShellCommand.isInteractive("git rebase -i HEAD~3"))
        #expect(!ShellCommand.isInteractive("ls -la"))
        #expect(!ShellCommand.isInteractive("git status"))
    }
}
