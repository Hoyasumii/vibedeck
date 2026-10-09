import Foundation

// MARK: - Workflow runs

/// State of one execution of a workflow.
public enum WorkflowRunStatus: String, Codable, CaseIterable, Sendable {
    /// A step is (or should be) running.
    case running
    /// Waiting for the user's answers to a step's questions.
    case waiting
    /// Ended normally: the last step had no transition that applied.
    case done
    /// Halted by a guard (maxSteps, maxVisits, no progress) or by the user.
    case stopped
}

/// One step run inside an execution, with the verdict that decided where to go.
public struct WorkflowRunEntry: Codable, Equatable, Sendable {
    public var step: String
    /// Last line of the step's result.
    public var verdict: String?
    public var summary: String?
    /// Step chosen after this one (nil = end).
    public var next: String?
    /// Which pass over the workflow this belongs to (a new one starts each time a finished run is started again).
    public var cycle: Int
    public var at: Date

    public init(step: String, verdict: String? = nil, summary: String? = nil, next: String? = nil, cycle: Int = 1, at: Date = .now) {
        self.step = step
        self.verdict = verdict
        self.summary = summary
        self.next = next
        self.cycle = cycle
        self.at = at
    }

    enum CodingKeys: String, CodingKey { case step, verdict, summary, next, cycle, at }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        step = try c.decode(String.self, forKey: .step)
        verdict = try c.decodeIfPresent(String.self, forKey: .verdict)?.trimmed.nonEmpty
        summary = try c.decodeIfPresent(String.self, forKey: .summary)?.trimmed.nonEmpty
        next = try c.decodeIfPresent(String.self, forKey: .next)
        cycle = try c.decodeIfPresent(Int.self, forKey: .cycle) ?? 1
        at = try c.decodeIfPresent(Date.self, forKey: .at) ?? .now
    }
}

public struct WorkflowQuestionOption: Codable, Equatable, Sendable {
    public var label: String
    public var description: String?

    public init(label: String, description: String? = nil) {
        self.label = label
        self.description = description
    }
}

/// A question a step needs the user to decide. Steps never talk to the user: they record the question and stop
/// with `PERGUNTA`; the orchestrating chat asks it and records the answer, and the step runs again reading it.
public struct WorkflowQuestion: Codable, Equatable, Identifiable, Sendable {
    public var number: Int
    public var step: String
    public var question: String
    public var context: String?
    public var options: [WorkflowQuestionOption]
    public var multiple: Bool
    public var answer: String?
    public var createdAt: Date
    public var answeredAt: Date?

    public var id: Int { number }
    public var isOpen: Bool { answer == nil }

    public init(
        number: Int, step: String, question: String, context: String? = nil, options: [WorkflowQuestionOption] = [],
        multiple: Bool = false, now: Date = .now
    ) {
        self.number = number
        self.step = step
        self.question = question
        self.context = context
        self.options = options
        self.multiple = multiple
        self.createdAt = now
    }

    enum CodingKeys: String, CodingKey { case number, step, question, context, options, multiple, answer, createdAt, answeredAt }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        number = try c.decode(Int.self, forKey: .number)
        step = try c.decode(String.self, forKey: .step)
        question = try c.decode(String.self, forKey: .question)
        context = try c.decodeIfPresent(String.self, forKey: .context)
        options = try c.decodeIfPresent([WorkflowQuestionOption].self, forKey: .options) ?? []
        multiple = try c.decodeIfPresent(Bool.self, forKey: .multiple) ?? false
        answer = try c.decodeIfPresent(String.self, forKey: .answer)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        answeredAt = try c.decodeIfPresent(Date.self, forKey: .answeredAt)
    }
}

/// What a step sends to `ask`: a question, before it gets its number and step.
public struct WorkflowQuestionDraft: Codable, Equatable, Sendable {
    public var question: String
    public var context: String?
    public var options: [WorkflowQuestionOption]?
    public var multiple: Bool?

    public init(question: String, context: String? = nil, options: [WorkflowQuestionOption]? = nil, multiple: Bool? = nil) {
        self.question = question
        self.context = context
        self.options = options
        self.multiple = multiple
    }
}

