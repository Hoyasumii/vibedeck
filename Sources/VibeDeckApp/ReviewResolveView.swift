import SwiftUI

/// Drives "Resolver": questions and plan with read-only tools, explicit acceptance, then writes one item at a time.
/// One runner per project (owned by `ProjectModel`), so only one Resolver runs at once. Status changes go through
/// `ProjectModel.mutateItem`, which registers undo; nothing here removes an item or writes `wontfix`.
@Observable @MainActor
final class ReviewResolveRunner {
    struct Entry: Identifiable {
        let item: ReviewItem
        let kind: String
        var questions: [ReviewResolve.Question] = []
        var answers: [Int: String] = [:]
        var plan: ReviewResolve.Plan?
        var outcome: ReviewResolve.Outcome?
        var id: ReviewItem.ID { item.id }

        var answered: [ReviewResolve.Answered] {
            questions.map { .init(question: $0.text, answer: (answers[$0.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) }
        }
        var hasAllAnswers: Bool { !answered.contains { $0.answer.isEmpty } }
    }

    enum Phase: Equatable {
        case idle, planning, asking, review, executing, finished
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    var entries: [Entry] = []
    private(set) var current: ReviewItem.ID?
    private(set) var title = ""
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var slug = ""
    @ObservationIgnored private var provider: AIProvider = .claude
    @ObservationIgnored private var single: ReviewItem.ID?
    @ObservationIgnored private weak var model: ProjectModel?
    @ObservationIgnored private var undo: UndoManager?

    var isActive: Bool { phase != .idle }
    var isBusy: Bool { phase == .planning || phase == .executing }
    var completed: Int { entries.filter { $0.outcome != nil }.count }

    /// Starts a run for `items` (already restricted to open/in_progress). Ignored while another run is active.
    func start(group slug: String, title: String, items: [ReviewItem], single: ReviewItem.ID? = nil,
               model: ProjectModel, provider: AIProvider, undo: UndoManager?) {
        guard !isActive else { return }
        let eligible = ReviewResolve.eligible(items)
        self.slug = slug; self.title = title; self.single = single
        self.model = model; self.provider = provider; self.undo = undo
        entries = eligible.map { Entry(item: $0, kind: model.project.kind($0.kind).label) }
        guard RemoteExecution.available(provider, root: model.store.root) else { phase = .failed("\(provider.title) não está instalado."); return }
        guard !entries.isEmpty else { phase = .failed("Não há itens abertos ou em andamento para resolver."); return }
        plan()
    }

    func cancel() {
        task?.cancel(); task = nil
        switch phase {
        case .planning, .asking, .review: phase = .idle; entries = []
        case .executing: phase = .finished   // the loop marks the rest as skipped; nothing becomes done
        default: break
        }
    }

    func dismiss() {
        guard !isBusy else { return }
        phase = .idle; entries = []
    }

    /// The user left the selected item while its plan was pending: the answer would be stale, so it is dropped.
    func selectionChanged(to selection: ReviewItem.ID?) {
        guard let single, selection != single, [.planning, .asking, .review].contains(phase) else { return }
        task?.cancel(); task = nil
        phase = .failed("O item deixou de estar selecionado; nada foi alterado.")
    }

    // MARK: Plan (read-only)

    func submitAnswers() {
        guard phase == .asking, entries.allSatisfy({ $0.questions.isEmpty || $0.hasAllAnswers }) else { return }
        plan()
    }

    private func plan() {
        phase = .planning
        task = Task { [weak self] in
            guard let self else { return }
            for index in entries.indices where entries[index].plan == nil {
                guard entries[index].questions.isEmpty || entries[index].hasAllAnswers else { continue }
                let entry = entries[index]
                current = entry.id
                let answers = entry.answered
                let prompt = ReviewResolve.planPrompt(item: entry.item, kind: entry.kind, answers: answers)
                let allowQuestions = answers.isEmpty
                do {
                    let reply = try await AIReadOnlyOperation.run(
                        root: model?.store.root ?? URL(fileURLWithPath: "/"), provider: provider, operation: "Resolver (plano)",
                        prompt: prompt, schema: ReviewResolve.schema) { data in
                        try ReviewResolve.parse(data, allowQuestions: allowQuestions)
                    }
                    guard !Task.isCancelled else { return }
                    guard isUnchanged(entry.item) else {
                        phase = .failed("O item «\(entry.item.title)» mudou durante o plano; nada foi alterado. Rode o Resolver de novo.")
                        return
                    }
                    switch reply {
                    case .questions(let questions): entries[index].questions = questions
                    case .plan(let plan): entries[index].plan = plan
                    }
                } catch is CancellationError {
                    return
                } catch {
                    guard !Task.isCancelled else { return }
                    phase = .failed(error.localizedDescription)
                    return
                }
            }
            current = nil
            phase = entries.contains { $0.plan == nil } ? .asking : .review
        }
    }

    private func isUnchanged(_ snapshot: ReviewItem) -> Bool {
        guard let item = model?.group(slug)?.items.first(where: { $0.id == snapshot.id }) else { return false }
        return item.updatedAt == snapshot.updatedAt && item.status == snapshot.status
    }

    // MARK: Execute (after acceptance)

    /// Writing starts here and only here, after the user accepted the plans.
    func accept() {
        guard phase == .review, entries.allSatisfy({ $0.plan != nil }), let model else { return }
        phase = .executing
        let items = entries.map(\.item)
        task = Task { [weak self] in
            guard let self else { return }
            let results = await ReviewResolve.resolveSequentially(items) { item in
                try await self.resolve(item, model: model)
            }
            for result in results {
                if let index = entries.firstIndex(where: { $0.id == result.id }) { entries[index].outcome = result.outcome }
            }
            current = nil
            phase = .finished
        }
    }

    private func resolve(_ item: ReviewItem, model: ProjectModel) async throws -> ReviewResolve.Outcome {
        guard let index = entries.firstIndex(where: { $0.id == item.id }), let plan = entries[index].plan else { return .skipped }
        current = item.id
        guard isUnchanged(item) else { return .failed("O item mudou antes da execução; nada foi alterado.") }
        let prompt = ReviewResolve.executionPrompt(item: item, kind: entries[index].kind, plan: plan, answers: entries[index].answered)
        let started = Date.now
        try await RuleTestGenerator.run(root: model.store.root, store: model.store, prompt: prompt, provider: provider, operation: "Resolver")
        try Task.checkCancellation()
        let store = model.store
        let problems = await ReviewResolve.verify(store: store, item: item, files: plan.files, verifiedSince: started,
                                                  checks: model.checks, topics: model.topics.map(\.value))
        try Task.checkCancellation()
        guard problems.isEmpty else {
            return .failed("Check não aprovado; o item continua como estava.\n" + problems.joined(separator: "\n"))
        }
        model.mutateItem(slug, item.id, "Resolver item", undo: undo) { $0.status = .done }
        return .resolved
    }
}

// MARK: - Sheet

struct ReviewResolveSheet: View {
    @Environment(\.logProject) private var logProject
    @Bindable var runner: ReviewResolveRunner

    var body: some View {
        VStack(spacing: 0) {
            content
            Divider()
            HStack {
                Spacer()
                buttons
            }
            .padding()
        }
        .frame(width: 560, height: 480)
        .navigationTitle("Resolver")
        .interactiveDismissDisabled(runner.isBusy)
    }

    @ViewBuilder
    private var content: some View {
        switch runner.phase {
        case .idle:
            EmptyView()
        case .planning:
            progress("Montando o plano (só leitura)…")
        case .executing:
            progress("Resolvendo \(runner.completed + 1) de \(runner.entries.count)…")
        case .asking:
            Form {
                ForEach($runner.entries) { $entry in
                    if !entry.questions.isEmpty {
                        Section(entry.item.title) {
                            ForEach(entry.questions) { question in
                                TextField(question.text, text: answerBinding($entry, question.id), axis: .vertical)
                                    .lineLimit(1...4)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
        case .review:
            Form {
                Section { Text("Nada foi alterado ainda. Revise o plano e aceite para a IA começar a escrever neste projeto.").font(.callout).foregroundStyle(.secondary) }
                ForEach(runner.entries) { entry in
                    if let plan = entry.plan {
                        Section(entry.item.title) {
                            Text(plan.summary)
                            ForEach(Array(plan.steps.enumerated()), id: \.offset) { index, step in
                                Text("\(index + 1). \(step)").font(.callout)
                            }
                            if !plan.files.isEmpty {
                                Text(plan.files.joined(separator: "\n")).font(.caption.monospaced()).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
        case .finished:
            Form {
                ForEach(runner.entries) { entry in
                    Section(entry.item.title) { outcome(entry.outcome) }
                }
            }
            .formStyle(.grouped)
        case .failed(let message):
            ContentUnavailableView("Resolver parou", systemImage: "exclamationmark.triangle", description: Text(message))
        }
    }

    @ViewBuilder
    private var buttons: some View {
        switch runner.phase {
        case .planning, .executing:
            LoggedButton("Cancelar", role: .cancel) { runner.cancel() }
                .loggedControl(control: "review_resolve.button_1", label: "Cancelar")
        case .asking:
            LoggedButton("Cancelar", role: .cancel) { runner.cancel() }
                .loggedControl(control: "review_resolve.button_2", label: "Cancelar")
            LoggedButton("Enviar respostas") { runner.submitAnswers() }
                .loggedControl(control: "review_resolve.button_3", label: "Enviar respostas")
                .keyboardShortcut(.defaultAction)
                .disabled(runner.entries.contains { !$0.questions.isEmpty && !$0.hasAllAnswers })
        case .review:
            LoggedButton("Recusar", role: .cancel) { runner.cancel() }
                .loggedControl(control: "review_resolve.button_4", label: "Recusar")
            LoggedButton("Aceitar e executar") { runner.accept() }
                .loggedControl(control: "review_resolve.button_5", label: "Aceitar e executar")
                .keyboardShortcut(.defaultAction)
        case .finished, .failed:
            LoggedButton("Fechar") { runner.dismiss() }
                .loggedControl(control: "review_resolve.button_6", label: "Fechar")
                .keyboardShortcut(.defaultAction)
        case .idle:
            EmptyView()
        }
    }

    private func progress(_ text: String) -> some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.large)
            Text(text).foregroundStyle(.secondary)
            if let id = runner.current, let entry = runner.entries.first(where: { $0.id == id }) {
                Text(entry.item.title).font(.callout.weight(.medium))
            }
            if runner.phase == .executing {
                ProgressView(value: Double(runner.completed), total: Double(max(runner.entries.count, 1)))
                    .padding(.horizontal, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func outcome(_ outcome: ReviewResolve.Outcome?) -> some View {
        switch outcome {
        case .resolved:
            Label("Resolvido e marcado como feito", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
        case .cancelled:
            Label("Cancelado; o item continua como estava", systemImage: "xmark.circle").foregroundStyle(.secondary)
        case .skipped, nil:
            Label("Não tentado; o item continua como estava", systemImage: "minus.circle").foregroundStyle(.secondary)
        }
    }

    private func answerBinding(_ entry: Binding<ReviewResolveRunner.Entry>, _ id: Int) -> Binding<String> {
        Binding(get: { entry.wrappedValue.answers[id] ?? "" }, set: { entry.wrappedValue.answers[id] = $0 })
    }
}
