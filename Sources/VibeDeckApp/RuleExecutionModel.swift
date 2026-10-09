import Foundation
import Observation
import VibeDeckCore

@Observable @MainActor
final class RuleExecutionModel {
    struct Step: Identifiable {
        let id: UUID
        let slug: String
        let topic: String
        let rule: Rule
        let ai: Bool
        var started: Date?
        var ended: Date?
        var result: RuleResult?
        var error: String?
        var finished: Bool { ended != nil }
    }
    struct TimingJob {
        let key: String
        let category: String
        let ids: [UUID]
    }
    let id = UUID()
    let started: Date
    let withAI: Bool
    let provider: AIProvider
    var ended: Date?
    var steps: [Step]
    var message: String?
    var saved = false
    let omitted: Int
    let scope: [String]
    private var timings: RuleExecutionTimings
    private let timingKey: String
    private let jobs: [TimingJob]
    var active: Bool { ended == nil }
    var completed: Int { steps.filter(\.finished).count }
    var progress: Double { steps.isEmpty ? 1 : Double(completed) / Double(steps.count) }

    init(snapshot: [(slug: String, topic: RuleTopic)], withAI: Bool, provider: AIProvider, root: URL, now: Date = .now) {
        self.started = now
        self.withAI = withAI
        self.provider = provider
        scope = snapshot.map(\.slug)
        let all = snapshot.flatMap { entry in entry.topic.rules.map {
            Step(id: $0.id, slug: entry.slug, topic: entry.topic.title, rule: $0, ai: $0.scriptCommand == nil)
        } }
        omitted = withAI ? 0 : all.filter(\.ai).count
        steps = all.filter { withAI || !$0.ai }.sorted { !$0.ai && $1.ai }
        timingKey = "ruleExecutionTimings:" + root.standardizedFileURL.path
        timings = UserDefaults.standard.data(forKey: timingKey).flatMap { try? JSONDecoder().decode(RuleExecutionTimings.self, from: $0) } ?? .init()
        var jobs = all.filter { !$0.ai }.map {
            TimingJob(key: "script:\($0.id):\($0.rule.contentHash):\($0.rule.scriptCommand ?? "")", category: "script", ids: [$0.id])
        }
        if withAI {
            for entry in snapshot {
                let rules = entry.topic.rules.filter { $0.scriptCommand == nil }
                if !rules.isEmpty {
                    jobs.append(TimingJob(key: "ai-\(provider.rawValue):\(entry.slug):" + rules.map { "\($0.id):\($0.contentHash)" }.joined(separator: ","), category: "ai-\(provider.rawValue)", ids: rules.map(\.id)))
                }
            }
        }
        self.jobs = jobs
    }

    func begin(_ ids: [UUID], now: Date = .now) {
        for index in steps.indices where ids.contains(steps[index].id) { steps[index].started = now }
    }

    func finish(_ ids: [UUID], results: [RuleResult] = [], error: String? = nil, now: Date = .now) {
        for index in steps.indices where ids.contains(steps[index].id) {
            steps[index].ended = now
            steps[index].result = results.first { $0.ruleId == steps[index].id }
            steps[index].error = error
        }
        if error == nil, let job = jobs.first(where: { $0.ids == ids }),
           let start = steps.first(where: { $0.id == ids.first })?.started {
            timings.record(now.timeIntervalSince(start), key: job.key)
            if let data = try? JSONEncoder().encode(timings) { UserDefaults.standard.set(data, forKey: timingKey) }
        }
    }

    /// nil means insufficient observations; a negative value signals an exceeded estimate.
    func remaining(at now: Date) -> TimeInterval? {
        guard active else { return 0 }
        var remaining: TimeInterval = 0
        for job in jobs {
            guard let step = steps.first(where: { $0.id == job.ids.first }), !step.finished else { continue }
            guard let estimate = timings.estimate(key: job.key, category: job.category) else { return nil }
            let elapsed = step.started.map { now.timeIntervalSince($0) } ?? 0
            if step.started != nil && elapsed >= estimate { return -1 }
            remaining += max(0, estimate - elapsed)
        }
        return remaining
    }
}

extension ProjectModel {
    func startRuleExecution(topic: String? = nil, withAI: Bool = false, provider: AIProvider = .claude,
                            runner: RuleTestRunner = .live,
                            providerAvailable: (AIProvider) -> Bool = { $0.isInstalled },
                            verify: @escaping @MainActor (URL, AIProvider, RuleTopic, String, [Rule], [RuleResult]) async throws -> [RuleResult] = RuleVerificationAI.run) {
        guard ruleExecution?.active != true, !isGeneratingTests, runningTests.isEmpty else { return }
        guard !withAI || providerAvailable(provider) else { errorMessage = "\(provider.title) não está instalado."; return }
        let snapshot: [(slug: String, topic: RuleTopic)]
        do {
            snapshot = try store.listTopics().filter { topic == nil || $0.slug == topic }
        } catch { errorMessage = error.localizedDescription; return }
        let execution = RuleExecutionModel(snapshot: snapshot, withAI: withAI, provider: provider, root: store.root)
        ruleExecution = execution
        guard !execution.steps.isEmpty else {
            execution.message = "Nenhuma regra executável neste modo."
            execution.ended = .now
            return
        }
        runningTests = Set(snapshot.map(\.slug) + ["*"])
        let store = store
        Task {
            defer { runningTests = []; execution.ended = .now }
            let events = AsyncStream<RuleScriptEvent> { continuation in
                Task.detached {
                    _ = store.runRuleScripts(snapshot: snapshot, runner: runner) { continuation.yield($0) }
                    continuation.finish()
                }
            }
            for await event in events {
                switch event {
                case .started(_, let rule, let date): execution.begin([rule.id], now: date)
                case .finished(let run, let date):
                    testRuns[run.rule.id] = run.outcome
                    execution.finish([run.rule.id], results: [RuleResult(topic: run.topic, ruleId: run.rule.id,
                        verdict: run.outcome.verdict, note: "\(run.command) (exit \(run.outcome.exitCode))\n\(run.outcome.output)",
                        source: .script, exitCode: run.outcome.exitCode)], now: date)
                }
            }
            if withAI {
                let scriptResults = execution.steps.compactMap(\.result)
                for entry in snapshot {
                    let rules = entry.topic.rules.filter { $0.scriptCommand == nil }
                    guard !rules.isEmpty else { continue }
                    let ids = rules.map(\.id)
                    execution.begin(ids)
                    do {
                        let results = try await verify(store.root, provider, entry.topic, entry.slug, rules, scriptResults)
                        execution.finish(ids, results: results)
                    } catch { execution.finish(ids, error: error.localizedDescription) }
                }
                do {
                    guard execution.steps.allSatisfy({ $0.result != nil && $0.error == nil }) else { throw RuleExecutionError.incomplete }
                    try store.completeRuleExecution(snapshot: snapshot, results: execution.steps.compactMap(\.result))
                    execution.saved = true
                    execution.message = "Verificação salva no histórico."
                    reloadChecks()
                } catch { execution.message = error.localizedDescription }
            } else {
                execution.message = "Scripts concluídos. \(execution.omitted) regra(s) precisam de IA."
            }
        }
    }
}
