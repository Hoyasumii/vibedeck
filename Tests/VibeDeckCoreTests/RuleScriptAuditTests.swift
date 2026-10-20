import Foundation
import Testing
@testable import VibeDeckCore

/// Opt-in integration audit; never changes historical checks or rule definitions.
@Suite struct RuleScriptAuditTests {
    @Test(.enabled(if: !(ProcessInfo.processInfo.environment["VIBEDECK_RULE_AUDIT_ROOT"] ?? "").isEmpty))
    func registeredScripts() throws {
        let env = ProcessInfo.processInfo.environment
        let root = try #require(env["VIBEDECK_RULE_AUDIT_ROOT"])
        let output = try #require(env["VIBEDECK_RULE_AUDIT_OUTPUT"])
        let concurrency = Int(env["VIBEDECK_RULE_AUDIT_CONCURRENCY"] ?? "1") ?? 1
        let store = ProjectStore(root: URL(fileURLWithPath: root))
        let runner = RuleTestRunner { command, context in
            // A helper may run the whole test suite: prevent recursive audits.
            let result = ShellRunner.run(command, in: context.root, environment: [
                "VIBEDECK_ROOT": context.root.path, "VIBEDECK_FILES": context.files.joined(separator: "\n"),
                "VIBEDECK_RULE_ID": context.ruleId.uuidString, "VIBEDECK_RULE_AUDIT_ROOT": "",
            ], timeout: 120, outputLimit: 4_000)
            return RuleTestOutcome(exitCode: result.status, output: result.output)
        }
        let runs = store.runRuleScripts(snapshot: try store.listTopics(), runner: runner, concurrency: concurrency)
        let records: [[String: Any]] = runs.map { run in [
            "topic": run.topic, "ruleId": run.rule.id.uuidString, "command": run.command,
            "severity": run.rule.severity.rawValue, "verdict": run.outcome.verdict.rawValue,
            "exitCode": run.outcome.exitCode, "output": run.outcome.output,
        ] }
        try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: output))
        #expect(!runs.isEmpty)
        for run in runs {
            #expect(run.outcome.verdict != .fail, "\(run.topic)/\(run.rule.id): \(run.outcome.output)")
        }
    }
}
