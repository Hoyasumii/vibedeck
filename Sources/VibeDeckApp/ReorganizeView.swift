import SwiftUI
import VibeDeckCore

@MainActor @Observable
final class ReorganizeRunner {
    enum State: Equatable { case idle, running, failed(String), ready(ReorganizeDiscover.Proposal) }
    private static var runners: [String: ReorganizeRunner] = [:]
    static func shared(root: URL) -> ReorganizeRunner {
        let key = root.standardizedFileURL.resolvingSymlinksInPath().path
        if let runner = runners[key] { return runner }
        let runner = ReorganizeRunner(); runners[key] = runner; return runner
    }
    private(set) var state: State = .idle
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    var isRunning: Bool { state == .running }
    func start(store: ProjectStore, provider: AIProvider,
               available: (AIProvider) -> Bool = { $0.isInstalled },
               request: ((String, AIProviderSettings) async throws -> Data)? = nil) {
        guard state == .idle else { return }
        guard RemoteWorkspace.existing(at: store.root) != nil || available(provider) else { state = .failed("Selecione um provedor de IA instalado no painel IA."); return }
        generation = UUID(); let run = generation
        state = .running
        task = Task {
            var lease: String?
            do {
                lease = try await ReorganizeLease.shared.acquire(store.root)
                let fingerprint = try store.reorganizeFingerprint()
                let prompt = try ReorganizeDiscover.prompt(store: store)
                let proposal = try await AIReadOnlyOperation.run(root: store.root, provider: provider,
                    operation: "Reorganizar", prompt: prompt, schema: ReorganizeDiscover.schema,
                    request: request, recover: { error in
                        if let error = error as? ReorganizeError, case .stale = error { return false }
                        return true
                    }) { data in
                        try ReorganizeDiscover.parse(data, store: store, fingerprint: fingerprint)
                    }
                try Task.checkCancellation()
                guard run == generation else { if let lease { await ReorganizeLease.shared.release(lease) }; return }
                guard try store.reorganizeFingerprint() == fingerprint else { throw ReorganizeError.stale }
                state = .ready(proposal)
            } catch {
                if run == generation, !Task.isCancelled {
                    state = .failed(error is ReorganizeError ? error.localizedDescription :
                        (error.localizedDescription == VibeDeckError.discoverFailed(AIPromptPolicy.incomplete).localizedDescription
                            ? ReorganizeError.invalidJSON.localizedDescription : error.localizedDescription))
                }
            }
            if let lease { await ReorganizeLease.shared.release(lease) }
        }
    }
    func cancel() { generation = UUID(); task?.cancel(); task = nil; state = .idle }
}

struct ReorganizeButton: View {
    @Environment(ProjectModel.self) private var model
    @Environment(AISession.self) private var session
    @Environment(\.undoManager) private var undo
    @State private var showing = false
    private var runner: ReorganizeRunner { .shared(root: model.store.root) }
    var body: some View {
        HStack {
            LoggedButton {
                if runner.state == .idle { runner.start(store: model.store, provider: session.provider) }
                showing = true
            } label: { Label(runner.isRunning ? "Reorganizando…" : "Reorganizar", systemImage: "arrow.triangle.branch") }
                .loggedControl(control: "reorganize.open", label: "Reorganizar")
            if runner.isRunning {
                ProgressView().controlSize(.small)
                LoggedButton("Cancelar") { runner.cancel() }
                    .loggedControl(control: "reorganize.cancel", label: "Cancelar reorganização")
            }
        }
        .sheet(isPresented: $showing, onDismiss: { runner.cancel() }) {
            ReorganizeSheet(runner: runner, model: model, undo: undo)
        }
    }
}

