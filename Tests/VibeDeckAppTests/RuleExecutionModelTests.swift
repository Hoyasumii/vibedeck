import Foundation
import Testing
@testable import VibeDeckApp

/// Lógica de apresentação da execução de regras (passos em paralelo, estimativa, cancelamento, durações).
/// A execução em si roda no Core Rust (`run_rule_tests`); aqui só o `RuleExecutionModel`.
@Suite(.serialized) @MainActor
struct RuleExecutionModelTests {
    private func scriptRule(_ text: String) -> Rule {
        var rule = Rule(text: text)
        rule.test = RuleTest(mode: .script, command: "stub", ruleHash: rule.contentHash)
        return rule
    }

    private func snapshot(scripts: Int) -> [(slug: String, topic: RuleTopic)] {
        let rules = (1...scripts).map { scriptRule("Script \($0)") } + [Rule(text: "Manual")]
        return [(slug: "fluxo", topic: RuleTopic(title: "Fluxo", rules: rules))]
    }

    private func timingKey(_ root: URL) -> String { "ruleExecutionTimings:" + root.standardizedFileURL.path }

    private func tempRoot() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "rule-exec-\(UUID().uuidString)")
    }

    @Test func remainingEstimateConsidersParallelism() {
        let root = tempRoot()
        let key = timingKey(root)
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let snap = snapshot(scripts: 4)
        let start = Date(timeIntervalSince1970: 100)
        let first = RuleExecutionModel(snapshot: snap, withAI: false, provider: .claude, root: root, concurrency: 1, now: start)
        for step in first.steps {
            first.begin([step.id], now: start)
            first.finish([step.id], now: start.addingTimeInterval(10))
        }
        let cpu = ProcessInfo.processInfo.activeProcessorCount
        let parallel = RuleExecutionModel(snapshot: snap, withAI: false, provider: .claude, root: root, concurrency: 4, now: start)
        #expect(parallel.remaining(at: start) == 10 * Double((4 + min(4, cpu) - 1) / min(4, cpu)))
        let serial = RuleExecutionModel(snapshot: snap, withAI: false, provider: .claude, root: root, concurrency: 1, now: start)
        #expect(serial.remaining(at: start) == 40)
        // A duração de cada passo usa o início do próprio passo, não a espera de outro.
        parallel.begin([parallel.steps[0].id], now: start)
        parallel.begin([parallel.steps[1].id], now: start.addingTimeInterval(5))
        parallel.finish([parallel.steps[1].id], now: start.addingTimeInterval(7))
        #expect(parallel.steps[1].ended!.timeIntervalSince(parallel.steps[1].started!) == 2)
    }

    @Test func progressEstimateAndEmptyScope() {
        let root = tempRoot()
        let key = timingKey(root)
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let snap = snapshot(scripts: 1)
        let start = Date(timeIntervalSince1970: 100)
        let first = RuleExecutionModel(snapshot: snap, withAI: false, provider: .claude, root: root, now: start)
        let id = first.steps[0].id
        #expect(first.remaining(at: start) == nil)
        first.begin([id], now: start)
        first.finish([id], now: start.addingTimeInterval(10))
        #expect(first.progress == 1)
        let next = RuleExecutionModel(snapshot: snap, withAI: false, provider: .claude, root: root, now: start)
        next.begin([id], now: start)
        #expect(next.remaining(at: start.addingTimeInterval(4)) == 6)
        #expect(next.remaining(at: start.addingTimeInterval(11)) == -1)
    }

    @Test func parallelStepsShowAsRunning() {
        let root = tempRoot()
        let execution = RuleExecutionModel(snapshot: snapshot(scripts: 3), withAI: false, provider: .claude, root: root, concurrency: 3)
        let ids = execution.steps.map(\.id)
        execution.begin(ids)
        // parallel steps show as running: todos os passos iniciados e sem fim estão em andamento ao mesmo tempo.
        #expect(execution.steps.filter { $0.started != nil && $0.ended == nil }.count == ids.count)
        execution.finish([ids[0]])
        #expect(execution.steps.filter { $0.started != nil && $0.ended == nil }.count == ids.count - 1)
    }

    @Test func cancelLeavesNoStepRunning() {
        let root = tempRoot()
        let execution = RuleExecutionModel(snapshot: snapshot(scripts: 3), withAI: false, provider: .claude, root: root, concurrency: 2)
        let ids = execution.steps.map(\.id)
        execution.begin([ids[0], ids[1]])
        execution.cancel()
        execution.interrupt("Execução cancelada. Nada foi salvo.")
        #expect(execution.cancelled)
        #expect(execution.steps.allSatisfy { !($0.started != nil && $0.ended == nil) })
        #expect(execution.steps[2].skipped)
        #expect(execution.saved == false)
    }

    @Test("cancelled scripts don't record durations") func cancelledScriptsDoNotRecordDurations() {
        let root = tempRoot()
        let key = timingKey(root)
        UserDefaults.standard.removeObject(forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let start = Date(timeIntervalSince1970: 100)
        let execution = RuleExecutionModel(snapshot: snapshot(scripts: 1), withAI: false, provider: .claude, root: root, now: start)
        let id = execution.steps[0].id
        execution.begin([id], now: start)
        execution.cancel()
        execution.finish([id], error: "Cancelado.", now: start.addingTimeInterval(3))
        #expect(UserDefaults.standard.data(forKey: key) == nil)
    }
}
