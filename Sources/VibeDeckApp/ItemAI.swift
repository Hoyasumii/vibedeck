import SwiftUI
import VibeDeckCore

/// Uma operação de IA por projeto por vez para criar/editar agentes, comandos, skills e workflows.
/// Nunca grava: só `ProjectModel.acceptItemAI` grava, após o aceite do usuário.
@MainActor @Observable
final class ItemAIRunner {
    enum Mode: Equatable { case create, edit(slug: String) }
    enum State: Equatable {
        case idle, running, failed(String), ready(ItemDiscover.Proposal)
    }
    static let timeout: Duration = .seconds(240)
    private static var runners: [String: ItemAIRunner] = [:]
    static func shared(root: URL) -> ItemAIRunner {
        let key = root.standardizedFileURL.resolvingSymlinksInPath().path
        if let runner = runners[key] { return runner }
        let runner = ItemAIRunner()
        runners[key] = runner
        return runner
    }

    private(set) var state: State = .idle
    private(set) var owner: String?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var timeoutTask: Task<Void, Never>?
    var isRunning: Bool { state == .running }
    var isBusy: Bool { state == .running }

    /// `current` é a proposta atual (item editado ou proposta em refinamento); `isStale` é checado ao fim da chamada.
    func start(owner: String, store: ProjectStore, kind: ItemDiscover.Kind, request: String, current: ItemDiscover.Proposal?,
               provider: AIProvider, isStale: @escaping () -> Bool = { false },
               available: (AIProvider) -> Bool = { $0.isInstalled },
               send: ((String, AIProviderSettings) async throws -> Data)? = nil) {
        guard !isRunning else { return }
        let request = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else {
            state = .failed("Descreva o que a IA deve fazer."); self.owner = owner; return
        }
        guard RemoteWorkspace.existing(at: store.root) != nil || available(provider) else {
            state = .failed("\(provider.title) não está instalado. Selecione um provedor disponível no painel IA.")
            self.owner = owner
            return
        }
        self.owner = owner
        state = .running
        let generation = UUID()
        token = generation
        task = Task {
            do {
                var refs: ItemDiscover.Refs?
                var listing: [String: [ItemDiscover.Existing]] = [:]
                if kind == .workflow { let found = try store.itemRefs(); refs = found.refs; listing = found.listing }
                let prompt = ItemDiscover.prompt(kind: kind, request: request, current: current,
                                                 existing: try store.existingItems(kind), refs: listing)
                let proposal = try await AIReadOnlyOperation.run(
                    root: store.root, provider: provider, operation: current == nil ? "Criar \(kind.title) com IA" : "Editar \(kind.title) com IA",
                    prompt: prompt, schema: ItemDiscover.schema(kind), request: send,
                    parse: { try ItemDiscover.parse(kind, $0, refs: refs) })
                try Task.checkCancellation()
                guard token == generation else { return }
                if isStale() {
                    state = .failed("O item mudou durante a chamada; a resposta da IA foi descartada.")
                } else {
                    state = .ready(proposal)
                }
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled, token == generation else { return }
                state = .failed(error.localizedDescription)
            }
            timeoutTask?.cancel()
        }
        timeoutTask = Task {
            try? await Task.sleep(for: Self.timeout)
            guard !Task.isCancelled, token == generation, isRunning else { return }
            task?.cancel()
            state = .failed("A IA demorou demais e a chamada foi cancelada. Nada foi gravado.")
        }
    }

    @ObservationIgnored private var token = UUID()

    func cancel() {
        token = UUID()
        task?.cancel(); task = nil
        timeoutTask?.cancel(); timeoutTask = nil
        state = .idle
        owner = nil
    }

    /// Volta a `idle` mantendo nada: usado após aceite.
    func reset() { cancel() }
}

