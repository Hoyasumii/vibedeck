import Foundation

/// A durable result separates completing a step from judging its conditional transitions.
public struct WorkflowStepCheckpoint: Codable, Equatable, Sendable {
    public var step: String
    public var verdict: String?
    public var output: String
    public var completed: Bool
    public init(step: String, verdict: String? = nil, output: String, completed: Bool) {
        self.step = step; self.verdict = verdict; self.output = output; self.completed = completed
    }
}

/// Both providers execute the same persisted state machine. The host supplies only AI calls and UI events.
@MainActor public enum AIWorkflowRunner {
    public typealias Execute = (String, AIProviderSettings, String) async throws -> String
    public typealias Decide = (String, [WorkflowTransition]) async throws -> String?

    public static func run(ref: String, store: ProjectStore, cli: String = "vibedeck",
                           settings: (String) throws -> AIProviderSettings,
                           execute: Execute, decide: Decide,
                           onAction: (WorkflowRunAction) -> Void = { _ in }) async throws -> WorkflowRunAction {
        while true {
            try Task.checkCancellation()
            let action = try store.nextRunAction(ref)
            onAction(action)
            switch action.action {
            case .done, .stop, .ask: return action
            case .runStep:
                let snapshot = try store.loadRun(ref)
                guard let step = action.step else { throw AIIntegrationError.invalidTransition }
                let checkpoint: WorkflowStepCheckpoint
                if let existing = snapshot.checkpoint, existing.step == step, existing.completed {
                    checkpoint = existing
                } else {
                    var prompt = try store.runStepPrompt(ref, cli: cli)
                    if let partial = snapshot.checkpoint, partial.step == step {
                        prompt += "\nEsta etapa foi interrompida. Consulte a saída parcial e o estado atual antes de continuar; não repita alterações já efetuadas.\n" + partial.output
                    }
                    let output = try await execute(prompt, settings(ref), action.title ?? step)
                    try Task.checkCancellation()
                    let current = try store.loadRun(ref)
                    guard !current.isFinished, current.current == step else { return try store.nextRunAction(ref) }
                    let verdict = output.split(whereSeparator: \.isNewline).last.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    guard !verdict.isEmpty else { throw VibeDeckError.invalidWorkflow("A etapa terminou sem veredito.") }
                    if verdict == "PERGUNTA" {
                        guard !current.openQuestions.isEmpty else { throw VibeDeckError.invalidWorkflow("A etapa retornou PERGUNTA sem registrar perguntas.") }
                        continue
                    }
                    checkpoint = .init(step: step, verdict: verdict, output: try store.saveRunOutput(ref, output: output), completed: true)
                    try store.checkpointRun(ref, checkpoint: checkpoint)
                }
                let next = try store.recordRun(ref, verdict: checkpoint.verdict, summary: checkpoint.output)
                if next.action == .decide {
                    let candidates = next.candidates ?? []
                    let target = try await decide(checkpoint.output, candidates)
                    try Task.checkCancellation()
                    let current = try store.loadRun(ref)
                    guard !current.isFinished, current.current == step else { return try store.nextRunAction(ref) }
                    if let target, !candidates.contains(where: { $0.to == target }) { throw AIIntegrationError.invalidTransition }
                    _ = try store.recordRun(ref, verdict: checkpoint.verdict, summary: checkpoint.output, to: target, noneHolds: target == nil)
                }
            case .decide: throw AIIntegrationError.invalidTransition
            }
        }
    }
}

extension ProjectStore {
    public func checkpointRun(_ ref: String, checkpoint: WorkflowStepCheckpoint) throws {
        var run = try loadRun(ref)
        guard run.current == checkpoint.step, !run.isFinished else { throw AIIntegrationError.invalidTransition }
        run.checkpoint = checkpoint; run.updatedAt = .now
        try saveRun(run, ref: ref)
    }
    /// Explicit resume retains the current step, history, user answers and guard counters.
    public func resumeRun(_ ref: String) throws -> WorkflowRun {
        var run = try loadRun(ref)
        if run.status == .stopped, run.current != nil {
            run.status = run.openQuestions.isEmpty ? .running : .waiting
            run.reason = nil; run.updatedAt = .now
            try saveRun(run, ref: ref)
        }
        return run
    }
}
