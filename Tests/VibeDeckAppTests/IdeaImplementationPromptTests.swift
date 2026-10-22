import Foundation
import Testing
@testable import VibeDeckApp

@Suite struct IdeaImplementationPromptTests {
    @Test func promptWithPromotedTopicPointsToTheTopicRules() {
        let idea = Idea(title: "Agrupar itens")
        let prompt = IdeaImplementation.prompt(slug: "agrupar-itens", idea: idea, topic: "agrupar-itens")
        #expect(prompt.contains("Implemente a ideia \"Agrupar itens\""))
        #expect(prompt.contains("get_idea (\"agrupar-itens\")"))
        #expect(prompt.contains("tópico \"agrupar-itens\" (get_rule_topic)"))
        #expect(!prompt.contains("regras rascunho"))
    }

    @Test func promptWithoutTopicPointsToTheDraftRules() {
        let idea = Idea(title: "Agrupar itens")
        let prompt = IdeaImplementation.prompt(slug: "agrupar-itens", idea: idea, topic: nil)
        #expect(prompt.contains("Implemente a ideia \"Agrupar itens\""))
        #expect(prompt.contains("get_idea (\"agrupar-itens\")"))
        #expect(prompt.contains("Siga as regras rascunho da ideia."))
        #expect(!prompt.contains("get_rule_topic"))
    }
}
