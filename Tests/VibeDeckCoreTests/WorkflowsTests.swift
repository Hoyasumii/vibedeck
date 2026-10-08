import Foundation
import Testing
@testable import VibeDeckCore

@Suite struct WorkflowsTests {
    private func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "vd-workflows-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func crudAndResolve() throws {
        let store = try ProjectStore.initialize(at: tempDir())
        let (slug, wf) = try store.createWorkflow(title: "Revisão de PR", summary: "Revisa até passar", input: "<número do PR>", author: .ai)
        #expect(slug == "revisao-de-pr")
        #expect(wf.author == .ai && wf.schema == SchemaURL.workflow)
        #expect(try store.resolveWorkflowSlug(String(wf.id.uuidString.prefix(6))) == slug)
        #expect(try store.resolveWorkflowSlug("Revisão de PR") == slug)
        try store.updateWorkflow(slug) { $0.maxSteps = 10 }
        #expect(try store.loadWorkflow(slug).maxSteps == 10)
        #expect(try store.listWorkflows().count == 1)
        try store.deleteWorkflow(slug)
        #expect(throws: VibeDeckError.workflowNotFound(slug)) { try store.loadWorkflow(slug) }
    }

    @Test func lenientDecodeAndOmitEmpty() throws {
        let store = try ProjectStore.initialize(at: tempDir())
        try Data(#"{"title":"Mínimo","steps":[{"ref":"revisor","transitions":[{"when":"  ","to":"revisor"}]}]}"#.utf8)
            .write(to: store.workflowURL("minimo"))
        let w = try store.loadWorkflow("minimo")
        #expect(w.author == .human && w.maxSteps == nil && w.summary == nil)
        #expect(w.steps == [WorkflowStep(id: "revisor", kind: .agent, ref: "revisor", transitions: [WorkflowTransition(to: "revisor")])])
        let text = String(decoding: try VDJSON.encode(Workflow(title: "Vazio")), as: UTF8.self)
        #expect(!text.contains("steps") && !text.contains("tags") && !text.contains("maxSteps") && !text.contains("input"))
    }

    @Test func stepsValidateAndGetUniqueIds() throws {
        let store = try ProjectStore.initialize(at: tempDir())
        let w = try store.createWorkflow(title: "Fluxo").slug
        let a = try store.createAgent(title: "Revisor").slug
        let c = try store.createCommand(title: "Commit").slug
        #expect(try store.addWorkflowStep(to: w, target: a).step == "revisor")
        #expect(try store.addWorkflowStep(to: w, target: "Revisor").step == "revisor-2")  // same agent twice
        #expect(try store.addWorkflowStep(to: w, kind: .command, target: c, note: "  feat: x ").step == "commit")
        #expect(try store.loadWorkflow(w).steps.last == WorkflowStep(id: "commit", kind: .command, ref: c, note: "feat: x"))
        #expect(throws: VibeDeckError.skillNotFound("nao-existe")) { try store.addWorkflowStep(to: w, kind: .skill, target: "nao-existe") }
        try store.moveWorkflowStep(w, step: "commit", to: 1)
        #expect(try store.loadWorkflow(w).steps.map(\.id) == ["commit", "revisor", "revisor-2"])
    }

    @Test func transitionsAllowLoopsAndKeepFallbackLast() throws {
        let store = try ProjectStore.initialize(at: tempDir())
        let w = try store.createWorkflow(title: "Fluxo").slug
        let a = try store.createAgent(title: "Autor").slug
        let r = try store.createAgent(title: "Revisor").slug
        try store.addWorkflowStep(to: w, target: a)
        try store.addWorkflowStep(to: w, target: r)
        try store.addWorkflowTransition(w, from: "autor", to: "revisor")
        try store.addWorkflowTransition(w, from: "revisor", to: "autor", when: "encontrou problemas")  // back: loop
        try store.addWorkflowTransition(w, from: "revisor", to: "2")  // fallback by position
        try store.addWorkflowTransition(w, from: "revisor", to: "autor", when: "faltam testes")
        let review = try store.loadWorkflow(w).steps[1]
        #expect(review.transitions.map(\.when) == ["encontrou problemas", "faltam testes", nil])
        #expect(throws: VibeDeckError.self) { try store.addWorkflowTransition(w, from: "revisor", to: "autor") }  // 2nd fallback
        #expect(throws: VibeDeckError.self) { try store.addWorkflowTransition(w, from: "revisor", to: "nao-existe") }
        try store.removeWorkflowTransition(w, from: "revisor", index: 2)
        #expect(try store.loadWorkflow(w).steps[1].transitions.count == 2)
        #expect(throws: VibeDeckError.self) { try store.removeWorkflowTransition(w, from: "revisor", index: 5) }
        // Removing a step drops the transitions that point to it.
        try store.removeWorkflowStep(w, step: "autor")
        let left = try store.loadWorkflow(w).steps
        #expect(left.map(\.id) == ["revisor"] && left[0].transitions == [WorkflowTransition(to: "revisor")])
    }

    @Test func planResolvesNodesAndWarns() throws {
        let store = try ProjectStore.initialize(at: tempDir())
        let a = try store.createAgent(title: "Revisor", model: "opus", prompt: "Revise.").slug
        let c = try store.createCommand(title: "Commit", argumentHint: "<mensagem>", prompt: "Commite $ARGUMENTS").slug
        try store.addNextStep(to: a, kind: .command, target: c)  // ignored by workflows
        let w = try store.createWorkflow(title: "Fluxo", input: "<PR>").slug
        try store.addWorkflowStep(to: w, target: a)
        try store.addWorkflowStep(to: w, kind: .command, target: c)
        try store.addWorkflowTransition(w, from: "revisor", to: "commit", when: "aprovado")
        try store.updateWorkflow(w) {
            $0.steps.append(WorkflowStep(id: "sumiu", kind: .skill, ref: "sumiu", transitions: [WorkflowTransition(to: "fantasma")]))
        }
        let plan = try store.workflowPlan(w, input: "PR 12")
        #expect(plan.start == "revisor" && plan.input == "PR 12" && plan.maxSteps == Workflow.defaultMaxSteps)
        #expect(plan.steps[0].title == "Revisor" && plan.steps[0].model == "opus" && plan.steps[0].prompt == "Revise.")
        #expect(plan.steps[1].argumentHint == "<mensagem>" && plan.steps[1].transitions == nil)
        #expect(plan.steps[2].warnings == ["Skill não encontrada: sumiu", "Transição para etapa inexistente: fantasma"])
        #expect(plan.allWarnings.count == 2 && plan.warnings == nil)
        #expect(plan.inputHint == "<PR>")
        #expect(try store.workflowPlan(w).input == nil)
        let json = try plan.json()
        #expect(json.contains("\"start\" : \"revisor\"") && !json.contains("\"nextSteps\" :"))
        #expect(try plan.prompt().contains("Execute o workflow \"Fluxo\""))
        let empty = WorkflowPlan.build(slug: "x", workflow: Workflow(title: "X"), agents: [])
        #expect(empty.start == nil && empty.warnings == ["O workflow não tem etapas."])
    }
}
