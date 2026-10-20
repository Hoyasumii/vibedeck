import SwiftUI
import VibeDeckCore

struct ReviewGroupView: View {
    @Environment(\.logProject) private var providerRoot
    @Environment(\.logProject) private var logProject
    let slug: String
    @Environment(ProjectModel.self) private var model
    @Environment(\.undoManager) private var undo
    @Environment(AISession.self) private var session
    @State private var selection: ReviewItem.ID?
    @State private var kindFilter: String?
    @State private var statusFilter: StatusFilter = .open
    @State private var showInspector = true
    @State private var newKind = "fix"
    @State private var newTitle = ""
    @FocusState private var quickAddFocused: Bool

    enum StatusFilter: String, CaseIterable {
        case open = "Abertos", closed = "Concluídos", all = "Todos"
    }

    private var group: ReviewGroup { model.group(slug) ?? ReviewGroup(title: slug) }

    private var items: [ReviewItem] {
        group.items
            .filter { kindFilter == nil || $0.kind == kindFilter }
            .filter {
                switch statusFilter {
                case .open: !$0.status.isClosed
                case .closed: $0.status.isClosed
                case .all: true
                }
            }
    }

    private var selectedItem: ReviewItem? {
        selection.flatMap { id in group.items.first { $0.id == id } }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            filters
            list
        }
        .safeAreaInset(edge: .bottom) { quickAdd }
        .inspector(isPresented: $showInspector) {
            Group {
                if let item = selectedItem {
                    ReviewItemInspector(
                        item: item, kinds: model.project.reviewKinds, topics: model.topics, store: model.store,
                        required: model.requiredTopics(for: item), problems: model.verificationProblems(for: item)
                    ) { action, change in
                        model.mutateItem(slug, item.id, action, undo: undo, change)
                    }
                    .id(item.id)
                } else {
                    ContentUnavailableView("Nenhum item selecionado", systemImage: "sidebar.right",
                                           description: Text("Selecione um ponto de revisão para editar."))
                }
            }
            .inspectorColumnWidth(min: 260, ideal: 300, max: 420)
        }
        .onChange(of: selection) { _, new in
            if new != nil { showInspector = true }
            model.resolver.selectionChanged(to: new)
        }
        .sheet(isPresented: Binding(get: { model.resolver.isActive }, set: { if !$0 { model.resolver.dismiss() } })) {
            ReviewResolveSheet(runner: model.resolver)
        }
        .navigationTitle(group.title)
        .navigationSubtitle("\(group.openCount) aberto(s) · \(group.items.count) no total")
        .toolbar {
            ToolbarItem {
                LoggedButton { showInspector.toggle() } label: { Label("Inspetor", systemImage: "sidebar.right") }.loggedControl(control: "review_group_view.button_1", label: "Inspetor")
                    .keyboardShortcut("i", modifiers: [.command, .option])
            }
        }
        .onAppear {
            if !model.project.reviewKinds.contains(where: { $0.id == newKind }) {
                newKind = model.project.reviewKinds.first?.id ?? "note"
            }
        }
    }

    // MARK: Sections

    private var header: some View {
        // A single HStack (not ViewThatFits): see IdeaView.header.
        HStack(alignment: .top, spacing: 16) {
            titleBlock
            VStack(alignment: .trailing, spacing: 8) {
                statusPicker
                if canResolve { resolveGroupButton }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            CommitTextField(control: "reviewgroupview.field_1", "Tema", value: group.title) { title in
                guard !title.isEmpty else { return }
                model.mutateGroup(slug, "Renomear grupo", undo: undo) { $0.title = title }
            }
            .font(.title2.weight(.semibold))
            .textFieldStyle(.plain)
            CommitTextField(control: "reviewgroupview.field_2", "Adicionar descrição…", value: group.description ?? "") { text in
                model.mutateGroup(slug, "Editar descrição", undo: undo) { $0.description = text.isEmpty ? nil : text }
            }
            .textFieldStyle(.plain)
            .foregroundStyle(.secondary)
            TagsField(tags: group.tags) { tags in model.mutateGroup(slug, "Editar tags", undo: undo) { $0.tags = tags } }
                .padding(.top, 6)
        }
        .frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)
    }

    /// Same check as Descubra and Gerar documentos: at least one supported provider installed.
    private var canResolve: Bool { !AIProvider.installed(in: providerRoot).isEmpty }

    private var resolveGroupButton: some View {
        let count = ReviewResolve.eligible(group.items).count
        return LoggedButton { resolve(group.items) } label: {
            Label("Resolver grupo", systemImage: "wand.and.stars")
        }.loggedControl(control: "review_group_view.button_resolve_group", label: "Resolver grupo")
        .buttonStyle(.glass)
        .controlSize(.small)
        .disabled(count == 0 || model.resolver.isActive)
        .help("Pede à IA, um item por vez, para resolver os itens abertos e em andamento (pergunta, plano, aceite, execução e check)")
    }

    private func resolve(_ items: [ReviewItem], single: ReviewItem.ID? = nil) {
        model.resolver.start(group: slug, title: group.title, items: items, single: single,
                             model: model, provider: session.provider, undo: undo)
    }

    private var statusPicker: some View {
        Picker("Status", selection: $statusFilter.logging(control: "review_group_view.selection_14", label: "Status", project: logProject)) {
            ForEach(StatusFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 6) {
                    FilterChip(label: "Todos", symbol: "square.grid.2x2", isOn: kindFilter == nil) { kindFilter = nil }
                    ForEach(model.project.reviewKinds) { kind in
                        let count = group.items.filter { $0.kind == kind.id && !$0.status.isClosed }.count
                        FilterChip(label: count > 0 ? "\(kind.label) \(count)" : kind.label, symbol: kind.symbol ?? "tag", isOn: kindFilter == kind.id) {
                            kindFilter = kindFilter == kind.id ? nil : kind.id
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var list: some View {
        if items.isEmpty {
            ContentUnavailableView {
                Label(group.items.isEmpty ? "Nenhum item ainda" : "Nada neste filtro", systemImage: "checklist")
            } description: {
                Text("Ex.: \"Inativar o botão de exportar\", \"Esse card não precisa aparecer agora\".")
            }
            .frame(maxHeight: .infinity)
        } else {
            List(selection: $selection.logging(control: "review_group_view.selection_15", label: "Seleção", project: logProject)) {
                ForEach(items) { item in
                    ReviewItemRow(item: item, kind: model.project.kind(item.kind), canResolve: canResolve, setStatus: { status in
                        model.mutateItem(slug, item.id, "Alterar status", undo: undo) { $0.status = status }
                    }, resolve: { resolve([item], single: item.id) })
                    .tag(item.id)
                    .contextMenu { contextMenu(for: item) }
                }
                .onMove { from, to in move(from: from, to: to) }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .onDeleteCommand { if let id = selection { delete(id) } }
        }
    }

    @ViewBuilder
    private func contextMenu(for item: ReviewItem) -> some View {
        Menu("Status") {
            ForEach(ReviewStatus.allCases, id: \.self) { status in
                LoggedButton(status.label) { model.mutateItem(slug, item.id, "Alterar status", undo: undo) { $0.status = status } }.loggedControl(control: "review_group_view.button_2", label: "Ativar controle")
            }
        }
        Menu("Tipo") {
            ForEach(model.project.reviewKinds) { kind in
                LoggedButton(kind.label) { model.mutateItem(slug, item.id, "Alterar tipo", undo: undo) { $0.kind = kind.id } }.loggedControl(control: "review_group_view.button_3", label: "Ativar controle")
            }
        }
        Menu("Mover para grupo") {
            ForEach(model.groups.filter { $0.slug != slug }) { entry in
                LoggedButton(entry.group.title) { moveItem(item, to: entry.slug) }.loggedControl(control: "review_group_view.button_4", label: "Ativar controle")
            }
        }
        LoggedButton("Copiar id") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.id.uuidString, forType: .string)
        }.loggedControl(control: "review_group_view.button_5", label: "Copiar id")
        if canResolve, !item.status.isClosed {
            LoggedButton("Resolver…") { resolve([item], single: item.id) }.loggedControl(control: "review_group_view.button_resolve_menu", label: "Resolver")
                .disabled(model.resolver.isActive)
        }
        Divider()
        LoggedButton("Remover", role: .destructive) { delete(item.id) }.loggedControl(control: "review_group_view.button_6", label: "Remover")
    }

    private var quickAdd: some View {
        HStack(spacing: 10) {
            Menu {
                Picker("Tipo", selection: $newKind.logging(control: "review_group_view.selection_16", label: "Tipo", project: logProject)) {
                    ForEach(model.project.reviewKinds) { kind in
                        Label(kind.label, systemImage: kind.symbol ?? "tag").tag(kind.id)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label(model.project.kind(newKind).label, systemImage: model.project.kind(newKind).symbol ?? "tag")
            }
            .menuStyle(.button)
            .buttonStyle(.glass)
            .fixedSize()

            LoggedTextField("Novo ponto de revisão…", text: $newTitle, onCommit: addItem).loggedField(control: "reviewgroupview.text_1", label: "Novo ponto de revisão…")
                .textFieldStyle(.plain)
                .focused($quickAddFocused)


            LoggedButton(action: addItem) { Image(systemName: "plus") }.loggedControl(control: "review_group_view.button_7", label: "Ativar controle")
                .buttonStyle(.glassProminent)
                .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
        .background {
            LoggedButton("") { quickAddFocused = true }.loggedControl(control: "review_group_view.button_8", label: "").keyboardShortcut("n", modifiers: [.command, .shift]).hidden()
        }
    }

    // MARK: Actions

    private func addItem() {
        let title = newTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        let item = ReviewItem(kind: newKind, title: title)
        model.mutateGroup(slug, "Adicionar item", undo: undo) { $0.items.append(item) }
        newTitle = ""
        if statusFilter == .closed { statusFilter = .open }
        selection = item.id
    }

    private func delete(_ id: ReviewItem.ID) {
        model.mutateGroup(slug, "Remover item", undo: undo) { $0.items.removeAll { $0.id == id } }
        if selection == id { selection = nil }
    }

    private func move(from: IndexSet, to: Int) {
        // Indices refer to the filtered list; translate to the full array.
        let visible = items.map(\.id)
        model.mutateGroup(slug, "Reordenar", undo: undo) { group in
            var ordered = visible
            ordered.move(fromOffsets: from, toOffset: to)
            let positions = visible.compactMap { id in group.items.firstIndex { $0.id == id } }.sorted()
            let byID = Dictionary(uniqueKeysWithValues: group.items.map { ($0.id, $0) })
            for (pos, id) in zip(positions, ordered) { group.items[pos] = byID[id]! }
        }
    }

    private func moveItem(_ item: ReviewItem, to target: String) {
        undo?.beginUndoGrouping()
        model.mutateGroup(slug, "Mover item", undo: undo) { $0.items.removeAll { $0.id == item.id } }
        model.mutateGroup(target, "Mover item", undo: undo) { $0.items.append(item) }
        undo?.endUndoGrouping()
    }
}

// MARK: - Row

struct ReviewItemRow: View {
    @Environment(\.logProject) private var providerRoot
    @Environment(\.logProject) private var logProject
    let item: ReviewItem
    let kind: ReviewKind
    var canResolve = false
    let setStatus: (ReviewStatus) -> Void
    var resolve: () -> Void = {}

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            LoggedButton {
                setStatus(item.status.isClosed ? .open : .done)
            } label: {
                Image(systemName: item.status == .done ? "checkmark.circle.fill" : item.status == .wontfix ? "xmark.circle" : "circle")
                    .foregroundStyle(item.status == .done ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                    .font(.title3)
            }.loggedControl(control: "review_group_view.button_9", label: "Ativar controle")
            .buttonStyle(.plain)
            .help(item.status.isClosed ? "Reabrir" : "Marcar como feito")

            VStack(alignment: .leading, spacing: 5) {
                Text(item.title)
                    .font(.body.weight(.medium))
                    .strikethrough(item.status.isClosed)
                    .foregroundStyle(item.status.isClosed ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    Label(kind.label, systemImage: kind.symbol ?? "tag")
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .glassEffect(.regular.tint(KindPalette.color(kind.id).opacity(0.35)), in: .capsule)
                    if item.status == .inProgress {
                        Text("Em andamento").font(.caption).fixedSize()
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .glassEffect(.regular.tint(.blue.opacity(0.3)), in: .capsule)
                    }
                    if item.priority == .high {
                        Label("Alta", systemImage: "exclamationmark.2").font(.caption).foregroundStyle(.orange).fixedSize()
                    }
                    if let where_ = targetText {
                        Text(where_).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    if !item.rules.isEmpty {
                        Image(systemName: "checkmark.shield").font(.caption).foregroundStyle(.secondary).help("Ligado a regras: \(item.rules.joined(separator: ", "))")
                    }
                    if item.author == .ai {
                        Image(systemName: "sparkles").font(.caption).foregroundStyle(.purple).help("Criado por IA")
                    }
                }

                if let details = item.details, !details.isEmpty {
                    Text(details).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            if canResolve, !item.status.isClosed {
                LoggedButton(action: resolve) { Label("Resolver", systemImage: "wand.and.stars").font(.caption) }
                    .loggedControl(control: "review_group_view.button_resolve_item", label: "Resolver")
                    .buttonStyle(.borderless)
                    .help("Pede à IA para resolver este item: perguntas, plano, aceite, execução e check")
            }
        }
        .padding(.vertical, 6)
    }

    private var targetText: String? {
        guard let t = item.target else { return nil }
        let parts = [t.file, t.route, t.component, t.selector].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: "  ·  ")
    }
}

enum KindPalette {
    static func color(_ id: String) -> Color {
        switch id {
        case "disable": .gray
        case "hide": .indigo
        case "fix": .red
        case "change": .blue
        case "remove": .orange
        case "note": .yellow
        default: [.teal, .mint, .pink, .cyan, .brown][id.unicodeScalars.reduce(0) { $0 + Int($1.value) } % 5]
        }
    }
}

struct FilterChip: View {
    @Environment(\.logProject) private var providerRoot
    @Environment(\.logProject) private var logProject
    let label: String
    let symbol: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        LoggedButton(action: action) {
            Label(label, systemImage: symbol)
                .font(.callout)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 10).padding(.vertical, 5)
        }.loggedControl(control: "review_group_view.button_10", label: "Ativar controle")
        .buttonStyle(.plain)
        .glassEffect(isOn ? .regular.tint(.accentColor.opacity(0.45)).interactive() : .regular.interactive(), in: .capsule)
    }
}

// MARK: - Inspector

struct ReviewItemInspector: View {
    @Environment(\.logProject) private var providerRoot
    @Environment(\.logProject) private var logProject
    let item: ReviewItem
    let kinds: [ReviewKind]
    let topics: [ProjectModel.Entry<RuleTopic>]
    let store: ProjectStore
    /// Topic slugs gating this item (explicit + global + matching target file).
    let required: [String]
    let problems: [String]
    let mutate: (String, @escaping (inout ReviewItem) -> Void) -> Void
    @Environment(AISession.self) private var session
    @State private var discover = ReviewDiscoverRunner()

    var body: some View {
        Form {
            Section("Item") {
                CommitTextField(control: "reviewgroupview.field_3", "Título", value: item.title) { v in
                    guard !v.isEmpty else { return }
                    mutate("Editar título") { $0.title = v }
                }
                CommitTextField(control: "reviewgroupview.field_4", "Detalhes", value: item.details ?? "", axis: .vertical) { v in
                    mutate("Editar detalhes") { $0.details = v.isEmpty ? nil : v }
                }
                .lineLimit(3...10)
                Picker("Tipo", selection: binding(\.kind, "Alterar tipo").logging(control: "review_group_view.selection_17", label: "Tipo", project: logProject)) {
                    ForEach(kinds) { Label($0.label, systemImage: $0.symbol ?? "tag").tag($0.id) }
                    if !kinds.contains(where: { $0.id == item.kind }) { Text(item.kind).tag(item.kind) }
                }
                Picker("Status", selection: binding(\.status, "Alterar status").logging(control: "review_group_view.selection_18", label: "Status", project: logProject)) {
                    ForEach(ReviewStatus.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Picker("Prioridade", selection: binding(\.priority, "Alterar prioridade").logging(control: "review_group_view.selection_19", label: "Prioridade", project: logProject)) {
                    ForEach(ReviewPriority.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            }
            Section {
                discoverStatus
                targetField("Arquivo", \.file)
                targetField("Rota / tela", \.route)
                targetField("Componente", \.component)
                targetField("Seletor", \.selector)
            } header: {
                HStack {
                    Text("Onde")
                    Spacer()
                    if !AIProvider.installed(in: providerRoot).isEmpty { discoverButton }
                }
            }
            rulesSection
            Section {
                LabeledContent("Autor", value: item.author == .ai ? "IA" : "Humano")
                LabeledContent("Criado", value: item.createdAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Atualizado", value: item.updatedAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Id") {
                    Text(item.id.uuidString.prefix(8)).font(.caption.monospaced()).textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: Binding(get: { proposal != nil }, set: { if !$0 { discover.dismiss() } })) {
            if let proposal {
                ReviewDiscoverSheet(proposal: proposal) { fields, topics in
                    mutate("Descobrir onde e regras") { proposal.apply(fields: fields, topics: topics, to: &$0) }
                }
            }
        }
        .onChange(of: item.updatedAt) { discover.itemChanged() }
        .onDisappear { discover.cancel() }
    }

    // MARK: Descubra

    private var proposal: ReviewDiscoverProposal? {
        if case .ready(let proposal) = discover.state { proposal } else { nil }
    }

    private var discoverButton: some View {
        LoggedButton {
            let kind = kinds.first { $0.id == item.kind }?.label ?? item.kind
            discover.start(item: item, kind: kind, topics: topics.map { ($0.slug, $0.value) }, store: store, provider: session.provider)
        } label: {
            Label("Descubra", systemImage: "sparkles")
        }.loggedControl(control: "review_group_view.button_11", label: "Descubra")
        .buttonStyle(.borderless)
        .controlSize(.small)
        .disabled(discover.isRunning)
        .help("Pede ao Claude Code (só leitura) para sugerir onde o item se aplica e quais regras ele segue")
    }

    @ViewBuilder
    private var discoverStatus: some View {
        switch discover.state {
        case .running:
            HStack {
                ProgressView().controlSize(.small)
                Text("Procurando no código…").foregroundStyle(.secondary)
                Spacer()
                LoggedButton("Cancelar") { discover.cancel() }.loggedControl(control: "review_group_view.button_12", label: "Cancelar")
            }
        case .failed(let message):
            HStack(alignment: .top) {
                Label(message, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
                Spacer()
                LoggedButton("OK") { discover.dismiss() }.loggedControl(control: "review_group_view.button_13", label: "OK").buttonStyle(.borderless)
            }
        case .idle, .ready:
            EmptyView()
        }
    }

    @ViewBuilder
    private var rulesSection: some View {
        Section {
            if topics.isEmpty {
                Text("Nenhum tópico de regras no projeto.").foregroundStyle(.secondary)
            }
            ForEach(topics) { topic in
                let explicit = item.rules.contains(topic.slug)
                let automatic = !explicit && required.contains(topic.slug)
                Toggle(isOn: Binding(get: { explicit || automatic }, set: { on in
                    mutate(on ? "Ligar regras" : "Desligar regras") { item in
                        if on { item.rules.append(topic.slug) } else { item.rules.removeAll { $0 == topic.slug } }
                    }
                }).logging(control: "review_group_view.selection_20", label: "Alternar", project: logProject)) {
                    Text(topic.value.title)
                    if automatic {
                        Text(topic.value.isGlobal ? "Vale para toda tarefa" : "Casa com o arquivo do item").font(.caption)
                    }
                }
                .disabled(automatic)
            }
            if !required.isEmpty {
                if problems.isEmpty {
                    Label("Regras verificadas", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                } else {
                    ForEach(problems, id: \.self) { problem in
                        Label(problem, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
                    }
                }
            }
        } header: {
            Text("Regras")
        } footer: {
            if !required.isEmpty {
                Text("Agentes só podem concluir este item depois de um check aprovado.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func binding<V: Equatable>(_ keyPath: WritableKeyPath<ReviewItem, V>, _ action: String) -> Binding<V> {
        Binding(get: { item[keyPath: keyPath] }, set: { v in mutate(action) { $0[keyPath: keyPath] = v } })
    }

    private func targetField(_ label: String, _ keyPath: WritableKeyPath<ReviewTarget, String?>) -> some View {
        CommitTextField(control: "reviewgroupview.field_5", label, value: item.target?[keyPath: keyPath] ?? "") { v in
            mutate("Editar alvo") { item in
                var target = item.target ?? ReviewTarget()
                target[keyPath: keyPath] = v.isEmpty ? nil : v
                item.target = target.isEmpty ? nil : target
            }
        }
    }
}

/// Text field that edits a local draft and commits on Return or when focus leaves,
/// so each edit becomes one undo step instead of one per keystroke.
struct CommitTextField: View {
    @Environment(\.logProject) private var providerRoot
    @Environment(\.logProject) private var logProject
    let control: String
    let title: String
    let value: String
    var axis: Axis = .horizontal
    let commit: (String) -> Void
    @State private var draft = ""
    @State private var confirmedDraft: String?
    @FocusState private var focused: Bool

    init(control: String, _ title: String, value: String, axis: Axis = .horizontal, commit: @escaping (String) -> Void) {
        self.control = control
        self.title = title
        self.value = value
        self.axis = axis
        self.commit = commit
    }

    var body: some View {
        TextField(title, text: $draft, axis: axis)
            .focused($focused)
            .onAppear { draft = value }
            .onChange(of: value) { _, new in if !focused { draft = new } }
            .onSubmit(submit)
            .onChange(of: draft) { _, _ in confirmedDraft = nil }
            .onChange(of: focused) { _, isFocused in if !isFocused { submit() } }
    }

    private func submit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != value, trimmed != confirmedDraft else { return }
        confirmedDraft = trimmed
        VDLog.withAction(control: control, label: title, project: logProject) { commit(trimmed) }
    }
}
