import SwiftUI
import VibeDeckCore

/// A workflow: ordered steps (VibeDeck agents/commands/skills), each with conditional transitions to other steps
/// (earlier ones included). The inspector shows the runs, the resulting map and what is broken; "Executar" starts a
/// run on disk and makes the Claude chat its orchestrator (one subagent per step, verdicts pick the transitions).
struct WorkflowView: View {
    let slug: String
    let open: (SidebarItem) -> Void
    @Environment(ProjectModel.self) private var model
    @Environment(ClaudeSession.self) private var claude
    @Environment(\.undoManager) private var undo
    @State private var showMap = true
    @State private var running = false
    @AppStorage("workflowMode") private var mode = Mode.steps

    enum Mode: String, CaseIterable {
        case steps, diagram
        var title: String { self == .steps ? "Etapas" : "Fluxo" }
    }

    private var workflow: Workflow { model.workflow(slug) ?? Workflow(title: slug) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if mode == .diagram, !workflow.steps.isEmpty {
                WorkflowDiagram(steps: workflow.steps, title: title) { open(item($0)) }
            } else {
                stepList
            }
        }
        .inspector(isPresented: $showMap) {
            mapInspector
                .inspectorColumnWidth(min: 260, ideal: 320, max: 440)
        }
        .navigationTitle(workflow.title)
        .navigationSubtitle("\(workflow.steps.count) etapa(s) · até \(workflow.maxSteps ?? Workflow.defaultMaxSteps) por execução")
        .toolbar {
            if ClaudeCode.isInstalled {
                ToolbarItem {
                    Button { running = true } label: { Label("Executar", systemImage: "play") }
                        .disabled(workflow.steps.isEmpty)
                        .help("Executa o workflow no Claude Code: o chat orquestra, cada etapa roda num subagente e o veredito decide a transição")
                }
            }
            ToolbarItem(placement: .principal) {
                Picker("Modo", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .help("Editar as etapas ou ver o fluxo: para onde cada etapa vai, a depender do resultado")
            }
            ToolbarItem {
                Button { copyJSON() } label: { Label("Copiar JSON", systemImage: "curlybraces") }
                    .help("Copia o JSON do workflow (etapas, transições e regras de execução) para orquestrar a IA")
            }
            ToolbarItem {
                Button { showMap.toggle() } label: { Label("Mapa", systemImage: "arrow.triangle.branch") }
                    .keyboardShortcut("i", modifiers: [.command, .option])
                    .help("Mostrar/ocultar o mapa do workflow (⌥⌘I)")
            }
        }
        .sheet(isPresented: $running) {
            WorkflowRunSheet(
                title: workflow.title, inputHint: workflow.input, warnings: model.workflowPlan(slug)?.allWarnings ?? [],
                runs: model.runs(of: slug).map(\.value)
            ) { input in
                guard let prompt = model.startRun(slug, input: input.isEmpty ? nil : input) else { return }
                claude.ask(prompt)
            }
        }
    }