/// Folha de "Criar com IA" / "Editar com IA": pedido, proposta completa editável e refinamento em sequência.
struct ItemAISheet: View {
    @Environment(\.logProject) private var providerRoot
    let kind: ItemDiscover.Kind
    let mode: ItemAIRunner.Mode
    let model: ProjectModel
    let provider: AIProvider
    let undo: UndoManager?
    /// Proposta do item no momento em que a folha abriu (só em edição).
    let baseline: ItemDiscover.Proposal?
    @Environment(\.dismiss) private var dismiss
    @State private var request = ""
    @State private var proposal: ItemDiscover.Proposal?
    @State private var saveError: String?

    private var runner: ItemAIRunner { model.itemAI }
    private var ownerKey: String {
        switch mode { case .create: "create:\(kind.rawValue)"; case .edit(let slug): "edit:\(kind.rawValue):\(slug)" }
    }
    private var ownsRunner: Bool { runner.owner == ownerKey }
    private var isEdit: Bool { if case .edit = mode { true } else { false } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isEdit ? "Editar \(kind.title) com IA" : "Criar \(kind.title) com IA").font(.title2.weight(.semibold))
            Text("A IA só lê o projeto. Nada é gravado antes do seu aceite.").foregroundStyle(.secondary)
            TextEditor(text: $request)
                .font(.body).frame(height: 90)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                .overlay(alignment: .topLeading) {
                    if request.isEmpty {
                        Text(proposal == nil && !isEdit ? "Descreva o \(kind.title) que você quer…" : "Peça um ajuste…")
                            .foregroundStyle(.tertiary).padding(8).allowsHitTesting(false)
                    }
                }
            HStack {
                LoggedButton(proposal == nil && !isEdit ? "Gerar proposta" : "Refinar") { send() }
                    .loggedControl(control: "item_ai_sheet.button_1", label: "Enviar pedido")
                    .disabled(runner.isRunning || request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (runner.isBusy && !ownsRunner))
                if ownsRunner, runner.isRunning {
                    ProgressView().controlSize(.small)
                    Text("Lendo o projeto e propondo…").foregroundStyle(.secondary)
                }
            }
            if ownsRunner, case .failed(let message) = runner.state {
                Text(message).foregroundStyle(.red)
            }
            if let proposal {
                Divider()
                proposalEditor(proposal)
            } else {
                Spacer(minLength: 0)
            }
            if let saveError { Text(saveError).foregroundStyle(.red) }
            HStack {
                Spacer()
                LoggedButton(runner.isRunning && ownsRunner ? "Cancelar chamada" : "Cancelar", role: .cancel) {
                    if ownsRunner { runner.cancel() }
                    dismiss()
                }
                .loggedControl(control: "item_ai_sheet.button_2", label: "Cancelar")
                .keyboardShortcut(.cancelAction)
                LoggedButton(isEdit ? "Aceitar edição" : "Criar \(kind.title)") { accept() }
                    .loggedControl(control: "item_ai_sheet.button_3", label: "Aceitar")
                    .disabled(valid == nil || runner.isRunning)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 680, height: 640)
        .onAppear { if ownsRunner, case .ready(let p) = runner.state { proposal = p } }
        .onDisappear { if ownsRunner { runner.cancel() } }
        .onChange(of: runner.state) { _, state in
            guard ownsRunner, case .ready(let p) = state else { return }
            proposal = p
            request = ""
        }
    }

    private var valid: ItemDiscover.Proposal? { proposal.flatMap { ItemDiscover.validated(kind, $0) } }

    @ViewBuilder private func proposalEditor(_ current: ItemDiscover.Proposal) -> some View {
        let binding = Binding<ItemDiscover.Proposal>(get: { proposal ?? current }, set: { proposal = $0 })
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                LoggedTextField("Nome", text: Binding(get: { binding.wrappedValue.title }, set: { binding.wrappedValue.title = $0 }))
                    .loggedField(control: "item_ai_sheet.field_1", label: "Nome").textFieldStyle(.roundedBorder)
                LoggedTextField(kind == .skill ? "Quando usar" : "Resumo", text: Binding(get: { binding.wrappedValue.summary ?? "" }, set: { binding.wrappedValue.summary = $0 }))
                    .loggedField(control: "item_ai_sheet.field_2", label: "Resumo").textFieldStyle(.roundedBorder)
                if kind == .workflow {
                    ForEach(Array(binding.wrappedValue.steps.enumerated()), id: \.offset) { index, step in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(index + 1). \(step.id) — \(step.kind.rawValue) \(step.ref)").font(.body.weight(.medium))
                            if let note = step.note { Text(note).foregroundStyle(.secondary) }
                            ForEach(Array(step.transitions.enumerated()), id: \.offset) { _, t in
                                Text("→ \(t.to) (\(t.label))").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    TextEditor(text: Binding(get: { binding.wrappedValue.prompt }, set: { binding.wrappedValue.prompt = $0 }))
                        .font(.body.monospaced()).frame(minHeight: 240)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                }
                if valid == nil {
                    Text("Informe nome e conteúdo; o conteúdo deve ter até \(ItemDiscover.maxContentLength) caracteres.")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
        }
    }

    private func send() {
        saveError = nil
        let current: ItemDiscover.Proposal? = proposal ?? baseline
        var edited = current
        if let proposal, let valid = ItemDiscover.validated(kind, proposal) { edited = valid }
        let slug: String? = { if case .edit(let slug) = mode { slug } else { nil } }()
        runner.start(owner: ownerKey, store: model.store, kind: kind, request: request, current: edited, provider: provider,
                     isStale: { [model, kind] in
                         guard let slug, let baseline else { return false }
                         return model.itemProposal(kind, slug: slug) != baseline
                     })
    }

    private func accept() {
        guard let valid else { return }
        let slug: String? = { if case .edit(let slug) = mode { slug } else { nil } }()
        if let slug, let baseline, model.itemProposal(kind, slug: slug) != baseline {
            saveError = "O item mudou desde que a folha foi aberta; a proposta foi descartada."
            return
        }
        if model.acceptItemAI(kind, slug: slug, valid, undo: undo) {
            runner.reset()
            dismiss()
        } else { saveError = model.errorMessage }
    }
}

/// "Editar com IA" no detalhe de um item; só aparece com provedor de IA suportado (mesmo teste de DocView).
struct EditWithAIButton: View {
    @Environment(\.logProject) private var providerRoot
    let kind: ItemDiscover.Kind
    let slug: String
    @Environment(ProjectModel.self) private var model
    @Environment(AISession.self) private var session
    @Environment(\.undoManager) private var undo
    @State private var showing = false
    @State private var baseline: ItemDiscover.Proposal?

    var body: some View {
        if !AIProvider.installed(in: providerRoot).isEmpty {
            LoggedButton {
                NotificationCenter.default.post(name: .vibedeckFlushPendingSaves, object: nil)
                baseline = model.itemProposal(kind, slug: slug)
                showing = baseline != nil
            } label: { Label("Editar com IA", systemImage: "wand.and.stars") }
                .loggedControl(control: "edit_with_ai.button_1", label: "Editar com IA")
                .help("Pede à IA uma atualização do \(kind.title); nada é gravado antes do seu aceite")
                .sheet(isPresented: $showing) {
                    ItemAISheet(kind: kind, mode: .edit(slug: slug), model: model, provider: session.provider, undo: undo, baseline: baseline)
                }
        }
    }
}

/// "Criar com IA" na lista de cada tipo.
struct CreateWithAIButton: View {
    @Environment(\.logProject) private var providerRoot
    let kind: ItemDiscover.Kind
    @Environment(ProjectModel.self) private var model
    @Environment(AISession.self) private var session
    @Environment(\.undoManager) private var undo
    @State private var showing = false

    var body: some View {
        if !AIProvider.installed(in: providerRoot).isEmpty {
            LoggedButton { showing = true } label: { Label("Criar com IA", systemImage: "wand.and.stars") }
                .loggedControl(control: "create_with_ai.button_1", label: "Criar com IA")
                .help("Descreva o \(kind.title) e refine a proposta da IA; nada é gravado antes do seu aceite")
                .sheet(isPresented: $showing) {
                    ItemAISheet(kind: kind, mode: .create, model: model, provider: session.provider, undo: undo, baseline: nil)
                }
        }
    }
}
