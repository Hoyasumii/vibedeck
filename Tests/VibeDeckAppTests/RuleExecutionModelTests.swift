import Foundation
import SwiftUI
import Testing
import VibeDeckCore
@testable import VibeDeckApp

@Suite(.serialized) @MainActor
struct RuleExecutionModelTests {
    private func fixture() throws -> (ProjectModel, String, UUID, UUID) {
        let store = try ProjectStore.initialize(at: FileManager.default.temporaryDirectory.appending(path: "rule-flow-\(UUID())"))
        let (slug, script) = try store.addRule(Rule(text: "Script rule"), toTopic: "Flow")
        _ = try store.setRuleTest(script.id.uuidString, mode: .script, command: "stub")
        let (_, manual) = try store.addRule(Rule(text: "Manual rule"), toTopic: slug)
        return (ProjectModel(store: store), slug, script.id, manual.id)
    }
    private func wait(_ model: ProjectModel) async throws {
        for _ in 0..<500 {
            if model.ruleExecution?.active != true { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Execution did not finish")
    }

    @Test func scriptsBeforeAIAndPersistFailure() async throws {
        let (model, slug, script, manual) = try fixture()
        defer { try? FileManager.default.removeItem(at: model.store.root) }
        var aiCalls = 0
        model.startRuleExecution(topic: slug, withAI: true, runner: .init { _, _ in .init(exitCode: 1, output: "failure") }, providerAvailable: { _ in true }) { _, _, _, topic, rules, scripts in
            aiCalls += 1
            #expect(model.testRuns[script]?.verdict == .fail)
            #expect(scripts.count == 1)
            #expect(rules.map(\.id) == [manual])
            return [RuleResult(topic: topic, ruleId: manual, verdict: .pass, note: "Evidence")]
        }
        try await wait(model)
        #expect(aiCalls == 1)
        #expect(model.ruleExecution?.saved == true)
        #expect(model.ruleExecution?.progress == 1)
        #expect(try model.store.listChecks().first?.passed == false)
    }

    @Test func scriptsOnlyAndUnavailableProvider() async throws {
        let (model, slug, _, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: model.store.root) }
        model.startRuleExecution(topic: slug, withAI: true, providerAvailable: { _ in false }) { _, _, _, _, _, _ in
            Issue.record("Unavailable provider was called"); return []
        }
        #expect(model.ruleExecution == nil)
        model.startRuleExecution(topic: slug, runner: .init { _, _ in .init(exitCode: 77, output: "not applicable") }, verify: { _, _, _, _, _, _ in
            Issue.record("AI was called in script mode"); return []
        })
        try await wait(model)
        #expect(model.ruleExecution?.steps.count == 1)
        #expect(model.ruleExecution?.omitted == 1)
        #expect(model.ruleExecution?.steps.first?.result?.verdict == .na)
        #expect(try model.store.listChecks().isEmpty)
    }

    @Test func providerFailureContinuesOtherTopicsWithoutSaving() async throws {
        let (model, _, _, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: model.store.root) }
        _ = try model.store.addRule(Rule(text: "Another"), toTopic: "Second")
        var calls = 0
        model.startRuleExecution(withAI: true, runner: .init { _, _ in .init(exitCode: 124, output: "timeout") }, providerAvailable: { _ in true }) { _, _, _, slug, rules, _ in
            calls += 1
            if calls == 1 { throw RuleExecutionError.invalidAnswer }
            return rules.map { RuleResult(topic: slug, ruleId: $0.id, verdict: .pass, note: "Evidence") }
        }
        try await wait(model)
        #expect(calls == 2)
        #expect(model.ruleExecution?.steps.contains { $0.error != nil } == true)
        #expect(model.ruleExecution?.saved == false)
        #expect(try model.store.listChecks().isEmpty)
    }

    @Test func staleRulesGoToAIAndChangesPreventSaving() async throws {
        let (model, slug, script, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: model.store.root) }
        try model.store.updateTopic(slug) { $0.rules[0].text = "Changed rule" }
        var calls = 0
        model.startRuleExecution(topic: slug, withAI: true, runner: .init { _, _ in
            Issue.record("Stale script must not execute")
            return .init(exitCode: 0, output: "")
        }, providerAvailable: { _ in true }) { _, _, _, topic, rules, scripts in
            calls += 1
            #expect(scripts.isEmpty)
            #expect(rules.contains { $0.id == script })
            let executionID = model.ruleExecution?.id
            model.startRuleExecution(topic: slug)
            #expect(model.ruleExecution?.id == executionID, "A second execution must not replace the active one")
            try model.store.updateTopic(slug) { $0.rules[0].details = "Changed while running" }
            return rules.map { RuleResult(topic: topic, ruleId: $0.id, verdict: .pass, note: "Evidence") }
        }
        try await wait(model)
        #expect(calls == 1)
        #expect(model.ruleExecution?.saved == false)
        #expect(model.ruleExecution?.message?.contains("mudaram") == true)
        #expect(try model.store.listChecks().isEmpty)
    }

    @Test func progressEstimateAndEmptyScope() throws {
        let (model, slug, script, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: model.store.root) }
        let root = model.store.root
        let key = "ruleExecutionTimings:" + root.standardizedFileURL.path
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let snapshot = [(slug: slug, topic: try model.store.loadTopic(slug))]
        let start = Date(timeIntervalSince1970: 100)
        let first = RuleExecutionModel(snapshot: snapshot, withAI: false, provider: .claude, root: root, now: start)
        #expect(first.remaining(at: start) == nil)
        first.begin([script], now: start)
        first.finish([script], now: start.addingTimeInterval(10))
        #expect(first.progress == 1)
        let next = RuleExecutionModel(snapshot: snapshot, withAI: false, provider: .claude, root: root, now: start)
        next.begin([script], now: start)
        #expect(next.remaining(at: start.addingTimeInterval(4)) == 6)
        #expect(next.remaining(at: start.addingTimeInterval(11)) == -1)
        model.startRuleExecution(topic: "missing", withAI: false)
        #expect(model.ruleExecution?.active == false)
        #expect(model.ruleExecution?.progress == 1)
    }
}
