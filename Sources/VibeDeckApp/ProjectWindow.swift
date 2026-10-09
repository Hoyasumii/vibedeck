import SwiftUI
import VibeDeckCore

struct ProjectWindow: View {
    @Environment(\.undoManager) private var undo
    @State private var model: ProjectModel
    @State private var claude: AISession
    @State private var selection: SidebarItem?
    /// Open tabs; `selection` always mirrors `tabs[activeTab]`.
    @State private var tabs: [SidebarItem] = [.links]
    @State private var activeTab = 0
    /// Sidebar sections whose children are shown. Toggled by the chevron, independent of selection.
    @State private var expanded = Set<SidebarSection>()
    @State private var newName: NewNamePrompt?

    init(root: URL) {
        let model = ProjectModel(store: ProjectStore(root: root))
        _model = State(initialValue: model)
        _claude = State(initialValue: AISession(root: root, projectId: model.project.id))
    }

    enum NewNamePrompt: Identifiable {
        case doc, group, topic, idea, agent, command, skill, workflow
        var id: Self { self }

        init(_ section: SidebarSection) {
            switch section {
            case .docs: self = .doc
            case .groups: self = .group
            case .topics: self = .topic
            case .ideas: self = .idea
            case .agents: self = .agent
            case .commands: self = .command
            case .skills: self = .skill
            case .workflows: self = .workflow
            }
        }

        var title: String {
            switch self {
            case .doc: "Novo documento"
            case .group: "Novo grupo de revisão"
            case .topic: "Novo tópico de regras"
            case .idea: "Nova ideia"
            case .agent: "Novo agente"
            case .command: "Novo comando"
            case .skill: "Nova skill"
            case .workflow: "Novo workflow"
            }
        }

        var placeholder: String {
            switch self {
            case .doc: "Título do documento"
            case .group: "Tema (ex.: Tela de login)"
            case .topic: "Tópico (ex.: Interface, API, Acessibilidade)"
            case .idea: "Ideia (ex.: Modo offline)"
            case .agent: "Nome do agente (ex.: Revisor de código)"
            case .command: "Nome do comando (ex.: commit)"
            case .skill: "Nome da skill (ex.: revisar-pr)"
            case .workflow: "Nome do workflow (ex.: Revisão até aprovar)"
            }
        }
    }