/// An execution of a workflow, in `.vibedeck/runs/<workflow>/<run>/run.json`. The run's folder also holds what the
/// steps write (plans, critiques, evaluations), so the next step picks up where the previous one stopped. Starting
/// the same workflow with the same input again resumes it.
public struct WorkflowRun: Codable, Equatable, Identifiable, Sendable {
    public var schema: String?
    public var id: UUID
    /// Slug of the workflow.
    public var workflow: String
    public var provider: AIProvider
    public var input: String?
    public var status: WorkflowRunStatus
    /// Step to run next (nil once finished).
    public var current: String?
    /// Why the run is waiting, finished or stopped.
    public var reason: String?
    public var cycle: Int
    public var history: [WorkflowRunEntry]
    public var questions: [WorkflowQuestion]
    public var createdAt: Date
    public var updatedAt: Date

    public init(workflow: String, input: String?, start: String?, provider: AIProvider = .claude, now: Date = .now) {
        self.schema = SchemaURL.workflowRun
        self.id = UUID()
        self.workflow = workflow
        self.provider = provider
        self.input = input
        self.status = start == nil ? .done : .running
        self.current = start
        self.reason = start == nil ? "o workflow não tem etapas" : nil
        self.cycle = 1
        self.history = []
        self.questions = []
        self.createdAt = now
        self.updatedAt = now
    }

    enum CodingKeys: String, CodingKey {
        case schema = "$schema", id, workflow, provider, input, status, current, reason, cycle, history, questions, createdAt, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decodeIfPresent(String.self, forKey: .schema)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        workflow = try c.decode(String.self, forKey: .workflow)
        provider = try c.decodeIfPresent(AIProvider.self, forKey: .provider) ?? .claude
        input = try c.decodeIfPresent(String.self, forKey: .input)
        status = try c.decodeIfPresent(WorkflowRunStatus.self, forKey: .status) ?? .running
        current = try c.decodeIfPresent(String.self, forKey: .current)
        reason = try c.decodeIfPresent(String.self, forKey: .reason)
        cycle = try c.decodeIfPresent(Int.self, forKey: .cycle) ?? 1
        history = try c.decodeIfPresent([WorkflowRunEntry].self, forKey: .history) ?? []
        questions = try c.decodeIfPresent([WorkflowQuestion].self, forKey: .questions) ?? []
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(schema, forKey: .schema)
        try c.encode(id, forKey: .id)
        try c.encode(workflow, forKey: .workflow)
        try c.encode(provider, forKey: .provider)
        try c.encodeIfPresent(input, forKey: .input)
        try c.encode(status, forKey: .status)
        try c.encodeIfPresent(current, forKey: .current)
        try c.encodeIfPresent(reason, forKey: .reason)
        try c.encode(cycle, forKey: .cycle)
        if !history.isEmpty { try c.encode(history, forKey: .history) }
        if !questions.isEmpty { try c.encode(questions, forKey: .questions) }
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
    }

    public var openQuestions: [WorkflowQuestion] { questions.filter(\.isOpen) }

    /// Entries of the current cycle (what `maxSteps` and `maxVisits` count).
    public var currentCycle: [WorkflowRunEntry] { history.filter { $0.cycle == cycle } }

    public var isFinished: Bool { status == .done || status == .stopped }

    /// Answers already given to a step (it reads them before starting, instead of asking again).
    public func answers(for step: String) -> [WorkflowQuestion] {
        questions.filter { $0.step == step && !$0.isOpen }
    }
}

/// What the orchestrator does next, like `task_input --conduzir` in claude-kit: the engine decides, the chat obeys.
public struct WorkflowRunAction: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// Launch a subagent for `step`.
        case runStep = "run-step"
        /// Ask the user the open questions, record the answers, then call `next`.
        case ask
        /// No verdict matched and the step has natural-language conditions: judge them and call `record` with `to`.
        case decide
        /// Finished normally.
        case done
        /// Halted by a guard or by the user.
        case stop
    }

    public var action: Kind
    /// `<workflow>/<run>`.
    public var run: String
    public var step: String?
    public var title: String?
    /// Model of the step's agent/command/skill (for the subagent).
    public var model: String?
    public var reason: String
    /// For `decide`: the step's conditional transitions to judge (in order).
    public var candidates: [WorkflowTransition]?
    /// For `decide`: the verdict to send back with `record`.
    public var verdict: String?
    /// For `ask`: the open questions.
    public var questions: [WorkflowQuestion]?

    public init(
        action: Kind, run: String, step: String? = nil, title: String? = nil, model: String? = nil, reason: String,
        candidates: [WorkflowTransition]? = nil, verdict: String? = nil, questions: [WorkflowQuestion]? = nil
    ) {
        self.action = action
        self.run = run
        self.step = step
        self.title = title
        self.model = model
        self.reason = reason
        self.candidates = candidates
        self.verdict = verdict
        self.questions = questions
    }
}

