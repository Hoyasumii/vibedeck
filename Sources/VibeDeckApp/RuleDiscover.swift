import SwiftUI

/// Runs the rules "Descubra" for a topic or an idea: an optional opening context, a read-only call proposing globs,
/// an interview (rounds of questions) that drafts rules, and last a rewritten description with suggested tags.
/// "Verificar" is separate: only the viability verdict of an idea. Each answer only becomes a proposal; the view
/// applies what the user accepts.
@Observable @MainActor
final class RuleDiscoverRunner {
    enum State: Equatable {
        case idle
        /// Waiting for the optional opening context.
        case intro
        case running(String)
        case failed(String)
        case scope(RuleDiscoverScope)
        case questions([RuleDiscover.Question])
        case drafts(RuleDiscoverDrafts)
        case details(RuleDiscoverDetails)
        case verdict(RuleDiscoverVerdict)
    }

    var state: State = .idle
    /// Opening context the user typed (empty = none); goes into every prompt of this Descubra.
    private(set) var context = ""
    /// Questions answered so far in this interview.
    private(set) var history: [RuleDiscover.Exchange] = []
    private(set) var round = 0
    /// What the running call was built from; a different subject means the answer is stale.
    @ObservationIgnored private var snapshot: RuleDiscover.Subject?
    @ObservationIgnored private var task: Task<Void, Never>?

    var isRunning: Bool { if case .running = state { true } else { false } }
    var isActive: Bool { state != .idle }

    /// Opens the sheet on the optional context prompt.
    func begin() {
        context = ""
        history = []
        round = 0
        state = .intro
    }

    /// The subject as the prompts see it: with the opening context.
    private func withContext(_ subject: RuleDiscover.Subject) -> RuleDiscover.Subject {
        var subject = subject
        subject.context = context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : context
        return subject
    }

