import Foundation

// MARK: - Workflows

/// Edge of a workflow: after a step runs, go to step `to` when its `verdict` (exact last line of the step's result,
/// ignoring case and accents) or its `when` (natural language, judged by the AI on the result) holds. A transition
/// with neither always holds ("senão"). Verdicts are checked first, then conditions, then the fallback; none = end.
public struct WorkflowTransition: Codable, Equatable, Sendable {
    public var verdict: String?
    public var when: String?
    /// Id of a step of the same workflow (earlier steps allowed: loops).
    public var to: String

    public init(verdict: String? = nil, when: String? = nil, to: String) {
        self.verdict = verdict
        self.when = when
        self.to = to
    }

    /// No verdict and no condition: the "senão" of the step.
    public var isFallback: Bool { verdict == nil && when == nil }

    /// Short pt-BR label: `= APROVADO`, `se <condição>` or `senão`.
    public var label: String {
        if let verdict { return "= \(verdict)" }
        if let when { return "se \(when)" }
        return "senão"
    }

    /// Whether `verdict` (a step's last line) matches this transition's verdict.
    public func matches(verdict other: String) -> Bool {
        guard let verdict else { return false }
        return WorkflowTransition.normalize(verdict) == WorkflowTransition.normalize(other)
    }

    static func normalize(_ verdict: String) -> String {
        verdict.trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "`*_.")).folding(
            options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")
        )
    }

    enum CodingKeys: String, CodingKey { case verdict, when, to }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        verdict = try c.decodeIfPresent(String.self, forKey: .verdict)?.trimmed.nonEmpty
        when = try c.decodeIfPresent(String.self, forKey: .when)?.trimmed.nonEmpty
        to = try c.decode(String.self, forKey: .to)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(verdict, forKey: .verdict)
        try c.encodeIfPresent(when, forKey: .when)
        try c.encode(to, forKey: .to)
    }
}

/// A node of a workflow: a VibeDeck agent, command or skill, plus where to go depending on its result.
public struct WorkflowStep: Codable, Equatable, Identifiable, Sendable {
    /// Readable key, unique inside the workflow (e.g. `revisor`, `revisor-2`); transitions point to it.
    public var id: String
    public var kind: NextStepKind
    /// Slug of a VibeDeck agent/command/skill, never of the AI provider's.
    public var ref: String
    /// Extra instruction for this step (for commands, what goes in `$ARGUMENTS`).
    public var note: String?
    /// Most runs of this step in one execution (e.g. 3 critiques); exceeding it stops the run.
    public var maxVisits: Int?
    public var transitions: [WorkflowTransition]

    public init(
        id: String, kind: NextStepKind = .agent, ref: String, note: String? = nil, maxVisits: Int? = nil,
        transitions: [WorkflowTransition] = []
    ) {
        self.id = id
        self.kind = kind
        self.ref = ref
        self.note = note
        self.maxVisits = maxVisits
        self.transitions = transitions
    }

    enum CodingKeys: String, CodingKey { case id, kind, ref, note, maxVisits, transitions }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decodeIfPresent(NextStepKind.self, forKey: .kind) ?? .agent
        ref = try c.decode(String.self, forKey: .ref)
        id = try c.decodeIfPresent(String.self, forKey: .id)?.trimmed.nonEmpty ?? ref
        note = try c.decodeIfPresent(String.self, forKey: .note)
        maxVisits = try c.decodeIfPresent(Int.self, forKey: .maxVisits).flatMap { $0 > 0 ? $0 : nil }
        transitions = try c.decodeIfPresent([WorkflowTransition].self, forKey: .transitions) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(ref, forKey: .ref)
        try c.encodeIfPresent(note, forKey: .note)
        try c.encodeIfPresent(maxVisits, forKey: .maxVisits)
        if !transitions.isEmpty { try c.encode(transitions, forKey: .transitions) }
    }
}

/// A file per workflow in `.vibedeck/workflows/`: a named state machine over VibeDeck agents, commands and skills.
/// The first step is the start; each step's transitions decide the next one from its result, until none applies.
public struct Workflow: Codable, Equatable, Identifiable, Sendable {
    public static let defaultMaxSteps = 25

