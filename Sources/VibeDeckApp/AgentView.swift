import SwiftUI
import VibeDeckCore

struct AgentView: View {
    let slug: String
    let openAgent: (String) -> Void
    @Environment(ProjectModel.self) private var model
    @Environment(\.undoManager) private var undo
    @State private var showFlow = true
    @State private var text = ""
    @State private var savedText = ""
    @State private var loaded = false
    @State private var saveTask: Task<Void, Never>?

    private var agent: Agent { model.agent(slug) ?? Agent(title: slug) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            MarkdownEditor(text: $text, undoManager: model.undoManager(forDoc: "agent:\(slug)"), autoFocus: false)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Prompt do agente em markdown: papel, regras, formato da resposta…")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 33).padding(.vertical, 24)
                            .allowsHitTesting(false)
                    }
                }
        }
        .inspector(isPresented: $showFlow) {
            flowInspector
                .inspectorColumnWidth(min: 260, ideal: 320, max: 440)
        }
        .navigationTitle(agent.title)
        .navigationSubtitle("\(agent.model ?? "modelo herdado") · \(agent.nextSteps.count) próximo(s) passo(s)")
        .toolbar {
            ToolbarItem {
                Button { copyFlow() } label: { Label("Copiar fluxo (JSON)", systemImage: "curlybraces") }
                    .help("Copia o JSON do fluxo (prompt + próximos passos) para orquestrar a IA")
            }
            ToolbarItem {
                Button { showFlow.toggle() } label: { Label("Fluxo", systemImage: "arrow.triangle.branch") }
                    .keyboardShortcut("i", modifiers: [.command, .option])
                    .help("Mostrar/ocultar o fluxo (⌥⌘I)")
            }
        }
        .onAppear(perform: load)
        .onChange(of: text) { _, _ in scheduleSave() }
        .onChange(of: agent.prompt) { _, new in
            // External edit (CLI/MCP): adopt it unless the user has unsaved typing.
            if text == savedText, new != text { text = new; savedText = new }
        }
        .onDisappear(perform: flush)
        .onReceive(NotificationCenter.default.publisher(for: .vibedeckFlushPendingSaves)) { _ in flush() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            CommitTextField("Agente", value: agent.title) { title in
                guard !title.isEmpty else { return }
                model.mutateAgent(slug, "Renomear agente", undo: undo) { $0.title = title }
            }
            .font(.title2.weight(.semibold))
            .textFieldStyle(.plain)

            // A single HStack (not ViewThatFits): see IdeaView.
            HStack(spacing: 12) {
                CommitTextField("Modelo (ex.: sonnet, opus)", value: agent.model ?? "") { value in
                    model.mutateAgent(slug, "Alterar modelo", undo: undo) { $0.model = value.isEmpty ? nil : value }
                }
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                TagsField(tags: agent.tags) { tags in model.mutateAgent(slug, "Editar tags", undo: undo) { $0.tags = tags } }
                if agent.author == .ai {
                    Image(systemName: "sparkles").foregroundStyle(.purple).help("Criado por IA")
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: Flow

    private var candidates: [Entry] {
        let taken = Set(agent.nextSteps.filter { $0.kind == .agent }.map(\.ref))
        return model.agents.filter { $0.slug != slug && !taken.contains($0.slug) }.map { Entry(slug: $0.slug, title: $0.value.title) }
    }

    private struct Entry: Identifiable { var slug: String; var title: String; var id: String { slug } }

    private var flowInspector: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Próximos passos").font(.headline)
                Text("Agentes do VibeDeck que atuam sobre o resultado deste. Formam um fluxo.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            List {
                ForEach(Array(agent.nextSteps.enumerated()), id: \.offset) { index, step in
                    HStack {
                        Image(systemName: step.kind == .agent ? "person.crop.rectangle" : "terminal")
                        VStack(alignment: .leading) {
                            Text(model.agent(step.ref)?.title ?? step.ref)
                            if step.kind == .agent, model.agent(step.ref) == nil {
                                Text("Agente não encontrado").font(.caption).foregroundStyle(.red)
                            } else if let note = step.note {
                                Text(note).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if step.kind == .agent, model.agent(step.ref) != nil {
                            Button { openAgent(step.ref) } label: { Image(systemName: "arrow.right.circle") }
                                .buttonStyle(.borderless)
                                .help("Abrir agente")
                        }
                    }
                    .contextMenu {
                        Button("Remover", role: .destructive) {
                            model.mutateAgent(slug, "Remover próximo passo", undo: undo) { $0.nextSteps.remove(at: index) }
                        }
                    }
                }
                .onMove { from, to in
                    model.mutateAgent(slug, "Reordenar passos", undo: undo) { $0.nextSteps.move(fromOffsets: from, toOffset: to) }
                }
                .onDelete { offsets in
                    model.mutateAgent(slug, "Remover próximo passo", undo: undo) { $0.nextSteps.remove(atOffsets: offsets) }
                }
            }
            .overlay {
                if agent.nextSteps.isEmpty {
                    ContentUnavailableView("Sem próximos passos", systemImage: "arrow.triangle.branch",
                                           description: Text("Escolha abaixo qual agente atua depois deste."))
                }
            }

            Menu {
                ForEach(candidates) { c in
                    Button(c.title) {
                        model.mutateAgent(slug, "Adicionar próximo passo", undo: undo) { $0.nextSteps.append(NextStep(kind: .agent, ref: c.slug)) }
                    }
                }
                Divider()
                Button("Comando (em breve)") {}.disabled(true)
            } label: {
                Label("Adicionar próximo passo", systemImage: "plus")
            }
            .menuStyle(.borderlessButton)
            .disabled(candidates.isEmpty)
            .padding(16)
        }
    }

    private func copyFlow() {
        flush()
        guard let json = try? AgentFlow.json(from: slug, agents: model.agents.map { ($0.slug, $0.value) }) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(json, forType: .string)
    }

    // MARK: Persistence (debounced, like IdeaView)

    private func load() {
        guard !loaded else { return }
        text = agent.prompt
        savedText = text
        loaded = true
    }

    private func scheduleSave() {
        guard loaded, text != savedText else { return }
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            save()
        }
    }

    private func save() {
        let prompt = text
        model.mutateAgent(slug, "Editar prompt", undo: nil) { $0.prompt = prompt }
        savedText = prompt
    }

    private func flush() {
        saveTask?.cancel()
        if loaded, text != savedText { save() }
    }
}