struct ReorganizeSheet: View {
    let runner: ReorganizeRunner
    let model: ProjectModel
    let undo: UndoManager?
    @Environment(\.dismiss) private var dismiss
    @State private var selected = Set<String>()
    @State private var conflicts: [String: String] = [:]
    @State private var error: String?
    @State private var blockers: [String: String] = [:]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reorganizar o projeto").font(.title2)
            Text("Nada será gravado antes do seu aceite.").foregroundStyle(.secondary)
            switch runner.state {
            case .idle: Spacer()
            case .running:
                Spacer(); ProgressView("Analisando regras, documentos, ideias e revisões…"); Spacer()
            case .failed(let message):
                ContentUnavailableView("Não foi possível reorganizar", systemImage: "exclamationmark.triangle", description: Text(message))
            case .ready(let proposal):
                if proposal.actions.isEmpty {
                    ContentUnavailableView("Nenhuma ação proposta", systemImage: "tray")
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(proposal.actions) { action in
                                VStack(alignment: .leading, spacing: 6) {
                                    Toggle(action.label + ": " + action.item.slug, isOn: Binding(
                                        get: { selected.contains(action.id) },
                                        set: { if $0 { selected.insert(action.id) } else { selected.remove(action.id) } }).logging(control: "reorganize.select", label: action.label, project: model.store.root))
                                    if let message = blockers[action.id] {
                                        Text(message + " Desmarque esta ação para continuar com as demais.")
                                            .foregroundStyle(.red)
                                    }
                                    Text(action.reason).foregroundStyle(.secondary)
                                    Text(action.references.map { $0.key }.joined(separator: " · ")).font(.caption)
                                    if let destination = action.destination { Text("Destino: " + (destination.isEmpty ? "raiz" : destination)) }
                                    if let title = action.title { Text(title).font(.headline) }
                                    if let content = action.content { Text(content).textSelection(.enabled) }
                                    if action.kind == .conflict {
                                        Picker("Qual manter?", selection: Binding(get: { conflicts[action.id] ?? "" }, set: { conflicts[action.id] = $0 }).logging(control: "reorganize.conflict", label: "Qual manter?", project: model.store.root)) {
                                            Text("Escolha explicitamente").tag("")
                                            ForEach(action.references, id: \.key) { ref in Text(ref.key).tag(ref.key) }
                                        }
                                        Text("Os demais serão arquivados. Sem escolha, nada muda.").font(.caption)
                                    }
                                }
                                Divider()
                            }
                        }
                    }
                }
                if proposal.discarded > 0 { Text("\(proposal.discarded) ação(ões) inválida(s) descartada(s).").font(.caption) }
            }
            if let error { Text(error).foregroundStyle(.red) }
            if !blockers.isEmpty {
                LoggedButton("Desmarcar ações que bloqueiam") {
                    selected.subtract(blockers.keys)
                    blockers = [:]
                    error = "Ações desmarcadas. Confira a seleção e clique em Aceitar selecionados."
                }
                .loggedControl(control: "reorganize.deselect_blockers", label: "Desmarcar ações que bloqueiam")
            }
            HStack {
                LoggedButton("Cancelar", role: .cancel) { runner.cancel(); dismiss() }
                    .loggedControl(control: "reorganize.dismiss", label: "Cancelar reorganização")
                Spacer()
                if case .ready(let proposal) = runner.state {
                    LoggedButton("Aceitar selecionados") { accept(proposal, ids: selected) }
                        .loggedControl(control: "reorganize.accept_selected", label: "Aceitar selecionados")
                        .disabled(eligible(proposal, ids: selected).isEmpty)
                    LoggedButton("Aceitar todos") { accept(proposal, ids: Set(proposal.actions.map(\.id))) }
                        .loggedControl(control: "reorganize.accept_all", label: "Aceitar todos")
                        .disabled(eligible(proposal, ids: Set(proposal.actions.map(\.id))).isEmpty)
                }
            }
        }.padding().frame(width: 720, height: 620)
        .onChange(of: runner.state, initial: true) { _, state in
            if case .ready(let proposal) = state { selected = Set(proposal.actions.filter { $0.kind != .conflict }.map(\.id)) }
        }
    }
    private func eligible(_ proposal: ReorganizeDiscover.Proposal, ids: Set<String>) -> [String] {
        proposal.actions.filter { ids.contains($0.id) && ($0.kind != .conflict || !(conflicts[$0.id] ?? "").isEmpty) }.map(\.id)
    }
    private func accept(_ proposal: ReorganizeDiscover.Proposal, ids: Set<String>) {
        if model.acceptReorganization(proposal, acceptance: .init(selected: eligible(proposal, ids: ids), conflicts: conflicts), undo: undo) {
            runner.cancel(); dismiss()
        } else {
            error = model.errorMessage
            do {
                blockers = try model.store.reorganizationBlockers(proposal,
                    acceptance: .init(selected: eligible(proposal, ids: ids), conflicts: conflicts))
                if !blockers.isEmpty {
                    error = "Nada foi aplicado. Há \(blockers.count) ação(ões) que bloqueiam o aceite. Desmarque-as para aceitar as demais."
                }
            } catch {
                blockers = [:]
                self.error = error.localizedDescription
            }
        }
    }
}

extension ProjectModel {
    @discardableResult
    func acceptReorganization(_ proposal: ReorganizeDiscover.Proposal, acceptance: ReorganizeDiscover.Acceptance, undo: UndoManager?) -> Bool {
        do {
            let receipt = try store.applyReorganization(proposal, acceptance: acceptance)
            reloadAfterReorganization(receipt.pathMoves)
            if !receipt.before.isEmpty || !receipt.after.isEmpty || !receipt.createdDirectories.isEmpty {
                undo?.registerUndo(withTarget: self) { model in model.toggleReorganization(receipt, forward: false, undo: undo) }
                undo?.setActionName("Reorganizar")
            }
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }
    private func toggleReorganization(_ receipt: ReorganizeReceipt, forward: Bool, undo: UndoManager?) {
        do {
            try store.restoreReorganization(receipt, forward: forward)
            reloadAfterReorganization(forward ? receipt.pathMoves : Dictionary(uniqueKeysWithValues: receipt.pathMoves.filter { receipt.before[$0.value] == nil }.map { ($0.value, $0.key) }))
            undo?.registerUndo(withTarget: self) { model in model.toggleReorganization(receipt, forward: !forward, undo: undo) }
            undo?.setActionName("Reorganizar")
        } catch { errorMessage = error.localizedDescription }
    }
}
