import Foundation
import Testing
@testable import VibeDeckCore

private func tempDir() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "vibedeck-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// A runner that answers by command name instead of spawning a shell, and records what it ran.
private final class StubRunner: @unchecked Sendable {
    private let lock = NSLock()
    private var _ran: [String] = []
    private var _files: [String] = []
    var ran: [String] { lock.withLock { _ran } }
    var files: [String] { lock.withLock { _files } }

    var runner: RuleTestRunner {
        RuleTestRunner { [self] command, context in
            lock.withLock { _ran.append(command); _files = context.files }
            let code: Int32 = switch command {
            case "ok": 0
            case "skip": 77
            default: 1
            }
            return RuleTestOutcome(exitCode: code, output: "saída de \(command)")
        }
    }
}

@Suite struct RuleTestsTests {
    @Test func hashAndState() {
        var rule = Rule(text: "Sem minWidth", details: "no root")
        #expect(rule.testState == .none)
        #expect(rule.contentHash.count == 16)
        rule.test = RuleTest(mode: .script, command: "ok", ruleHash: rule.contentHash)
        #expect(rule.testState == .script)
        #expect(rule.scriptCommand == "ok")
        rule.severity = .should
        #expect(rule.testState == .script, "severidade não muda o que a regra pede")
        rule.details = "no root da janela"
        #expect(rule.testState == .stale)
        #expect(rule.scriptCommand == nil)
        rule.test = RuleTest(mode: .manual, reason: "subjetiva", ruleHash: rule.contentHash)
        #expect(rule.testState == .manual)
        #expect(rule.testState.needsAgent)
    }

    @Test func ruleRoundTripKeepsTestAndOldFilesStillDecode() throws {
        var rule = Rule(text: "x")
        rule.test = RuleTest(mode: .script, command: ".vibedeck/tests/t/ab.sh", reason: "r", ruleHash: rule.contentHash, now: Date(timeIntervalSince1970: 1_700_000_000))
        let back = try VDJSON.decoder.decode(Rule.self, from: VDJSON.encode(rule))
        #expect(back.test == rule.test)

        let handWritten = #"{"text": "à mão", "test": {"command": "./check.sh"}}"#
        let lenient = try VDJSON.decoder.decode(Rule.self, from: Data(handWritten.utf8))
        #expect(lenient.test?.mode == .script)
        #expect(lenient.testState == .stale, "sem ruleHash não decide sozinho até ser registrado")

        let legacy = #"{"text": "antiga"}"#
        #expect(try VDJSON.decoder.decode(Rule.self, from: Data(legacy.utf8)).test == nil)
        let untested = String(decoding: try VDJSON.encode(Rule(text: "y")), as: UTF8.self)
        #expect(!untested.contains("\"test\""))

        let oldResult = #"{"topic": "t", "ruleId": "\#(UUID().uuidString)", "verdict": "pass"}"#
        #expect(try VDJSON.decoder.decode(RuleResult.self, from: Data(oldResult.utf8)).source == .agent)
    }

    @Test func outcomeFromExitCode() {
        #expect(RuleTestOutcome(exitCode: 0, output: "").verdict == .pass)
        #expect(RuleTestOutcome(exitCode: 77, output: "").verdict == .na)
        #expect(RuleTestOutcome(exitCode: 2, output: "").verdict == .fail)
    }

    @Test func setAndClearRuleTest() throws {
        let store = try ProjectStore.initialize(at: tempDir())
        let (slug, rule) = try store.addRule(Rule(text: "A"), toTopic: "Geral")
        #expect(throws: VibeDeckError.invalidRuleTest("Informe o comando do script.")) {
            try store.setRuleTest(rule.id.uuidString, mode: .script, command: "  ")
        }
        let script = store.root.appending(path: RuleTestPrompt.scriptPath(topic: slug, rule: rule))
        try FileManager.default.createDirectory(at: script.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("exit 0".utf8).write(to: script)

        let set = try store.setRuleTest(String(rule.id.uuidString.prefix(6)), mode: .script, command: RuleTestPrompt.scriptPath(topic: slug, rule: rule))
        #expect(set.testState == .script)
        #expect(try store.loadTopic(slug).rules[0].test?.ruleHash == rule.contentHash)

        try store.clearRuleTest(rule.id.uuidString)
        #expect(try store.loadTopic(slug).rules[0].test == nil)
        #expect(!FileManager.default.fileExists(atPath: script.path), "script gerado sai junto com o teste")
    }