    private var selectionKey: String { "selection.\(model.project.id.uuidString)" }
    private var tabsKey: String { "tabs.\(model.project.id.uuidString)" }
    private var activeTabKey: String { "activeTab.\(model.project.id.uuidString)" }
    private var expandedKey: String { "expanded.\(model.project.id.uuidString)" }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
                .toolbar {
                    ToolbarItem(placement: .automatic) {
                        Text(model.project.name)
                            .font(.headline)
                            .lineLimit(1)
                            .help(model.project.description ?? model.project.name)
                    }
                    // Plain title, not a glass capsule like the toolbar buttons.
                    .sharedBackgroundVisibility(.hidden)
                    ToolbarSpacer(.flexible)
                }
        } detail: {
            detail
        }
        .onChange(of: claude.requestedPage) { _, page in
            switch page {
            case .chat: openInNewTab(.claude)
            case .terminal(let id): openInNewTab(.terminal(id))
            case nil: return
            }
            claude.requestedPage = nil
        }
        .environment(model)
        .environment(claude)
        .focusedSceneValue(\.claudeSession, claude)
        .focusedSceneValue(\.closeActiveTab, tabs.count > 1 ? { closeTab(activeTab) } : nil)
        .task {
            model.startWatching()
            restoreState()
        }
        .onChange(of: selection) { _, new in
            // Clicking empty sidebar space clears the selection; keep showing the active tab instead.
            guard let new else { selection = tabs[activeTab]; return }
            // A terminal tab is never replaced (that would end its shell): the item opens beside it.
            if tabs[activeTab].isTerminal, new != tabs[activeTab] {
                openInNewTab(new)
                return
            }
            tabs[activeTab] = new
            if let section = new.section { expanded.insert(section) }
            if !new.isTerminal { UserDefaults.standard.set(new.storageKey, forKey: selectionKey) }
        }
        .onChange(of: tabs) { old, new in
            // Closing a terminal's tab ends its shell.
            for case .terminal(let id) in Set(old).subtracting(new) { claude.closeTerminal(id) }
            // Shells don't survive a relaunch, so terminal tabs aren't saved.
            UserDefaults.standard.set(new.filter { !$0.isTerminal }.map(\.storageKey), forKey: tabsKey)
        }
        .onChange(of: activeTab) { _, new in
            UserDefaults.standard.set(new, forKey: activeTabKey)
        }
        .onChange(of: expanded) { _, new in
            UserDefaults.standard.set(new.map(\.rawValue), forKey: expandedKey)
        }
        .onChange(of: tabs.map(exists)) { pruneTabs() }
        .onDisappear {
            model.stopWatching()
            claude.stop()
            claude.terminals.keys.forEach(claude.closeTerminal)
        }
        .sheet(item: $newName) { prompt in
            NamePromptSheet(title: prompt.title, placeholder: prompt.placeholder) { name in
                switch prompt {
                case .doc: if let slug = model.createDoc(title: name) { selection = .doc(slug) }
                case .group: if let slug = model.createGroup(title: name) { selection = .group(slug) }
                case .topic: if let slug = model.createTopic(title: name) { selection = .topic(slug) }
                case .idea: if let slug = model.createIdea(title: name) { selection = .idea(slug) }
                case .agent: if let slug = model.createAgent(title: name) { selection = .agent(slug) }
                case .command: if let slug = model.createCommand(title: name) { selection = .command(slug) }
                case .skill: if let slug = model.createSkill(title: name) { selection = .skill(slug) }
                case .workflow: if let slug = model.createWorkflow(title: name) { selection = .workflow(slug) }
                }
            }
        }
        .alert("Erro", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    private var sidebar: some View {
        // The list must stay the column's root scroll view: wrapped in a VStack, AppKit applies the
        // title-bar inset only after the first layout, so the top rows open hidden under the title.
        // A safe-area bar insets the list's content, so the last rows still scroll clear of the footer.
        // With the toolbar background hidden, the soft edge effect lets rows show through the
        // traffic lights and title; a hard edge gives the title area an opaque backing instead.
        sidebarList
            .scrollEdgeEffectStyle(.hard, for: .top)
            .safeAreaBar(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    Divider()
                    sidebarFooter
                }
            }
    }

    private var sidebarList: some View {
        List(selection: $selection) {
            Section {
                Label("Stack", systemImage: "square.stack.3d.up")
                    .badge(model.project.stack.count)
                    .tag(SidebarItem.stack)
                    .contextMenu { openInNewTabButton(.stack) }
                Label("Padrões", systemImage: "building.columns")
                    .badge(model.project.patterns.count)
                    .tag(SidebarItem.patterns)
                    .contextMenu { openInNewTabButton(.patterns) }
                Label("Links", systemImage: "link")
                    .badge(model.project.links.count)
                    .tag(SidebarItem.links)
                    .contextMenu { openInNewTabButton(.links) }
                Label("Grafo", systemImage: "point.3.connected.trianglepath.dotted")
                    .tag(SidebarItem.graph)
                    .contextMenu { openInNewTabButton(.graph) }
                if !AIProvider.installed.isEmpty {
                    Label("IA", systemImage: "sparkles")
                        .tag(SidebarItem.claude)
                        .contextMenu { openInNewTabButton(.claude) }
                }
                // An action, not a page: every click opens a new shell in its own tab.
                Label("Terminal", systemImage: "terminal")
                    .badge(claude.terminals.count)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { claude.openTerminal() }
                    .help("Abrir um terminal novo em outra aba (⌃`)")
            }

            ForEach(SidebarSection.allCases, id: \.self) { section in
                Section {
                    SectionSidebarRow(section: section, count: model.count(section), expanded: expanded.contains(section)) {
                        newName = NewNamePrompt(section)
                    } onToggle: {
                        if expanded.contains(section) { expanded.remove(section) } else { expanded.insert(section) }
                    }
                    .tag(SidebarItem.section(section))
                    .contextMenu { openInNewTabButton(.section(section)) }

                    if expanded.contains(section) {
                        children(of: section)
                            .padding(.leading, 12)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
        }
        .animation(.snappy(duration: 0.25), value: expanded)
        .listStyle(.sidebar)
        // Hard edge under the title so scrolled rows don't blend into it.
        .scrollEdgeEffectStyle(.hard, for: .top)
    }

    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !AIProvider.installed.isEmpty { AIUsageView() }
            HStack {
                Image(systemName: "folder")
                Text(model.store.root.path(percentEncoded: false))
                    .lineLimit(1).truncationMode(.head)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .onTapGesture { NSWorkspace.shared.activateFileViewerSelecting([model.store.manifestURL]) }
            .help("Mostrar vibedeck.json no Finder")
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func openInNewTabButton(_ item: SidebarItem) -> some View {
        Button("Abrir em Nova Aba") { openInNewTab(item) }
    }

    @ViewBuilder
    private func children(of section: SidebarSection) -> some View {
        switch section {
        case .docs:
            ForEach(model.docs) { doc in
                Label(doc.title, systemImage: "doc.text")
                    .help(doc.title)
                    .tag(SidebarItem.doc(doc.slug))
                    .contextMenu {
                        openInNewTabButton(.doc(doc.slug))
                        Divider()
                        Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.store.docURL(doc.slug)]) }
                        Button("Mover para o Lixo", role: .destructive) {
                            if selection == .doc(doc.slug) { selection = .section(.docs) }
                            model.deleteDoc(doc.slug)
                        }
                    }
            }
        case .groups:
            ForEach(model.groups) { entry in
                Label(entry.group.title, systemImage: "checklist")
                    .help(entry.group.title)
                    .badge(entry.group.openCount)
                    .tag(SidebarItem.group(entry.slug))
                    .contextMenu {
                        openInNewTabButton(.group(entry.slug))
                        Divider()
                        Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.store.groupURL(entry.slug)]) }
                        Button("Mover para o Lixo", role: .destructive) {
                            if selection == .group(entry.slug) { selection = .section(.groups) }
                            model.deleteGroup(entry.slug)
                        }
                    }
            }
        case .topics:
            ForEach(model.topics) { entry in
                Label(entry.value.title, systemImage: entry.value.isGlobal ? "checkmark.shield" : "scope")
                    .badge(entry.value.rules.count)
                    .tag(SidebarItem.topic(entry.slug))
                    .help(entry.value.isGlobal ? "\(entry.value.title) — vale para toda tarefa" : "\(entry.value.title) — \(entry.value.paths.joined(separator: ", "))")
                    .contextMenu {
                        openInNewTabButton(.topic(entry.slug))
                        Divider()
                        Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.store.topicURL(entry.slug)]) }
                        Button("Mover para o Lixo", role: .destructive) {
                            if selection == .topic(entry.slug) { selection = .section(.topics) }
                            model.deleteTopic(entry.slug)
                        }
                    }
            }
        case .ideas:
            ForEach(model.ideas) { entry in
                Label(entry.value.title, systemImage: entry.value.status.symbol)
                    .foregroundStyle(entry.value.status.isClosed ? .secondary : .primary)
                    .tag(SidebarItem.idea(entry.slug))
                    .help("\(entry.value.title) — \(entry.value.status.label)")
                    .contextMenu {
                        openInNewTabButton(.idea(entry.slug))
                        Divider()
                        Menu("Status") {
                            ForEach(IdeaStatus.allCases, id: \.self) { status in
                                Button(status.label) { model.mutateIdea(entry.slug, "Alterar status", undo: undo) { $0.status = status } }
                            }
                        }
                        if !AIProvider.installed.isEmpty {
                            Button("Perguntar à IA sobre esta ideia") {
                                claude.ask("Leia a ideia \"\(entry.value.title)\" (get_idea com \"\(entry.slug)\") e me ajude a refiná-la: aponte lacunas, riscos e regras que ela deveria ter. Se precisar de decisões minhas, me pergunte.")
                            }
                        }
                        Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.store.ideaURL(entry.slug)]) }
                        Button("Mover para o Lixo", role: .destructive) {
                            if selection == .idea(entry.slug) { selection = .section(.ideas) }
                            model.deleteIdea(entry.slug)
                        }
                    }
            }
        case .agents:
            ForEach(model.agents) { entry in
                Label(entry.value.title, systemImage: "person.crop.rectangle")
                    .tag(SidebarItem.agent(entry.slug))
                    .help("\(entry.value.title) — \(entry.value.model ?? "modelo herdado")")
                    .contextMenu {
                        openInNewTabButton(.agent(entry.slug))
                        Divider()
                        Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.store.agentURL(entry.slug)]) }
                        Button("Mover para o Lixo", role: .destructive) {
                            if selection == .agent(entry.slug) { selection = .section(.agents) }
                            model.deleteAgent(entry.slug)
                        }
                    }
            }
        case .commands:
            ForEach(model.commands) { entry in
                Label(entry.value.title, systemImage: "command")
                    .tag(SidebarItem.command(entry.slug))
                    .help("\(entry.value.title)\(entry.value.argumentHint.map { " \($0)" } ?? "") — \(entry.value.model ?? "modelo herdado")")
                    .contextMenu {
                        openInNewTabButton(.command(entry.slug))
                        Divider()
                        Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.store.commandURL(entry.slug)]) }
                        Button("Mover para o Lixo", role: .destructive) {
                            if selection == .command(entry.slug) { selection = .section(.commands) }
                            model.deleteCommand(entry.slug)
                        }
                    }
            }
        case .skills:
            ForEach(model.skills) { entry in
                Label(entry.value.title, systemImage: "wand.and.stars")
                    .tag(SidebarItem.skill(entry.slug))
                    .help("\(entry.value.title)\(entry.value.summary.map { " — \($0)" } ?? "")")
                    .contextMenu {
                        openInNewTabButton(.skill(entry.slug))
                        Divider()
                        Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.store.skillURL(entry.slug)]) }
                        Button("Mover para o Lixo", role: .destructive) {
                            if selection == .skill(entry.slug) { selection = .section(.skills) }
                            model.deleteSkill(entry.slug)
                        }
                    }
            }
        case .workflows:
            ForEach(model.workflows) { entry in
                Label(entry.value.title, systemImage: "point.3.connected.trianglepath.dotted")
                    .tag(SidebarItem.workflow(entry.slug))
                    .help("\(entry.value.title) — \(entry.value.steps.count) etapa(s)\(entry.value.summary.map { " — \($0)" } ?? "")")
                    .contextMenu {
                        openInNewTabButton(.workflow(entry.slug))
                        Divider()
                        Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.store.workflowURL(entry.slug)]) }
                        Button("Mover para o Lixo", role: .destructive) {
                            if selection == .workflow(entry.slug) { selection = .section(.workflows) }
                            model.deleteWorkflow(entry.slug)
                        }
                    }
            }
        }
    }

    private var detail: some View {
        // Stacked, not a top safe-area inset: pages with an `.inspector` are rehosted in their own
        // AppKit split view, which drops that inset and lays their header out under the tab bar.
        VStack(spacing: 0) {
            if tabs.count > 1 {
                TabBar(tabs: tabs, active: activeTab, onSelect: activateTab, onClose: closeTab)
            }
            detailContent
                .transition(.opacity)
                .id(selection)
                .animation(.easeInOut(duration: 0.18), value: selection)
        }
        // No separate toolbar strip: the title area takes the same tone as the sidebars.
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    }

    // MARK: Tabs

    private func restoreState() {
        let defaults = UserDefaults.standard
        let saved = (defaults.stringArray(forKey: tabsKey) ?? []).compactMap(SidebarItem.init(storageKey:)).filter(exists)
        if saved.isEmpty {
            tabs = [SidebarItem(storageKey: defaults.string(forKey: selectionKey)).flatMap { exists($0) ? $0 : nil } ?? .links]
            activeTab = 0
        } else {
            tabs = saved
            activeTab = min(max(defaults.integer(forKey: activeTabKey), 0), saved.count - 1)
        }
        expanded = Set((defaults.stringArray(forKey: expandedKey) ?? []).compactMap(SidebarSection.init(rawValue:)))
        // The stack is the first thing someone opening the project sees.
        if !model.project.stack.isEmpty {
            if let i = tabs.firstIndex(of: .stack) { activeTab = i } else { tabs.insert(.stack, at: 0); activeTab = 0 }
        }
        selection = tabs[activeTab]
    }

    private func openInNewTab(_ item: SidebarItem) {
        if let existing = tabs.firstIndex(of: item) {
            activateTab(existing)
            return
        }
        tabs.insert(item, at: activeTab + 1)
        activateTab(activeTab + 1)
    }

    private func activateTab(_ index: Int) {
        activeTab = index
        selection = tabs[index]
    }

    private func closeTab(_ index: Int) {
        guard tabs.count > 1 else { return }
        tabs.remove(at: index)
        if index < activeTab || activeTab == tabs.count { activeTab -= 1 }
        selection = tabs[activeTab]
    }

    /// Whether `item` can still be shown: a terminal while its shell runs, anything else per the model.
    private func exists(_ item: SidebarItem) -> Bool {
        if case .terminal(let id) = item { return claude.terminals[id] != nil }
        return model.exists(item)
    }

    /// Closes tabs whose item was deleted (from the app or on disk) or whose shell exited.
    private func pruneTabs() {
        let current = tabs[activeTab]
        let kept = tabs.filter(exists)
        guard kept.count != tabs.count else { return }
        if kept.isEmpty {
            tabs = [current.section.map(SidebarItem.section) ?? .links]
            activeTab = 0
        } else {
            tabs = kept
            activeTab = kept.firstIndex(of: current) ?? min(activeTab, kept.count - 1)
        }
        selection = tabs[activeTab]
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selection {
        case .stack:
            StackView()
        case .patterns:
            PatternsView { selection = $0 }
        case .links, .none:
            LinksView()
        case .graph:
            GraphView()
        case .claude:
            ClaudeChatPage()
        case .terminal(let id):
            TerminalPage(id: id)
        case .section(let section):
            SectionListView(section: section) { selection = $0 } onOpenInNewTab: { openInNewTab($0) } onAdd: { newName = NewNamePrompt(section) }
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
                IdeaView(slug: slug) { selection = .topic($0) }
            } else {
                ContentUnavailableView("Ideia não encontrada", systemImage: "questionmark.folder")
            }
        case .agent(let slug):
            if model.agent(slug) != nil {
                AgentView(slug: slug) { selection = $0 }
            } else {
                ContentUnavailableView("Agente não encontrado", systemImage: "questionmark.folder")
            }
        case .command(let slug):
            if model.command(slug) != nil {
                CommandView(slug: slug) { selection = $0 }
            } else {
                ContentUnavailableView("Comando não encontrado", systemImage: "questionmark.folder")
            }
        case .skill(let slug):
            if model.skill(slug) != nil {
                SkillView(slug: slug) { selection = $0 }
            } else {
                ContentUnavailableView("Skill não encontrada", systemImage: "questionmark.folder")
            }
        case .workflow(let slug):
            if model.workflow(slug) != nil {
                WorkflowView(slug: slug) { selection = $0 }
            } else {
                ContentUnavailableView("Workflow não encontrado", systemImage: "questionmark.folder")
            }
        }
    }
}

/// A sidebar section shown as a selectable page row, with a create button and an accordion chevron.
private struct SectionSidebarRow: View {
    let section: SidebarSection
    let count: Int
    let expanded: Bool
    let onAdd: () -> Void
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Label(section.title, systemImage: section.symbol)
            Spacer()
            if !expanded, count > 0 {
                Text("\(count)").foregroundStyle(.secondary).monospacedDigit()
            }
            Button(action: onAdd) { Image(systemName: "plus") }
                .buttonStyle(.borderless)
                .help("Adicionar")
            // A button, so clicking it toggles the accordion without selecting the row (no page change).
            Button(action: onToggle) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help(expanded ? "Recolher" : "Expandir")
        }
    }
}

struct NamePromptSheet: View {
    let title: String
    let placeholder: String
    let onSubmit: (String) -> Void
    @State private var name = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.headline)
            TextField(placeholder, text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)
            HStack {
                Spacer()
                Button("Cancelar", role: .cancel) { dismiss() }.buttonStyle(.glass)
                Button("Criar", action: submit)
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 380)
    }

    private func submit() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onSubmit(trimmed)
        dismiss()
    }
}