/// Pure state machine over a `WorkflowRun` (no disk), so it can be tested and shared by app, CLI and MCP.
public enum WorkflowRunEngine {
    /// Restarts a finished run (a new cycle from `from`, or the start); keeps an unfinished one where it is.
    public static func restart(_ run: inout WorkflowRun, workflow: Workflow, from: String? = nil, now: Date = .now) throws {
        let target = try from.map { try stepId($0, in: workflow) }
        guard run.isFinished || target != nil else { return }
        guard let first = target ?? workflow.steps.first?.id else {
            throw VibeDeckError.invalidWorkflow("o workflow não tem etapas.")
        }
        if run.isFinished, !run.history.isEmpty { run.cycle += 1 }
        run.current = first
        run.status = run.openQuestions.isEmpty ? .running : .waiting
        run.reason = nil
        run.updatedAt = now
    }

    /// What to do now.
    public static func next(_ run: WorkflowRun, ref: String, workflow: Workflow, resolve: (WorkflowStep) -> (title: String?, model: String?)) -> WorkflowRunAction {
        switch run.status {
        case .done: return WorkflowRunAction(action: .done, run: ref, reason: run.reason ?? "o workflow terminou")
        case .stopped: return WorkflowRunAction(action: .stop, run: ref, step: run.current, reason: run.reason ?? "execução parada")
        case .running, .waiting: break
        }
        let open = run.openQuestions
        if !open.isEmpty {
            return WorkflowRunAction(
                action: .ask, run: ref, step: open.first?.step,
                reason: "pergunta(s) aberta(s) da etapa \(open.first?.step ?? "?")", questions: open
            )
        }
        guard let current = run.current, let step = workflow.steps.first(where: { $0.id == current }) else {
            return WorkflowRunAction(action: .stop, run: ref, step: run.current, reason: "etapa atual inexistente no workflow: \(run.current ?? "nenhuma")")
        }
        let info = resolve(step)
        let visits = run.currentCycle.filter { $0.step == current }.count
        return WorkflowRunAction(
            action: .runStep, run: ref, step: current, title: info.title, model: info.model,
            reason: visits == 0 ? "próxima etapa: \(current)" : "etapa \(current) de novo (\(visits + 1)ª vez neste ciclo)"
        )
    }