    public var schema: String?
    public var id: UUID
    public var title: String
    public var summary: String?
    /// What the user is asked for when starting the workflow (e.g. `<número do PR>`).
    public var input: String?
    /// Guard against endless loops: at most this many step runs (default `defaultMaxSteps`).
    public var maxSteps: Int?
    public var steps: [WorkflowStep]
    public var tags: [String]
    public var author: Author
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        title: String, summary: String? = nil, input: String? = nil, maxSteps: Int? = nil, tags: [String] = [],
        author: Author = .human, now: Date = .now
    ) {
        self.schema = SchemaURL.workflow
        self.id = UUID()
        self.title = title
        self.summary = summary
        self.input = input
        self.maxSteps = maxSteps
        self.steps = []
        self.tags = tags
        self.author = author
        self.createdAt = now
        self.updatedAt = now
    }

    enum CodingKeys: String, CodingKey {
        case schema = "$schema", id, title, summary, input, maxSteps, steps, tags, author, createdAt, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decodeIfPresent(String.self, forKey: .schema)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decode(String.self, forKey: .title)
        summary = try c.decodeIfPresent(String.self, forKey: .summary)
        input = try c.decodeIfPresent(String.self, forKey: .input)
        maxSteps = try c.decodeIfPresent(Int.self, forKey: .maxSteps)
        steps = try c.decodeIfPresent([WorkflowStep].self, forKey: .steps) ?? []
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        author = try c.decodeIfPresent(Author.self, forKey: .author) ?? .human
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(schema, forKey: .schema)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(summary, forKey: .summary)
        try c.encodeIfPresent(input, forKey: .input)
        try c.encodeIfPresent(maxSteps, forKey: .maxSteps)
        if !steps.isEmpty { try c.encode(steps, forKey: .steps) }
        if !tags.isEmpty { try c.encode(tags, forKey: .tags) }
        try c.encode(author, forKey: .author)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
    }

    /// Index of a step by id, by `Slug.make(ref)` or by 1-based position.
    public func stepIndex(_ ref: String) -> Int? {
        let ref = ref.trimmed
        if let i = steps.firstIndex(where: { $0.id == ref }) { return i }
        if let i = steps.firstIndex(where: { $0.id == Slug.make(ref) }) { return i }
        if let n = Int(ref), steps.indices.contains(n - 1) { return n - 1 }
        return nil
    }

    /// A step id not used yet, derived from `base` (`revisor`, `revisor-2`, …).
    public func newStepId(_ base: String) -> String {
        let base = Slug.make(base)
        let taken = Set(steps.map(\.id))
        var id = base
        var n = 2
        while taken.contains(id) {
            id = "\(base)-\(n)"
            n += 1
        }
        return id
    }

    /// Removes a step and every transition pointing to it.
    public mutating func removeStep(at index: Int) {
        let id = steps.remove(at: index).id
        for i in steps.indices { steps[i].transitions.removeAll { $0.to == id } }
    }

    /// Adds a transition keeping the unconditional one ("senão") last, since the first match wins.
    public mutating func addTransition(_ transition: WorkflowTransition, toStepAt index: Int) {
        guard !steps[index].transitions.contains(transition) else { return }
        if !transition.isFallback, let otherwise = steps[index].transitions.firstIndex(where: \.isFallback) {
            steps[index].transitions.insert(transition, at: otherwise)
        } else {
            steps[index].transitions.append(transition)
        }
    }
}

// MARK: - Plan (JSON that orchestrates the AI)

public struct WorkflowPlanStep: Codable, Equatable, Sendable {
    public var id: String
    public var kind: NextStepKind
    public var ref: String
    /// Resolved agent/command/skill (nil when the ref is missing).
    public var title: String?
    public var model: String?
    /// Commands only: what goes in `$ARGUMENTS`.
    public var argumentHint: String?
    public var note: String?
    public var maxVisits: Int?
    public var prompt: String?
    public var transitions: [WorkflowTransition]?
    public var warnings: [String]?
}

public struct WorkflowPlan: Codable, Equatable, Sendable {
    public var workflow: String
    public var title: String
    public var summary: String?
    /// What the workflow asks for (`Workflow.input`).
    public var inputHint: String?
    /// The input of this run.
    public var input: String?
    public var maxSteps: Int
    public var start: String?
    /// How to run the workflow (pt-BR), for the AI that orchestrates it.
    public var rules: [String]
    public var steps: [WorkflowPlanStep]
    public var warnings: [String]?

