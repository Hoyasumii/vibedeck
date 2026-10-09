import SwiftUI
import VibeDeckCore

struct IdeaView: View {
    let slug: String
    let openTopic: (String) -> Void
    @Environment(ProjectModel.self) private var model
    @Environment(\.undoManager) private var undo
    @State private var showRules = true
    @State private var text = ""
    @State private var savedText = ""
    @State private var loaded = false
    @State private var saveTask: Task<Void, Never>?
    @State private var insertion: MarkdownInsertion?
    /// Globs of the idea that match no file, waiting for the user's choice before promoting.
    @State private var stalePaths: [String] = []
    @AppStorage("ideaViewMode") private var mode: MarkdownViewMode = .edit

    private var idea: Idea { model.idea(slug) ?? Idea(title: slug) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .markdownModeShortcut($mode)
        .inspector(isPresented: $showRules) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Regras da ideia").font(.headline)
                    Text(idea.promotedTopic == nil
                         ? "Rascunho: só passam a valer depois de promovidas."
                         : "Promovida: novas regras entram no tópico ao sincronizar.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                RuleListEditor(
                    rules: idea.rules,
                    emptyTitle: "Sem regras",
                    emptyHint: "Como essa ideia deve se comportar quando existir?"
                ) { action, change in
                    model.mutateIdea(slug, action, undo: undo) { change(&$0.rules) }
                }
            }
            .inspectorColumnWidth(min: 260, ideal: 320, max: 440)
        }
        .navigationTitle(idea.title)
        .navigationSubtitle("\(idea.status.label) · \(idea.rules.count) regra(s)")
        .toolbar {
            if !AIProvider.installed.isEmpty { ToolbarItem { discoverButton } }
            ToolbarItem { promoteButton }
            ToolbarItem { AttachButton(onPick: attach) }
            ToolbarItem { MarkdownModePicker(mode: $mode) }
            ToolbarItem {
                Button { showRules.toggle() } label: { Label("Regras", systemImage: "checkmark.shield") }
                    .keyboardShortcut("i", modifiers: [.command, .option])
                    .help("Mostrar/ocultar regras da ideia (⌥⌘I)")
            }
        }
        .onAppear(perform: load)
        .onChange(of: text) { _, _ in scheduleSave() }
        .onChange(of: idea.body) { _, new in
            // External edit (CLI/MCP): adopt it unless the user has unsaved typing.
            let disk = new ?? ""
            if text == savedText, disk != text { text = disk; savedText = disk }
        }
        .onDisappear(perform: flush)
        .onReceive(NotificationCenter.default.publisher(for: .vibedeckFlushPendingSaves)) { _ in flush() }
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .edit:
            editor
        case .read:
            preview
        case .split:
            HSplitView {
                editor.frame(minWidth: 280)
                preview.frame(minWidth: 280)
            }
        }
    }

    private var editor: some View {
        MarkdownEditor(
            text: $text,
            undoManager: model.undoManager(forDoc: "idea:\(slug)"),
            autoFocus: false,
            importFiles: { model.importAttachments($0, owner: slug) },
            importImage: { model.importAttachment(data: $0, name: "colagem-\(Date.now.formatted(.iso8601)).png", owner: slug) },
            insertion: insertion
        )
        .overlay(alignment: .topLeading) {
            if text.isEmpty {
                Text("Descreva a ideia em markdown: problema, proposta, dúvidas… (arraste arquivos para anexar)")
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 33).padding(.vertical, 24)
                    .allowsHitTesting(false)
            }
        }
    }

    private var preview: some View {
        MarkdownPreview(text: text, baseURL: model.store.ideasDir)
    }

    /// Files from the "Anexar" button go in through the editor (so ⌘Z undoes them): at the cursor, or
    /// at the end after opening the editor beside the preview when only the preview is showing.
    private func attach(_ urls: [URL]) {
        let links = model.importAttachments(urls, owner: slug).joined(separator: "\n")
        guard !links.isEmpty else { return }
        guard mode == .read else { return insertion = MarkdownInsertion(text: links) }
        mode = .split
        DispatchQueue.main.async { insertion = MarkdownInsertion(text: links, atEnd: true) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            CommitTextField("Ideia", value: idea.title) { title in
                guard !title.isEmpty else { return }
                model.mutateIdea(slug, "Renomear ideia", undo: undo) { $0.title = title }
            }
            .font(.title2.weight(.semibold))
            .textFieldStyle(.plain)

            // A single HStack (not ViewThatFits): switching layouts changes the detail column's
            // min width mid-layout, which loops NavigationSplitView/inspector sizing and crashes AppKit.
            HStack(spacing: 12) {
                statusPicker; tagsField; promotedBadge
                if idea.author == .ai {
                    Image(systemName: "sparkles").foregroundStyle(.purple).help("Criado por IA")
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var statusPicker: some View {
        Picker("Status", selection: Binding(get: { idea.status }, set: { s in model.mutateIdea(slug, "Alterar status", undo: undo) { $0.status = s } })) {
            ForEach(IdeaStatus.allCases, id: \.self) { Label($0.label, systemImage: $0.symbol).tag($0) }
        }
        .labelsHidden()
        .fixedSize()
    }

    private var tagsField: some View {
        TagsField(tags: idea.tags) { tags in model.mutateIdea(slug, "Editar tags", undo: undo) { $0.tags = tags } }
    }

    @ViewBuilder
    private var promotedBadge: some View {
        if let topic = idea.promotedTopic {
            Button { openTopic(topic) } label: {
                Label("Tópico: \(model.topic(topic)?.title ?? topic)", systemImage: "checkmark.shield")
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .buttonStyle(.glass)
            // Bounded width: the topic title must not drive the header's minimum width, or the
            // detail column + inspector outgrow the window and the split view loops.
            .frame(maxWidth: 260)
            .layoutPriority(-1)
            .help("Abrir o tópico de regras criado a partir desta ideia (clique direito para despromover)")
            .contextMenu {
                Button("Despromover", role: .destructive) {
                    flush()
                    model.unpromoteIdea(slug, undo: undo)
                }
                .help("Apaga o tópico de regras; as regras rascunho continuam na ideia")
            }
        }
    }

    /// "Descubra": globs, tags and an interview that drafts rules into `idea.rules`; each accept is one undo step.
    private var discoverButton: some View {
        RuleDiscoverButton(
            subject: .init(idea: idea),
            current: { flush(); return .init(idea: idea) },
            vocabulary: model.tagVocabulary,
            topics: model.knownTopics(),
            store: model.store,
            applyScope: { scope, paths, tags in
                model.mutateIdea(slug, "Descubra: globs e tags", undo: undo) { scope.apply(paths: paths, tags: tags, to: &$0.paths, tags: &$0.tags) }
            },
            applyRules: { drafts, chosen in
                model.mutateIdea(slug, "Descubra: regras", undo: undo) { drafts.apply(chosen, to: &$0.rules) }
            }
        )
        .id(slug)
    }

    private var promoteButton: some View {
        Button {
            flush()
            stalePaths = (try? model.store.unmatchedIdeaPaths(slug)) ?? []
            if stalePaths.isEmpty, let topic = model.promoteIdea(slug) { openTopic(topic) }
        } label: {
            Label(idea.promotedTopic == nil ? "Promover para Regras" : "Sincronizar regras", systemImage: "arrow.up.forward.square")
        }
        .disabled(idea.rules.isEmpty)
        .help(idea.promotedTopic == nil
              ? "Cria um tópico de regras ativo com as regras (e os globs) desta ideia"
              : "Leva regras e globs novos desta ideia para o tópico já criado")
        .confirmationDialog("Globs que não casam nenhum arquivo", isPresented: Binding(get: { !stalePaths.isEmpty }, set: { if !$0 { stalePaths = [] } })) {
            Button("Promover sem eles") {
                let skipped = Set(stalePaths)
                stalePaths = []
                if let topic = model.promoteIdea(slug, skippingPaths: skipped) { openTopic(topic) }
            }
            Button("Promover com eles") {
                stalePaths = []
                if let topic = model.promoteIdea(slug) { openTopic(topic) }
            }
            Button("Cancelar", role: .cancel) { stalePaths = [] }
        } message: {
            Text("Estes globs da ideia não casam mais nenhum arquivo do projeto (renomeado ou apagado?):\n" + stalePaths.joined(separator: "\n"))
        }
    }


    // MARK: Persistence (debounced, like DocView)

    private func load() {
        guard !loaded else { return }
        text = idea.body ?? ""
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
        let body = text
        // The text view keeps its own undo history; don't duplicate it in the window's.
        model.mutateIdea(slug, "Editar texto", undo: nil) { $0.body = body.isEmpty ? nil : body }
        savedText = body
    }

    private func flush() {
        saveTask?.cancel()
        if loaded, text != savedText { save() }
    }
}
