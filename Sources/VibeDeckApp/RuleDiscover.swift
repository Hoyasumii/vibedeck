import SwiftUI
import VibeDeckCore

/// Runs the rules "Descubra" for a topic or an idea: first a read-only call proposing globs and tags, then an
/// interview (rounds of questions) that drafts rules, and last a rewritten description (with, for ideas, the
/// viability verdict). Each answer only becomes a proposal; the view applies what the user accepts.
@Observable @MainActor
final class RuleDiscoverRunner {
    enum State: Equatable {
        case idle
        case running(String)
        case failed(String)
        case scope(RuleDiscoverScope)
        case questions([RuleDiscover.Question])
        case drafts(RuleDiscoverDrafts)
        case description(RuleDiscoverDescription)
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

    /// Phase 3: the description rewritten with what was gathered (and the idea's viability). Alone, it's "Verificar".
    func describe(_ subject: RuleDiscover.Subject, topics: [RuleDiscover.KnownTopic], store: ProjectStore, provider: AIProvider) {
        let prompt = RuleDiscover.descriptionPrompt(subject, topics: topics, history: history)
        run(subject, message: subject.kind == .idea ? "Atualizando a descrição e avaliando a ideia…" : "Atualizando a descrição…",
            provider: provider, store: store, prompt: prompt, schema: RuleDiscover.descriptionSchema) { data in
            let answer = try JSONDecoder().decode(RuleDiscover.DescriptionAnswer.self, from: data)
            return .description(RuleDiscover.description(answer, subject: subject))
        }
    }

    /// Only the description/viability phase, without the scope and interview.
    func assess(_ subject: RuleDiscover.Subject, topics: [RuleDiscover.KnownTopic], store: ProjectStore, provider: AIProvider) {
        history = []
        round = 0
        describe(subject, topics: topics, store: store, provider: provider)
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
/// `apply*` closures write one undoable change each. `assessOnly` makes it the idea's "Verificar": just the
/// description/viability phase.
struct RuleDiscoverButton: View {
    var assessOnly = false
    let subject: RuleDiscover.Subject
    /// Fresh subject after an accept (the interview starts from what was just applied).
    let current: () -> RuleDiscover.Subject
    let vocabulary: [String]
    let topics: [RuleDiscover.KnownTopic]
    let store: ProjectStore
    let applyScope: (RuleDiscoverScope, Set<String>, Set<String>) -> Void
    let applyRules: (RuleDiscoverDrafts, Set<UUID>) -> Void
    /// The proposal and whether the new text was accepted (false keeps the current one).
    let applyDescription: (RuleDiscoverDescription, Bool) -> Void
    @Environment(AISession.self) private var session
    @State private var runner = RuleDiscoverRunner()

    var body: some View {
        Button {
            if assessOnly {
                runner.assess(subject, topics: topics, store: store, provider: session.provider)
            } else {
                runner.start(subject, vocabulary: vocabulary, topics: topics, store: store, provider: session.provider)
            }
        } label: {
            if assessOnly {
                Label("Verificar", systemImage: "checkmark.circle.badge.questionmark")
            } else {
                Label("Descubra", systemImage: "sparkles")
            }
        }
        .disabled(runner.isActive)
        .help(assessOnly
              ? "Pede à IA (só leitura) para revisar a descrição e dizer se a ideia já dá para implementar."
              : "Pede à IA (só leitura) globs e tags, uma entrevista para gerar regras e, por fim, a descrição atualizada. Nada é gravado sem aceite.")
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
                                  describe()
                              },
                              describe: describe,
                              applyDescription: { proposal, accepted in
                                  applyDescription(proposal, accepted)
                                  runner.cancel()
                              })
        }
        .onChange(of: subject) { _, new in runner.subjectChanged(new) }
        .onDisappear { runner.cancel() }
    }

    private func interview() {
        runner.interview(current(), topics: topics, store: store, provider: session.provider)
    }

    private func describe() {
        runner.describe(current(), topics: topics, store: store, provider: session.provider)
    }
}

private struct RuleDiscoverSheet: View {
    let runner: RuleDiscoverRunner
    let subject: RuleDiscover.Subject.Kind
    let applyScope: (RuleDiscoverScope, Set<String>, Set<String>, Bool) -> Void
    let interview: () -> Void
    let answer: ([String], Bool) -> Void
    let applyRules: (RuleDiscoverDrafts, Set<UUID>) -> Void
    let describe: () -> Void
    let applyDescription: (RuleDiscoverDescription, Bool) -> Void

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
        case .description(let proposal):
            descriptionForm(proposal)
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
            Button("Pular para a descrição") { describe() }
            Button(subject == .idea ? "Adicionar ao rascunho" : "Adicionar regras") { applyRules(drafts, rules) }
                .keyboardShortcut(.defaultAction)
                .disabled(rules.isEmpty)
        case .description(let proposal):
            if proposal.suggested == nil {
                Button(subject == .idea ? "Salvar avaliação" : "Fechar") { applyDescription(proposal, false) }
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Manter a atual") { applyDescription(proposal, false) }
                Button("Usar nova descrição") { applyDescription(proposal, true) }
                    .keyboardShortcut(.defaultAction)
            }
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

    private func descriptionForm(_ proposal: RuleDiscoverDescription) -> some View {
        Form {
            if subject == .idea {
                Section("Viabilidade") {
                    if proposal.viable {
                        Label("Dá para implementar", systemImage: "checkmark.seal").foregroundStyle(.green)
                    } else {
                        Label("Ainda não dá para implementar", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                        ForEach(proposal.missing, id: \.self) { Text("• \($0)").font(.callout) }
                    }
                }
            }
            if let suggested = proposal.suggested {
                Section {
                    ScrollView {
                        Text(suggested).font(.callout.monospaced()).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 180)
                    if let reason = proposal.reason { Text(reason).font(.caption) }
                } header: {
                    Text("Descrição nova")
                } footer: {
                    Text(subject == .idea
                         ? "Substitui a atual (⌘Z desfaz). A IA avaliou a ideia com este texto: manter a atual não conta como viável."
                         : "Substitui a atual (⌘Z desfaz).")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let current = proposal.current {
                    Section("Descrição atual") {
                        ScrollView {
                            Text(current).font(.callout.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 100)
                    }
                }
            } else {
                Text("A IA manteve a descrição atual.").foregroundStyle(.secondary)
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
        case .idle, .running, .failed, .description:
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
