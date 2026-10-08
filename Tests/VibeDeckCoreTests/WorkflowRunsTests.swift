import Foundation
import Testing
@testable import VibeDeckCore

@Suite struct WorkflowRunsTests {
    private func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "vd-runs-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// planejar → criticar (APROVADO → implementar, REPROVADO → planejar) → implementar (fim).
    private func cycleStore(maxVisits: Int? = nil) throws -> ProjectStore {
        let store = try ProjectStore.initialize(at: tempDir())
        try store.createCommand(title: "Planejar")
        try store.updateCommand("planejar") { $0.prompt = "Planeje $ARGUMENTS em $RUN_DIR/plano.md"; $0.model = "opus" }
        try store.createAgent(title: "Critico")
        try store.createCommand(title: "Implementar")
        try store.createWorkflow(title: "Ciclo", input: "<issue>")
        try store.addWorkflowStep(to: "ciclo", kind: .command, target: "planejar")
        try store.addWorkflowStep(to: "ciclo", target: "critico")
        try store.addWorkflowStep(to: "ciclo", kind: .command, target: "implementar")
        try store.addWorkflowTransition("ciclo", from: "planejar", to: "critico")
        try store.addWorkflowTransition("ciclo", from: "critico", to: "implementar", verdict: "APROVADO")
        try store.addWorkflowTransition("ciclo", from: "critico", to: "planejar", verdict: "REPROVADO")
        if let maxVisits { try store.setWorkflowStepMaxVisits("ciclo", step: "critico", maxVisits: maxVisits) }
        return store
    }

    @Test func verdictMatchingIgnoresCaseAccentsAndMarkup() {
        let t = WorkflowTransition(verdict: "VIÁVEL", to: "x")
        #expect(t.matches(verdict: "viavel"))
        #expect(t.matches(verdict: " `VIÁVEL`. "))
        #expect(!t.matches(verdict: "INVIÁVEL"))
        #expect(!WorkflowTransition(when: "ok", to: "x").matches(verdict: "ok"))
        #expect(WorkflowTransition(to: "x").isFallback && !t.isFallback)
    }

    @Test func fallbackStaysLastWithVerdicts() throws {
        let store = try cycleStore()
        try store.addWorkflowTransition("ciclo", from: "critico", to: "planejar")  // senão
        try store.addWorkflowTransition("ciclo", from: "critico", to: "implementar", verdict: "PARCIAL")
        let t = try store.loadWorkflow("ciclo").steps[1].transitions
        #expect(t.map(\.label) == ["= APROVADO", "= REPROVADO", "= PARCIAL", "senão"])
        #expect(throws: VibeDeckError.self) { try store.addWorkflowTransition("ciclo", from: "critico", to: "implementar") }
    }

    @Test func runFollowsVerdictsToTheEnd() throws {
        let store = try cycleStore()
        let started = try store.startRun("ciclo", input: "#12")
        #expect(started.ref == "ciclo/12")
        #expect(started.action.action == .runStep && started.action.step == "planejar" && started.action.model == "opus")
        #expect(try store.recordRun("ciclo/12", verdict: "PLANO", summary: "plano 001").step == "critico")
        #expect(try store.recordRun("12", verdict: "reprovado", summary: nil).step == "planejar")  // loop back
        try store.recordRun("ciclo/12", verdict: "PLANO", summary: nil)
        #expect(try store.recordRun("ciclo/12", verdict: "APROVADO", summary: nil).step == "implementar")
        let end = try store.recordRun("ciclo/12", verdict: "IMPLEMENTADO", summary: nil)
        #expect(end.action == .done)
        let run = try store.loadRun("ciclo/12")
        #expect(run.status == .done && run.current == nil)
        #expect(run.history.map(\.step) == ["planejar", "critico", "planejar", "critico", "implementar"])
        #expect(run.history.map(\.next) == ["critico", "planejar", "critico", "implementar", nil])
        #expect(throws: VibeDeckError.self) { try store.recordRun("ciclo/12", verdict: "X", summary: nil) }
    }

    @Test func stepPromptResolvesArgumentsRunDirAndProtocol() throws {
        let store = try cycleStore()
        try store.startRun("ciclo", input: "#7")
        let prompt = try store.runStepPrompt("ciclo/7", cli: "/x/vibedeck")
        let dir = store.runDir(workflow: "ciclo", run: "7").path
        #expect(prompt.contains("Planeje #7 em \(dir)/plano.md"))
        #expect(prompt.contains("/x/vibedeck runs ask ciclo/7"))
        #expect(prompt.contains("`PERGUNTA`"))
        try store.recordRun("ciclo/7", verdict: "PLANO", summary: nil)
        let critico = try store.runStepPrompt("ciclo/7")
        #expect(critico.contains("`APROVADO`, `REPROVADO`"))
        #expect(critico.contains("`planejar` → PLANO"))
    }

    @Test func maxVisitsStopsAndRestartOpensNewCycle() throws {
        let store = try cycleStore(maxVisits: 2)
        try store.startRun("ciclo", input: "a")
        for _ in 0..<2 {
            try store.recordRun("ciclo/a", verdict: "PLANO", summary: nil)
            try store.recordRun("ciclo/a", verdict: "REPROVADO", summary: nil)
        }
        let action = try store.recordRun("ciclo/a", verdict: "PLANO", summary: nil)
        #expect(action.action == .stop && action.reason.contains("maxVisits"))
        // Starting again with the same input resumes the run in a new cycle, from the chosen step.
        let again = try store.startRun("ciclo", input: "a", from: "critico")
        #expect(again.ref == "ciclo/a" && again.action.step == "critico" && again.run.cycle == 2)
        #expect(try store.recordRun("ciclo/a", verdict: "APROVADO", summary: nil).step == "implementar")
    }

