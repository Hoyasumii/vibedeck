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
        /// Never started: the execution was cancelled or interrupted first.
        var skipped = false
        var finished: Bool { ended != nil }
    }
    struct TimingJob {
        let key: String
        let category: String
        let ids: [UUID]
    }
    /// UserDefaults key of the limit of scripts running at the same time (app settings, per machine).
    nonisolated static let concurrencyKey = "ruleScriptConcurrency"
    /// The configured limit; nil (not set) uses the Core default. The Core clamps it to 1...activeProcessorCount.
    nonisolated static var configuredConcurrency: Int? { UserDefaults.standard.object(forKey: concurrencyKey) as? Int }

    let id = UUID()
    let started: Date
    let concurrency: Int
    let cancellation = ShellCancellation()
    private(set) var cancelled = false
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

    init(snapshot: [(slug: String, topic: RuleTopic)], withAI: Bool, provider: AIProvider, root: URL,
         concurrency: Int? = RuleExecutionModel.configuredConcurrency, now: Date = .now) {
        self.started = now
        self.concurrency = ProjectStore.scriptConcurrency(concurrency)
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

    /// Terminates running scripts and keeps queued ones from starting; no AI verification and no check follow.
    func cancel() {
        guard active, !cancelled else { return }
        cancelled = true
        cancellation.cancel()
    }

    /// Closes an interrupted execution: steps that never started are marked as not executed, none stays running.
    func interrupt(_ message: String, now: Date = .now) {
        for index in steps.indices where !steps[index].finished {
            if steps[index].started == nil { steps[index].skipped = true }
            else { steps[index].ended = now; steps[index].error = steps[index].error ?? "Interrompido." }
        }
        self.message = message
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
        if error == nil, !cancelled,
           !steps.contains(where: { !$0.ai && $0.rule.severity == .must && $0.result?.verdict == .fail }),
           let job = jobs.first(where: { $0.ids == ids }),
           let start = steps.first(where: { $0.id == ids.first })?.started {
            timings.record(now.timeIntervalSince(start), key: job.key)
            if let data = try? JSONEncoder().encode(timings) { UserDefaults.standard.set(data, forKey: timingKey) }
        }
    }

    /// nil means insufficient observations; a negative value signals an exceeded estimate. Scripts run up to
    /// `concurrency` at a time (spread over that many lanes, running ones first); AI topics run one after another.
    func remaining(at now: Date) -> TimeInterval? {
        guard active else { return 0 }
        var lanes = [TimeInterval](repeating: 0, count: concurrency)
        var ai: TimeInterval = 0
        var scripts: [(running: Bool, left: TimeInterval)] = []
        for job in jobs {
            guard let step = steps.first(where: { $0.id == job.ids.first }), !step.finished, !step.skipped else { continue }
            guard let estimate = timings.estimate(key: job.key, category: job.category) else { return nil }
            let elapsed = step.started.map { now.timeIntervalSince($0) } ?? 0
            if step.started != nil && elapsed >= estimate { return -1 }
            if job.category == "script" { scripts.append((step.started != nil, max(0, estimate - elapsed))) }
            else { ai += max(0, estimate - elapsed) }
        }
        for script in scripts.sorted(by: { $0.running && !$1.running }) {
            let lane = lanes.indices.min { lanes[$0] < lanes[$1] } ?? 0
            lanes[lane] += script.left
        }
        return (lanes.max() ?? 0) + ai
    }
}

extension ProjectModel {
    func startRuleExecution(topic: String? = nil, withAI: Bool = false, provider: AIProvider = .claude,
                            runner: RuleTestRunner = .live, concurrency: Int? = RuleExecutionModel.configuredConcurrency,
                            providerAvailable: (AIProvider) -> Bool = { $0.isInstalled },
                            verify: @escaping @MainActor (URL, AIProvider, RuleTopic, String, [Rule], [RuleResult]) async throws -> [RuleResult] = RuleVerificationAI.run) {
        guard ruleExecution?.active != true, !isGeneratingTests, runningTests.isEmpty else { return }
        guard !withAI || RemoteWorkspace.existing(at: store.root) != nil || providerAvailable(provider) else { errorMessage = "\(provider.title) não está instalado."; return }
        do { try RemoteWorkspace.existing(at: store.root)?.requireSynchronized() }
        catch { errorMessage = error.localizedDescription; return }
        let snapshot: [(slug: String, topic: RuleTopic)]
        do {
            snapshot = try store.listTopics().filter { topic == nil || $0.slug == topic }
        } catch { errorMessage = error.localizedDescription; return }
        let execution = RuleExecutionModel(snapshot: snapshot, withAI: withAI, provider: provider, root: store.root, concurrency: concurrency)
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
            let concurrency = execution.concurrency
            let cancellation = execution.cancellation
            let events = AsyncStream<RuleScriptEvent> { continuation in
                VDLog.detached {
                    _ = store.runRuleScripts(snapshot: snapshot, runner: runner, concurrency: concurrency,
                                             cancellation: cancellation, stopOnMustFailure: true) { continuation.yield($0) }
                    continuation.finish()
                }
            }
            // Scripts run in parallel: several steps can be running at once, each with its own start and end.
            for await event in events {
                switch event {
                case .started(_, let rule, let date): execution.begin([rule.id], now: date)
                case .finished(let run, let date):
                    if execution.cancelled {
                        execution.finish([run.rule.id], error: "Cancelado.", now: date)
                        continue
                    }
                    testRuns[run.rule.id] = run.outcome
                    execution.finish([run.rule.id], results: [RuleResult(topic: run.topic, ruleId: run.rule.id,
                        verdict: run.outcome.verdict, note: "\(run.command) (exit \(run.outcome.exitCode))\n\(run.outcome.output)",
                        source: .script, exitCode: run.outcome.exitCode)], now: date)
                }
            }
            // The AI verification only starts after every script ended, and never after an interruption.
            if execution.cancelled {
                execution.interrupt("Execução cancelada. Nada foi salvo.")
                return
            }
            if let failed = execution.steps.first(where: { !$0.ai && $0.rule.severity == .must && $0.result?.verdict == .fail }) {
                execution.interrupt("Interrompida: a regra must \"\(failed.rule.text)\" falhou. Nada foi salvo.")
                return
            }
            if withAI {
                let scriptResults = execution.steps.compactMap(\.result)
                for entry in snapshot {
                    guard !execution.cancelled else {
                        execution.interrupt("Execução cancelada. Nada foi salvo.")
                        return
                    }
                    let rules = entry.topic.rules.filter { $0.scriptCommand == nil }
                    guard !rules.isEmpty else { continue }
                    let ids = rules.map(\.id)
                    execution.begin(ids)
                    do {
                        let results = try await verify(store.root, provider, entry.topic, entry.slug, rules, scriptResults)
                        guard !execution.cancelled else {
                            execution.interrupt("Execução cancelada. Nada foi salvo.")
                            return
                        }
                        execution.finish(ids, results: results)
                    } catch {
                        guard !execution.cancelled else {
                            execution.interrupt("Execução cancelada. Nada foi salvo.")
                            return
                        }
                        execution.finish(ids, error: error.localizedDescription)
                    }
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