    /// Phase 1: globs. `context` is the opening text (may be empty).
    func start(_ subject: RuleDiscover.Subject, context: String, topics: [RuleDiscover.KnownTopic], store: CoreStore, provider: AIProvider) {
        self.context = context
        history = []
        round = 0
        let prompt = RuleDiscover.scopePrompt(withContext(subject), topics: topics)
        run(subject, message: "Procurando globs no código…", provider: provider, store: store,
            prompt: prompt, schema: RuleDiscover.scopeSchema) { data in
            let answer = try JSONDecoder().decode(RuleDiscover.ScopeAnswer.self, from: data)
            guard answer.paths.allSatisfy({ !$0.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { throw VibeDeckError.discoverInvalidAnswer }
            return .scope(RuleDiscover.scope(answer, subject: subject, vocabulary: [], files: RuleDiscover.projectFiles(root: store.root)))
        }
    }

    /// Phase 2: one interview round. `answers` are the replies to the questions on screen (nil = first round);
    /// `finish` asks for rules now. Past `maxRounds` the call always generates.
    func interview(_ subject: RuleDiscover.Subject, answers: [String]? = nil, finish: Bool = false,
                   topics: [RuleDiscover.KnownTopic], store: CoreStore, provider: AIProvider) {
        if case .questions(let questions) = state, let answers {
            history += zip(questions, answers).map { .init(question: $0.text, answer: $1) }
        }
        round += 1
        let finish = finish || round > RuleDiscover.maxRounds
        let prompt = RuleDiscover.interviewPrompt(withContext(subject), topics: topics, history: history, finish: finish)
        run(subject, message: finish ? "Gerando regras…" : "Preparando perguntas…", provider: provider, store: store,
            prompt: prompt, schema: RuleDiscover.interviewSchema) { data in
            let answer = try JSONDecoder().decode(RuleDiscover.InterviewAnswer.self, from: data)
            guard answer.rules.allSatisfy({ !$0.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { throw VibeDeckError.discoverInvalidAnswer }
            if !finish, !answer.questions.isEmpty { return .questions(answer.questions) }
            return .drafts(RuleDiscover.drafts(answer, subject: subject, topics: topics))
        }
    }

    /// Phase 3: the description rewritten and tags suggested with what was gathered.
    func describe(_ subject: RuleDiscover.Subject, vocabulary: [String], topics: [RuleDiscover.KnownTopic], store: CoreStore, provider: AIProvider) {
        let prompt = RuleDiscover.detailsPrompt(withContext(subject), vocabulary: vocabulary, topics: topics, history: history)
        run(subject, message: "Escrevendo a descrição e sugerindo tags…", provider: provider, store: store,
            prompt: prompt, schema: RuleDiscover.detailsSchema) { data in
            let answer = try JSONDecoder().decode(RuleDiscover.DetailsAnswer.self, from: data)
            guard answer.tags.allSatisfy({ !$0.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { throw VibeDeckError.discoverInvalidAnswer }
            return .details(RuleDiscover.details(answer, subject: subject, vocabulary: vocabulary))
        }
    }

    /// "Verificar": only the viability verdict of an idea, without scope, interview or description.
    func assess(_ subject: RuleDiscover.Subject, topics: [RuleDiscover.KnownTopic], store: CoreStore, provider: AIProvider) {
        context = ""
        history = []
        round = 0
        let prompt = RuleDiscover.verdictPrompt(subject, topics: topics)
        run(subject, message: "Avaliando a ideia…", provider: provider, store: store,
            prompt: prompt, schema: RuleDiscover.verdictSchema) { data in
            .verdict(RuleDiscover.verdict(try JSONDecoder().decode(RuleDiscover.VerdictAnswer.self, from: data), subject: subject))
        }
    }

    private func run(_ subject: RuleDiscover.Subject, message: String, provider: AIProvider, store: CoreStore,
                     prompt: String, schema: String, parse: @escaping (Data) throws -> State) {
        guard RemoteExecution.available(provider, root: store.root) else { state = .failed("\(provider.title) não está instalado."); return }
        task?.cancel()
        snapshot = subject
        state = .running(message)
        task = Task {
            do {
                let next = try await AIReadOnlyOperation.run(root: store.root, provider: provider, operation: "Descubra regras",
                                                             prompt: prompt, schema: schema, store: store, parse: parse)
                guard !Task.isCancelled else { return }
                complete(next, for: subject)
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                snapshot = nil
                state = .failed(error.localizedDescription)
            }
        }
    }

    /// Keeps the assessed content until acceptance, so a completed verdict cannot be applied to later edits.
    func complete(_ next: State, for subject: RuleDiscover.Subject) {
        if case .verdict = next { snapshot = subject } else { snapshot = nil }
        state = next
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
        guard let snapshot, !snapshot.hasSameContent(as: subject) else { return }
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
    @Environment(\.logProject) private var logProject
    var assessOnly = false
    var implementation = false
    var onImplement: (() -> Void)? = nil
    var subjectReady = false
    let subject: RuleDiscover.Subject
    /// Fresh subject after an accept (the interview starts from what was just applied).
    let current: () -> RuleDiscover.Subject
    let vocabulary: [String]
    let topics: [RuleDiscover.KnownTopic]
    let store: CoreStore
    let applyScope: (RuleDiscoverScope, Set<String>) -> Void
    let applyRules: (RuleDiscoverDrafts, Set<UUID>) -> Void
    /// The proposal, whether the new description was accepted (false keeps the current one) and the chosen tags.
    let applyDetails: (RuleDiscoverDetails, Bool, Set<String>) -> Void
    /// "Verificar" result (only when `assessOnly`).
    let applyVerdict: (RuleDiscoverVerdict) -> Void
    @Environment(AISession.self) private var session
    @State private var runner = RuleDiscoverRunner()
    @State private var implementAfterDismiss = false

    var body: some View {
        LoggedButton {
            if implementation, onImplement != nil, subjectReady {
                onImplement?()
            } else if assessOnly {
                runner.assess(current(), topics: topics, store: store, provider: session.provider)
            } else {
                runner.begin()
            }
        } label: {
            if implementation {
                Label("Implementar", systemImage: "hammer")
            } else if assessOnly {
                Label("Verificar", systemImage: "checkmark.circle.badge.questionmark")
            } else {
                Label("Descubra", systemImage: "sparkles")
            }
        }.loggedControl(control: "rule_discover.button_1", label: "Verificar")
        .disabled(runner.isActive)
        .help(assessOnly
              ? "Pede à IA (só leitura) para dizer se a ideia já dá para implementar."
              : "Pede à IA (só leitura) globs, uma entrevista para gerar regras e, por fim, a descrição e as tags. Você pode dar um contexto inicial. Nada é gravado sem aceite.")
        .sheet(isPresented: Binding(get: { runner.isActive }, set: { if !$0 { runner.cancel() } }), onDismiss: {
            if implementAfterDismiss {
                implementAfterDismiss = false
                onImplement?()
            }
        }) {
            RuleDiscoverSheet(runner: runner, subject: subject.kind,
                              start: { context in
                                  runner.start(current(), context: context, topics: topics, store: store, provider: session.provider)
                              },
                              applyScope: { scope, paths, next in
                                  applyScope(scope, paths)
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
                              applyDetails: { proposal, accepted, tags in
                                  applyDetails(proposal, accepted, tags)
                                  runner.cancel()
                              },
                              applyVerdict: { verdict in
                                  runner.subjectChanged(current())
                                  guard case .verdict = runner.state else { return }
                                  applyVerdict(verdict)
                                  implementAfterDismiss = implementation && verdict.viable
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
        runner.describe(current(), vocabulary: vocabulary, topics: topics, store: store, provider: session.provider)
    }
}

private struct RuleDiscoverSheet: View {
    @Environment(\.logProject) private var logProject
    let runner: RuleDiscoverRunner
    let subject: RuleDiscover.Subject.Kind
    let start: (String) -> Void
    let applyScope: (RuleDiscoverScope, Set<String>, Bool) -> Void
    let interview: () -> Void
    let answer: ([String], Bool) -> Void
    let applyRules: (RuleDiscoverDrafts, Set<UUID>) -> Void
    let describe: () -> Void
    let applyDetails: (RuleDiscoverDetails, Bool, Set<String>) -> Void
    let applyVerdict: (RuleDiscoverVerdict) -> Void

    @State private var context = ""
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
                LoggedButton("Cancelar", role: .cancel) { runner.cancel() }.loggedControl(control: "rule_discover.button_2", label: "Cancelar")
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
        case .intro:
            introForm
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
        case .details(let proposal):
            detailsForm(proposal)
        case .verdict(let verdict):
            verdictForm(verdict)
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch runner.state {
        case .intro:
            LoggedButton("Começar") { start(context) }.loggedControl(control: "rule_discover.button_3", label: "Começar")
                .keyboardShortcut(.defaultAction)
        case .scope(let scope):
            LoggedButton("Só aplicar") { applyScope(scope, paths, false) }.loggedControl(control: "rule_discover.button_4", label: "Só aplicar")
                .disabled(paths.isEmpty)
            LoggedButton(paths.isEmpty ? "Gerar regras" : "Aplicar e gerar regras") { applyScope(scope, paths, true) }.loggedControl(control: "rule_discover.button_5", label: "Ativar controle")
                .keyboardShortcut(.defaultAction)
        case .questions:
            LoggedButton("Gerar com o que já tenho") { answer(answers, true) }.loggedControl(control: "rule_discover.button_6", label: "Gerar com o que já tenho")
            LoggedButton("Responder") { answer(answers, false) }.loggedControl(control: "rule_discover.button_7", label: "Responder")
                .keyboardShortcut(.defaultAction)
        case .drafts(let drafts):
            LoggedButton("Pular para descrição e tags") { describe() }.loggedControl(control: "rule_discover.button_8", label: "Pular para descrição e tags")
            LoggedButton(subject == .idea ? "Adicionar ao rascunho" : "Adicionar regras") { applyRules(drafts, rules) }.loggedControl(control: "rule_discover.button_9", label: "Ativar controle")
                .keyboardShortcut(.defaultAction)
                .disabled(rules.isEmpty)
        case .details(let proposal):
            if proposal.suggested == nil {
                LoggedButton(tags.isEmpty ? "Fechar" : "Adicionar tags") { applyDetails(proposal, false, tags) }.loggedControl(control: "rule_discover.button_10", label: "Ativar controle")
                    .keyboardShortcut(.defaultAction)
            } else {
                LoggedButton("Manter a atual") { applyDetails(proposal, false, tags) }.loggedControl(control: "rule_discover.button_11", label: "Manter a atual")
                LoggedButton("Usar nova descrição") { applyDetails(proposal, true, tags) }.loggedControl(control: "rule_discover.button_12", label: "Usar nova descrição")
                    .keyboardShortcut(.defaultAction)
            }
        case .verdict(let verdict):
            LoggedButton("Salvar avaliação") { applyVerdict(verdict) }.loggedControl(control: "rule_discover.button_13", label: "Salvar avaliação")
                .keyboardShortcut(.defaultAction)
        case .idle, .running, .failed:
            EmptyView()
        }
    }

    private func scopeForm(_ scope: RuleDiscoverScope) -> some View {
        Form {
            if scope.paths.isEmpty {
                Text("A IA não encontrou globs novos.").foregroundStyle(.secondary)
            }
            if !scope.paths.isEmpty {
                Section {
                    ForEach(scope.paths) { path in
                        Toggle(isOn: member(path.glob, in: $paths).logging(control: "rule_discover.selection_14", label: "Alternar", project: logProject)) {
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
            discarded(scope.discarded)
        }
        .formStyle(.grouped)
    }

    private func questionsForm(_ questions: [RuleDiscover.Question]) -> some View {
        Form {
            ForEach(questions) { question in
                Section(question.text) {
                    if !question.options.isEmpty {
                        Picker("Opções", selection: answerBinding(question.id).logging(control: "rule_discover.selection_15", label: "Opções", project: logProject)) {
                            Text("—").tag("")
                            ForEach(question.options, id: \.self) { Text($0).tag($0) }
                            let typed = answerBinding(question.id).wrappedValue
                            if !typed.isEmpty, !question.options.contains(typed) { Text("Outra").tag(typed) }
                        }
                        .pickerStyle(.radioGroup)
                        .labelsHidden()
                    }
                    LoggedTextField(question.options.isEmpty ? "Resposta" : "Ou escreva outra resposta", text: answerBinding(question.id), axis: .vertical).loggedField(control: "rulediscover.text_1", label: "Confirmar campo")
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
                    Toggle(isOn: member(draft.id, in: $rules).logging(control: "rule_discover.selection_16", label: "Alternar", project: logProject)) {
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

    private var introForm: some View {
        Form {
            Section {
                TextEditor(text: $context)
                    .font(.body)
                    .frame(minHeight: 200)
            } header: {
                Text("Contexto inicial (opcional)")
            } footer: {
                Text("Conte o que você quer fazer, restrições e decisões já tomadas. A IA usa isto além do título e da descrição; deixe em branco para seguir só com eles.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func detailsForm(_ proposal: RuleDiscoverDetails) -> some View {
        Form {
            if let suggested = proposal.suggested {
                Section {
                    ScrollView {
                        Text(suggested).font(.callout.monospaced()).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 160)
                    if let reason = proposal.reason { Text(reason).font(.caption) }
                } header: {
                    Text("Descrição nova")
                } footer: {
                    Text("Substitui a atual (⌘Z desfaz).").font(.caption).foregroundStyle(.secondary)
                }
                if let current = proposal.current {
                    Section("Descrição atual") {
                        ScrollView {
                            Text(current).font(.callout.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 80)
                    }
                }
            } else {
                Text("A IA manteve a descrição atual.").foregroundStyle(.secondary)
            }
            if !proposal.tags.isEmpty {
                Section {
                    ForEach(proposal.tags) { tag in
                        Toggle(isOn: member(tag.tag, in: $tags).logging(control: "rule_discover.selection_17", label: "Alternar", project: logProject)) {
                            Text("#\(tag.tag)")
                            if tag.isNew { Text("Tag nova: ainda não existe no projeto").font(.caption).foregroundStyle(.orange) }
                            if let reason = tag.reason { Text(reason).font(.caption) }
                        }
                    }
                } header: {
                    Text("Tags")
                } footer: {
                    Text("Só adiciona; as tags atuais continuam.").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("A IA não sugeriu tags novas.").foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func verdictForm(_ verdict: RuleDiscoverVerdict) -> some View {
        Form {
            Section("Viabilidade") {
                if verdict.viable {
                    Label("Dá para implementar", systemImage: "checkmark.seal").foregroundStyle(.green)
                } else {
                    Label("Ainda não dá para implementar", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    ForEach(Array(verdict.missing.enumerated()), id: \.offset) { Text("• \($0.element)").font(.callout) }
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func discarded(_ list: [String]) -> some View {
        if !list.isEmpty {
            Section("Descartado") {
                ForEach(Array(list.enumerated()), id: \.offset) { Text($0.element).font(.callout).foregroundStyle(.secondary) }
            }
        }
    }

    /// Starting selection of each proposal: every glob, rules not flagged, catalogued tags.
    private func reset(for state: RuleDiscoverRunner.State) {
        switch state {
        case .scope(let scope):
            paths = Set(scope.paths.map(\.glob))
        case .questions(let questions):
            answers = Array(repeating: "", count: questions.count)
        case .drafts(let drafts):
            rules = drafts.defaultRules
        case .details(let details):
            tags = details.defaultTags
        case .idle, .intro, .running, .failed, .verdict:
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
