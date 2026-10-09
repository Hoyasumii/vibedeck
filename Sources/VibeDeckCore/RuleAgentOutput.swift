import Foundation

// What `rules_for` and `submit_rule_check` hand to an agent. Both are paid on every task, so the default
// is compact; the full forms stay one parameter (`verbose`) or one file away.

extension RuleCheck {
    /// Published path of this check, relative to the project root.
    public var relativePath: String { ".vibedeck/checks/\(ProjectStore.checkFileName(self))" }

    /// Verdict, every failure and warning, the failing script output and where the full check lives.
    /// Passing notes are left out: they're in the file. `verbose` appends the full JSON (the old answer).
    public func agentSummary(verbose: Bool = false) throws -> String {
        var summary = passed
            ? "✅ Check aprovado (\(results.count) regra(s))."
            : "❌ Check reprovado. Corrija e envie um novo check antes de concluir:\n" + failures.map { "- \($0)" }.joined(separator: "\n")
        if !warnings.isEmpty {
            summary += "\n⚠️ Recomendações não cumpridas (avise o usuário):\n" + warnings.map { "- \($0)" }.joined(separator: "\n")
        }
        if !pending.isEmpty {
            summary += "\n⏭️ \(pending.count) regra(s) manual(is) não verificada(s) (peça verify_manual=true para checá-las): "
                + pending.prefix(5).joined(separator: "; ") + (pending.count > 5 ? "; …" : "")
        }
        let scripted = results.filter { $0.source == .script }
        if !scripted.isEmpty {
            summary += "\n⚙️ \(scripted.count) regra(s) decidida(s) por script."
            for r in scripted where r.verdict == .fail { summary += "\n--- script reprovado:\n\(r.note ?? "")" }
        }
        summary += "\nCheck \(id.uuidString.prefix(8).lowercased()): \(relativePath)"
        guard verbose else { return summary }
        return summary + "\n" + String(decoding: try VDJSON.encoder.encode(self), as: UTF8.self)
    }
}

/// A topic's rules as an agent checklist (`rules_for`, `get_rule_topic`, `vibedeck rules … --json`).
public struct TopicChecklist: Encodable {
    public let slug: String
    public let title: String
    public let description: String?
    public let paths: [String]?
    public let rules: [RuleRow]
    /// Manual rules left out of `rules` (see `includeManual`).
    public let manualRules: Int?

    public struct RuleRow: Encodable {
        public let ruleId: String
        public let text: String
        public let details: String?
        public let severity: RuleSeverity
        /// "script": decided by running `test` in submit_rule_check; "manual": the agent answers it.
        public let check: String
        public let test: String?
        /// The rule changed since its test was written: answer it manually and regenerate the test.
        public let staleTest: Bool?
    }

    /// Without `includeManual` only script rules are listed, without `details` (the cheap flow: a script decides
    /// them); the rest comes as a count. `idLength` shortens rule ids (`compact`).
    public init(slug: String, topic: RuleTopic, includeManual: Bool = true) {
        self.init(slug: slug, topic: topic, includeManual: includeManual, compact: false, idLength: 36)
    }

    /// `compact` drops what an agent doesn't need to act: topic description and paths, and script paths
    /// (submit_rule_check runs them itself).
    private init(slug: String, topic: RuleTopic, includeManual: Bool, compact: Bool, idLength: Int) {
        self.slug = slug
        title = topic.title
        description = compact ? nil : topic.description
        paths = compact ? nil : topic.paths
        let listed = topic.rules.filter { includeManual || $0.testState == .script }
        manualRules = listed.count < topic.rules.count ? topic.rules.count - listed.count : nil
        rules = listed.map {
            RuleRow(ruleId: String($0.id.uuidString.prefix(idLength)), text: $0.text, details: includeManual ? $0.details : nil,
                    severity: $0.severity, check: $0.testState == .script ? "script" : "manual",
                    test: compact ? nil : $0.scriptCommand, staleTest: $0.testState == .stale ? true : nil)
        }
    }

    /// `rules_for`'s default answer. Rule ids are 8-character prefixes (submit_rule_check resolves prefixes), or
    /// full ids if two rules of the answer would share one.
    public static func compact(_ topics: [(slug: String, topic: RuleTopic)], includeManual: Bool) -> [TopicChecklist] {
        let prefixes = topics.flatMap { $0.topic.rules.map { $0.id.uuidString.prefix(8) } }
        let idLength = Set(prefixes).count == prefixes.count ? 8 : 36
        return topics.map { TopicChecklist(slug: $0.slug, topic: $0.topic, includeManual: includeManual, compact: true, idLength: idLength) }
    }

    /// Single-line JSON: indentation is pure token cost for an agent.
    public static func compactJSON(_ checklists: [TopicChecklist]) throws -> String {
        String(decoding: try VDJSON.compactEncoder.encode(checklists), as: UTF8.self)
    }
}
