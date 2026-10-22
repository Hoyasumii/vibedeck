import SwiftUI

/// Ação do atalho ⇧⌘C (alternar o painel de IA) da janela em foco. Sempre igual para o SwiftUI não republicar o valor.
struct AIPanelToggle: Equatable {
    let run: () -> Void
    static func == (a: AIPanelToggle, b: AIPanelToggle) -> Bool { true }
}

extension FocusedValues {
    @Entry var aiPanelToggle: AIPanelToggle?
}

/// Janela do projeto V2: trilho de espaços, coluna de conteúdo com lista filtrável, detalhe,
/// painel de IA à direita (inspector, ⇧⌘C) e barra de status. Sem nuvem.
struct ProjectWindowV2: View {
    @Environment(\.openSettings) private var openSettings
    @State private var model: ProjectModel
    @State private var claude: AISession
    @State private var workspace: RemoteWorkspace?
    @State private var space: V2Space = .project
    @State private var conceptBySpace: [V2Space: V2Concept] = [:]
    @State private var selection: SidebarItem?
    @State private var aiVisible = false
    @State private var aiExpanded = false
    @State private var newName: ProjectWindow.NewNamePrompt?
    @State private var filterFocusRequest = 0
    @State private var reconciledMoveRevision = 0

    init(root: URL) {
        let model = ProjectModel(store: CoreStore(root: root))
        _model = State(initialValue: model)
        _claude = State(initialValue: AISession(root: root, projectId: model.project.id))
        _workspace = State(initialValue: RemoteWorkspace.existing(at: root))
    }

    // MARK: Estado derivado

    private var concept: V2Concept { conceptBySpace[space] ?? space.concepts[0] }

    private func key(_ name: String) -> String { "v2.\(name).\(model.project.id.uuidString)" }

    private var resolvedSelection: SidebarItem? {
        guard let selection else { return nil }
        if exists(selection) { return selection }
        return model.latestPathMoves[selection] ?? selection
    }

    private var selectionExists: Bool {
        guard let selection else { return true }
        return exists(selection)
    }

    /// Um terminal enquanto o shell roda; qualquer outro item conforme o modelo.
    private func exists(_ item: SidebarItem) -> Bool {
        if case .terminal(let id) = item { return claude.terminals[id] != nil }
        return model.exists(item)
    }

    // MARK: Corpo (em etapas: uma cadeia longa de modificadores estoura o type-checker)

    var body: some View {
        withLifecycle
            .sheet(item: $newName) { prompt in createItem(prompt) }
            .sheet(item: ideaRequestBinding) { request in
                IdeaImplementationSheet(request: request)
                    .environment(model)
                    .environment(claude)
                    .environment(\.logProject, model.store.root)
            }
            .alert("Erro", isPresented: errorPresented) {
                LoggedButton("OK") { model.errorMessage = nil }
                    .loggedControl(control: "v2_project_window.error_ok", label: "OK")
            } message: { Text(model.errorMessage ?? "") }
    }

    private var ideaRequestBinding: Binding<AISession.IdeaRequest?> {
        Binding(get: { claude.ideaRequest }, set: { claude.ideaRequest = $0 })
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    }

    private var withContext: some View {
        shell
            .onChange(of: claude.requestedPage) { _, page in handleRequestedPage(page) }
            .background(LoggingWindowContext(root: model.store.root).allowsHitTesting(false))
            .environment(\.logProject, model.store.root)
            .environment(model)
            .environment(claude)
            .focusedSceneValue(\.logProjectRoot, model.store.root)
            .focusedSceneValue(\.claudeSession, claude)
            .focusedSceneValue(\.aiPanelToggle, AIPanelToggle { toggleAI() })
    }

