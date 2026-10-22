import Foundation
import Testing
@testable import VibeDeckApp

@Suite @MainActor struct IdeaVerdictTests {
    @Test func staleNegativeVerdictCanBeReassessedAndCompletedAnswerCannotFollowEdits() {
        var idea = Idea(title: "Agrupar")
        idea.rules = [Rule(text: "Organizar itens")]
        RuleDiscoverVerdict(viable: false, missing: ["Escolher formato"]).apply(to: &idea)
        idea.body = "Formato escolhido pelo usuário."
        #expect(idea.implementBlocker?.contains("mudou") == true)
        #expect(idea.canRequestImplementation)
        let runner = RuleDiscoverRunner()
        runner.complete(.verdict(.init(viable: true)), for: .init(idea: idea))
        idea.body = "Especificação alterada depois de receber a resposta."
        runner.subjectChanged(.init(idea: idea))
        guard case .failed(let message) = runner.state else { Issue.record("A avaliação antiga continuou disponível"); return }
        #expect(message.contains("conteúdo mudou"))
        RuleDiscoverVerdict(viable: true).apply(to: &idea)
        #expect(idea.implementBlocker == nil)
        idea.status = .done
        #expect(!idea.canRequestImplementation)
    }
}
