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

extension IdeaEvaluationTests {
    @Test func implementationChoiceAndCancellationHaveNoProjectEffects() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "idea-choice-\(UUID())")
        let store = try ProjectStore.initialize(at: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let (slug, _) = try store.createIdea(title: "Escolha")
        try store.updateIdea(slug) { $0.rules = [Rule(text: "R")]; RuleDiscoverVerdict(viable: true).apply(to: &$0) }
        let idea = try store.loadIdea(slug)
        let session = AISession(root: root, projectId: try store.loadProject().id)
        session.requestIdeaImplementation(idea)
        #expect(session.ideaRequest?.ideaID == idea.id)
        #expect(!session.isWorking)
        #expect(session.entries.isEmpty)
        session.ideaRequest = nil
        #expect(try store.loadIdea(slug) == idea)
        #expect(try store.listTopics().isEmpty)
        #expect(try store.listRuns().isEmpty)
    }

    @Test func standardImplementationUsesSharedPromptAndUndoesPromotion() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "idea-standard-\(UUID())")
        let store = try ProjectStore.initialize(at: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let (slug, _) = try store.createIdea(title: "Padrão")
        try store.updateIdea(slug) { $0.rules = [Rule(text: "R")]; RuleDiscoverVerdict(viable: true).apply(to: &$0) }
        let idea = try store.loadIdea(slug)
        let model = ProjectModel(store: store)
        let undo = UndoManager(); undo.groupsByEvent = false
        undo.beginUndoGrouping()
        let prepared = try model.prepareIdeaImplementation(idea.id, provider: .codex, undo: undo)
        undo.endUndoGrouping()
        let saved = try store.loadIdea(slug)
        #expect(prepared.prompt == IdeaImplementation.prompt(slug: slug, idea: idea, topic: saved.promotedTopic))
        #expect(prepared.execution == nil)
        #expect(try store.listRuns().isEmpty)
        #expect(try store.listTopics().count == 1)
        undo.undo()
        #expect(try store.loadIdea(slug) == idea)
        #expect(try store.listTopics().isEmpty)
        undo.redo()
        #expect(try store.loadIdea(slug) == saved)
        #expect(try store.listTopics().count == 1)
    }

    @Test func confirmationReadsDiskEvenBeforeWatcherDeliversExternalEdit() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "idea-external-\(UUID())")
        let store = try ProjectStore.initialize(at: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let (slug, _) = try store.createIdea(title: "Atual")
        try store.updateIdea(slug) { $0.rules = [Rule(text: "R")]; RuleDiscoverVerdict(viable: true).apply(to: &$0) }
        let model = ProjectModel(store: store)
        let id = try model.currentImplementationIdea(try store.loadIdea(slug).id).idea.id
        try store.updateIdea(slug) { $0.body = "Edição externa" }
        #expect(throws: VibeDeckError.self) {
            try model.prepareIdeaImplementation(id, provider: .codex, undo: nil)
        }
        #expect(try store.listTopics().isEmpty)
        #expect(try store.listRuns().isEmpty)
    }
}


extension IdeaEvaluationTests {
    @Test func failedWorkflowCreationRollsBackPromotionWithoutCreatingUndo() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "idea-rollback-\(UUID())")
        let store = try ProjectStore.initialize(at: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let (slug, _) = try store.createIdea(title: "Rollback")
        try store.updateIdea(slug) { $0.rules = [Rule(text: "R")]; RuleDiscoverVerdict(viable: true).apply(to: &$0) }
        try store.createCommand(title: "Etapa")
        try store.createWorkflow(title: "Fluxo")
        try store.addWorkflowStep(to: "fluxo", kind: .command, target: "etapa")
        let idea = try store.loadIdea(slug)
        let blocked = store.runDir(workflow: "fluxo", run: Slug.make(IdeaImplementation.workflowInput(idea)))
        try FileManager.default.createDirectory(at: blocked.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("bloqueado".utf8).write(to: blocked)
        let model = ProjectModel(store: store)
        let undo = UndoManager(); undo.groupsByEvent = false
        undo.beginUndoGrouping()
        #expect(throws: (any Error).self) {
            try model.prepareIdeaImplementation(idea.id, workflow: "fluxo", provider: .codex, undo: undo)
        }
        undo.endUndoGrouping()
        #expect(try store.loadIdea(slug) == idea)
        #expect(try store.listTopics().isEmpty)
        #expect(try store.listRuns().isEmpty)
        // Foundation keeps empty groups on the stack; undoing that group must have no effects.
        #expect(undo.undoActionName.isEmpty)
        undo.undo()
        #expect(try store.loadIdea(slug) == idea)
        #expect(try store.listTopics().isEmpty)
        #expect(!undo.canUndo)
    }
}
