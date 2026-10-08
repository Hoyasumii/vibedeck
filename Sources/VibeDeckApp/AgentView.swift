import SwiftUI
import VibeDeckCore

struct AgentView: View {
    let slug: String
    let open: (SidebarItem) -> Void
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

    private var flowInspector: some View {
        NextStepsInspector(owner: .agent(slug), steps: agent.nextSteps, mutate: { actionName, change in
            model.mutateAgent(slug, actionName, undo: undo) { change(&$0.nextSteps) }
        }, open: open)
    }

    private func copyFlow() {
        flush()
        guard let json = try? AgentFlow.json(
            from: slug, agents: model.agents.map { ($0.slug, $0.value) }, commands: model.commands.map { ($0.slug, $0.value) },
            skills: model.skills.map { ($0.slug, $0.value) }
        ) else { return }
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
