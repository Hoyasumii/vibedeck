import Foundation
import Testing
@testable import VibeDeckCore

private func newStore() throws -> ProjectStore {
    let url = FileManager.default.temporaryDirectory.appending(path: "vibedeck-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return try ProjectStore.initialize(at: url)
}

@Suite struct StopGateTests {
    @Test func blocksUntilApprovedCheckAfterChange() throws {
        let store = try newStore()
        let (_, rule) = try store.addRule(Rule(text: "Sem minWidth no root"), toTopic: "Interface")
        _ = try store.updateTopic("interface") { $0.paths = ["Sources/App/**"] }
        let changed = Date.now.addingTimeInterval(-60)

        // Arquivo fora do escopo das regras não precisa de check.
        #expect(try store.unverifiedChanges([("README.md", changed)]).isEmpty)

        let pending = try store.unverifiedChanges([("Sources/App/View.swift", changed)])
        #expect(pending == [UnverifiedChange(file: "Sources/App/View.swift", topics: ["interface"], lastCheckFailed: false)])

        try store.submitCheck(task: "t", files: ["Sources/App/View.swift"], answers: [.init(ruleId: rule.id.uuidString, verdict: .fail)])
        #expect(try store.unverifiedChanges([("Sources/App/View.swift", changed)]).first?.lastCheckFailed == true)

        try store.submitCheck(task: "t", files: ["Sources/App/View.swift"], answers: [.init(ruleId: rule.id.uuidString, verdict: .pass)])
        #expect(try store.unverifiedChanges([("Sources/App/View.swift", changed)]).isEmpty)

        // Alterar o arquivo depois do check volta a exigir um check.
        #expect(try store.unverifiedChanges([("Sources/App/View.swift", .now.addingTimeInterval(60))]).count == 1)
    }

    @Test func checkMustCoverEveryTopicOfTheFile() throws {
        let store = try newStore()
        let (_, global) = try store.addRule(Rule(text: "Textos em pt-BR"), toTopic: "Geral")
        let (_, ui) = try store.addRule(Rule(text: "Sem minWidth"), toTopic: "Interface")
        _ = try store.updateTopic("interface") { $0.paths = ["Sources/App/**"] }
        let changed = Date.now.addingTimeInterval(-60)

        // Um check só dos tópicos globais (sem o arquivo) não cobre o tópico da interface.
        try store.submitCheck(task: "t", files: [], answers: [.init(ruleId: global.id.uuidString, verdict: .pass)])
        #expect(try store.unverifiedChanges([("Sources/App/View.swift", changed)]).first?.topics == ["geral", "interface"])
        #expect(try store.unverifiedChanges([("Package.swift", changed)]).isEmpty)

        try store.submitCheck(task: "t", files: ["Sources/App/View.swift"], answers: [
            .init(ruleId: global.id.uuidString, verdict: .pass), .init(ruleId: ui.id.uuidString, verdict: .pass),
        ])
        #expect(try store.unverifiedChanges([("Sources/App/View.swift", changed)]).isEmpty)
    }

    @Test func workingTreeChangesSinceSessionStart() throws {
        let store = try newStore()
        let git = { (args: [String]) in #expect(Git.run(args, in: store.root).ok) }
        git(["init", "-q"])
        git(["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "init"])
        try Data("a".utf8).write(to: store.root.appending(path: "old.txt"))
        try FileManager.default.setAttributes([.modificationDate: Date.now.addingTimeInterval(-3600)], ofItemAtPath: store.root.appending(path: "old.txt").path)
        try Data("b".utf8).write(to: store.root.appending(path: "new.txt"))
        try store.submitCheck(task: "t", files: [], answers: [])

        let files = store.workingTreeChanges(since: .now.addingTimeInterval(-60)).map(\.file)
        #expect(files.contains("new.txt"))
        #expect(!files.contains("old.txt"))
        #expect(!files.contains { $0.hasPrefix(".vibedeck/checks/") })
        #expect(!files.contains(".vibedeck/AGENTS.md"))
    }

    @Test func installAndUninstallKeepOtherHooks() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "vibedeck-settings-\(UUID().uuidString).json")
        let other: [String: Any] = ["hooks": ["Stop": [["hooks": [["type": "command", "command": "say pronto"]]]]], "model": "opus"]
        try JSONSerialization.data(withJSONObject: other).write(to: url)

        try ClaudeCode.installStopHook(executable: "/usr/local/bin/vibedeck", settings: url)
        try ClaudeCode.installStopHook(executable: "/usr/local/bin/vibedeck", settings: url)
        #expect(try ClaudeCode.hasStopHook(settings: url))
        var settings = try ClaudeCode.readSettings(url)
        #expect(((settings["hooks"] as? [String: Any])?["Stop"] as? [Any])?.count == 2)

        try ClaudeCode.uninstallStopHook(settings: url)
        #expect(try !ClaudeCode.hasStopHook(settings: url))
        settings = try ClaudeCode.readSettings(url)
        #expect(((settings["hooks"] as? [String: Any])?["Stop"] as? [Any])?.count == 1)
        #expect(settings["model"] as? String == "opus")
    }

    @Test func codexHooksFileGetsSessionStart() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "vibedeck-codex-\(UUID().uuidString)/hooks.json")
        try ClaudeCode.installStopHook(executable: "vibedeck", settings: url, sessionStart: HookAgent.codex.needsSessionStart)
        var hooks = try ClaudeCode.readSettings(url)["hooks"] as? [String: Any]
        let command = { (event: String) in
            ((hooks?[event] as? [[String: Any]])?.first?["hooks"] as? [[String: Any]])?.first?["command"] as? String
        }
        #expect(command("Stop") == "'vibedeck' hook stop")
        #expect(command("SessionStart") == "'vibedeck' hook start")
        #expect(try ClaudeCode.hasStopHook(settings: url))

        try ClaudeCode.uninstallStopHook(settings: url)
        hooks = try ClaudeCode.readSettings(url)["hooks"] as? [String: Any]
        #expect(hooks == nil)
        #expect(!HookAgent.claude.needsSessionStart)
    }
}