    @Test func deleteRuleRemovesGeneratedScriptOnly() throws {
        let store = try ProjectStore.initialize(at: tempDir())
        let (slug, generated) = try store.addRule(Rule(text: "A"), toTopic: "Geral")
        let (_, outside) = try store.addRule(Rule(text: "B"), toTopic: "Geral")
        let script = store.root.appending(path: RuleTestPrompt.scriptPath(topic: slug, rule: generated))
        try FileManager.default.createDirectory(at: script.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: script)
        let own = store.root.appending(path: "check.sh")
        try Data().write(to: own)
        try store.setRuleTest(generated.id.uuidString, mode: .script, command: RuleTestPrompt.scriptPath(topic: slug, rule: generated))
        try store.setRuleTest(outside.id.uuidString, mode: .script, command: "check.sh")

        try store.deleteRule(generated.id.uuidString)
        try store.deleteRule(outside.id.uuidString)
        #expect(!FileManager.default.fileExists(atPath: script.path))
        #expect(FileManager.default.fileExists(atPath: own.path), "scripts fora de .vibedeck/tests são do usuário")
    }

    @Test func submitCheckRunsScriptsAndAsksOnlyManualRules() throws {
        let store = try ProjectStore.initialize(at: tempDir())
        let (_, passing) = try store.addRule(Rule(text: "passa"), toTopic: "Geral")
        let (_, skipped) = try store.addRule(Rule(text: "não se aplica"), toTopic: "Geral")
        let (_, manual) = try store.addRule(Rule(text: "subjetiva"), toTopic: "Geral")
        let (_, untested) = try store.addRule(Rule(text: "sem teste", severity: .should), toTopic: "Geral")
        try store.setRuleTest(passing.id.uuidString, mode: .script, command: "ok")
        try store.setRuleTest(skipped.id.uuidString, mode: .script, command: "skip")
        try store.setRuleTest(manual.id.uuidString, mode: .manual, reason: "julgamento")
        let stub = StubRunner()

        #expect(throws: VibeDeckError.self) {
            try store.submitCheck(task: "x", files: [], answers: [RuleAnswer(ruleId: manual.id.uuidString, verdict: .pass)], runner: stub.runner)
        }
        #expect(stub.ran.isEmpty, "check incompleto não roda scripts")

