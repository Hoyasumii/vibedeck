import Foundation
import SwiftUI
import Testing
@testable import VibeDeckCore
@testable import VibeDeckApp

@Suite @MainActor
struct IdeaEvaluationTests {
    @Test func savedEvaluationUndoesStatusAndReadinessTogether() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "idea-evaluation-\(UUID())")
        let store = try ProjectStore.initialize(at: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let (slug, _) = try store.createIdea(title: "Avaliação")
        try store.updateIdea(slug) { $0.status = .exploring; $0.rules = [Rule(text: "R")] }
        let model = ProjectModel(store: store)
        let before = try store.loadIdea(slug)
        let undo = UndoManager()
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        model.mutateIdea(slug, "Verificar: avaliação", undo: undo) {
            RuleDiscoverVerdict(viable: true).apply(to: &$0)
        }
        undo.endUndoGrouping()
        let saved = try store.loadIdea(slug)
        #expect(saved.status == .approved)
        #expect(saved.readiness?.viable == true)
        #expect(saved.promotedTopic == nil)
        #expect(undo.undoActionName == "Verificar: avaliação")
        undo.undo()
        #expect(model.idea(slug) == before)
        #expect(try store.loadIdea(slug) == before)
        #expect(!undo.canUndo)
        undo.redo()
        #expect(try store.loadIdea(slug) == saved)
    }
}

extension IdeaEvaluationTests {
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
