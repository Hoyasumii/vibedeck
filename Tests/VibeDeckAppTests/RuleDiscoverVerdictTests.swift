import Foundation
import Testing
@testable import VibeDeckApp

/// "Salvar avaliação" (RuleDiscoverVerdict.apply) aprova ideias elegíveis sem promovê-las.
/// Os dados são gravados pelo Core Rust; aqui só se cobre a decisão do status no app.
@Suite @MainActor struct RuleDiscoverVerdictTests {
    @Test func savedViableVerdictApprovesEligibleIdeas() {
        let now = Date(timeIntervalSince1970: 1234)
        for status in [IdeaStatus.new, .exploring, .approved] {
            var idea = Idea(title: "Avaliação")
            idea.status = status
            idea.rules = [Rule(text: "R")]
            let before = idea
            let verdict = RuleDiscoverVerdict(viable: true)
            _ = verdict.readiness(for: idea, now: now)
            #expect(idea == before) // Computing a verdict does not save it.
            verdict.apply(to: &idea, now: now)
            #expect(idea.status == .approved)
            #expect(idea.readiness == verdict.readiness(for: before, now: now))
            #expect(idea.promotedTopic == nil)
            #expect(idea.rules == before.rules)
        }
    }

    @Test func savedNonviableVerdictPreservesEveryStatus() {
        for status in IdeaStatus.allCases {
            var idea = Idea(title: "Avaliação")
            idea.status = status
            idea.rules = [Rule(text: "R")]
            idea.readiness = RuleDiscoverVerdict(viable: true).readiness(for: idea)
            RuleDiscoverVerdict(viable: false, missing: ["Qual tela?"]).apply(to: &idea)
            #expect(idea.status == status)
            #expect(idea.readiness?.viable == false)
            #expect(idea.readiness?.missing == ["Qual tela?"])
        }
    }

    @Test func savedVerdictWithoutRulesDoesNotApprove() {
        for status in IdeaStatus.allCases {
            var idea = Idea(title: "Sem regras")
            idea.status = status
            RuleDiscoverVerdict(viable: true).apply(to: &idea)
            #expect(idea.status == status)
            #expect(idea.readiness?.viable == false)
        }
    }

    @Test func savedViableVerdictPreservesClosedAndPromotedIdeas() {
        for status in IdeaStatus.allCases {
            for topic in [nil, "existente"] as [String?] {
                guard status.isClosed || topic != nil else { continue }
                var idea = Idea(title: "Preservada")
                idea.status = status
                idea.promotedTopic = topic
                idea.rules = [Rule(text: "R")]
                RuleDiscoverVerdict(viable: true).apply(to: &idea)
                #expect(idea.status == status)
                #expect(idea.promotedTopic == topic)
                #expect(idea.readiness?.viable == true)
            }
        }
    }

    /// Salvar a avaliação só altera a ideia recebida: não promove nem muda regras ou escopo.
    @Test func savedEvaluationDoesNotPromoteOrTouchRules() {
        var idea = Idea(title: "Avaliação")
        idea.rules = [Rule(text: "R")]
        idea.paths = ["Sources/**"]
        let before = idea
        RuleDiscoverVerdict(viable: true).apply(to: &idea)
        #expect(idea.status == .approved)
        #expect(idea.promotedTopic == nil)
        #expect(idea.rules == before.rules)
        #expect(idea.paths == before.paths)
        #expect(idea.readiness?.viable == true)
    }
}