        let check = try store.submitCheck(
            task: "x", files: ["Sources/A.swift"],
            answers: [
                RuleAnswer(ruleId: manual.id.uuidString, verdict: .pass, note: "li"),
                RuleAnswer(ruleId: untested.id.uuidString, verdict: .fail),
                RuleAnswer(ruleId: passing.id.uuidString, verdict: .fail, note: "o agente não decide"),
            ],
            runner: stub.runner
        )
        #expect(stub.ran == ["ok", "skip"])
        #expect(stub.files == ["Sources/A.swift"])
        #expect(check.passed)
        #expect(check.warnings == ["sem teste"])
        let byRule = Dictionary(uniqueKeysWithValues: check.results.map { ($0.ruleId, $0) })
        #expect(byRule[passing.id]?.verdict == .pass)
        #expect(byRule[passing.id]?.source == .script)
        #expect(byRule[passing.id]?.exitCode == 0)
        #expect(byRule[skipped.id]?.verdict == .na)
        #expect(byRule[manual.id]?.source == .agent)
        #expect(check.results.count == 4)
    }

    @Test func failingScriptBlocksMustAndWarnsShould() throws {
        let store = try ProjectStore.initialize(at: tempDir())
        let (_, must) = try store.addRule(Rule(text: "obrigatória"), toTopic: "Geral")
        let (_, should) = try store.addRule(Rule(text: "recomendada", severity: .should), toTopic: "Geral")
        try store.setRuleTest(must.id.uuidString, mode: .script, command: "boom")
        try store.setRuleTest(should.id.uuidString, mode: .script, command: "boom")

        let check = try store.submitCheck(task: "x", files: [], answers: [], runner: StubRunner().runner)
        #expect(!check.passed)
        #expect(check.failures == ["obrigatória"])
        #expect(check.warnings == ["recomendada"])
        #expect(check.results.first { $0.ruleId == must.id }?.note?.contains("saída de boom") == true)
    }

    @Test func staleTestFallsBackToAgentWithWarning() throws {
        let store = try ProjectStore.initialize(at: tempDir())
        let (_, rule) = try store.addRule(Rule(text: "antes"), toTopic: "Geral")
        try store.setRuleTest(rule.id.uuidString, mode: .script, command: "ok")
        try store.updateRule(rule.id.uuidString) { $0.text = "depois" }
        let stub = StubRunner()

        #expect(throws: VibeDeckError.self) { try store.submitCheck(task: "x", files: [], answers: [], runner: stub.runner) }
        let check = try store.submitCheck(task: "x", files: [], answers: [RuleAnswer(ruleId: rule.id.uuidString, verdict: .pass)], runner: stub.runner)
        #expect(stub.ran.isEmpty)
        #expect(check.passed)
        #expect(check.warnings == ["Teste desatualizado (a regra mudou): depois"])
    }

    @Test func runRuleTestsScopesToTopics() throws {
        let store = try ProjectStore.initialize(at: tempDir())
        let (_, global) = try store.addRule(Rule(text: "g"), toTopic: "Geral")
        let ui = try store.createTopic(title: "UI", paths: ["Sources/App/**"]).slug
        let (_, scoped) = try store.addRule(Rule(text: "u"), toTopic: ui)
        try store.setRuleTest(global.id.uuidString, mode: .script, command: "ok")
        try store.setRuleTest(scoped.id.uuidString, mode: .script, command: "boom")

        let stub = StubRunner()
        #expect(try store.runRuleTests(topics: [ui], onlyTopics: true, runner: stub.runner).map(\.rule.id) == [scoped.id])
        #expect(try store.runRuleTests(files: ["README.md"], runner: stub.runner).map(\.rule.id) == [global.id])
        let both = try store.runRuleTests(files: ["Sources/App/X.swift"], runner: stub.runner)
        #expect(Set(both.map(\.rule.id)) == [global.id, scoped.id])
        #expect(both.first { $0.rule.id == scoped.id }?.outcome.verdict == .fail)
    }

    @Test func liveRunnerUsesExitCodesAndEnvironment() throws {
        let dir = try tempDir()
        let context = RuleTestRunner.Context(root: dir, files: ["a.swift", "b.swift"], ruleId: UUID())
        let live = RuleTestRunner.live
        #expect(live.run("exit 0", context).verdict == .pass)
        #expect(live.run("exit 77", context).verdict == .na)
        let fail = live.run("echo quebrou; exit 3", context)
        #expect(fail.verdict == .fail)
        #expect(fail.exitCode == 3)
        #expect(fail.output == "quebrou")
        #expect(live.run(#"printf '%s' "$VIBEDECK_FILES" | wc -l | tr -d ' '"#, context).output == "1")
        #expect(live.run("pwd", context).output.hasSuffix(dir.lastPathComponent))
    }

    @Test func shellRunnerTimesOut() {
        let result = ShellRunner.run("sleep 5", in: FileManager.default.temporaryDirectory, timeout: 0.5)
        #expect(result.status == ShellRunner.timedOutStatus)
        #expect(result.output.contains("Tempo esgotado"))
    }

    @Test func promptListsOnlyPendingRules() throws {
        var topic = RuleTopic(title: "Geral")
        var done = Rule(text: "já testada")
        done.test = RuleTest(mode: .script, command: "ok", ruleHash: done.contentHash)
        var stale = Rule(text: "mudou")
        stale.test = RuleTest(mode: .script, command: "velho.sh", ruleHash: "x")
        topic.rules = [done, stale, Rule(text: "nova", details: "como verificar")]

        #expect(RuleTestPrompt.pending(topic).map(\.text) == ["mudou", "nova"])
        let prompt = RuleTestPrompt.generate(slug: "geral", topic: topic, onlyPending: true)
        #expect(!prompt.contains("já testada"))
        #expect(prompt.contains("mudou") && prompt.contains("velho.sh"))
        #expect(prompt.contains("> como verificar"))
        #expect(prompt.contains(".vibedeck/tests/geral/"))
        #expect(prompt.contains("set_rule_test"))
        #expect(RuleTestPrompt.generate(slug: "geral", topic: topic, onlyPending: false).contains("já testada"))
    }

    @Test func selectionPicksMissingStaleOrAll() {
        var topic = RuleTopic(title: "Geral")
        var done = Rule(text: "já testada")
        done.test = RuleTest(mode: .script, command: "ok", ruleHash: done.contentHash)
        var stale = Rule(text: "mudou")
        stale.test = RuleTest(mode: .script, command: "velho.sh", ruleHash: "x")
        var manual = Rule(text: "subjetiva")
        manual.test = RuleTest(mode: .manual, reason: "julgamento", ruleHash: manual.contentHash)
        topic.rules = [done, stale, Rule(text: "nova"), manual]

        #expect(RuleTestPrompt.rules(topic, .missing).map(\.text) == ["nova"])
        #expect(RuleTestPrompt.rules(topic, .stale).map(\.text) == ["mudou"])
        #expect(RuleTestPrompt.rules(topic, .pending).map(\.text) == ["mudou", "nova"])
        #expect(RuleTestPrompt.rules(topic, .all).count == 4)
    }

    @Test func headlessPromptRegistersThroughCLI() {
        var topic = RuleTopic(title: "Geral")
        topic.rules = [Rule(text: "nova")]
        let prompt = RuleTestPrompt.generate(slug: "geral", topic: topic, selection: .missing, headless: "/opt/bin/vibedeck")
        #expect(prompt.contains("`/opt/bin/vibedeck rules set-test <id> --command"))
        #expect(prompt.contains("--manual --reason"))
        #expect(!prompt.contains("set_rule_test"))
        #expect(prompt.contains("segundo plano"))
        #expect(!prompt.contains("avise-me"))
    }
}
