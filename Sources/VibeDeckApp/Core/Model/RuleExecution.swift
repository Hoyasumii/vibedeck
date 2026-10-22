import Foundation

enum RuleScriptEvent: Sendable {
    case started(topic: String, rule: Rule, at: Date)
    case finished(RuleTestRun, at: Date)
}

enum RuleExecutionError: LocalizedError {
    case changed, incomplete, invalidAnswer
    var errorDescription: String? {
        switch self {
        case .changed: "As regras mudaram durante a execução. Execute novamente para salvar a verificação."
        case .incomplete: "A verificação está incompleta e não foi salva."
        case .invalidAnswer: "A IA não retornou um resultado válido para cada regra."
        }
    }
}

/// Strict structured answers: omissions, duplicates and unexpected rules are errors, never passes.
enum RuleVerificationAnswer {
    struct Answer: Decodable, Sendable {
        struct Entry: Decodable, Sendable {
            var ruleId: UUID
            var verdict: RuleVerdict
            var note: String
        }
        var results: [Entry]
    }
    static let schema = #"""
    {"type":"object","additionalProperties":false,"properties":{"results":{"type":"array","items":{"type":"object","additionalProperties":false,"properties":{"ruleId":{"type":"string"},"verdict":{"type":"string","enum":["pass","fail","na"]},"note":{"type":"string"}},"required":["ruleId","verdict","note"]}}},"required":["results"]}
    """#

    static func parse(_ data: Data, rules: [Rule], topic: String) throws -> [RuleResult] {
        guard let answer = try? VDJSON.decoder.decode(Answer.self, from: data),
              answer.results.count == rules.count,
              Set(answer.results.map(\.ruleId)) == Set(rules.map(\.id)),
              answer.results.allSatisfy({ !$0.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw RuleExecutionError.invalidAnswer
        }
        return answer.results.map { RuleResult(topic: topic, ruleId: $0.ruleId, verdict: $0.verdict, note: $0.note) }
    }
}

/// Bounded timing history; callers persist it outside the repository.
struct RuleExecutionTimings: Codable, Sendable {
    var samples: [String: [TimeInterval]] = [:]
    init() {}
    mutating func record(_ duration: TimeInterval, key: String) {
        guard duration.isFinite, duration >= 0 else { return }
        samples[key] = Array(((samples[key] ?? []) + [duration]).suffix(10))
    }
    func estimate(key: String, category: String) -> TimeInterval? {
        let exact = samples[key] ?? []
        let values = (exact.isEmpty ? samples.filter { $0.key.hasPrefix(category + ":") }.flatMap(\.value) : exact).sorted()
        guard !values.isEmpty else { return nil }
        let middle = values.count / 2
        return values.count.isMultiple(of: 2) ? (values[middle - 1] + values[middle]) / 2 : values[middle]
    }
}