    @Test func maxStepsAndNoProgressGuards() throws {
        let store = try ProjectStore.initialize(at: tempDir())
        try store.createAgent(title: "Loop")
        try store.createWorkflow(title: "Laço", maxSteps: 3)
        try store.addWorkflowStep(to: "laco", target: "loop")
        try store.addWorkflowTransition("laco", from: "loop", to: "loop")
        try store.startRun("laco", input: "x")
        #expect(try store.recordRun("laco/x", verdict: "A", summary: nil).action == .runStep)
        let same = try store.recordRun("laco/x", verdict: "a", summary: nil)
        #expect(same.action == .stop && same.reason.contains("não andou"))

        try store.startRun("laco", input: "y")
        try store.recordRun("laco/y", verdict: "1", summary: nil)
        try store.recordRun("laco/y", verdict: "2", summary: nil)
        #expect(try store.recordRun("laco/y", verdict: "3", summary: nil).reason.contains("maxSteps"))
    }

    @Test func conditionsNeedTheOrchestratorToDecide() throws {
        let store = try ProjectStore.initialize(at: tempDir())
        try store.createAgent(title: "A")
        try store.createAgent(title: "B")
        try store.createWorkflow(title: "W")
        try store.addWorkflowStep(to: "w", target: "a")
        try store.addWorkflowStep(to: "w", target: "b")
        try store.addWorkflowTransition("w", from: "a", to: "b", when: "achou problemas")
        try store.startRun("w", input: "i")
        let decide = try store.recordRun("w/i", verdict: "OK", summary: nil)
        #expect(decide.action == .decide && decide.candidates?.first?.when == "achou problemas" && decide.verdict == "OK")
        #expect(try store.loadRun("w/i").history.isEmpty)  // nothing recorded yet
        #expect(throws: VibeDeckError.self) { try store.recordRun("w/i", verdict: "OK", summary: nil, to: "a") }  // no such transition
        #expect(try store.recordRun("w/i", verdict: "OK", summary: nil, to: "b").step == "b")
        try store.startRun("w", input: "j")
        #expect(try store.recordRun("w/j", verdict: "OK", summary: nil, noneHolds: true).action == .done)
    }

    @Test func questionsBlockUntilAnswered() throws {
        let store = try cycleStore()
        try store.startRun("ciclo", input: "q")
        let asked = try store.askRun("ciclo/q", questions: [
            WorkflowQuestionDraft(question: "Qual base?", options: [WorkflowQuestionOption(label: "main"), WorkflowQuestionOption(label: "dev")]),
            WorkflowQuestionDraft(question: "  "),
        ])
        #expect(asked.map(\.number) == [1] && asked[0].step == "planejar")
        let ask = try store.nextRunAction("ciclo/q")
        #expect(ask.action == .ask && ask.questions?.count == 1)
        #expect(try store.loadRun("ciclo/q").status == .waiting)
        #expect(throws: VibeDeckError.self) { try store.recordRun("ciclo/q", verdict: "PLANO", summary: nil) }
        let after = try store.answerRun("ciclo/q", number: 1, answer: "main")
        #expect(after.action == .runStep && after.step == "planejar")
        #expect(try store.runStepPrompt("ciclo/q").contains("**Qual base?** → main"))
    }

    @Test func listResolveStopAndRoundTrip() throws {
        let store = try cycleStore()
        try store.startRun("ciclo", input: "um")
        let second = try store.startRun("ciclo").ref
        #expect(second.hasPrefix("ciclo/execucao-"))
        #expect(try store.listRuns().count == 2 && store.listRuns(workflow: "Ciclo").count == 2)
        let run = try store.loadRun("ciclo/um")
        #expect(try store.resolveRunRef(String(run.id.uuidString.prefix(6))) == "ciclo/um")
        #expect(throws: VibeDeckError.runNotFound("nada")) { try store.resolveRunRef("nada") }
        #expect(try store.stopRun("um", reason: nil).status == .stopped)
        #expect(try store.nextRunAction("um").action == .stop)
        let decoded = try VDJSON.decoder.decode(WorkflowRun.self, from: VDJSON.encode(try store.loadRun("ciclo/um")))
        #expect(decoded == (try store.loadRun("ciclo/um")))
        try store.deleteRun("ciclo/um")
        #expect(try store.listRuns().count == 1)
    }

    @Test func lenientHandWrittenRunAndOmitEmpty() throws {
        let store = try cycleStore()
        let url = store.runURL("ciclo/manual")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"workflow":"ciclo","current":"critico","history":[{"step":"planejar","verdict":" PLANO "}]}"#.utf8).write(to: url)
        let run = try store.loadRun("ciclo/manual")
        #expect(run.status == .running && run.cycle == 1 && run.history == [WorkflowRunEntry(step: "planejar", verdict: "PLANO", cycle: 1, at: run.history[0].at)])
        #expect(try store.recordRun("manual", verdict: "APROVADO", summary: nil).step == "implementar")
        let text = String(decoding: try VDJSON.encode(WorkflowRun(workflow: "w", input: nil, start: "a")), as: UTF8.self)
        #expect(!text.contains("history") && !text.contains("questions") && !text.contains("input") && !text.contains("reason"))
    }
}
