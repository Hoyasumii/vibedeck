import Foundation
import Testing
import VibeDeckCore
@testable import VibeDeckApp

@Suite @MainActor struct AIRecoveryTests {
    @Test func invalidAnswerGetsOneRecoveryWithoutChangingSettings() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? AIUsageStore(root: root).clear() }
        var prompts: [String] = [], settings: [AIProviderSettings] = []
        let result: Int = try await AIReadOnlyOperation.run(root: root, provider: .codex, operation: "Teste",
            prompt: "Preserve todos os requisitos", schema: "{}", request: { prompt, value in
                prompts.append(prompt); settings.append(value)
                return Data((prompts.count == 1 ? "invalid" : "42").utf8)
            }, parse: { try JSONDecoder().decode(Int.self, from: $0) })
        #expect(result == 42 && prompts.count == 2)
        #expect(prompts[1].contains("Preserve todos os requisitos"))
        #expect(settings[0] == settings[1])
        let records = try AIUsageStore(root: root).list()
        #expect(records.count == 2 && Set(records.map(\.taskID)).count == 1)
        #expect(Set(records.map(\.status)) == ["completed", "invalid-answer"])
    }

    @Test func persistentFailureStopsAndTransportErrorsDoNotRetry() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? AIUsageStore(root: root).clear() }
        var count = 0
        do {
            let _: Int = try await AIReadOnlyOperation.run(root: root, provider: .codex, operation: "Teste",
                prompt: "tarefa", schema: "{}", request: { _, _ in count += 1; return Data("invalid".utf8) },
                parse: { try JSONDecoder().decode(Int.self, from: $0) })
            Issue.record("Resposta inválida foi aceita")
        } catch { #expect(error.localizedDescription.contains("modelo mais capaz")) }
        #expect(count == 2)
        count = 0
        do {
            let _: Int = try await AIReadOnlyOperation.run(root: root, provider: .codex, operation: "Teste",
                prompt: "tarefa", schema: "{}", request: { _, _ in count += 1; throw CancellationError() },
                parse: { try JSONDecoder().decode(Int.self, from: $0) })
            Issue.record("Cancelamento ignorado")
        } catch { #expect(error is CancellationError) }
        #expect(count == 1)
    }

    @Test func generationChecksOnlySelectedRulesAndRejectsChangedRequirements() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ProjectStore.initialize(at: root)
        let (slug, selected) = try store.addRule(Rule(text: "Requer julgamento"), toTopic: "Geral")
        _ = try store.addRule(Rule(text: "Fora da seleção"), toTopic: slug)
        try store.setRuleTest(selected.id.uuidString, mode: .manual, reason: "Requer evidência humana")
        try RuleTestGenerator.validateGeneration(root: root, topic: slug, expected: [selected])
        var changed = try store.loadTopic(slug)
        changed.rules[0].text = "Requisito enfraquecido"
        try store.saveTopic(changed, slug: slug)
        #expect(throws: (any Error).self) { try RuleTestGenerator.validateGeneration(root: root, topic: slug, expected: [selected]) }
    }
}
