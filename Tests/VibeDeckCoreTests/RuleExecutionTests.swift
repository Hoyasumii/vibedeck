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

    /// Counts scripts running at the same time; `hold` keeps each one running until `target` overlap or a timeout.
    private final class Peak: @unchecked Sendable {
        let lock = NSLock()
        var active = 0
        var peak = 0
        var intervals: [String: (start: Date, end: Date)] = [:]
        func runner(target: Int = 1, hold: TimeInterval = 0.02) -> RuleTestRunner {
            RuleTestRunner { [self] command, _ in
                let start = Date.now
                lock.withLock { active += 1; peak = max(peak, active) }
                let deadline = Date.now.addingTimeInterval(1)
                while lock.withLock({ active < target }), Date.now < deadline { Thread.sleep(forTimeInterval: 0.005) }
                Thread.sleep(forTimeInterval: hold)
                lock.withLock { active -= 1; intervals[command] = (start, .now) }
                return .init(exitCode: 0, output: command)
            }
        }
        func overlap(_ a: String, _ b: String) -> Bool {
            lock.withLock {
                guard let x = intervals[a], let y = intervals[b] else { return false }
                return x.start < y.end && y.start < x.end
            }
        }
    }

    /// One topic with a script rule per command, in order.
    private func scripts(_ store: ProjectStore, _ commands: [String], severity: RuleSeverity = .must) throws -> [(slug: String, topic: RuleTopic)] {
        var slug = ""
        let title = "Parallel \(UUID().uuidString.prefix(8))"
        for command in commands {
            let added = try store.addRule(Rule(text: "Rule \(command)", severity: severity), toTopic: slug.isEmpty ? title : slug)
            slug = added.0
            _ = try store.setRuleTest(added.1.id.uuidString, mode: .script, command: command)
        }
        return [(slug: slug, topic: try store.loadTopic(slug))]
    }

    @Test func runsInParallelUpToTheLimit() throws {
        let store = try store()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let cpu = ProcessInfo.processInfo.activeProcessorCount
        let eight = try scripts(store, (1...8).map { "stub-\($0)" })
        let byDefault = Peak()
        #expect(store.runRuleScripts(snapshot: eight, runner: byDefault.runner(target: min(cpu, 8))).count == 8)
        #expect(byDefault.peak == min(cpu, 8))
        if cpu > 1 { #expect(byDefault.peak > 1) }

        let six = [(slug: eight[0].slug, topic: RuleTopic(title: "Six", rules: Array(eight[0].topic.rules.prefix(6))))]
        let two = Peak()
        _ = store.runRuleScripts(snapshot: six, runner: two.runner(target: 6, hold: 0.05), concurrency: 2)
        #expect(two.peak == min(2, cpu))
        for limit in [0, cpu + 10] {
            let peak = Peak()
            #expect(store.runRuleScripts(snapshot: six, runner: peak.runner(), concurrency: limit).count == 6)
            #expect((1...cpu).contains(peak.peak))
        }
        #expect(ProjectStore.scriptConcurrency(nil) == cpu)
        #expect(ProjectStore.scriptConcurrency(0) == 1)
        #expect(ProjectStore.scriptConcurrency(cpu + 10) == cpu)
    }

    @Test func resultsInDeclarationOrderWithOneEventPairPerRule() throws {
        let store = try store()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let snapshot = try scripts(store, ["slow", "a", "b", "c", "d"])
        let events = Events()
        let inside = NSLock()
        let reentered = Events()
        let runs = store.runRuleScripts(snapshot: snapshot, runner: RuleTestRunner { command, _ in
            Thread.sleep(forTimeInterval: command == "slow" ? 0.2 : 0.01)
            return .init(exitCode: 0, output: command)
        }, concurrency: 4) { event in
            if !inside.try() { reentered.append("re"); return }
            defer { inside.unlock() }
            switch event {
            case .started(_, let rule, _): events.append("start \(rule.scriptCommand ?? "")")
            case .finished(let run, _): events.append("finish \(run.command)")
            }
            Thread.sleep(forTimeInterval: 0.002)
        }
        #expect(runs.map(\.command) == ["slow", "a", "b", "c", "d"])
        #expect(runs.allSatisfy { $0.outcome.output == $0.command })
        #expect(reentered.values.isEmpty, "onEvent must never run concurrently")
        for command in ["slow", "a", "b", "c", "d"] {
            let start = events.values.firstIndex(of: "start \(command)")
            let finish = events.values.firstIndex(of: "finish \(command)")
            #expect(events.values.filter { $0 == "start \(command)" }.count == 1)
            #expect(events.values.filter { $0 == "finish \(command)" }.count == 1)
            #expect(start != nil && finish != nil && start! < finish!)
        }
    }

    @Test func sameBuildToolNeverOverlaps() throws {
        let store = try store()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let tests = store.root.appending(path: ".vibedeck/tests/x")
        try FileManager.default.createDirectory(at: tests, withIntermediateDirectories: true)
        try "#!/usr/bin/env bash\nswift test --filter A\n".write(to: tests.appending(path: "a.sh"), atomically: true, encoding: .utf8)
        try "#!/usr/bin/env bash\nsource \"$(dirname \"$0\")/_lib.sh\"\nrun_tests\n".write(to: tests.appending(path: "b.sh"), atomically: true, encoding: .utf8)
        try "run_tests() { swift test --skip-build; }\n".write(to: tests.appending(path: "_lib.sh"), atomically: true, encoding: .utf8)
        try "python3 .vibedeck/tests/x/check.py\n".write(to: tests.appending(path: "c.sh"), atomically: true, encoding: .utf8)
        try "import subprocess\nsubprocess.run(['swift', 'test'])\n".write(to: tests.appending(path: "check.py"), atomically: true, encoding: .utf8)
        #expect(BuildToolLock.keys(command: "bash .vibedeck/tests/x/a.sh", root: store.root) == ["swift"])
        #expect(BuildToolLock.keys(command: "bash .vibedeck/tests/x/b.sh", root: store.root) == ["swift"])
        let files = try scripts(store, ["bash .vibedeck/tests/x/a.sh", "bash .vibedeck/tests/x/b.sh", "bash .vibedeck/tests/x/c.sh", "plain"])
        let peak = Peak()
        _ = store.runRuleScripts(snapshot: files, runner: peak.runner(target: 2, hold: 0.1), concurrency: 4)
        #expect(!peak.overlap("bash .vibedeck/tests/x/a.sh", "bash .vibedeck/tests/x/b.sh"))
        #expect(!peak.overlap("bash .vibedeck/tests/x/a.sh", "bash .vibedeck/tests/x/c.sh"))
        #expect(!peak.overlap("bash .vibedeck/tests/x/b.sh", "bash .vibedeck/tests/x/c.sh"))
        if ProcessInfo.processInfo.activeProcessorCount > 1 {
            #expect(peak.overlap("bash .vibedeck/tests/x/a.sh", "plain"), "another tool runs alongside")
        }

        // Waiting for a tool doesn't take a slot: with limit 2 the script without a tool runs with the first swift one.
        let inline = try scripts(store, ["swift test --filter A", "swift test --filter B", "echo free"])
        let slots = Peak()
        _ = store.runRuleScripts(snapshot: inline, runner: slots.runner(target: 2, hold: 0.1), concurrency: 2)
        #expect(!slots.overlap("swift test --filter A", "swift test --filter B"))
        if ProcessInfo.processInfo.activeProcessorCount > 1 { #expect(slots.overlap("swift test --filter A", "echo free")) }
    }

    @Test func runRuleTestsPreservesTopicAndRuleOrder() throws {
        let store = try store()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let first = try scripts(store, ["slow", "quick-a"])
        let second = try scripts(store, ["quick-b", "quick-c"])
        let topics = [first[0].slug, second[0].slug]
        let expected = try store.listTopics().filter { topics.contains($0.slug) }
            .flatMap { $0.topic.rules.compactMap(\.scriptCommand) }
        let runs = try store.runRuleTests(topics: topics, onlyTopics: true, runner: .init { command, _ in
            Thread.sleep(forTimeInterval: command == "slow" ? 0.1 : 0.01)
            return .init(exitCode: 0, output: command)
        }, concurrency: 2)
        #expect(runs.map(\.command) == expected)
    }

    @Test func cancellationStopsQueueAndRunningScripts() throws {
        let store = try store()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let snapshot = try scripts(store, ["one", "two", "three"])
        let cancellation = ShellCancellation()
        let events = Events()
        let terminated = Events()
        let runs = store.runRuleScripts(snapshot: snapshot, runner: RuleTestRunner { command, context in
            // A blocking script that only ends when terminated.
            let done = DispatchSemaphore(value: 0)
            context.cancellation?.onCancel { terminated.append(command); done.signal() }
            cancellation.cancel()
            done.wait()
            return .init(exitCode: ShellRunner.cancelledStatus, output: "Cancelado.")
        }, concurrency: 1, cancellation: cancellation) { event in
            if case .started(_, let rule, _) = event { events.append(rule.scriptCommand ?? "") }
        }
        #expect(events.values == ["one"])
        #expect(terminated.values == ["one"])
        #expect(runs.map(\.command) == ["one"])
    }

    @Test func mustFailureStopsQueueOnlyWhenAsked() throws {
        let store = try store()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let snapshot = try scripts(store, ["fail", "next", "last"])
        let runner = RuleTestRunner { command, _ in .init(exitCode: command == "fail" ? 1 : 0, output: "") }
        let started = Events()
        _ = store.runRuleScripts(snapshot: snapshot, runner: runner, concurrency: 1, stopOnMustFailure: true) {
            if case .started(_, let rule, _) = $0 { started.append(rule.scriptCommand ?? "") }
        }
        #expect(started.values == ["fail"])
        // Slots are released after a timeout or a launch failure: the next script still starts.
        for code in [ShellRunner.timedOutStatus, 127] {
            let runs = store.runRuleScripts(snapshot: snapshot, runner: RuleTestRunner { command, _ in
                .init(exitCode: command == "fail" ? code : 0, output: "")
            }, concurrency: 1)
            #expect(runs.map(\.command) == ["fail", "next", "last"])
        }
        // submitCheck answers every rule, even after a failed must.
        let check = try store.submitCheck(task: "t", files: [], topics: [snapshot[0].slug], answers: [], runner: runner)
        let ids = Set(snapshot[0].topic.rules.map(\.id))
        #expect(Set(check.results.filter { $0.source == .script }.map(\.ruleId)) == ids)
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