    /// Records the current step's result and moves on. Returns `decide` (nothing recorded) when only natural-language
    /// conditions can decide and `to`/`noneHolds` were not given.
    @discardableResult
    public static func record(
        _ run: inout WorkflowRun, workflow: Workflow, verdict: String?, summary: String?, to: String? = nil,
        noneHolds: Bool = false, ref: String, now: Date = .now
    ) throws -> WorkflowRunAction? {
        guard !run.isFinished else { throw VibeDeckError.invalidWorkflow("a execução já terminou (\(run.status.rawValue)); use start para retomar.") }
        guard run.openQuestions.isEmpty else {
            throw VibeDeckError.invalidWorkflow("há perguntas abertas: responda-as antes de registrar a etapa.")
        }
        guard let current = run.current, let step = workflow.steps.first(where: { $0.id == current }) else {
            throw VibeDeckError.invalidWorkflow("etapa atual inexistente no workflow: \(run.current ?? "nenhuma").")
        }
        let verdict = verdict?.trimmed.nonEmpty
        let next: String?
        if let to {
            let target = try stepId(to, in: workflow)
            guard step.transitions.contains(where: { $0.to == target }) else {
                throw VibeDeckError.invalidWorkflow("a etapa \(current) não tem transição para \(target).")
            }
            next = target
        } else if let verdict, let match = step.transitions.first(where: { $0.matches(verdict: verdict) }) {
            next = match.to
        } else {
            let conditions = step.transitions.filter { $0.verdict == nil && $0.when != nil }
            if !conditions.isEmpty, !noneHolds {
                return WorkflowRunAction(
                    action: .decide, run: ref, step: current,
                    reason: "nenhum veredito casou: avalie as condições na ordem e registre com `to` (ou `nenhuma`)",
                    candidates: conditions, verdict: verdict
                )
            }
            next = step.transitions.first(where: \.isFallback)?.to
        }

        let previous = run.history.last
        run.history.append(WorkflowRunEntry(step: current, verdict: verdict, summary: summary?.trimmed.nonEmpty, next: next, cycle: run.cycle, at: now))
        run.updatedAt = now
        run.current = next
        guard let next else {
            run.status = .done
            run.reason = "a etapa \(current) terminou\(verdict.map { " com \($0)" } ?? "") e nenhuma transição se aplica"
            return nil
        }
        let cycle = run.currentCycle
        let maxSteps = max(1, workflow.maxSteps ?? Workflow.defaultMaxSteps)
        if cycle.count >= maxSteps {
            run.status = .stopped
            run.reason = "limite de \(maxSteps) etapas por execução atingido (maxSteps)"
        } else if let limit = workflow.steps.first(where: { $0.id == next })?.maxVisits,
                  cycle.filter({ $0.step == next }).count >= limit {
            run.status = .stopped
            run.reason = "a etapa \(next) já rodou \(limit) vez(es) neste ciclo (maxVisits): decida se libera mais uma"
        } else if next == current, let previous, previous.cycle == run.cycle, previous.step == current,
                  previous.verdict.map(WorkflowTransition.normalize) == verdict.map(WorkflowTransition.normalize) {
            run.status = .stopped
            run.reason = "a etapa \(current) voltou para si com o mesmo veredito duas vezes seguidas: não andou"
        }
        return nil
    }

    /// Records questions of the current step; the run waits for the answers.
    public static func ask(_ run: inout WorkflowRun, drafts: [WorkflowQuestionDraft], now: Date = .now) throws -> [WorkflowQuestion] {
        guard let step = run.current, !run.isFinished else { throw VibeDeckError.invalidWorkflow("a execução não tem etapa em andamento.") }
        let drafts = drafts.filter { !$0.question.trimmed.isEmpty }
        guard !drafts.isEmpty else { throw VibeDeckError.invalidWorkflow("nenhuma pergunta recebida.") }
        var number = run.questions.map(\.number).max() ?? 0
        let added = drafts.map { d -> WorkflowQuestion in
            number += 1
            return WorkflowQuestion(
                number: number, step: step, question: d.question.trimmed, context: d.context?.trimmed.nonEmpty,
                options: (d.options ?? []).filter { !$0.label.trimmed.isEmpty }, multiple: d.multiple ?? false, now: now
            )
        }
        run.questions += added
        run.status = .waiting
        run.reason = "aguardando resposta do usuário (etapa \(step))"
        run.updatedAt = now
        return added
    }

    /// Records the user's answer; with none left open the run goes back to running the same step.
    public static func answer(_ run: inout WorkflowRun, number: Int, text: String, now: Date = .now) throws {
        guard let i = run.questions.firstIndex(where: { $0.number == number }) else {
            throw VibeDeckError.invalidWorkflow("pergunta não encontrada: \(number).")
        }
        guard let text = text.trimmed.nonEmpty else { throw VibeDeckError.invalidWorkflow("resposta vazia.") }
        run.questions[i].answer = text
        run.questions[i].answeredAt = now
        if run.openQuestions.isEmpty, run.status == .waiting {
            run.status = .running
            run.reason = nil
        }
        run.updatedAt = now
    }

    public static func stop(_ run: inout WorkflowRun, reason: String?, now: Date = .now) {
        run.status = .stopped
        run.reason = reason?.trimmed.nonEmpty ?? "parada pelo usuário"
        run.updatedAt = now
    }

    static func stepId(_ ref: String, in workflow: Workflow) throws -> String {
        guard let i = workflow.stepIndex(ref) else { throw VibeDeckError.invalidWorkflow("etapa não encontrada: \(ref).") }
        return workflow.steps[i].id
    }
}

// MARK: - Prompts

public enum WorkflowOrchestration {
    /// Verdicts a step's transitions expect, for the step's prompt.
    public static func expectedVerdicts(of step: WorkflowStep) -> [String] {
        var seen = Set<String>()
        return step.transitions.compactMap(\.verdict).filter { seen.insert(WorkflowTransition.normalize($0)).inserted }
    }

