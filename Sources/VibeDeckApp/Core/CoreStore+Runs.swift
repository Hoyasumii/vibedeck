import Foundation

// Execuções de workflow (`workflow_run_*`). O Core só devolve a próxima ação e o prompt; quem chama o provedor de IA é o app.
extension CoreStore {
    private struct RunStartReply: Decodable {
        var ref: String
        var action: WorkflowRunAction
        var prompt: String?
    }

    /// Inicia (ou retoma, com a mesma entrada) uma execução. Devolve a referência, a próxima ação e o prompt do orquestrador.
    func startRun(_ workflow: String, input: String?, from: String? = nil, provider: AIProvider = .claude) async throws
        -> (ref: String, action: WorkflowRunAction, prompt: String) {
        var args: [String: Any] = ["workflow": workflow, "provider": provider.rawValue]
        if let input = input, !input.isEmpty { args["input"] = input }
        if let from = from, !from.isEmpty { args["from"] = from }
        let reply: RunStartReply = try await callJSON("workflow_run_start", args)
        return (reply.ref, reply.action, reply.prompt ?? "")
    }

    func nextRunAction(_ ref: String) async throws -> WorkflowRunAction {
        try await callJSON("workflow_run_next", ["run": ref], idempotent: true)
    }

    /// Prompt da etapa atual (texto). `cli` não é mais usado: o prompt já vem pronto do Core.
    func runStepPrompt(_ ref: String, cli: String = "vibedeck") async throws -> String {
        try await call("workflow_run_step", ["run": ref], idempotent: true)
    }

    @discardableResult
    func recordRun(_ ref: String, verdict: String?, summary: String?, to: String? = nil, noneHolds: Bool = false) async throws -> WorkflowRunAction {
        var args: [String: Any] = ["run": ref]
        if let verdict = verdict, !verdict.isEmpty { args["verdict"] = verdict }
        if let summary = summary, !summary.isEmpty { args["summary"] = summary }
        if let to = to, !to.isEmpty { args["to"] = to }
        if noneHolds { args["none_holds"] = true }
        return try await callJSON("workflow_run_record", args)
    }

    func stopRun(_ ref: String, reason: String? = nil) async throws {
        var args: [String: Any] = ["run": ref]
        if let reason = reason, !reason.isEmpty { args["reason"] = reason }
        _ = try await call("workflow_run_stop", args)
    }

    @discardableResult
    func answerRun(_ ref: String, number: Int, answer: String) async throws -> WorkflowRunAction {
        try await callJSON("workflow_run_answer", ["run": ref, "number": number, "answer": answer])
    }

    /// PEDIDO-CORE (workflow_run_save_output): grava a saída completa de uma etapa em `outputs/` e devolve o resumo com o caminho.
    func saveRunOutput(_ ref: String, output: String) async throws -> String {
        try await call("workflow_run_save_output", ["run": ref, "output": output])
    }

    /// PEDIDO-CORE (workflow_run_checkpoint): guarda o resultado (parcial ou completo) da etapa atual.
    func checkpointRun(_ ref: String, checkpoint: WorkflowStepCheckpoint) async throws {
        var args: [String: Any] = ["run": ref, "step": checkpoint.step, "output": checkpoint.output, "completed": checkpoint.completed]
        if let verdict = checkpoint.verdict { args["verdict"] = verdict }
        _ = try await call("workflow_run_checkpoint", args)
    }

    /// PEDIDO-CORE (workflow_run_delete).
    func deleteRun(_ ref: String) async throws {
        _ = try await call("workflow_run_delete", ["run": ref])
    }
}

extension CoreStore {
    /// Uma execução parada volta a andar. PEDIDO-CORE (workflow_run_resume); sem a tool, só devolve a execução.
    func resumeRun(_ ref: String) async throws -> WorkflowRun {
        let run = try await loadRun(ref)
        guard run.status == .stopped, run.current != nil else { return run }
        _ = try await call("workflow_run_resume", ["run": ref])
        return try await loadRun(ref)
    }
}

extension CoreStore {
    /// Recomeça a execução da primeira etapa, em novo ciclo (`workflow_run_restart`, só no modo --app).
    func restartRun(_ ref: String) async throws -> WorkflowRun {
        _ = try await call("workflow_run_restart", ["run": ref])
        return try await loadRun(ref)
    }

    /// Solta ideias e padrões promovidos para tópico inexistente (`release_orphaned`, só no modo --app).
    func releaseOrphaned() async throws {
        _ = try await call("release_orphaned")
    }
}
