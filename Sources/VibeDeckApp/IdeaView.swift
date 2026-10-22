import SwiftUI

struct IdeaView: View {
    @Environment(\.logProject) private var providerRoot
    @Environment(\.logProject) private var logProject
    let slug: String
    let openTopic: (String) -> Void
    let openIdea: (String) -> Void
    @Environment(ProjectModel.self) private var model
    @Environment(\.undoManager) private var undo
    @Environment(AISession.self) private var session
    @State private var showRules = true
    @State private var editingAction: String?
    @State private var text = ""
    @State private var savedText = ""
    @State private var loaded = false
    @State private var insertion: MarkdownInsertion?
    @State private var promptCopiedAt: Date?
    /// Globs of the idea that match no file, waiting for the user's choice before promoting.
    @State private var stalePaths: [String] = []
    /// What runs with the topic slug once the promotion (and the stale-globs dialog) is done.
    @State private var afterPromote: ((String) -> Void)?
    /// The pending promotion leads to implementing, so its confirmation rechecks the dependencies first.
    @State private var promotionForImplementation = false
    @State private var choosingDependencies = false
    @AppStorage("ideaViewMode") private var mode: MarkdownViewMode = .edit

    private var idea: Idea { model.idea(slug) ?? Idea(title: slug) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .markdownModeShortcut($mode)
        .detailContext(isPresented: $showRules) {
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
        }
        .navigationTitle(idea.title)
        .navigationSubtitle("\(idea.status.label) · \(idea.rules.count) regra(s)")
        .toolbar {
            if !AIProvider.installed(in: providerRoot).isEmpty {
                ToolbarItem { discoverButton }
                // Fixed set of items: appearing/disappearing buttons change the toolbar width mid-layout.
                ToolbarItem { verifyButton }
                ToolbarItem { implementButton }
            }
            ToolbarItem { copyPromptButton }
            ToolbarItem { promoteButton }
            ToolbarItem { AttachButton(onPick: attach) }
            ToolbarItem { MarkdownModePicker(mode: $mode) }
            ToolbarItem {
                LoggedButton { showRules.toggle() } label: { Label("Regras", systemImage: "checkmark.shield") }.loggedControl(control: "idea_view.button_1", label: "Regras")
                    .keyboardShortcut("i", modifiers: [.command, .option])
                    .help("Mostrar/ocultar regras da ideia (⌥⌘I)")
            }
        }
        .onAppear(perform: load)
        .task(id: promptCopiedAt) {
            guard promptCopiedAt != nil else { return }
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            promptCopiedAt = nil
        }
        .onChange(of: text) { _, _ in saveIfNeeded() }
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
            // Zero min width on the preview: otherwise its markdown (long inline code, long lines) sets the pane's
            // min width, which raises the detail column's next to the rules inspector and loops AppKit's constraint pass.
            HSplitView {
                editor
                preview.frame(minWidth: 0, maxWidth: .infinity)
            }
        }
    }

    private var editor: some View {
        MarkdownEditor(
            text: $text,
            undoManager: model.undoManager(forDoc: "idea:\(slug)"),
            autoFocus: false,
            baseURL: model.store.ideasDir,
            reference: slug,
            importFiles: { model.importAttachments($0, owner: slug) },
            importImage: { model.importAttachment(data: $0, name: "colagem-\(Date.now.formatted(.iso8601)).png", owner: slug) },
            insertion: insertion,
            onEditingAction: { editingAction = $0 }
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
        MarkdownPreview(text: CoreStore.markdownForGroupedRecord(text, reference: slug), baseURL: model.store.ideaURL(slug).deletingLastPathComponent())
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
            CommitTextField(control: "ideaview.field_1", "Ideia", value: idea.title) { title in
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
            dependencyRow
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        // The header must not set the detail column's min width: its controls (fixed picker + tags at 180+ + badge/
        // sparkles) add up to ~410pt, and that min width fights the inspector split until AppKit aborts the window.
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    private var statusPicker: some View {
        Picker("Status", selection: Binding(get: { idea.status }, set: { s in model.mutateIdea(slug, "Alterar status", undo: undo) { $0.status = s } }).logging(control: "idea_view.selection_9", label: "Status", project: logProject)) {
            ForEach(IdeaStatus.allCases, id: \.self) { Label($0.label, systemImage: $0.symbol).tag($0) }
        }
        .labelsHidden()
        .fixedSize()
    }

    private var tagsField: some View {
        TagsField(tags: idea.tags) { tags in model.mutateIdea(slug, "Editar tags", undo: undo) { $0.tags = tags } }
    }

    /// Dependências (chips with ✕ + multi-selection popover) and Dependentes (derived, live). Horizontal scroll so
    /// the row never sets the detail column's min width.
    private var dependencyRow: some View {
        let dependents = model.ideaDependents(idea.id)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                LoggedButton { choosingDependencies = true } label: {
                    Label("Dependências", systemImage: "link")
                }.loggedControl(control: "idea_view.dependencies", label: "Dependências")
                .help("Ideias que precisam estar implementadas antes desta")
                .popover(isPresented: $choosingDependencies, arrowEdge: .bottom) { dependencyPicker }
                if idea.dependencies.isEmpty {
                    Text("Nenhuma").foregroundStyle(.secondary)
                }
                ForEach(idea.dependencies, id: \.self) { dependencyChip($0) }
                Divider().frame(height: 16)
                Label("Dependentes", systemImage: "arrow.turn.down.right").foregroundStyle(.secondary)
                if dependents.isEmpty {
                    Text("Nenhum").foregroundStyle(.secondary)
                }
                ForEach(dependents, id: \.id) { link in
                    LoggedButton { openIdea(link.slug) } label: {
                        Label(link.title, systemImage: link.status.symbol).lineLimit(1)
                    }.loggedControl(control: "idea_view.open_dependent", label: "Abrir dependente")
                    .buttonStyle(.link)
                    .help("Depende desta ideia (\(link.status.label.lowercased()))")
                }
            }
            .controlSize(.small)
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    private func dependencyChip(_ id: UUID) -> some View {
        let entry = model.ideas.first { $0.value.id == id }
        return HStack(spacing: 4) {
            Image(systemName: entry?.value.status.symbol ?? "questionmark.circle")
                .foregroundStyle(entry?.value.status == .done ? .green : .orange)
            if let entry {
                LoggedButton { openIdea(entry.slug) } label: { Text(entry.value.title).lineLimit(1) }
                    .loggedControl(control: "idea_view.open_dependency", label: "Abrir dependência")
                    .buttonStyle(.plain)
            } else {
                Text("Ausente: \(id.uuidString)").lineLimit(1)
            }
            LoggedButton {
                model.setIdeaDependencies(slug, idea.dependencies.filter { $0 != id }, "Remover dependência", undo: undo)
            } label: { Image(systemName: "xmark.circle.fill") }
            .loggedControl(control: "idea_view.remove_dependency", label: "Remover dependência")
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Remover esta dependência")
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .overlay(Capsule().strokeBorder(.quaternary))
        .help(entry.map { "\($0.value.status.label): só uma ideia implementada satisfaz a dependência" }
              ?? "Ideia não encontrada no projeto: bloqueia a implementação até ser removida")
    }

    /// Every idea of the project except this one, including the done ones the sidebar hides.
    private var dependencyPicker: some View {
        let candidates = model.ideas.filter { $0.value.id != idea.id }
        return VStack(alignment: .leading, spacing: 8) {
            Text("Dependências").font(.headline)
            Text("Só ideias implementadas liberam a implementação desta.").font(.caption).foregroundStyle(.secondary)
            if candidates.isEmpty {
                Text("Não há outras ideias no projeto.").foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(candidates) { entry in
                            Toggle(isOn: Binding(get: { idea.dependencies.contains(entry.value.id) }, set: { on in
                                let ids = on ? idea.dependencies + [entry.value.id] : idea.dependencies.filter { $0 != entry.value.id }
                                model.setIdeaDependencies(slug, ids, on ? "Adicionar dependência" : "Remover dependência", undo: undo)
                            }).logging(control: "idea_view.toggle_dependency", label: "Dependência", project: logProject)) {
                                Label(entry.value.title, systemImage: entry.value.status.symbol).lineLimit(1)
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                }
                .frame(maxHeight: 320)
            }
        }
        .padding(14)
        .frame(width: 320)
    }

    @ViewBuilder
    private var promotedBadge: some View {
        if let topic = idea.promotedTopic {
            LoggedButton { openTopic(topic) } label: {
                Label("Tópico: \(model.topic(topic)?.title ?? topic)", systemImage: "checkmark.shield")
                    .lineLimit(1)
                    .truncationMode(.tail)
            }.loggedControl(control: "idea_view.button_2", label: "Ativar controle")
            .buttonStyle(.glass)
            // Bounded width: the topic title must not drive the header's minimum width, or the
            // detail column + inspector outgrow the window and the split view loops.
            .frame(maxWidth: 260)
            .layoutPriority(-1)
            .help("Abrir o tópico de regras criado a partir desta ideia (clique direito para despromover)")
            .contextMenu {
                LoggedButton("Despromover", role: .destructive) {
                    flush()
                    model.unpromoteIdea(slug, undo: undo)
                }.loggedControl(control: "idea_view.button_3", label: "Despromover")
                .help("Apaga o tópico de regras; as regras rascunho continuam na ideia")
            }
        }
    }

    /// "Descubra": globs, an interview that drafts rules into `idea.rules`, then the rewritten description and tags;
    /// each accept is one undo step. `assessOnly` is "Verificar" (viability verdict only).
    private var discoverButton: some View { ruleDiscover(assessOnly: false) }

    private func ruleDiscover(assessOnly: Bool, implementation: Bool = false) -> some View {
        RuleDiscoverButton(
            assessOnly: assessOnly,
            implementation: implementation,
            onImplement: implementation ? {
                flush()
                guard let current = model.idea(slug) else { return }
                // Pending dependencies stop here, before any promotion.
                guard model.ideaDependenciesMet(slug) else { return }
                if IdeaImplementation.isEligible(current) {
                    session.requestIdeaImplementation(current)
                } else if current.status != .approved, current.implementBlocker == nil,
                          readyToPromote(then: implement, forImplementation: true) {
                    Task {
                        if let topic = await model.promoteIdea(slug, forImplementation: true) { implement(topic) }
                    }
                }
            } : nil,
            subjectReady: idea.implementBlocker == nil,
            subject: .init(idea: idea),
            current: { flush(); return .init(idea: idea) },
            vocabulary: model.tagVocabulary,
            topics: model.knownTopics(),
            store: model.store,
            applyScope: { scope, paths in
                model.mutateIdea(slug, "Descubra: globs", undo: undo) { scope.apply(paths: paths, tags: [], to: &$0.paths, tags: &$0.tags) }
            },
            applyRules: { drafts, chosen in
                model.mutateIdea(slug, "Descubra: regras", undo: undo) { drafts.apply(chosen, to: &$0.rules) }
            },
            applyDetails: { proposal, accepted, tags in
                flush()
                model.mutateIdea(slug, "Descubra: descrição e tags", undo: undo) { idea in
                    proposal.apply(acceptDescription: accepted, tags: tags, description: &idea.body, tags: &idea.tags)
                }
                if accepted, let suggested = proposal.suggested { text = suggested; savedText = suggested }
            },
            applyVerdict: { verdict in
                flush()
                let previousStatus = idea.status
                model.mutateIdea(slug, "Verificar: avaliação", undo: undo) { verdict.apply(to: &$0) }
                if idea.status != previousStatus {
                    VDLog.info("idea.status_changed", "Status da ideia alterado", project: model.store.root, component: .app,
                               context: ["slug": slug, "status": idea.status.rawValue])
                }
            }
        )
        .id("\(slug)-\(assessOnly)-\(implementation)")
    }

    /// Not verified, stale or vague: "Verificar" re-runs only the viability verdict. Always in the toolbar
    /// (disabled when there is nothing to verify) so the toolbar never changes size.
    private var verifyButton: some View {
        let needed = idea.implementBlocker != nil && !idea.rules.isEmpty && !idea.status.isClosed
        return ruleDiscover(assessOnly: true)
            .disabled(!needed)
    }

    /// "Implementar": only for a viable idea (rules + current AI verdict). Promotes/syncs the rules (so rules_for
    /// enforces them; the idea becomes Aprovada) and asks the chat to implement it.
    private var implementButton: some View {
        let blockers = model.ideaDependencyBlockers(idea)
        return ruleDiscover(assessOnly: true, implementation: true)
            .disabled(!idea.canRequestImplementation || !blockers.isEmpty)
            .help(!blockers.isEmpty ? "Dependências pendentes:\n" + blockers.map(\.message).joined(separator: "\n")
                  : idea.implementBlocker.map { "Reavaliar antes de implementar: " + $0 } ?? "Implementar a ideia avaliada")
    }

    private var copyPromptButton: some View {
        LoggedButton {
            flush()
            let prompt = IdeaImplementation.prompt(slug: slug, idea: idea, topic: idea.promotedTopic)
            NSPasteboard.general.clearContents()
            if NSPasteboard.general.setString(prompt, forType: .string) {
                promptCopiedAt = .now
            }
        } label: {
            Label(promptCopiedAt == nil ? "Copiar prompt" : "Copiado",
                  systemImage: promptCopiedAt == nil ? "doc.on.doc" : "checkmark")
        }.loggedControl(control: "idea_view.copy_prompt", label: "Copiar prompt")
        .help("Copiar o prompt de implementação da ideia para a área de transferência")
    }

    private var promoteButton: some View {
        LoggedButton {
            if readyToPromote(then: openTopic) {
                Task {
                    if let topic = await model.promoteIdea(slug) { openTopic(topic) }
                }
            }
        } label: {
            Label(idea.promotedTopic == nil ? "Promover para Regras" : "Sincronizar regras", systemImage: "arrow.up.forward.square")
        }.loggedControl(control: "idea_view.button_5", label: "Ativar controle")
        .disabled(idea.rules.isEmpty)
        .help(idea.promotedTopic == nil
              ? "Cria um tópico de regras ativo com as regras (e os globs) desta ideia"
              : "Leva regras e globs novos desta ideia para o tópico já criado")
        .confirmationDialog("Globs que não casam nenhum arquivo", isPresented: Binding(get: { !stalePaths.isEmpty }, set: { if !$0 { stalePaths = [] } })) {
            LoggedButton("Promover sem eles") {
                let (skipped, then, implementing) = takePendingPromotion()
                Task {
                    if let topic = await model.promoteIdea(slug, skippingPaths: skipped, forImplementation: implementing) { then?(topic) }
                }
            }.loggedControl(control: "idea_view.button_6", label: "Promover sem eles")
            LoggedButton("Promover com eles") {
                let (_, then, implementing) = takePendingPromotion()
                Task {
                    if let topic = await model.promoteIdea(slug, forImplementation: implementing) { then?(topic) }
                }
            }.loggedControl(control: "idea_view.button_7", label: "Promover com eles")
            LoggedButton("Cancelar", role: .cancel) { stalePaths = []; afterPromote = nil; promotionForImplementation = false }.loggedControl(control: "idea_view.button_8", label: "Cancelar")
        } message: {
            Text("Estes globs da ideia não casam mais nenhum arquivo do projeto (renomeado ou apagado?):\n" + stalePaths.joined(separator: "\n"))
        }
    }

    private func implement(_ topic: String) {
        session.ask(IdeaImplementation.prompt(slug: slug, idea: idea, topic: topic), inspectIdeas: false)
    }

    /// Before promoting from a button: true when it can go ahead now; false when globs match no file, and the
    /// dialog asks first (its buttons promote and then run `then` with the topic).
    /// `forImplementation`: the dialog's confirmation rechecks the dependencies (Core, from disk) before promoting.
    private func readyToPromote(then: @escaping (String) -> Void, forImplementation: Bool = false) -> Bool {
        flush()
        stalePaths = model.unmatchedIdeaPaths(slug)
        afterPromote = stalePaths.isEmpty ? nil : then
        promotionForImplementation = !stalePaths.isEmpty && forImplementation
        return stalePaths.isEmpty
    }

    /// Closes the stale-globs dialog: the globs it listed and what to run after promoting.
    private func takePendingPromotion() -> (Set<String>, ((String) -> Void)?, Bool) {
        defer { stalePaths = []; afterPromote = nil; promotionForImplementation = false }
        return (Set(stalePaths), afterPromote, promotionForImplementation)
    }

    // MARK: Persistence (debounced, like DocView)

    private func load() {
        guard !loaded else { return }
        text = idea.body ?? ""
        savedText = text
        loaded = true
    }

    private func saveIfNeeded() {
        guard loaded, text != savedText else { return }
        save()
    }

    private func save() {
        VDLog.$actionID.withValue(VDLog.actionID ?? editingAction) {
            let body = text
            // The text view keeps its own undo history; don't duplicate it in the window's.
            model.mutateIdea(slug, "Editar texto", undo: nil) { $0.body = body.isEmpty ? nil : body }
            savedText = body
        }
    }

    private func flush() {
        if loaded, text != savedText { save() }
    }
}