    /// Everything the subagent running `step` needs: the resolved instructions, the run's folder and history, the
    /// user's answers to this step and the output protocol. The orchestrator passes only the run reference.
    public static func stepPrompt(
        run: WorkflowRun, ref: String, workflow: Workflow, step: WorkflowStep, title: String?, instructions: String?,
        runDir: URL, cli: String = "vibedeck"
    ) -> String {
        let input = run.input ?? ""
        let arguments = step.note?.trimmed.nonEmpty ?? input
        var body = (instructions ?? "").replacingOccurrences(of: "$RUN_DIR", with: runDir.path)
        if step.kind == .command {
            body = body.replacingOccurrences(of: "$ARGUMENTS", with: arguments)
        }
        var lines: [String] = []
        lines.append("# Etapa `\(step.id)` — \(title ?? step.ref)")
        lines.append("")
        lines.append("Você executa **uma** etapa do workflow \"\(workflow.title)\" do VibeDeck (execução `\(ref)`), a pedido do orquestrador. Tudo o que você precisa está aqui e no disco.")
        lines.append("")
        lines.append("- Entrada da execução: \(input.isEmpty ? "(nenhuma)" : input)")
        lines.append("- Pasta da execução (`$RUN_DIR`): `\(runDir.path)` — leia o que as etapas anteriores gravaram e grave aqui o que esta etapa produz.")
        if step.kind != .command, let note = step.note?.trimmed.nonEmpty { lines.append("- Instrução extra desta etapa: \(note)") }
        lines.append("- Histórico completo e decisões anteriores: `\(runDir.appending(path: "run.json").path)`. Consulte quando uma referência ou decisão anterior for necessária.")
        if run.history.count > 3 {
            lines.append("Histórico anterior (consulte run.json para evidências e pendências):")
            for entry in run.history.dropLast(3) {
                lines.append("- `\(entry.step)` → \(entry.verdict ?? "sem veredito")")
            }
        }
        let previous = run.history.suffix(3)
        if !previous.isEmpty {
            lines.append("")
            lines.append("## Etapas anteriores")
            for (n, e) in previous.enumerated() {
                lines.append("\(n + 1). `\(e.step)` → \(e.verdict ?? "—")\(e.summary.map { ": \($0)" } ?? "")")
            }
        }
        let answers = run.questions.filter { $0.answer != nil }
        if !answers.isEmpty {
            lines.append("")
            lines.append("## Decisões do usuário nesta execução")
            lines.append("São decisões do usuário: use cada uma quando chegar àquele ponto, sem perguntar de novo.")
            for q in answers { lines.append("- **\(q.question)** → \(q.answer ?? "")") }
        }
        lines.append("")
        lines.append(AIPromptPolicy.instructions)
        lines.append("## Instruções da etapa")
        lines.append("")
        lines.append(body.trimmed.nonEmpty ?? "(a etapa não tem instruções: \(step.kind.rawValue) `\(step.ref)` não encontrado)")
        lines.append("")
        lines.append("## Protocolo")
        lines.append("1. Siga as instruções até o fim. Portões, arquivos gravados e formato da saída são delas.")
        lines.append("2. Você **não** fala com o usuário. Onde as instruções mandarem perguntar ou pedirem uma decisão do usuário, e não houver resposta acima: não adivinhe e não faça nada irreversível antes. Grave as perguntas (de 2 a 4 opções cada, a recomendada primeiro):")
        lines.append("   ```bash")
        lines.append("   \(cli) runs ask \(ref) <<'__FIM__'")
        lines.append("   [{\"question\": \"<pergunta direta>\", \"context\": \"<o que gerou a dúvida>\", \"options\": [{\"label\": \"<1 a 5 palavras>\", \"description\": \"<o que acontece>\"}], \"multiple\": false}]")
        lines.append("   __FIM__")
        lines.append("   ```")
        lines.append("   e termine com um resumo curto de onde parou e a **última linha, sozinha:** `PERGUNTA`.")
        let verdicts = expectedVerdicts(of: step)
        if verdicts.isEmpty {
            lines.append("3. Ao terminar, devolva a saída final com a **última linha, sozinha,** sendo o veredito da etapa (uma palavra ou frase curta).")
        } else {
            lines.append("3. Ao terminar, devolva a saída final com a **última linha, sozinha,** sendo o veredito: \(verdicts.map { "`\($0)`" }.joined(separator: ", ")) (ou outro, se as instruções definirem).")
        }
        lines.append("4. Não chame `\(cli) runs record`: quem registra o veredito é o orquestrador.")
        return lines.joined(separator: "\n")
    }

