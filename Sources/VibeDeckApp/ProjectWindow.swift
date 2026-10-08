import SwiftUI
import VibeDeckCore

struct ProjectWindow: View {
    @State private var model: ProjectModel
    @State private var claude: ClaudeSession
    @State private var selection: SidebarItem?
    /// Open tabs; `selection` always mirrors `tabs[activeTab]`.
    @State private var tabs: [SidebarItem] = [.links]
    @State private var activeTab = 0
    /// Sidebar sections whose children are shown. Toggled by the chevron, independent of selection.
    @State private var expanded = Set<SidebarSection>()
    @State private var newName: NewNamePrompt?
    /// Follows `claude.isPanelVisible`, but only after the window has been widened to fit the panel.
    @State private var window = WeakWindow()

    init(root: URL) {
        let model = ProjectModel(store: ProjectStore(root: root))
        _model = State(initialValue: model)
        _claude = State(initialValue: ClaudeSession(root: root, projectId: model.project.id))
    }

    enum NewNamePrompt: Identifiable {
        case doc, group, topic, idea, agent
        var id: Self { self }

        init(_ section: SidebarSection) {
            switch section {
            case .docs: self = .doc
            case .groups: self = .group
            case .topics: self = .topic
            case .ideas: self = .idea
            case .agents: self = .agent
            }
        }

        var title: String {
            switch self {
            case .doc: "Novo documento"
            case .group: "Novo grupo de revisão"
            case .topic: "Novo tópico de regras"
            case .idea: "Nova ideia"
            case .agent: "Novo agente"
            }
        }

        var placeholder: String {
            switch self {
            case .doc: "Título do documento"
            case .group: "Tema (ex.: Tela de login)"
            case .topic: "Tópico (ex.: Interface, API, Acessibilidade)"
            case .idea: "Ideia (ex.: Modo offline)"
            case .agent: "Nome do agente (ex.: Revisor de código)"
            }
        }
    }

    private var selectionKey: String { "selection.\(model.project.id.uuidString)" }
    private var tabsKey: String { "tabs.\(model.project.id.uuidString)" }
    private var activeTabKey: String { "activeTab.\(model.project.id.uuidString)" }
    private var expandedKey: String { "expanded.\(model.project.id.uuidString)" }

    var body: some View {
        // The Claude panel is a plain trailing column, not an `.inspector`: Ideas, Rules, Reviews and
        // Agents each host their own inspector, and nesting two in one split view crashes/hangs AppKit.
        HStack(spacing: 0) {
            splitView
            if claude.isPanelVisible {
                Divider()
                ClaudePanel()
                    .frame(width: 340)
            }
        }
        .environment(model)
        .environment(claude)
    }

