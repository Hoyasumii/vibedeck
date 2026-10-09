import SwiftUI
import VibeDeckCore

/// Shared across windows for one canonical project; only explicit acceptance writes Docs.
@MainActor @Observable
final class DocGenerateRunner {
    enum State: Equatable {
        case idle, running, failed(String), ready([DocGenerate.Document])
    }
    private static var runners: [String: DocGenerateRunner] = [:]
    static func shared(root: URL) -> DocGenerateRunner {
        let key = root.standardizedFileURL.resolvingSymlinksInPath().path
        if let runner = runners[key] { return runner }
        let runner = DocGenerateRunner()
        runners[key] = runner
        return runner
    }

    private(set) var state: State = .idle
    @ObservationIgnored private var task: Task<Void, Never>?
    var isRunning: Bool { state == .running }
    var isActive: Bool { state != .idle }

    func start(store: ProjectStore, provider: AIProvider, available: (AIProvider) -> Bool = { $0.isInstalled },
               request: ((String, AIProviderSettings) async throws -> Data)? = nil) {
        guard !isActive else { return }
        guard available(provider) else {
            state = .failed("\(provider.title) não está instalado. Selecione um provedor disponível no painel IA.")
            return
        }
        state = .running
        task = Task {
            do {
                let documents = try await AIReadOnlyOperation.run(root: store.root, provider: provider,
                    operation: "Gerar documentos", prompt: DocGenerate.prompt(existing: try store.listDocs()),
                    schema: DocGenerate.schema, request: request, parse: DocGenerate.parse)
                try Task.checkCancellation()
                state = .ready(documents)
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                let message = error.localizedDescription
                state = .failed(message == VibeDeckError.discoverFailed(AIPromptPolicy.incomplete).localizedDescription
                    ? VibeDeckError.docGenerationInvalidAnswer.localizedDescription : message)
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        state = .idle
    }
}

struct DocGenerateSheet: View {
    let runner: DocGenerateRunner
    let model: ProjectModel
    let undo: UndoManager?
    @Environment(\.dismiss) private var dismiss
    @State private var documents: [DocGenerate.Document] = []
    @State private var selected: Set<UUID> = []
    @State private var preview: UUID?
    @State private var saveError: String?

    var body: some View {
        VStack(spacing: 0) {
            switch runner.state {
            case .running:
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Lendo o projeto e propondo documentos…")
                    Text("Nada será gravado antes do seu aceite.").foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ContentUnavailableView("Não foi possível gerar documentos", systemImage: "exclamationmark.triangle",
                                       description: Text(message))
            case .ready:
                if documents.isEmpty {
                    ContentUnavailableView("Nenhum documento proposto", systemImage: "doc.text",
                        description: Text("A IA não encontrou conteúdo novo dentro dos limites da geração."))
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            Text("Revise os documentos. Editar ou descartar aqui não altera arquivos.")
                                .foregroundStyle(.secondary)
                            ForEach($documents) { $document in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Toggle("Aceitar", isOn: Binding(get: { selected.contains(document.id) }, set: {
                                            if $0 { selected.insert(document.id) } else { selected.remove(document.id) }
                                        }))
                                        Spacer()
                                        Button(preview == document.id ? "Editar" : "Pré-visualizar") {
                                            preview = preview == document.id ? nil : document.id
                                        }
                                        Button("Descartar", role: .destructive) {
                                            selected.remove(document.id)
                                            documents.removeAll { $0.id == document.id }
                                        }
                                    }
                                    TextField("Título", text: $document.title)
                                    if preview == document.id {
                                        MarkdownPreview(text: "# \(document.title)\n\n\(document.content)", baseURL: model.store.docsDir)
                                            .frame(height: 240)
                                    } else {
                                        TextEditor(text: $document.content).font(.body.monospaced()).frame(height: 200)
                                    }
                                    if DocGenerate.validated([document]).isEmpty {
                                        Text("Informe título e conteúdo; o conteúdo deve ter até 40.000 caracteres.")
                                            .font(.caption).foregroundStyle(.orange)
                                    }
                                }
                                Divider()
                            }
                        }.padding()
                    }
                }
            case .idle: EmptyView()
            }
            if let saveError { Text(saveError).foregroundStyle(.red).padding(.horizontal) }
            HStack {
                Spacer()
                Button(runner.isRunning ? "Cancelar geração" : "Cancelar", role: .cancel) { close() }
                    .keyboardShortcut(.cancelAction)
                if case .ready = runner.state {
                    Button("Aceitar selecionados") { accept(documents.filter { selected.contains($0.id) }) }
                        .disabled(validSelected.isEmpty)
                    Button("Aceitar todos") { accept(documents) }
                        .disabled(DocGenerate.validated(documents).isEmpty)
                        .keyboardShortcut(.defaultAction)
                }
            }.padding()
        }
        .frame(width: 680, height: 600)
        .navigationTitle("Gerar documentos")
        .onAppear {
            if case .ready(let proposal) = runner.state { load(proposal) }
        }
        .onChange(of: runner.state) { _, state in
            if case .ready(let proposal) = state { load(proposal) }
        }
    }

    private var validSelected: [DocGenerate.Document] {
        DocGenerate.validated(documents.filter { selected.contains($0.id) })
    }
    private func load(_ proposal: [DocGenerate.Document]) {
        documents = proposal
        selected = Set(proposal.map(\.id))
    }
    private func accept(_ chosen: [DocGenerate.Document]) {
        if model.acceptGeneratedDocs(chosen, undo: undo) { close() }
        else { saveError = model.errorMessage }
    }
    private func close() { runner.cancel(); dismiss() }
}