    /// Message that makes the chat the orchestrator of a run, like `/conduzir` + the `operador` of claude-kit.
    public static func orchestratorPrompt(ref: String, title: String, input: String?, cli: String = "vibedeck", provider: AIProvider = .claude) -> String {
        let prompt = """
        Conduza a execução `\(ref)` do workflow "\(title)" do VibeDeck\(input.map { " (entrada: \($0))" } ?? ""). \
        Rodar o workflow autoriza o que as etapas fazem, no modo de permissão desta sessão.

        Você é o **orquestrador** e o **único ponto de contato com o usuário**. Quem decide a próxima etapa é o \
        VibeDeck; quem trabalha são as etapas, cada uma num subagente com contexto limpo; quem responde é o usuário. \
        Você não lê código, não lê os arquivos da execução, não resume nada para as etapas e não corrige nada.

        ## Ciclo
        1. `\(cli) runs next \(ref) --json` → use `action` e `reason` (ou a ferramenta MCP `workflow_run_next`).
        2. Conforme `action`:
           - `run-step` → anuncie "▶ Etapa <step> — <title>" e lance **um** subagente (`Agent`, \
        `subagent_type: "general-purpose"`, `model` = o `model` da ação quando houver, `description: "<step>"`) com \
        exatamente este prompt:
             > Você executa a etapa `<step>` da execução `\(ref)` do VibeDeck. Rode `\(cli) runs step \(ref)` e siga o \
        texto que ele imprime até o fim. A última linha da sua resposta é o veredito, ou `PERGUNTA`.
             Espere o retorno (etapas longas levam dezenas de minutos).
           - `ask` → passo 4.
           - `done` ou `stop` → **Relatório final**.
        3. Retorno da etapa — a **última linha** é o veredito:
           - `PERGUNTA` → passo 4.
           - qualquer outra → `\(cli) runs record \(ref) --verdict "<última linha>" --summary "<1 a 3 linhas do que a \
        etapa fez>" --json`. Se vier `action: decide`, avalie os `candidates` na ordem sobre a saída da etapa e \
        registre de novo com `--to <etapa>` da primeira condição verdadeira, ou `--nenhuma` se nenhuma valer. \
        Volte ao passo 1.
        4. Perguntas: `\(cli) runs questions \(ref) --open --json` e faça-as com `AskUserQuestion` (até 4 por vez, na \
        ordem do `number`; `header` = "<step> <number>"; as `options` como vieram; `multiSelect` = `multiple`). Não \
        reescreva nem acrescente opções. Grave cada resposta com `\(cli) runs answer \(ref) <number> "<resposta>"` e \
        volte ao passo 1 (a etapa roda de novo e lê as respostas).

        ## Paradas
        - Erro do CLI → pare e mostre o erro.
        - Parada com decisão do usuário (`stop` por `maxVisits`, por exemplo): resuma o que falta pelo `reason` e \
        pelo histórico (`\(cli) runs show \(ref) --json`) e pergunte se libera mais uma volta \
        (`\(cli) runs start <workflow> --input "<entrada>" --from <etapa>`) ou se para.

        ## Relatório final (pt-BR)
        - Tabela: nº | etapa | veredito
        - Estado final (`done`/`stop`) e o `reason`
        - Próximo passo humano
        """
        guard provider == .codex else { return prompt }
        return prompt.replacingOccurrences(of: "(`Agent`, ", with: "(a ferramenta de subagente disponível no Codex, ")
            .replacingOccurrences(of: "`subagent_type: \"general-purpose\"`, `model` = o `model` da ação quando houver, `description: \"<step>\"`)", with: "contexto limpo; use o modelo configurado para Codex quando disponível)")
            .replacingOccurrences(of: "faça-as com `AskUserQuestion` (até 4 por vez, na ", with: "apresente-as ao usuário (até 4 por vez, na ")
    }
}
