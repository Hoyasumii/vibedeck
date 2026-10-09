import SwiftUI
import VibeDeckCore

/// Same page as `AgentView`, for a command: a slash-command-like prompt (with `$ARGUMENTS`) plus its flow.
struct CommandView: View {
    let slug: String
    let open: (SidebarItem) -> Void
    @Environment(ProjectModel.self) private var model
    @Environment(\.undoManager) private var undo
    @State private var showFlow = true
    @State private var text = ""
    @State private var savedText = ""
    @State private var loaded = false
    @State private var saveTask: Task<Void, Never>?

    private var command: Command { model.command(slug) ?? Command(title: slug) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            MarkdownEditor(text: $text, undoManager: model.undoManager(forDoc: "command:\(slug)"), autoFocus: false)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Prompt do comando em markdown. Use $ARGUMENTS para os argumentos da chamada.")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 33).padding(.vertical, 24)
                            .allowsHitTesting(false)
                    }
                }
        }
        .inspector(isPresented: $showFlow) {
            NextStepsInspector(owner: .command(slug), steps: command.nextSteps, mutate: { actionName, change in
                model.mutateCommand(slug, actionName, undo: undo) { change(&$0.nextSteps) }
            }, open: open)
            .inspectorColumnWidth(min: 260, ideal: 320, max: 440)
        }
        .navigationTitle(command.title)
        .navigationSubtitle("\(command.model ?? "modelo herdado") · \(command.nextSteps.count) próximo(s) passo(s)")
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
        .onChange(of: command.prompt) { _, new in
            // External edit (CLI/MCP): adopt it unless the user has unsaved typing.
            if text == savedText, new != text { text = new; savedText = new }
        }
        .onDisappear(perform: flush)
        .onReceive(NotificationCenter.default.publisher(for: .vibedeckFlushPendingSaves)) { _ in flush() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            CommitTextField("Comando", value: command.title) { title in
                guard !title.isEmpty else { return }
                model.mutateCommand(slug, "Renomear comando", undo: undo) { $0.title = title }
            }
            .font(.title2.weight(.semibold))
            .textFieldStyle(.plain)

            CommitTextField("Descrição (o que o comando faz)", value: command.summary ?? "") { value in
                model.mutateCommand(slug, "Alterar descrição", undo: undo) { $0.summary = value.isEmpty ? nil : value }
            }
            .textFieldStyle(.plain)
            .foregroundStyle(.secondary)

            // Hidden, not disabled, when no AI provider is installed.
            if !AIProvider.installed.isEmpty {
                AIProviderSettingsView(settings: command.providerSettings) { provider, settings in
                    model.mutateCommand(slug, "Configurar provedor", undo: undo) {
                        var all = $0.providerSettings ?? [:]; all[provider] = settings; $0.providerSettings = all
                    }
                }
            }

            // A single HStack (not ViewThatFits): see IdeaView.
            HStack(spacing: 12) {
                CommitTextField("Argumentos (ex.: <mensagem>)", value: command.argumentHint ?? "") { value in
                    model.mutateCommand(slug, "Alterar argumentos", undo: undo) { $0.argumentHint = value.isEmpty ? nil : value }
                }
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                CommitTextField("Modelo (ex.: sonnet, opus)", value: command.model ?? "") { value in
                    model.mutateCommand(slug, "Alterar modelo", undo: undo) { $0.model = value.isEmpty ? nil : value }
                }
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                TagsField(tags: command.tags) { tags in model.mutateCommand(slug, "Editar tags", undo: undo) { $0.tags = tags } }
                if command.author == .ai {
                    Image(systemName: "sparkles").foregroundStyle(.purple).help("Criado por IA")
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func copyFlow() {
        flush()
        guard let json = try? AgentFlow.json(
            kind: .command, from: slug,
            agents: model.agents.map { ($0.slug, $0.value) }, commands: model.commands.map { ($0.slug, $0.value) },
            skills: model.skills.map { ($0.slug, $0.value) }
        ) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(json, forType: .string)
    }

    // MARK: Persistence (debounced, like IdeaView)

    private func load() {
        guard !loaded else { return }
        text = command.prompt
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
        model.mutateCommand(slug, "Editar prompt", undo: nil) { $0.prompt = prompt }
        savedText = prompt
    }

    private func flush() {
        saveTask?.cancel()
        if loaded, text != savedText { save() }
    }
}
