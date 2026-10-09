import Foundation
import Testing
@testable import VibeDeckCore

@Suite struct RuleExecutionTests {
    private func store() throws -> ProjectStore {
        try ProjectStore.initialize(at: FileManager.default.temporaryDirectory.appending(path: "rule-execution-\(UUID())"))
    }
    private final class Events: @unchecked Sendable {
        let lock = NSLock()
        var values: [String] = []
        func append(_ value: String) { lock.withLock { values.append(value) } }
    }

    @Test func orderedEventsAndSaveWithoutRerunning() throws {
        let store = try store()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let (slug, rule) = try store.addRule(Rule(text: "Script"), toTopic: "Selected")
        _ = try store.setRuleTest(rule.id.uuidString, mode: .script, command: "stub")
        let (_, manual) = try store.addRule(Rule(text: "Manual"), toTopic: slug)
        _ = try store.addRule(Rule(text: "Global outside scope"), toTopic: "Outside")
        let snapshot = [(slug: slug, topic: try store.loadTopic(slug))]
        let events = Events()
        let runs = store.runRuleScripts(snapshot: snapshot, runner: RuleTestRunner { _, _ in
            events.append("execute")
            return .init(exitCode: 1, output: "failed")
        }) { event in
            switch event { case .started: events.append("start"); case .finished: events.append("finish") }
        }
        #expect(events.values == ["start", "execute", "finish"])
        #expect(runs.count == 1)
        let check = try store.completeRuleExecution(snapshot: snapshot, results: [
            RuleResult(topic: slug, ruleId: rule.id, verdict: runs[0].outcome.verdict, source: .script, exitCode: 1),
            RuleResult(topic: slug, ruleId: manual.id, verdict: .pass, note: "Evidence")
        ])
        #expect(!check.passed)
        #expect(check.topics == [slug])
        #expect(try store.listChecks().count == 1)
        #expect(events.values.count == 3)
    }

    @Test func rejectsIncompleteAndChangedSnapshots() throws {
        let store = try store()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let (slug, rule) = try store.addRule(Rule(text: "Manual"), toTopic: "Topic")
        let snapshot = [(slug: slug, topic: try store.loadTopic(slug))]
        #expect(throws: RuleExecutionError.self) { try store.completeRuleExecution(snapshot: snapshot, results: []) }
        _ = try store.setRuleTest(rule.id.uuidString, mode: .manual, reason: "Changed config")
        #expect(throws: RuleExecutionError.self) {
            try store.completeRuleExecution(snapshot: snapshot, results: [RuleResult(topic: slug, ruleId: rule.id, verdict: .pass)])
        }
        #expect(try store.listChecks().isEmpty)
    }

    @Test func validatesAIAnswers() throws {
        let rule = Rule(text: "Rule")
        let good = #"{"ruleId":"\#(rule.id)","verdict":"pass","note":"Sources/A.swift:12"}"#
        let parse: (String) throws -> [RuleResult] = { try RuleVerificationAnswer.parse(Data($0.utf8), rules: [rule], topic: "topic") }
        #expect(try parse("{\"results\":[\(good)]}").first?.verdict == .pass)
        for invalid in ["{}", "{\"results\":[]}", "{\"results\":[\(good),\(good)]}",
                        "{\"results\":[\(good.replacingOccurrences(of: rule.id.uuidString, with: UUID().uuidString))]}",
                        "{\"results\":[\(good.replacingOccurrences(of: "Sources/A.swift:12", with: " "))]}"] {
            #expect(throws: RuleExecutionError.self) { try parse(invalid) }
        }
    }

    @Test func boundedTimingHistoryAndCategoryFallback() {
        var timings = RuleExecutionTimings()
        #expect(timings.estimate(key: "script:a", category: "script") == nil)
        for sample in 1...12 { timings.record(Double(sample), key: "script:a") }
        #expect(timings.samples["script:a"]?.count == 10)
        #expect(timings.estimate(key: "script:a", category: "script") == 7.5)
        #expect(timings.estimate(key: "script:b", category: "script") == 7.5)
        #expect(timings.estimate(key: "ai-codex:a", category: "ai-codex") == nil)
    }
}
