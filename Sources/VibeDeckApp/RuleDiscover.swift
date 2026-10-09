import SwiftUI
import VibeDeckCore

/// Runs the rules "Descubra" for a topic or an idea: first a read-only call proposing globs and tags, then an
/// interview (rounds of questions) that drafts rules. Each answer only becomes a proposal; the view applies
/// what the user accepts.
@Observable @MainActor
final class RuleDiscoverRunner {
    enum State: Equatable {
        case idle
        case running(String)
        case failed(String)
        case scope(RuleDiscoverScope)
        case questions([RuleDiscover.Question])
        case drafts(RuleDiscoverDrafts)
    }

    var state: State = .idle
    /// Questions answered so far in this interview.
    private(set) var history: [RuleDiscover.Exchange] = []
    private(set) var round = 0
    /// What the running call was built from; a different subject means the answer is stale.
    @ObservationIgnored private var snapshot: RuleDiscover.Subject?
    @ObservationIgnored private var task: Task<Void, Never>?

    var isRunning: Bool { if case .running = state { true } else { false } }
    var isActive: Bool { state != .idle }

    /// Phase 1: globs and tags.
    func start(_ subject: RuleDiscover.Subject, vocabulary: [String], topics: [RuleDiscover.KnownTopic], store: ProjectStore, provider: AIProvider) {
        history = []
        round = 0
        let prompt = RuleDiscover.scopePrompt(subject, vocabulary: vocabulary, topics: topics)
        run(subject, message: "Procurando globs e tags no código…", provider: provider, store: store,
            prompt: prompt, schema: RuleDiscover.scopeSchema) { data in
            let answer = try JSONDecoder().decode(RuleDiscover.ScopeAnswer.self, from: data)
            guard (answer.paths + answer.tags).allSatisfy({ !$0.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { throw VibeDeckError.discoverInvalidAnswer }
            return .scope(RuleDiscover.scope(answer, subject: subject, vocabulary: vocabulary, files: RuleDiscover.projectFiles(root: store.root)))
        }
    }

    /// Phase 2: one interview round. `answers` are the replies to the questions on screen (nil = first round);
    /// `finish` asks for rules now. Past `maxRounds` the call always generates.
    func interview(_ subject: RuleDiscover.Subject, answers: [String]? = nil, finish: Bool = false,
                   topics: [RuleDiscover.KnownTopic], store: ProjectStore, provider: AIProvider) {
        if case .questions(let questions) = state, let answers {
            history += zip(questions, answers).map { .init(question: $0.text, answer: $1) }
        }
        round += 1
        let finish = finish || round > RuleDiscover.maxRounds
        let prompt = RuleDiscover.interviewPrompt(subject, topics: topics, history: history, finish: finish)
        run(subject, message: finish ? "Gerando regras…" : "Preparando perguntas…", provider: provider, store: store,
            prompt: prompt, schema: RuleDiscover.interviewSchema) { data in
            let answer = try JSONDecoder().decode(RuleDiscover.InterviewAnswer.self, from: data)
            guard answer.rules.allSatisfy({ !$0.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { throw VibeDeckError.discoverInvalidAnswer }
            if !finish, !answer.questions.isEmpty { return .questions(answer.questions) }
            return .drafts(RuleDiscover.drafts(answer, subject: subject, topics: topics))
        }
    }

    private func run(_ subject: RuleDiscover.Subject, message: String, provider: AIProvider, store: ProjectStore,
                     prompt: String, schema: String, parse: @escaping (Data) throws -> State) {
        guard provider.isInstalled else { state = .failed("\(provider.title) não está instalado."); return }
        task?.cancel()
        snapshot = subject
        state = .running(message)
        task = Task {
            do {
                let next = try await AIReadOnlyOperation.run(root: store.root, provider: provider, operation: "Descubra regras",
                                                             prompt: prompt, schema: schema, parse: parse)
                guard !Task.isCancelled else { return }
                snapshot = nil
                state = next
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                snapshot = nil
                state = .failed(error.localizedDescription)
            }
        }
    }

    /// Stops the call (the process is terminated) and closes the Descubra.
    func cancel() {
        task?.cancel()
        task = nil
        snapshot = nil
        state = .idle
    }

    /// The topic or idea was edited while the call ran: the answer would be based on stale data.
    func subjectChanged(_ subject: RuleDiscover.Subject) {
        guard isRunning, let snapshot, snapshot != subject else { return }
        task?.cancel()
        task = nil
        self.snapshot = nil
        state = .failed("O conteúdo mudou durante a busca; nada foi alterado. Rode o Descubra de novo.")
    }
}

/// The "Descubra" button shared by the topic and idea editors, with the sheet that walks through the proposals.
/// `apply*` closures write one undoable change each.
struct RuleDiscoverButton: View {
    let subject: RuleDiscover.Subject
    /// Fresh subject after an accept (the interview starts from what was just applied).
    let current: () -> RuleDiscover.Subject
    let vocabulary: [String]
    let topics: [RuleDiscover.KnownTopic]
    let store: ProjectStore
    let applyScope: (RuleDiscoverScope, Set<String>, Set<String>) -> Void
    let applyRules: (RuleDiscoverDrafts, Set<UUID>) -> Void
    @Environment(AISession.self) private var session
    @State private var runner = RuleDiscoverRunner()

    var body: some View {
        Button {
            runner.start(subject, vocabulary: vocabulary, topics: topics, store: store, provider: session.provider)
        } label: {
            Label("Descubra", systemImage: "sparkles")
        }
        .disabled(runner.isActive)
        .help("Pede à IA (só leitura) globs e tags e, depois, uma entrevista para gerar regras. Nada é gravado sem aceite.")
        .sheet(isPresented: Binding(get: { runner.isActive }, set: { if !$0 { runner.cancel() } })) {
            RuleDiscoverSheet(runner: runner, subject: subject.kind,
                              applyScope: { scope, paths, tags, next in
                                  applyScope(scope, paths, tags)
                                  if next { interview() } else { runner.cancel() }
                              },
                              interview: interview,
                              answer: { answers, finish in
                                  runner.interview(current(), answers: answers, finish: finish, topics: topics, store: store, provider: session.provider)
                              },
                              applyRules: { drafts, chosen in
                                  applyRules(drafts, chosen)
                                  runner.cancel()
                              })
        }
        .onChange(of: subject) { _, new in runner.subjectChanged(new) }
        .onDisappear { runner.cancel() }
    }

    private func interview() {
        runner.interview(current(), topics: topics, store: store, provider: session.provider)
    }
}

private struct RuleDiscoverSheet: View {
    let runner: RuleDiscoverRunner
    let subject: RuleDiscover.Subject.Kind
    let applyScope: (RuleDiscoverScope, Set<String>, Set<String>, Bool) -> Void
    let interview: () -> Void
    let answer: ([String], Bool) -> Void
    let applyRules: (RuleDiscoverDrafts, Set<UUID>) -> Void

    @State private var paths: Set<String> = []
    @State private var tags: Set<String> = []
    @State private var answers: [String] = []
    @State private var rules: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            content
            Divider()
            HStack {
                if case .questions = runner.state {
                    Text("Rodada \(runner.round) de \(RuleDiscover.maxRounds)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancelar", role: .cancel) { runner.cancel() }
                    .keyboardShortcut(.cancelAction)
                actions
            }
            .padding()
        }
        .frame(width: 520, height: 480)
        .navigationTitle("Descubra")
        .onChange(of: runner.state, initial: true) { _, state in reset(for: state) }
    }

    @ViewBuilder
    private var content: some View {
        switch runner.state {
        case .idle:
            Spacer()
        case .running(let message):
            VStack(spacing: 10) {
                ProgressView()
                Text(message).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("Nada foi alterado", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            }
        case .scope(let scope):
            scopeForm(scope)
        case .questions(let questions):
            questionsForm(questions)
        case .drafts(let drafts):
            draftsForm(drafts)
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch runner.state {
        case .scope(let scope):
            Button("Só aplicar") { applyScope(scope, paths, tags, false) }
                .disabled(paths.isEmpty && tags.isEmpty)
            Button(paths.isEmpty && tags.isEmpty ? "Gerar regras" : "Aplicar e gerar regras") { applyScope(scope, paths, tags, true) }
                .keyboardShortcut(.defaultAction)
        case .questions:
            Button("Gerar com o que já tenho") { answer(answers, true) }
            Button("Responder") { answer(answers, false) }
                .keyboardShortcut(.defaultAction)
        case .drafts(let drafts):
            Button(subject == .idea ? "Adicionar ao rascunho" : "Adicionar regras") { applyRules(drafts, rules) }
                .keyboardShortcut(.defaultAction)
                .disabled(rules.isEmpty)
        case .idle, .running, .failed:
            EmptyView()
        }
    }

    private func scopeForm(_ scope: RuleDiscoverScope) -> some View {
        Form {
            if scope.isEmpty {
                Text("A IA não encontrou globs nem tags novos.").foregroundStyle(.secondary)
            }
            if !scope.paths.isEmpty {
                Section {
                    ForEach(scope.paths) { path in
                        Toggle(isOn: member(path.glob, in: $paths)) {
                            Text(path.glob).font(.body.monospaced())
                            Text("Casa \(path.matches) arquivo(s)").font(.caption).foregroundStyle(.secondary)
                            if let reason = path.reason { Text(reason).font(.caption) }
                        }
                    }
                } header: {
                    Text("Globs")
                } footer: {
                    Text("Só adiciona; os globs atuais continuam.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if !scope.tags.isEmpty {
                Section("Tags") {
                    ForEach(scope.tags) { tag in
                        Toggle(isOn: member(tag.tag, in: $tags)) {
                            Text("#\(tag.tag)")
                            if tag.isNew { Text("Tag nova: ainda não existe no projeto").font(.caption).foregroundStyle(.orange) }
                            if let reason = tag.reason { Text(reason).font(.caption) }
                        }
                    }
                }
            }
            discarded(scope.discarded)
        }
        .formStyle(.grouped)
    }

    private func questionsForm(_ questions: [RuleDiscover.Question]) -> some View {
        Form {
            ForEach(questions) { question in
                Section(question.text) {
                    if !question.options.isEmpty {
                        Picker("Opções", selection: answerBinding(question.id)) {
                            Text("—").tag("")
                            ForEach(question.options, id: \.self) { Text($0).tag($0) }
                            let typed = answerBinding(question.id).wrappedValue
                            if !typed.isEmpty, !question.options.contains(typed) { Text("Outra").tag(typed) }
                        }
                        .pickerStyle(.radioGroup)
                        .labelsHidden()
                    }
                    TextField(question.options.isEmpty ? "Resposta" : "Ou escreva outra resposta", text: answerBinding(question.id), axis: .vertical)
                        .lineLimit(1...4)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func draftsForm(_ drafts: RuleDiscoverDrafts) -> some View {
        Form {
            if drafts.isEmpty {
                Text("A IA não sugeriu regras novas.").foregroundStyle(.secondary)
            }
            Section {
                ForEach(drafts.rules) { draft in
                    Toggle(isOn: member(draft.id, in: $rules)) {
                        HStack(spacing: 4) {
                            Image(systemName: draft.severity.symbol)
                                .foregroundStyle(draft.severity == .must ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                            Text(draft.text)
                        }
                        if let details = draft.details { Text(details).font(.caption).foregroundStyle(.secondary) }
                        if draft.relation != .none {
                            Text("\(draft.relation == .duplicate ? "Duplica" : "Conflita com"): \(draft.related ?? "regra existente")")
                                .font(.caption).foregroundStyle(.orange)
                        }
                        if let reason = draft.reason { Text(reason).font(.caption) }
                    }
                }
            } footer: {
                Text(subject == .idea
                     ? "Entram como rascunho na ideia; só valem depois de promovidas."
                     : "Só viram regras do tópico as que você marcar.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func discarded(_ list: [String]) -> some View {
        if !list.isEmpty {
            Section("Descartado") {
                ForEach(list, id: \.self) { Text($0).font(.callout).foregroundStyle(.secondary) }
            }
        }
    }

    /// Starting selection of each proposal: catalogued tags, every glob, rules not flagged.
    private func reset(for state: RuleDiscoverRunner.State) {
        switch state {
        case .scope(let scope):
            paths = Set(scope.paths.map(\.glob))
            tags = scope.defaultTags
        case .questions(let questions):
            answers = Array(repeating: "", count: questions.count)
        case .drafts(let drafts):
            rules = drafts.defaultRules
        case .idle, .running, .failed:
            break
        }
    }

    private func answerBinding(_ index: Int) -> Binding<String> {
        Binding(get: { answers.indices.contains(index) ? answers[index] : "" },
                set: { if answers.indices.contains(index) { answers[index] = $0 } })
    }

    private func member<T: Hashable>(_ value: T, in set: Binding<Set<T>>) -> Binding<Bool> {
        Binding(get: { set.wrappedValue.contains(value) }, set: { on in
            if on { set.wrappedValue.insert(value) } else { set.wrappedValue.remove(value) }
        })
    }
}
