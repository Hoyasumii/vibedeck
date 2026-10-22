import Foundation

/// A durable result separates completing a step from judging its conditional transitions.
struct WorkflowStepCheckpoint: Codable, Equatable, Sendable {
    var step: String
    var verdict: String?
    var output: String
    var completed: Bool
    init(step: String, verdict: String? = nil, output: String, completed: Bool) {
        self.step = step; self.verdict = verdict; self.output = output; self.completed = completed
    }
}

/// Both providers execute the same persisted state machine. The host supplies only AI calls and UI events.
@MainActor enum AIWorkflowRunner {
    typealias Execute = (String, AIProviderSettings, String) async throws -> String
    typealias Decide = (String, [WorkflowTransition]) async throws -> String?

    static func run(ref: String, store: CoreStore, cli: String = "vibedeck",
                           settings: (String) async throws -> AIProviderSettings,
                           execute: Execute, decide: Decide,
                           onAction: (WorkflowRunAction) -> Void = { _ in }) async throws -> WorkflowRunAction {
        while true {
            try Task.checkCancellation()
            let action = try await store.nextRunAction(ref)
            onAction(action)
            switch action.action {
            case .done, .stop, .ask: return action
            case .runStep:
                let snapshot = try await store.loadRun(ref)
                guard let step = action.step else { throw AIIntegrationError.invalidTransition }
                let checkpoint: WorkflowStepCheckpoint
                if let existing = snapshot.checkpoint, existing.step == step, existing.completed {
                    checkpoint = existing
                } else {
                    var prompt = try await store.runStepPrompt(ref, cli: cli)
                    if let partial = snapshot.checkpoint, partial.step == step {
                        prompt += "\nEsta etapa foi interrompida. Consulte a saída parcial e o estado atual antes de continuar; não repita alterações já efetuadas.\n" + partial.output
                    }
                    let output = try await execute(prompt, try await settings(ref), action.title ?? step)
                    try Task.checkCancellation()
                    let current = try await store.loadRun(ref)
                    guard !current.isFinished, current.current == step else { return try await store.nextRunAction(ref) }
                    let verdict = output.split(whereSeparator: \.isNewline).last.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    guard !verdict.isEmpty else { throw VibeDeckError.invalidWorkflow("A etapa terminou sem veredito.") }
                    if verdict == "PERGUNTA" {
                        guard !current.openQuestions.isEmpty else { throw VibeDeckError.invalidWorkflow("A etapa retornou PERGUNTA sem registrar perguntas.") }
                        continue
                    }
                    checkpoint = .init(step: step, verdict: verdict, output: try await store.saveRunOutput(ref, output: output), completed: true)
                    try await store.checkpointRun(ref, checkpoint: checkpoint)
                }
                let next = try await store.recordRun(ref, verdict: checkpoint.verdict, summary: checkpoint.output)
                if next.action == .decide {
                    let candidates = next.candidates ?? []
                    let target = try await decide(checkpoint.output, candidates)
                    try Task.checkCancellation()
                    let current = try await store.loadRun(ref)
                    guard !current.isFinished, current.current == step else { return try await store.nextRunAction(ref) }
                    if let target, !candidates.contains(where: { $0.to == target }) { throw AIIntegrationError.invalidTransition }
                    _ = try await store.recordRun(ref, verdict: checkpoint.verdict, summary: checkpoint.output, to: target, noneHolds: target == nil)
                }
            case .decide: throw AIIntegrationError.invalidTransition
            }
        }
    }
}