    private var splitView: some View {
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
        .toolbar {
            if ClaudeCode.isInstalled {
                ToolbarItem(placement: .primaryAction) {
                    Button { claude.isPanelVisible.toggle() } label: { Label("Claude", systemImage: "sparkles") }
                        .help(claude.isPanelVisible ? "Ocultar o Claude (⇧⌘C)" : "Conversar com o Claude Code (⇧⌘C)")
                }
            }
        }
        .background(WindowReader { window.value = $0; makeRoomForPanel() })
        .onChange(of: claude.isPanelVisible, initial: true) { _, visible in
            // Widen first: opening the inspector in a window narrower than all columns' minimums
            // leaves AppKit's split view unsolvable (hangs, columns overlapping, panel off-window).
            if visible { makeRoomForPanel() }
        }
        .environment(model)
        .environment(claude)
        .focusedSceneValue(\.claudeSession, ClaudeCode.isInstalled ? claude : nil)
        .task {
            model.startWatching()
            restoreState()
        }
        .onChange(of: selection) { _, new in
            // Clicking empty sidebar space clears the selection; keep showing the active tab instead.
            guard let new else { selection = tabs[activeTab]; return }
            tabs[activeTab] = new
            if let section = new.section { expanded.insert(section) }
            UserDefaults.standard.set(new.storageKey, forKey: selectionKey)
        }
        .onChange(of: tabs) { _, new in
            UserDefaults.standard.set(new.map(\.storageKey), forKey: tabsKey)
        }
        .onChange(of: activeTab) { _, new in
            UserDefaults.standard.set(new, forKey: activeTabKey)
        }
        .onChange(of: expanded) { _, new in
            UserDefaults.standard.set(new.map(\.rawValue), forKey: expandedKey)
        }
        .onChange(of: tabs.map(model.exists)) { pruneTabs() }
        .onDisappear {
            model.stopWatching()
            claude.stop()
            claude.terminal.terminate()
        }
        .sheet(item: $newName) { prompt in
            NamePromptSheet(title: prompt.title, placeholder: prompt.placeholder) { name in
                switch prompt {
                case .doc: if let slug = model.createDoc(title: name) { selection = .doc(slug) }
                case .group: if let slug = model.createGroup(title: name) { selection = .group(slug) }
                case .topic: if let slug = model.createTopic(title: name) { selection = .topic(slug) }
                case .idea: if let slug = model.createIdea(title: name) { selection = .idea(slug) }
                case .agent: if let slug = model.createAgent(title: name) { selection = .agent(slug) }
                }
            }
        }
        .alert("Erro", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    private var sidebar: some View {
        // The footer sits below the list (not in a safe-area inset) so rows never scroll under it.
        VStack(spacing: 0) {
            sidebarList
            Divider()
            sidebarFooter
        }
    }

    private var sidebarList: some View {
        List(selection: $selection) {
            Section {
                Label("Links", systemImage: "link")
                    .badge(model.project.links.count)
                    .tag(SidebarItem.links)
                    .contextMenu { openInNewTabButton(.links) }
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
            if ClaudeCode.isInstalled { ClaudeUsageView() }
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
                                Button(status.label) { model.mutateIdea(entry.slug, "Alterar status", undo: nil) { $0.status = status } }
                            }
                        }
                        if ClaudeCode.isInstalled {
                            Button("Perguntar ao Claude sobre esta ideia") {
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
        }
    }

    private var detail: some View {
        detailContent
            .transition(.opacity)
            .id(selection)
            .animation(.easeInOut(duration: 0.18), value: selection)
            .safeAreaInset(edge: .top, spacing: 0) {
                if tabs.count > 1 {
                    TabBar(tabs: tabs, active: activeTab, onSelect: activateTab, onClose: closeTab)
                }
            }
            // No separate toolbar strip: the title area takes the same tone as the sidebars.
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    }

    // MARK: Window

    /// Window width that fits sidebar, a usable detail column and the Claude panel.
    private static let widthWithPanel: CGFloat = 1080

    private func makeRoomForPanel() {
        guard claude.isPanelVisible, let window = window.value, !window.styleMask.contains(.fullScreen),
              let screen = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
        let width = min(Self.widthWithPanel, screen.width)
        guard window.frame.width < width else { return }
        var frame = window.frame
        frame.size.width = width
        // Grow to the right, sliding left when that would leave the screen.
        frame.origin.x = max(min(frame.origin.x, screen.maxX - width), screen.minX)
        window.setFrame(frame, display: true)
    }

    // MARK: Tabs

    private func restoreState() {
        let defaults = UserDefaults.standard
        let saved = (defaults.stringArray(forKey: tabsKey) ?? []).compactMap(SidebarItem.init(storageKey:)).filter(model.exists)
        if saved.isEmpty {
            tabs = [SidebarItem(storageKey: defaults.string(forKey: selectionKey)) ?? .links]
            activeTab = 0
        } else {
            tabs = saved
            activeTab = min(max(defaults.integer(forKey: activeTabKey), 0), saved.count - 1)
        }
        expanded = Set((defaults.stringArray(forKey: expandedKey) ?? []).compactMap(SidebarSection.init(rawValue:)))
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

    /// Closes tabs whose item was deleted (from the app or on disk).
    private func pruneTabs() {
        let current = tabs[activeTab]
        let kept = tabs.filter(model.exists)
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
        case .links, .none:
            LinksView()
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
                AgentView(slug: slug) { selection = .agent($0) }
            } else {
                ContentUnavailableView("Agente não encontrado", systemImage: "questionmark.folder")
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

final class WeakWindow {
    weak var value: NSWindow?
}

/// Hands over the hosting `NSWindow` once the view is in one.
private struct WindowReader: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView { ReaderView(onWindow: onWindow) }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ReaderView: NSView {
        let onWindow: (NSWindow) -> Void
        init(onWindow: @escaping (NSWindow) -> Void) {
            self.onWindow = onWindow
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError() }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { DispatchQueue.main.async { self.onWindow(window) } }
        }
    }
}