    static let executionRules = [
        "Comece pela etapa `start`, usando `input` como entrada. Sem `input`, e com `inputHint`, pergunte ao usuário antes de começar.",
        "Em cada etapa, anuncie \"▶ Etapa <id> — <title>\" e execute o `prompt` dela sobre a entrada e o resultado da etapa anterior: agente = assuma o papel (ou use um subagente com esse prompt e o `model`), comando = troque $ARGUMENTS pela `note` ou pela entrada, skill = siga as instruções. A `note` é uma instrução extra da etapa.",
        "Termine cada etapa com o veredito na última linha. Depois, escolha a transição: primeiro a que tiver `verdict` igual ao veredito (sem diferenciar maiúsculas e acentos), depois a primeira cujo `when` for verdadeiro para o resultado, por fim a sem `verdict` e sem `when` (senão). Voltar para etapas anteriores é permitido.",
        "Se nenhuma transição se aplicar, ou a etapa não tiver transições, o workflow termina.",
        "Nunca execute mais que `maxSteps` etapas no total, nem uma etapa mais vezes que o `maxVisits` dela; se atingir um limite, pare e avise o usuário.",
        "Para execução com estado em disco, uma etapa por subagente e perguntas ao usuário, prefira `vibedeck runs start` (ou `workflow_run_start`) e siga o orquestrador.",
        "Ignore os próximos passos (nextSteps) dos agentes, comandos e skills: só as transições do workflow valem.",
        "Se uma condição depender de uma decisão do usuário, pergunte antes de seguir.",
        "Ao terminar, resuma o caminho percorrido (etapas e transições escolhidas) e o resultado final.",
    ]

    public static func build(
        slug: String, workflow: Workflow, input: String? = nil,
        agents: [(slug: String, agent: Agent)], commands: [(slug: String, command: Command)] = [],
        skills: [(slug: String, skill: Skill)] = []
    ) -> WorkflowPlan {
        let agentIndex = Dictionary(agents.map { ($0.slug, $0.agent) }, uniquingKeysWith: { a, _ in a })
        let commandIndex = Dictionary(commands.map { ($0.slug, $0.command) }, uniquingKeysWith: { a, _ in a })
        let skillIndex = Dictionary(skills.map { ($0.slug, $0.skill) }, uniquingKeysWith: { a, _ in a })
        let ids = Set(workflow.steps.map(\.id))
        let steps = workflow.steps.map { step -> WorkflowPlanStep in
            var out = WorkflowPlanStep(
                id: step.id, kind: step.kind, ref: step.ref, note: step.note?.trimmed.nonEmpty, maxVisits: step.maxVisits,
                transitions: step.transitions.isEmpty ? nil : step.transitions
            )
            var warnings: [String] = []
            switch step.kind {
            case .agent:
                if let a = agentIndex[step.ref] { (out.title, out.model, out.prompt) = (a.title, a.model, a.prompt) }
                else { warnings.append("Agente não encontrado: \(step.ref)") }
            case .command:
                if let c = commandIndex[step.ref] { (out.title, out.model, out.argumentHint, out.prompt) = (c.title, c.model, c.argumentHint, c.prompt) }
                else { warnings.append("Comando não encontrado: \(step.ref)") }
            case .skill:
                if let s = skillIndex[step.ref] { (out.title, out.model, out.prompt) = (s.title, s.model, s.prompt) }
                else { warnings.append("Skill não encontrada: \(step.ref)") }
            }
            for t in step.transitions where !ids.contains(t.to) { warnings.append("Transição para etapa inexistente: \(t.to)") }
            out.warnings = warnings.isEmpty ? nil : warnings
            return out
        }
        var warnings: [String] = []
        if workflow.steps.isEmpty { warnings.append("O workflow não tem etapas.") }
        let duplicated = Dictionary(grouping: workflow.steps.map(\.id), by: { $0 }).filter { $0.value.count > 1 }.keys.sorted()
        if !duplicated.isEmpty { warnings.append("Ids de etapa repetidos: \(duplicated.joined(separator: ", "))") }
        return WorkflowPlan(
            workflow: slug, title: workflow.title, summary: workflow.summary?.trimmed.nonEmpty,
            inputHint: workflow.input?.trimmed.nonEmpty, input: input?.trimmed.nonEmpty,
            maxSteps: max(1, workflow.maxSteps ?? Workflow.defaultMaxSteps), start: workflow.steps.first?.id,
            rules: executionRules, steps: steps, warnings: warnings.isEmpty ? nil : warnings
        )
    }

    /// Every warning of the plan (workflow-level and per step), for validation views.
    public var allWarnings: [String] {
        (warnings ?? []) + steps.flatMap { step in (step.warnings ?? []).map { "\(step.id): \($0)" } }
    }

    /// Pretty JSON of the plan, meant to be pasted into / sent in a prompt.
    public func json() throws -> String {
        String(decoding: try VDJSON.encode(self), as: UTF8.self)
    }

    /// Message that asks the AI to run the workflow now, with the plan as JSON.
    public func prompt() throws -> String {
        """
        Execute o workflow "\(title)" do VibeDeck seguindo o JSON abaixo (máquina de estados: \
        etapas, transições e regras de execução em `rules`).

        ```json
        \(try json())
        ```
        """
    }
}
