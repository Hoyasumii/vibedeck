import SwiftUI
import VibeDeckCore

/// A workflow: ordered steps (VibeDeck agents/commands/skills), each with conditional transitions to other steps
/// (earlier ones included). The inspector shows the runs, the resulting map and what is broken; "Executar" starts a
/// run on disk and makes the Claude chat its orchestrator (one subagent per step, verdicts pick the transitions).
struct WorkflowView: View {
    @Environment(\.logProject) private var providerRoot
    @Environment(\.logProject) private var logProject
    let slug: String
    let open: (SidebarItem) -> Void
    @Environment(ProjectModel.self) private var model
    @Environment(AISession.self) private var claude
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
            ToolbarItem { KitCatalogButton() }
            ToolbarItem { EditWithAIButton(kind: .workflow, slug: slug) }
            if !AIProvider.installed(in: providerRoot).isEmpty {
                ToolbarItem {
                    LoggedButton { running = true } label: { Label("Executar", systemImage: "play") }.loggedControl(control: "workflow_view.button_1", label: "Executar")
                        .disabled(workflow.steps.isEmpty)
                        .help("Executa o workflow no provedor selecionado: o chat orquestra, cada etapa roda num subagente e o veredito decide a transição")
                }
            }
            ToolbarItem(placement: .principal) {
                Picker("Modo", selection: $mode.logging(control: "workflow_view.selection_19", label: "Modo", project: logProject)) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .help("Editar as etapas ou ver o fluxo: para onde cada etapa vai, a depender do resultado")
            }
            ToolbarItem {
                LoggedButton { copyJSON() } label: { Label("Copiar JSON", systemImage: "curlybraces") }.loggedControl(control: "workflow_view.button_2", label: "Copiar JSON")
                    .help("Copia o JSON do workflow (etapas, transições e regras de execução) para orquestrar a IA")
            }
            ToolbarItem {
                LoggedButton { showMap.toggle() } label: { Label("Mapa", systemImage: "arrow.triangle.branch") }.loggedControl(control: "workflow_view.button_3", label: "Mapa")
                    .keyboardShortcut("i", modifiers: [.command, .option])
                    .help("Mostrar/ocultar o mapa do workflow (⌥⌘I)")
            }
        }
        .sheet(isPresented: $running) {
            WorkflowRunSheet(
                title: workflow.title, inputHint: workflow.input, warnings: model.workflowPlan(slug)?.allWarnings ?? [],
                runs: model.runs(of: slug).map(\.value)
            ) { input in
                claude.executeWorkflow(slug, input: input.isEmpty ? nil : input, store: model.store)
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
            CommitTextField(control: "workflowview.field_1", "Workflow", value: workflow.title) { title in
                guard !title.isEmpty else { return }
                mutate("Renomear workflow") { $0.title = title }
            }
            .font(.title2.weight(.semibold))
            .textFieldStyle(.plain)

            CommitTextField(control: "workflowview.field_2", "O que o workflow faz", value: workflow.summary ?? "") { value in
                mutate("Alterar descrição") { $0.summary = value.isEmpty ? nil : value }
            }
            .textFieldStyle(.plain)
            .foregroundStyle(.secondary)

            // A single HStack (not ViewThatFits): see IdeaView.
            HStack(spacing: 12) {
                CommitTextField(control: "workflowview.field_3", "Entrada (ex.: <número do PR>)", value: workflow.input ?? "") { value in
                    mutate("Alterar entrada") { $0.input = value.isEmpty ? nil : value }
                }
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
                .help("O que pedir ao executar o workflow")
                CommitTextField(control: "workflowview.field_4", "Limite (\(Workflow.defaultMaxSteps))", value: workflow.maxSteps.map(String.init) ?? "") { value in
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
                    ForEach(agents) { e in LoggedButton(e.value.title) { addStep(.agent, e.slug) }.loggedControl(control: "workflow_view.button_4", label: "Ativar controle") }
                }
            }
            if !commands.isEmpty {
                Section("Comandos") {
                    ForEach(commands) { e in LoggedButton(e.value.title) { addStep(.command, e.slug) }.loggedControl(control: "workflow_view.button_5", label: "Ativar controle") }
                }
            }
            if !skills.isEmpty {
                Section("Skills") {
                    ForEach(skills) { e in LoggedButton(e.value.title) { addStep(.skill, e.slug) }.loggedControl(control: "workflow_view.button_6", label: "Ativar controle") }
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
                            claude.resumeWorkflow(entry.slug, run: entry.value, store: model.store)
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
    @Environment(\.logProject) private var providerRoot
    @Environment(\.logProject) private var logProject
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
                    LoggedButton(action: open) { Image(systemName: "arrow.right.circle") }.loggedControl(control: "workflow_view.button_7", label: "Ativar controle")
                        .buttonStyle(.borderless)
                        .help("Abrir")
                }
                Menu {
                    LoggedButton("Mover para cima") { change("Mover etapa") { w, i in w.steps.swapAt(i, i - 1) } }.loggedControl(control: "workflow_view.button_8", label: "Mover para cima")
                        .disabled(index == 0)
                    LoggedButton("Mover para baixo") { change("Mover etapa") { w, i in w.steps.swapAt(i, i + 1) } }.loggedControl(control: "workflow_view.button_9", label: "Mover para baixo")
                        .disabled(index == steps.count - 1)
                    LoggedButton("Tornar início") { change("Tornar início") { w, i in w.steps.insert(w.steps.remove(at: i), at: 0) } }.loggedControl(control: "workflow_view.button_10", label: "Tornar início")
                        .disabled(index == 0)
                    Divider()
                    LoggedButton("Remover etapa", role: .destructive) { change("Remover etapa") { w, i in w.removeStep(at: i) } }.loggedControl(control: "workflow_view.button_11", label: "Remover etapa")
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            HStack(spacing: 8) {
                CommitTextField(control: "workflowview.field_5", step.kind == .command ? "Argumentos ($ARGUMENTS) ou instrução extra" : "Instrução extra da etapa (opcional)",
                                value: step.note ?? "") { value in
                    change("Alterar instrução") { w, i in w.steps[i].note = value.isEmpty ? nil : value }
                }
                .textFieldStyle(.roundedBorder)
                CommitTextField(control: "workflowview.field_6", "Máx. vezes", value: step.maxVisits.map(String.init) ?? "") { value in
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
                CommitTextField(control: "workflowview.field_7", "veredito", value: verdict) { value in
                    guard !value.isEmpty else { return }
                    change("Alterar veredito") { w, i in w.steps[i].transitions[j].verdict = value }
                }
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
            } else if let when = t.when {
                Text("se").foregroundStyle(.secondary)
                CommitTextField(control: "workflowview.field_8", "condição", value: when) { value in
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
            }).logging(control: "workflow_view.selection_20", label: "Destino", project: logProject)) {
                if !steps.contains(where: { $0.id == t.to }) { Text("\(t.to) (não existe)").tag(t.to) }
                ForEach(Array(steps.enumerated()), id: \.element.id) { n, s in
                    Text("\(n + 1). \(title(s) ?? s.ref)").tag(s.id)
                }
            }
            .labelsHidden()
            .fixedSize()
            LoggedButton { change("Remover transição") { w, i in w.steps[i].transitions.remove(at: j) } } label: {
                Image(systemName: "minus.circle")
            }.loggedControl(control: "workflow_view.button_12", label: "Ativar controle")
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
            Picker("Tipo", selection: $byVerdict.logging(control: "workflow_view.selection_21", label: "Tipo", project: logProject)) {
                Text("=").tag(true)
                Text("se").tag(false)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .fixedSize()
            .help("= veredito (última linha do resultado da etapa) · se = condição em linguagem natural")
            LoggedTextField(placeholder, text: $condition, onCommit: addTransition).loggedField(control: "workflowview.text_1", label: "Confirmar campo")
                .textFieldStyle(.roundedBorder)

            Image(systemName: "arrow.right").foregroundStyle(.secondary)
            Picker("Destino", selection: $target.logging(control: "workflow_view.selection_22", label: "Destino", project: logProject)) {
                Text("Etapa…").tag("")
                ForEach(Array(steps.enumerated()), id: \.element.id) { n, s in
                    Text("\(n + 1). \(title(s) ?? s.ref)").tag(s.id)
                }
            }
            .labelsHidden()
            .fixedSize()
            LoggedButton(action: addTransition) { Image(systemName: "plus.circle") }.loggedControl(control: "workflow_view.button_13", label: "Ativar controle")
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
    @Environment(\.logProject) private var providerRoot
    @Environment(\.logProject) private var logProject
    let ref: String
    let run: WorkflowRun
    let label: (String) -> String
    let resume: () -> Void
    @Environment(ProjectModel.self) private var model
    @Environment(AISession.self) private var claude
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
                    if !AIProvider.installed(in: providerRoot).isEmpty, run.status != .done {
                        LoggedButton(run.isFinished ? "Retomar" : "Continuar") {
                            do {
                                let resumed = try model.store.resumeRun(ref)
                                claude.resumeWorkflow(ref, run: resumed, store: model.store)
                            } catch { model.errorMessage = error.localizedDescription }
                        }.loggedControl(control: "workflow_view.button_14", label: "Ativar controle")
                        .help("O chat volta a orquestrar esta execução de onde ela parou")
                    }
                    if !run.isFinished {
                        LoggedButton("Parar") { model.stopRun(ref) }.loggedControl(control: "workflow_view.button_15", label: "Parar")
                    }
                    LoggedButton("Apagar", role: .destructive) { model.deleteRun(ref) }.loggedControl(control: "workflow_view.button_16", label: "Apagar")
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

    private var symbol: String { run.status.symbol }

    private var color: Color { run.status.color }
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

    var symbol: String {
        switch self {
        case .running: "play.circle"
        case .waiting: "questionmark.circle"
        case .done: "checkmark.circle"
        case .stopped: "stop.circle"
        }
    }

    var color: Color {
        switch self {
        case .running: .accentColor
        case .waiting: .orange
        case .done: .green
        case .stopped: .secondary
        }
    }
}

/// Asks for the run's input, then starts (or resumes) the run and makes the Claude chat its orchestrator.
private struct WorkflowRunSheet: View {
    @Environment(\.logProject) private var providerRoot
    @Environment(\.logProject) private var logProject
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
            LoggedTextField(inputHint ?? "Entrada (opcional)", text: $input, axis: .vertical).loggedField(control: "workflowview.text_2", label: "Confirmar campo")
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
                LoggedButton("Cancelar", role: .cancel) { dismiss() }.loggedControl(control: "workflow_view.button_17", label: "Cancelar").buttonStyle(.glass)
                LoggedButton(existing == nil ? "Executar" : "Retomar", action: run).loggedControl(control: "workflow_view.button_18", label: "Ativar controle")
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

/// One app gate for the Implementar button and chat requests. No project write until final confirmation.
struct IdeaImplementationSheet: View {
    @Environment(ProjectModel.self) private var model
    @Environment(AISession.self) private var session
    @Environment(\.undoManager) private var undo
    @Environment(\.logProject) private var logProject
    let request: AISession.IdeaRequest
    @State private var choosingWorkflow = false
    @State private var workflow: String?
    @State private var existing: WorkflowRun?
    @State private var stalePaths: [String] = []
    @State private var pendingRestart = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Implementar ideia").font(.headline)
            if let error {
                Text(error).foregroundStyle(.red)
            } else if !stalePaths.isEmpty {
                Text("Globs que não casam nenhum arquivo")
                Text(stalePaths.joined(separator: "\n")).font(.caption)
                LoggedButton("Promover sem eles") { finish(skipping: Set(stalePaths)) }
                    .loggedControl(control: "idea_implementation.skip_paths", label: "Promover sem eles")
                LoggedButton("Promover com eles") { finish() }
                    .loggedControl(control: "idea_implementation.keep_paths", label: "Promover com eles")
            } else if let existing {
                Text("Já existe uma execução para esta ideia e este workflow. Deseja retomar do estado salvo ou reiniciar pela primeira etapa?")
                Text("Ciclo \(existing.cycle) · \(existing.current ?? "Concluída")").font(.caption).foregroundStyle(.secondary)
                LoggedButton("Retomar") { confirm(restart: false) }
                    .loggedControl(control: "idea_implementation.resume", label: "Retomar")
                LoggedButton("Reiniciar") { confirm(restart: true) }
                    .loggedControl(control: "idea_implementation.restart", label: "Reiniciar")
            } else if choosingWorkflow {
                Text("Escolha um workflow do projeto.")
                ForEach(model.workflows) { entry in
                    LoggedButton { selectWorkflow(entry.slug) } label: { Text(entry.value.title) }
                        .loggedControl(control: "idea_implementation.select_workflow", label: "Selecionar workflow")
                }
                KitCatalogButton()
            } else {
                Text("Como deseja implementar esta ideia?")
                if !model.workflows.isEmpty {
                    LoggedButton("Workflow") { choosingWorkflow = true }
                        .loggedControl(control: "idea_implementation.workflow", label: "Workflow")
                }
                LoggedButton("Execução padrão") { confirm(restart: false) }
                    .loggedControl(control: "idea_implementation.standard", label: "Execução padrão")
            }
            HStack {
                Spacer()
                LoggedButton("Cancelar", role: .cancel) { session.ideaRequest = nil }
                    .loggedControl(control: "idea_implementation.cancel", label: "Cancelar")
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24).frame(width: 440)
        .task {
            VDLog.$actionID.withValue(request.actionID) {
                if request.mode == .standard { confirm(restart: false) }
                else if request.mode == .workflow {
                    if let workflow = request.workflow { selectWorkflow(workflow) }
                    else if !model.workflows.isEmpty { choosingWorkflow = true }
                }
            }
        }
    }

    private func selectWorkflow(_ slug: String) {
        do {
            let (_, idea) = try model.currentImplementationIdea(request.ideaID)
            workflow = slug
            existing = try model.store.ideaRun(idea, workflow: slug)?.run
            if existing == nil { confirm(restart: false) }
        } catch { self.error = error.localizedDescription }
    }

    private func confirm(restart: Bool) {
        do {
            let (slug, _) = try model.currentImplementationIdea(request.ideaID)
            pendingRestart = restart
            stalePaths = try model.store.unmatchedIdeaPaths(slug)
            if stalePaths.isEmpty { finish() }
        } catch { self.error = error.localizedDescription }
    }

    private func finish(skipping: Set<String> = []) {
        do {
            guard !session.isWorking else { return }
            try RemoteWorkspace.existing(at: model.store.root)?.requireSynchronized()
            let (_, idea) = try model.currentImplementationIdea(request.ideaID)
            if let workflow, let latest = try model.store.ideaRun(idea, workflow: workflow)?.run,
               latest.id != existing?.id {
                existing = latest
                stalePaths = []
                return
            }
            let prepared = try model.prepareIdeaImplementation(request.ideaID, workflow: workflow,
                restart: pendingRestart, skippingPaths: skipping, provider: session.provider, undo: undo)
            session.ideaRequest = nil
            if let execution = prepared.execution {
                session.resumeWorkflow(execution.ref, run: execution.run, store: model.store)
            } else {
                session.ask(prepared.prompt, inspectIdeas: false)
            }
        } catch { self.error = error.localizedDescription }
    }
}
