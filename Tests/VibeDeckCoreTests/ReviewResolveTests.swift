import Foundation
import Testing
@testable import VibeDeckCore

private func newStore() throws -> ProjectStore {
    let url = FileManager.default.temporaryDirectory.appending(path: "vibedeck-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return try ProjectStore.initialize(at: url)
}

private func data(_ json: String) -> Data { Data(json.utf8) }

@Suite struct ReviewResolveTests {
    @Test func groupSendsOnlyOpenAndInProgress() {
        let items = [ReviewStatus.open, .inProgress, .done, .wontfix].map { ReviewItem(kind: "fix", title: $0.rawValue, status: $0) }
        let eligible = ReviewResolve.eligible(items)
        #expect(eligible.map(\.title) == ["open", "in_progress"])
        let prompts = eligible.map { ReviewResolve.planPrompt(item: $0, kind: "Corrigir") }.joined()
        #expect(prompts.contains("Título: open") && prompts.contains("Título: in_progress"))
        #expect(!prompts.contains("Título: done") && !prompts.contains("Título: wontfix"))
    }

    @Test func planPhaseIsReadOnly() {
        #expect(ReviewResolve.planTools == ["Read", "Grep", "Glob"])
        let args = ReviewDiscover.arguments()
        #expect(args[args.firstIndex(of: "--allowedTools")! + 1] == "Read,Grep,Glob")
        #expect(!args.joined(separator: " ").contains("Edit") && !args.joined(separator: " ").contains("Bash"))
    }

    @Test func parsesValidPlanAndQuestions() throws {
        let plan = try ReviewResolve.parse(data(#"{"questions":[],"summary":" Ajustar ","steps":["a","b"],"files":["Sources/A.swift"]}"#), allowQuestions: true)
        #expect(plan == .plan(.init(summary: "Ajustar", steps: ["a", "b"], files: ["Sources/A.swift"])))
        let questions = try ReviewResolve.parse(data(#"{"questions":["Qual tela?"],"summary":"","steps":[],"files":[]}"#), allowQuestions: true)
        #expect(questions == .questions([.init(id: 0, text: "Qual tela?")]))
    }

    @Test func rejectsMalformedAndEmptyAnswers() {
        let invalid: [(String, Bool)] = [
            ("não é json", true),
            (#"{"questions":"x"}"#, true),
            (#"{"questions":[],"summary":"","steps":["a"],"files":[]}"#, true),       // resumo vazio
            (#"{"questions":[],"summary":"x","steps":[],"files":[]}"#, true),          // sem passos
            (#"{"questions":[],"summary":"x","steps":["  "],"files":[]}"#, true),      // passo vazio
            (#"{"questions":[" "],"summary":"","steps":[],"files":[]}"#, true),        // pergunta vazia
            (#"{"questions":["?"],"summary":"","steps":[],"files":[]}"#, false),       // perguntas depois de respondidas
            (#"{"questions":[],"summary":"x","steps":["a"],"files":["../fora"]}"#, true),
            (#"{"questions":[],"summary":"x","steps":["a"],"files":["/etc/passwd"]}"#, true),
        ]
        for (json, allow) in invalid {
            #expect(throws: VibeDeckError.discoverInvalidAnswer, "\(json)") { try ReviewResolve.parse(data(json), allowQuestions: allow) }
        }
    }

    @Test func executionPromptCarriesPlanAndLimits() {
        let item = ReviewItem(kind: "fix", title: "Botão")
        let prompt = ReviewResolve.executionPrompt(item: item, kind: "Corrigir", plan: .init(summary: "Fazer X", steps: ["um"], files: ["A.swift"]),
                                                   answers: [.init(question: "Qual?", answer: "Esta")])
        #expect(prompt.contains("Fazer X") && prompt.contains("1. um") && prompt.contains("Qual? → Esta"))
        #expect(prompt.contains("Não apague o item"))
        #expect(prompt.contains("review_item=\(item.id.uuidString)"))
        #expect(prompt.contains("rules_for e submit_rule_check no MCP vibedeck"))
        #expect(prompt.contains("verify_manual=true com evidência"))
    }

    @Test func middleFailureDoesNotStopOthersNorRevertDone() async {
        let items = (1...3).map { ReviewItem(kind: "fix", title: "i\($0)") }
        var attempted: [String] = []
        let results = await ReviewResolve.resolveSequentially(items) { item in
            attempted.append(item.title)
            return item.title == "i2" ? .failed("check") : .resolved
        }
        #expect(attempted == ["i1", "i2", "i3"])
        #expect(results.map(\.outcome) == [.resolved, .failed("check"), .resolved])
    }

    @Test func thrownErrorIsFailureAndCancellationSkipsTheRest() async {
        struct Boom: LocalizedError { var errorDescription: String? { "boom" } }
        let items = (1...3).map { ReviewItem(kind: "fix", title: "i\($0)") }
        let thrown = await ReviewResolve.resolveSequentially(items) { item in
            if item.title == "i1" { throw Boom() }
            return .resolved
        }
        #expect(thrown.map(\.outcome) == [.failed("boom"), .resolved, .resolved])
        let cancelled = await ReviewResolve.resolveSequentially(items) { item in
            if item.title == "i2" { throw CancellationError() }
            return .resolved
        }
        #expect(cancelled.map(\.outcome) == [.resolved, .cancelled, .skipped])
    }

    @Test func verifyAllowsDoneOnlyWithApprovedCheck() throws {
        let store = try newStore()
        func topic(_ title: String, command: String) throws -> String {
            var rule = Rule(text: title)
            rule.test = RuleTest(mode: .script, command: command, ruleHash: rule.contentHash)
            return try store.addRule(rule, toTopic: title).slug
        }
        let runner = RuleTestRunner { command, _ in RuleTestOutcome(exitCode: command == "ok" ? 0 : 1, output: command) }
        let (slug, _) = try store.createGroup(title: "G")

        let good = ReviewItem(kind: "fix", title: "bom", rules: [try topic("Boa", command: "ok")])
        _ = try store.addItem(good, toGroup: slug)
        #expect(ReviewResolve.verify(store: store, item: good, files: [], runner: runner).isEmpty)

        // Topics without paths are global: from here on every item also answers to the failing rule.
        let bad = ReviewItem(kind: "fix", title: "ruim", rules: [try topic("Ruim", command: "falha")])
        _ = try store.addItem(bad, toGroup: slug)
        let problems = ReviewResolve.verify(store: store, item: bad, files: [], runner: runner)
        #expect(!problems.isEmpty)
        #expect(try store.loadGroup(slug).items.first { $0.id == bad.id }?.status == .open, "verify não muda status")
    }

    @Test func finalVerificationRetainsOnlyCurrentManualEvidenceAndRerunsScripts() throws {
        let store = try newStore()
        let (group, _) = try store.createGroup(title: "G")
        let manual = Rule(text: "Inspeção manual")
        _ = try store.addRule(manual, toTopic: "Regras")
        var script = Rule(text: "Teste automático")
        script.test = RuleTest(mode: .script, command: "check", ruleHash: script.contentHash)
        _ = try store.addRule(script, toTopic: "Regras")
        let item = ReviewItem(kind: "fix", title: "Resolver")
        _ = try store.addItem(item, toGroup: group)
        let passing = RuleTestRunner { _, _ in RuleTestOutcome(exitCode: 0, output: "ok") }
        let started = Date.now.addingTimeInterval(-1)
        _ = try store.submitCheck(task: "IA", files: ["Actual.swift"], reviewItem: item.id.uuidString,
                                  answers: [.init(ruleId: manual.id.uuidString, verdict: .pass, note: "Inspecionado")],
                                  verifyManual: true, runner: passing)
        #expect(ReviewResolve.verify(store: store, item: item, files: ["Planned.swift"], verifiedSince: started, runner: passing).isEmpty)
        let final = try #require(store.listChecks().first)
        #expect(final.files == ["Actual.swift", "Planned.swift"])
        #expect(final.results.first { $0.ruleId == manual.id }?.note == "Inspecionado")
        let failing = RuleTestRunner { _, _ in RuleTestOutcome(exitCode: 1, output: "regressão") }
        #expect(!ReviewResolve.verify(store: store, item: item, files: [], verifiedSince: started, runner: failing).isEmpty)
        #expect(!ReviewResolve.verify(store: store, item: item, files: [], verifiedSince: Date.distantFuture, runner: passing).isEmpty)
        #expect(try store.loadGroup(group).items.first?.status == .open)
    }
}