    private var stepList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(workflow.steps.enumerated()), id: \.element.id) { index, step in
                    WorkflowStepCard(
                        index: index, step: step, steps: workflow.steps, title: title, mutate: mutate,
                        open: title(step) == nil ? nil : { open(item(step)) }
                    )
                }
                addStepMenu
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay {
            if workflow.steps.isEmpty {
                ContentUnavailableView("Sem etapas", systemImage: "point.3.connected.trianglepath.dotted",
                                       description: Text("Adicione agentes, comandos ou skills do VibeDeck. A primeira etapa é o início."))
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            CommitTextField("Workflow", value: workflow.title) { title in
                guard !title.isEmpty else { return }
                mutate("Renomear workflow") { $0.title = title }
            }
            .font(.title2.weight(.semibold))
            .textFieldStyle(.plain)

            CommitTextField("O que o workflow faz", value: workflow.summary ?? "") { value in
                mutate("Alterar descrição") { $0.summary = value.isEmpty ? nil : value }
            }
            .textFieldStyle(.plain)
            .foregroundStyle(.secondary)

            // A single HStack (not ViewThatFits): see IdeaView.
            HStack(spacing: 12) {
                CommitTextField("Entrada (ex.: <número do PR>)", value: workflow.input ?? "") { value in
                    mutate("Alterar entrada") { $0.input = value.isEmpty ? nil : value }
                }
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
                .help("O que pedir ao executar o workflow")
                CommitTextField("Limite (\(Workflow.defaultMaxSteps))", value: workflow.maxSteps.map(String.init) ?? "") { value in
                    let limit = Int(value).flatMap { $0 > 0 ? $0 : nil }
                    mutate("Alterar limite de etapas") { $0.maxSteps = limit }
                }
                .textFieldStyle(.roundedBorder)
                .frame(width: 90)
                .help("Máximo de etapas executadas por execução (evita laço infinito)")
                TagsField(tags: workflow.tags) { tags in mutate("Editar tags") { $0.tags = tags } }
                if workflow.author == .ai {
                    Image(systemName: "sparkles").foregroundStyle(.purple).help("Criado por IA")
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var addStepMenu: some View {
        let agents = model.agents, commands = model.commands, skills = model.skills
        return Menu {
            if !agents.isEmpty {
                Section("Agentes") {
                    ForEach(agents) { e in Button(e.value.title) { addStep(.agent, e.slug) } }
                }
            }
            if !commands.isEmpty {
                Section("Comandos") {
                    ForEach(commands) { e in Button(e.value.title) { addStep(.command, e.slug) } }
                }
            }
            if !skills.isEmpty {
                Section("Skills") {
                    ForEach(skills) { e in Button(e.value.title) { addStep(.skill, e.slug) } }
                }
            }
        } label: {
            Label("Adicionar etapa", systemImage: "plus")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(agents.isEmpty && commands.isEmpty && skills.isEmpty)
        .help("Agentes, comandos e skills do VibeDeck")
    }

    // MARK: Map

    private var mapInspector: some View {
        let warnings = model.workflowPlan(slug)?.allWarnings ?? []
        let steps = workflow.steps
        let runs = model.runs(of: slug)
        return List {
            if !runs.isEmpty {
                Section("Execuções") {
                    ForEach(runs) { entry in
                        WorkflowRunRow(ref: entry.slug, run: entry.value, label: { label(of: $0, in: steps) }) {
                            claude.ask(model.orchestratorPrompt(entry.slug, entry.value))
                        }
                    }
                }
            }
            if !warnings.isEmpty {
                Section("Problemas") {
                    ForEach(warnings, id: \.self) { w in
                        Label(w, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    }
                }
            }
            Section("Mapa") {
                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                    VStack(alignment: .leading, spacing: 3) {
                        Label("\(index + 1). \(title(step) ?? step.ref)", systemImage: step.kind.symbol)
                            .font(.body.weight(index == 0 ? .semibold : .regular))
                        ForEach(Array(step.transitions.enumerated()), id: \.offset) { _, t in
                            Text("\(t.label) → \(label(of: t.to, in: steps))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if step.transitions.isEmpty || !step.transitions.contains(where: \.isFallback) {
                            Text(step.transitions.isEmpty ? "→ fim" : "senão → fim")
                                .font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .overlay {
            if steps.isEmpty {
                ContentUnavailableView("Sem etapas", systemImage: "arrow.triangle.branch")
            }
        }
    }

    private func label(of id: String, in steps: [WorkflowStep]) -> String {
        guard let i = steps.firstIndex(where: { $0.id == id }) else { return "\(id) (não existe)" }
        return "\(i + 1). \(title(steps[i]) ?? steps[i].ref)"
    }

    // MARK: Helpers

    private func title(_ step: WorkflowStep) -> String? {
        switch step.kind {
        case .agent: model.agent(step.ref)?.title
        case .command: model.command(step.ref)?.title
        case .skill: model.skill(step.ref)?.title
        }
    }

    private func item(_ step: WorkflowStep) -> SidebarItem {
        switch step.kind {
        case .agent: .agent(step.ref)
        case .command: .command(step.ref)
        case .skill: .skill(step.ref)
        }
    }

    private func mutate(_ actionName: String, _ change: @escaping (inout Workflow) -> Void) {
        model.mutateWorkflow(slug, actionName, undo: undo, change)
    }

    private func addStep(_ kind: NextStepKind, _ ref: String) {
        mutate("Adicionar etapa") { w in
            w.steps.append(WorkflowStep(id: w.newStepId(ref), kind: kind, ref: ref))
        }
    }

    private func copyJSON() {
        guard let json = try? model.workflowPlan(slug)?.json() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(json, forType: .string)
    }
}

private extension NextStepKind {
    var symbol: String {
        switch self {
        case .agent: "person.crop.rectangle"
        case .command: "command"
        case .skill: "wand.and.stars"
        }
    }
}

/// One step: what runs, its extra instruction and its transitions ("se … → etapa", "senão → etapa").
private struct WorkflowStepCard: View {
    let index: Int
    let step: WorkflowStep
    let steps: [WorkflowStep]
    let title: (WorkflowStep) -> String?
    let mutate: (String, @escaping (inout Workflow) -> Void) -> Void
    let open: (() -> Void)?
    @Environment(ProjectModel.self) private var model
    @State private var condition = ""
    @State private var target = ""
    @State private var byVerdict = true

    private var hasFallback: Bool { step.transitions.contains(where: \.isFallback) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("\(index + 1)")
                    .font(.caption.weight(.bold)).monospacedDigit()
                    .frame(width: 22, height: 22)
                    .background(.tint.opacity(0.15), in: Circle())
                Image(systemName: step.kind.symbol)
                Text(title(step) ?? step.ref).font(.headline)
                if index == 0 {
                    Text("Início").font(.caption.weight(.medium))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.green.opacity(0.18), in: Capsule())
                }
                if title(step) == nil {
                    Text(missing).font(.caption).foregroundStyle(.red)
                }
                Spacer()
                Text(step.id).font(.caption.monospaced()).foregroundStyle(.secondary)
                if let open {
                    Button(action: open) { Image(systemName: "arrow.right.circle") }
                        .buttonStyle(.borderless)
                        .help("Abrir")
                }
                Menu {
                    Button("Mover para cima") { change("Mover etapa") { w, i in w.steps.swapAt(i, i - 1) } }
                        .disabled(index == 0)
                    Button("Mover para baixo") { change("Mover etapa") { w, i in w.steps.swapAt(i, i + 1) } }
                        .disabled(index == steps.count - 1)
                    Button("Tornar início") { change("Tornar início") { w, i in w.steps.insert(w.steps.remove(at: i), at: 0) } }
                        .disabled(index == 0)
                    Divider()
                    Button("Remover etapa", role: .destructive) { change("Remover etapa") { w, i in w.removeStep(at: i) } }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            HStack(spacing: 8) {
                CommitTextField(step.kind == .command ? "Argumentos ($ARGUMENTS) ou instrução extra" : "Instrução extra da etapa (opcional)",
                                value: step.note ?? "") { value in
                    change("Alterar instrução") { w, i in w.steps[i].note = value.isEmpty ? nil : value }
                }
                .textFieldStyle(.roundedBorder)
                CommitTextField("Máx. vezes", value: step.maxVisits.map(String.init) ?? "") { value in
                    let limit = Int(value).flatMap { $0 > 0 ? $0 : nil }
                    change("Alterar máximo de vezes") { w, i in w.steps[i].maxVisits = limit }
                }
                .textFieldStyle(.roundedBorder)
                .frame(width: 90)
                .help("Quantas vezes a etapa pode rodar por ciclo de uma execução (vazio = sem limite)")
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(step.transitions.enumerated()), id: \.offset) { j, t in
                    transitionRow(j, t)
                }
                if !hasFallback {
                    Text(step.transitions.isEmpty ? "Sem transições: o workflow termina aqui." : "Se nenhuma valer, o workflow termina.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                newTransitionRow
            }
            .padding(.leading, 30)
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }

    private var missing: String {
        switch step.kind {
        case .agent: "Agente não encontrado"
        case .command: "Comando não encontrado"
        case .skill: "Skill não encontrada"
        }
    }

    private func transitionRow(_ j: Int, _ t: WorkflowTransition) -> some View {
        HStack(spacing: 8) {
            if let verdict = t.verdict {
                Text("=").foregroundStyle(.secondary).help("Veredito: a última linha do resultado da etapa")
                CommitTextField("veredito", value: verdict) { value in
                    guard !value.isEmpty else { return }
                    change("Alterar veredito") { w, i in w.steps[i].transitions[j].verdict = value }
                }
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
            } else if let when = t.when {
                Text("se").foregroundStyle(.secondary)
                CommitTextField("condição", value: when) { value in
                    if value.isEmpty, hasFallback {
                        model.errorMessage = "A etapa já tem uma transição sem condição (senão)."
                        return
                    }
                    change("Alterar condição") { w, i in
                        if value.isEmpty {
                            // Becomes the fallback, which goes last.
                            var moved = w.steps[i].transitions.remove(at: j)
                            moved.when = nil
                            w.steps[i].transitions.append(moved)
                        } else {
                            w.steps[i].transitions[j].when = value
                        }
                    }
                }
                .textFieldStyle(.roundedBorder)
            } else {
                Text("senão").foregroundStyle(.secondary)
                Spacer()
            }
            Image(systemName: "arrow.right").foregroundStyle(.secondary)
            Picker("Destino", selection: Binding(get: { t.to }, set: { to in
                change("Alterar destino") { w, i in w.steps[i].transitions[j].to = to }
            })) {
                if !steps.contains(where: { $0.id == t.to }) { Text("\(t.to) (não existe)").tag(t.to) }
                ForEach(Array(steps.enumerated()), id: \.element.id) { n, s in
                    Text("\(n + 1). \(title(s) ?? s.ref)").tag(s.id)
                }
            }
            .labelsHidden()
            .fixedSize()
            Button { change("Remover transição") { w, i in w.steps[i].transitions.remove(at: j) } } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Remover transição")
        }
    }

    private var newTransitionRow: some View {
        let trimmed = condition.trimmingCharacters(in: .whitespacesAndNewlines)
        let blocked = trimmed.isEmpty && hasFallback
        let placeholder = byVerdict
            ? (hasFallback ? "Novo veredito (ex.: APROVADO)" : "Novo veredito (vazio = senão)")
            : (hasFallback ? "Nova condição (ex.: encontrou problemas)" : "Nova condição (vazio = senão)")
        return HStack(spacing: 8) {
            Picker("Tipo", selection: $byVerdict) {
                Text("=").tag(true)
                Text("se").tag(false)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .fixedSize()
            .help("= veredito (última linha do resultado da etapa) · se = condição em linguagem natural")
            TextField(placeholder, text: $condition)
                .textFieldStyle(.roundedBorder)
                .onSubmit(addTransition)
            Image(systemName: "arrow.right").foregroundStyle(.secondary)
            Picker("Destino", selection: $target) {
                Text("Etapa…").tag("")
                ForEach(Array(steps.enumerated()), id: \.element.id) { n, s in
                    Text("\(n + 1). \(title(s) ?? s.ref)").tag(s.id)
                }
            }
            .labelsHidden()
            .fixedSize()
            Button(action: addTransition) { Image(systemName: "plus.circle") }
                .buttonStyle(.borderless)
                .disabled(target.isEmpty || blocked)
                .help(blocked ? "A etapa já tem um senão" : "Adicionar transição (pode voltar a etapas anteriores)")
        }
    }

    private func addTransition() {
        let when = condition.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty, !(when.isEmpty && hasFallback) else { return }
        let value = when.isEmpty ? nil : when
        let transition = byVerdict ? WorkflowTransition(verdict: value, to: target) : WorkflowTransition(when: value, to: target)
        change("Adicionar transição") { w, i in w.addTransition(transition, toStepAt: i) }
        condition = ""
        target = ""
    }

    /// Mutates the workflow at this step's current index (looked up by id, so it survives reordering).
    private func change(_ actionName: String, _ body: @escaping (inout Workflow, Int) -> Void) {
        let id = step.id
        mutate(actionName) { w in
            guard let i = w.steps.firstIndex(where: { $0.id == id }) else { return }
            body(&w, i)
        }
    }
}

/// One run in the inspector: status, where it is, open questions and the path taken (verdicts).
private struct WorkflowRunRow: View {
    let ref: String
    let run: WorkflowRun
    let label: (String) -> String
    let resume: () -> Void
    @Environment(ProjectModel.self) private var model
    @Environment(ClaudeSession.self) private var claude
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 3) {
                if let reason = run.reason {
                    Text(reason).font(.caption).foregroundStyle(.secondary)
                }
                ForEach(Array(run.history.enumerated()), id: \.offset) { n, e in
                    Text("\(n + 1). \(e.step) → \(e.verdict ?? "—")")
                        .font(.caption.monospaced())
                        .help(e.summary ?? "")
                }
                ForEach(run.openQuestions) { q in
                    Label(q.question, systemImage: "questionmark.bubble").font(.caption).foregroundStyle(.orange)
                }
                HStack {
                    if ClaudeCode.isInstalled, run.status != .done {
                        Button(run.isFinished ? "Retomar" : "Continuar") {
                            if run.isFinished, let prompt = model.startRun(run.workflow, input: run.input) {
                                claude.ask(prompt)
                            } else {
                                resume()
                            }
                        }
                        .help("O chat volta a orquestrar esta execução de onde ela parou")
                    }
                    if !run.isFinished {
                        Button("Parar") { model.stopRun(ref) }
                    }
                    Button("Apagar", role: .destructive) { model.deleteRun(ref) }
                        .help("Move a execução e os arquivos das etapas para a Lixeira")
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .padding(.top, 2)
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Label(run.input ?? ref.split(separator: "/").last.map(String.init) ?? ref, systemImage: symbol)
                    .foregroundStyle(color)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var subtitle: String {
        var parts = [run.status.title]
        if let current = run.current, !run.isFinished { parts.append(label(current)) }
        if !run.openQuestions.isEmpty { parts.append("\(run.openQuestions.count) pergunta(s)") }
        return parts.joined(separator: " · ")
    }

    private var symbol: String {
        switch run.status {
        case .running: "play.circle"
        case .waiting: "questionmark.circle"
        case .done: "checkmark.circle"
        case .stopped: "stop.circle"
        }
    }

    private var color: Color {
        switch run.status {
        case .running: .accentColor
        case .waiting: .orange
        case .done: .green
        case .stopped: .secondary
        }
    }
}

extension WorkflowRunStatus {
    var title: String {
        switch self {
        case .running: "Em andamento"
        case .waiting: "Aguardando resposta"
        case .done: "Concluída"
        case .stopped: "Parada"
        }
    }
}

/// Asks for the run's input, then starts (or resumes) the run and makes the Claude chat its orchestrator.
private struct WorkflowRunSheet: View {
    let title: String
    let inputHint: String?
    let warnings: [String]
    let runs: [WorkflowRun]
    let onRun: (String) -> Void
    @State private var input = ""
    @Environment(\.dismiss) private var dismiss

    /// The run this input resumes (runs are named after their input).
    private var existing: WorkflowRun? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return runs.first { $0.input.map(Slug.make) == Slug.make(trimmed) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Executar \"\(title)\"").font(.headline)
            Text("O chat orquestra: cada etapa roda num subagente com contexto limpo, o veredito decide a próxima e as perguntas das etapas chegam até você aqui.")
                .font(.callout).foregroundStyle(.secondary)
            TextField(inputHint ?? "Entrada (opcional)", text: $input, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.roundedBorder)
            if let existing {
                Label(
                    existing.isFinished
                        ? "Já existe uma execução com essa entrada (\(existing.status.title.lowercased())): ela recomeça num novo ciclo."
                        : "Já existe uma execução com essa entrada: ela continua de \(existing.current ?? "onde parou").",
                    systemImage: "arrow.clockwise"
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            if !warnings.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(warnings, id: \.self) { w in
                        Label(w, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                    }
                }
            }
            HStack {
                Spacer()
                Button("Cancelar", role: .cancel) { dismiss() }.buttonStyle(.glass)
                Button(existing == nil ? "Executar" : "Retomar", action: run)
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private func run() {
        onRun(input.trimmingCharacters(in: .whitespacesAndNewlines))
        dismiss()
    }
}