    private var withLifecycle: some View {
        withContext
            .task {
                model.startWatching()
                restoreState()
            }
            .onChange(of: selection) { _, new in selectionChanged(new) }
            .onChange(of: selectionExists) { _, _ in pruneSelection() }
            .onChange(of: model.moveRevision) { _, _ in reconcileMoves() }
            .onChange(of: concept) { _, new in UserDefaults.standard.set(new.rawValue, forKey: key("concept")) }
            .onChange(of: aiVisible) { _, new in UserDefaults.standard.set(new, forKey: key("ai")) }
            .onDisappear {
                model.stopWatching()
                claude.stop()
                Array(claude.terminals.keys).forEach(claude.closeTerminal)
            }
    }

    private var shell: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                rail
                splitView
            }
            statusBar
        }
        // O header da janela tem a mesma cor do conteúdo (sem faixa de toolbar separada).
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    }

    private var rail: some View {
        V2Rail(selected: space, projectName: model.project.name,
               onSelect: { showSpace($0) },
               onSearch: { filterFocusRequest += 1 },
               onSettings: { openSettings() },
               onProject: { NSWorkspace.shared.activateFileViewerSelecting([model.store.manifestURL]) })
    }

    private var statusBar: some View {
        V2StatusBar(workspace: workspace,
                    onOpenChecks: { show(.rules) },
                    onOpenTerminal: { selection = .terminal($0) })
    }

    private var splitView: some View {
        NavigationSplitView {
            contentColumn
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
        } detail: {
            detail
        }
    }

    private var contentColumn: some View {
        V2ContentColumn(space: space, concept: conceptBinding, selection: $selection,
                        focusRequest: filterFocusRequest, onAdd: { newName = ProjectWindow.NewNamePrompt($0) })
    }

    private var conceptBinding: Binding<V2Concept> {
        Binding(get: { concept }, set: { show($0) })
    }

    // MARK: Detalhe e painel de IA

    private var detail: some View {
        detailBody
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .toolbar { aiToolbar }
            .inspector(isPresented: inspectorPresented) {
                aiPanel
                    .inspectorColumnWidth(min: 300, ideal: 340, max: 460)
            }
    }

    private var inspectorPresented: Binding<Bool> {
        Binding(get: { aiVisible && !aiExpanded }, set: { aiVisible = $0 })
    }

    @ViewBuilder
    private var detailBody: some View {
        if aiExpanded {
            expandedAI
        } else {
            detailContent
                .transition(.opacity)
                .id(detailIdentity)
                .animation(.easeInOut(duration: DesignTokens.Motion.base), value: selection)
        }
    }

    private var detailIdentity: String {
        concept.rawValue + ":" + model.contentIdentity(for: resolvedSelection)
    }

    @ToolbarContentBuilder
    private var aiToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if aiVisible && !aiExpanded {
                LoggedButton { aiExpanded = true } label: { Label("Expandir IA", systemImage: "arrow.up.left.and.arrow.down.right") }
                    .loggedControl(control: "v2_project_window.ai_expand", label: "Expandir IA")
                    .help("Mostrar a IA em tela cheia")
            }
            LoggedButton { toggleAI() } label: { Label("Painel de IA", systemImage: "sidebar.right") }
                .loggedControl(control: "v2_project_window.ai_toggle", label: "Painel de IA")
                .help("Mostrar ou ocultar o painel de IA (⇧⌘C)")
        }
    }

    @ViewBuilder
    private var aiPanel: some View {
        if AIProvider.installed(in: model.store.root).isEmpty {
            ContentUnavailableView("IA indisponível", systemImage: "sparkles",
                                   description: Text("Instale o Claude Code ou o Codex para usar o painel de IA."))
        } else {
            ClaudeChatPage()
        }
    }

    private var expandedAI: some View {
        VStack(spacing: 0) {
            HStack {
                Text("IA").font(DesignTokens.Typography.title)
                Spacer()
                LoggedButton("Voltar ao painel") { aiExpanded = false; aiVisible = true }
                    .loggedControl(control: "v2_project_window.ai_collapse", label: "Voltar ao painel")
                    .buttonStyle(.glass)
            }
            .padding(.horizontal, DesignTokens.Space.s4)
            .padding(.vertical, DesignTokens.Space.s2)
            Divider()
            aiPanel
        }
    }

    private func toggleAI() {
        if aiExpanded {
            aiExpanded = false
            aiVisible = true
        } else {
            aiVisible.toggle()
        }
    }

    private func handleRequestedPage(_ page: AISession.Page?) {
        switch page {
        case .chat:
            aiExpanded = false
            aiVisible = true
        case .terminal(let id):
            selection = .terminal(id)
        case nil:
            return
        }
        claude.requestedPage = nil
    }

    // MARK: Conteúdo do detalhe (reaproveita as telas V1)

    @ViewBuilder
    private var detailContent: some View {
        switch resolvedSelection {
        case .none:
            homeContent
        case .some(let item):
            itemContent(item)
        }
    }

    /// Sem item selecionado: a tabela da seção (com as ações V1), os Links ou a Visão geral.
    @ViewBuilder
    private var homeContent: some View {
        if let section = concept.section {
            sectionTable(section)
        } else if concept == .references {
            LinksView()
        } else {
            V2OverviewView { open($0) }
        }
    }

    private func sectionTable(_ section: SidebarSection) -> some View {
        SectionListView(section: section) { open($0) } onOpenInNewTab: { open($0) } onAdd: { newName = ProjectWindow.NewNamePrompt(section) }
    }

    @ViewBuilder
    private func itemContent(_ item: SidebarItem) -> some View {
        switch item {
        case .stack:
            StackView()
        case .patterns:
            PatternsView { open($0) }
        case .links:
            LinksView()
        case .claudeItems:
            ClaudeItemsView()
        case .graph:
            GraphView()
        case .claude:
            ClaudeChatPage()
        case .terminal(let id):
            V2TerminalPage(id: id) {
                claude.closeTerminal(id)
                selection = nil
            }
        case .section(let section):
            sectionTable(section)
        default:
            itemDetail(item)
        }
    }

    @ViewBuilder
    private func itemDetail(_ item: SidebarItem) -> some View {
        switch item {
        case .doc(let slug):
            if model.docs.contains(where: { $0.slug == slug }) {
                DocView(slug: slug)
            } else {
                ContentUnavailableView("Documento não encontrado", systemImage: "doc.questionmark")
            }
        case .group(let slug):
            if model.group(slug) != nil {
                ReviewGroupView(slug: slug)
            } else {
                ContentUnavailableView("Grupo não encontrado", systemImage: "questionmark.folder")
            }
        case .topic(let slug):
            if model.topic(slug) != nil {
                RuleTopicView(slug: slug)
            } else {
                ContentUnavailableView("Tópico não encontrado", systemImage: "questionmark.folder")
            }
        case .idea(let slug):
            if model.idea(slug) != nil {
                IdeaView(slug: slug) { open(.topic($0)) } openIdea: { open(.idea($0)) }
            } else {
                ContentUnavailableView("Ideia não encontrada", systemImage: "questionmark.folder")
            }
        default:
            automationDetail(item)
        }
    }

    @ViewBuilder
    private func automationDetail(_ item: SidebarItem) -> some View {
        switch item {
        case .agent(let slug):
            if model.agent(slug) != nil {
                AgentView(slug: slug) { open($0) }
            } else {
                ContentUnavailableView("Agente não encontrado", systemImage: "questionmark.folder")
            }
        case .command(let slug):
            if model.command(slug) != nil {
                CommandView(slug: slug) { open($0) }
            } else {
                ContentUnavailableView("Comando não encontrado", systemImage: "questionmark.folder")
            }
        case .skill(let slug):
            if model.skill(slug) != nil {
                SkillView(slug: slug) { open($0) }
            } else {
                ContentUnavailableView("Skill não encontrada", systemImage: "questionmark.folder")
            }
        case .workflow(let slug):
            if model.workflow(slug) != nil {
                WorkflowView(slug: slug) { open($0) }
            } else {
                ContentUnavailableView("Workflow não encontrado", systemImage: "questionmark.folder")
            }
        default:
            EmptyView()
        }
    }

    // MARK: Criação

    private func createItem(_ prompt: ProjectWindow.NewNamePrompt) -> some View {
        NamePromptSheet(title: prompt.title, placeholder: prompt.placeholder) { name in
            switch prompt {
            case .doc: if let slug = model.createDoc(title: name) { open(.doc(slug)) }
            case .group: if let slug = model.createGroup(title: name) { open(.group(slug)) }
            case .topic: if let slug = model.createTopic(title: name) { open(.topic(slug)) }
            case .idea: if let slug = model.createIdea(title: name) { open(.idea(slug)) }
            case .agent: if let slug = model.createAgent(title: name) { open(.agent(slug)) }
            case .command: if let slug = model.createCommand(title: name) { open(.command(slug)) }
            case .skill: if let slug = model.createSkill(title: name) { open(.skill(slug)) }
            case .workflow: if let slug = model.createWorkflow(title: name) { open(.workflow(slug)) }
            }
        }
    }

    // MARK: Navegação e estado

    private func open(_ item: SidebarItem) {
        selection = item
    }

    private func showSpace(_ target: V2Space) {
        show(conceptBySpace[target] ?? target.concepts[0])
    }

    /// Entra num conceito: troca de espaço e abre a página inicial dele (ou mantém o item, se já for do conceito).
    private func show(_ target: V2Concept) {
        space = target.space
        conceptBySpace[target.space] = target
        if let current = selection, V2Concept.of(current) == target { return }
        selection = target.defaultSelection
    }

    private func selectionChanged(_ item: SidebarItem?) {
        let defaults = UserDefaults.standard
        guard let item else {
            defaults.removeObject(forKey: key("selection"))
            return
        }
        if item == .claude {
            aiExpanded = false
            aiVisible = true
            selection = nil
            return
        }
        if let target = V2Concept.of(item) {
            space = target.space
            conceptBySpace[target.space] = target
        }
        if !item.isTerminal { defaults.set(item.storageKey, forKey: key("selection")) }
    }

    private func reconcileMoves() {
        guard reconciledMoveRevision != model.moveRevision else { return }
        reconciledMoveRevision = model.moveRevision
        if let current = selection, let moved = model.latestPathMoves[current] { selection = moved }
    }

    /// Limpa a seleção quando o item foi apagado (no app ou no disco) ou o shell do terminal terminou.
    private func pruneSelection() {
        reconcileMoves()
        if let current = selection, !exists(current) { selection = nil }
    }

    private func restoreState() {
        let defaults = UserDefaults.standard
        aiVisible = defaults.bool(forKey: key("ai"))
        if let saved = SidebarItem(storageKey: defaults.string(forKey: key("selection"))),
           !saved.isTerminal, saved != .claude, exists(saved) {
            selection = saved
        }
        if let raw = defaults.string(forKey: key("concept")), let saved = V2Concept(rawValue: raw) {
            space = saved.space
            conceptBySpace[saved.space] = saved
        }
        if let current = selection, let owner = V2Concept.of(current) {
            space = owner.space
            conceptBySpace[owner.space] = owner
        } else if selection == nil, let fallback = concept.defaultSelection {
            selection = fallback
        }
    }
}

/// Um terminal do projeto como página do detalhe, com cabeçalho e botão para encerrar o shell.
private struct V2TerminalPage: View {
    let id: UUID
    let onClose: () -> Void
    @Environment(AISession.self) private var claude

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DesignTokens.Space.s2) {
                VDIcon(.terminal, size: 13)
                Text(claude.terminals[id]?.title ?? "Terminal").font(DesignTokens.Typography.headline)
                Spacer()
                LoggedButton("Encerrar", role: .destructive, action: onClose)
                    .loggedControl(control: "v2_project_window.terminal_close", label: "Encerrar terminal")
                    .buttonStyle(.glass)
            }
            .padding(.horizontal, DesignTokens.Space.s4)
            .padding(.vertical, DesignTokens.Space.s2)
            Divider()
            TerminalPage(id: id)
        }
    }
}
