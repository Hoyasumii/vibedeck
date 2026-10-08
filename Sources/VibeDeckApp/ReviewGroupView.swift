import SwiftUI
import VibeDeckCore

struct ReviewGroupView: View {
    let slug: String
    @Environment(ProjectModel.self) private var model
    @Environment(\.undoManager) private var undo
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
                        item: item, kinds: model.project.reviewKinds, topics: model.topics,
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
        .onChange(of: selection) { _, new in if new != nil { showInspector = true } }
        .navigationTitle(group.title)
        .navigationSubtitle("\(group.openCount) aberto(s) · \(group.items.count) no total")
        .toolbar {
            ToolbarItem {
                Button { showInspector.toggle() } label: { Label("Inspetor", systemImage: "sidebar.right") }
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
            statusPicker
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            CommitTextField("Tema", value: group.title) { title in
                guard !title.isEmpty else { return }
                model.mutateGroup(slug, "Renomear grupo", undo: undo) { $0.title = title }
            }
            .font(.title2.weight(.semibold))
            .textFieldStyle(.plain)
            CommitTextField("Adicionar descrição…", value: group.description ?? "") { text in
                model.mutateGroup(slug, "Editar descrição", undo: undo) { $0.description = text.isEmpty ? nil : text }
            }
            .textFieldStyle(.plain)
            .foregroundStyle(.secondary)
            TagsField(tags: group.tags) { tags in model.mutateGroup(slug, "Editar tags", undo: undo) { $0.tags = tags } }
                .padding(.top, 6)
        }
        .frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)
    }

    private var statusPicker: some View {
        Picker("Status", selection: $statusFilter) {
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
            List(selection: $selection) {
                ForEach(items) { item in
                    ReviewItemRow(item: item, kind: model.project.kind(item.kind)) { status in
                        model.mutateItem(slug, item.id, "Alterar status", undo: undo) { $0.status = status }
                    }
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
                Button(status.label) { model.mutateItem(slug, item.id, "Alterar status", undo: undo) { $0.status = status } }
            }
        }
        Menu("Tipo") {
            ForEach(model.project.reviewKinds) { kind in
                Button(kind.label) { model.mutateItem(slug, item.id, "Alterar tipo", undo: undo) { $0.kind = kind.id } }
            }
        }
        Menu("Mover para grupo") {
            ForEach(model.groups.filter { $0.slug != slug }) { entry in
                Button(entry.group.title) { moveItem(item, to: entry.slug) }
            }
        }
        Button("Copiar id") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.id.uuidString, forType: .string)
        }
        Divider()
        Button("Remover", role: .destructive) { delete(item.id) }
    }

    private var quickAdd: some View {
        HStack(spacing: 10) {
            Menu {
                Picker("Tipo", selection: $newKind) {
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

            TextField("Novo ponto de revisão…", text: $newTitle)
                .textFieldStyle(.plain)
                .focused($quickAddFocused)
                .onSubmit(addItem)

            Button(action: addItem) { Image(systemName: "plus") }
                .buttonStyle(.glassProminent)
                .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
        .background {
            Button("") { quickAddFocused = true }.keyboardShortcut("n", modifiers: [.command, .shift]).hidden()
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
    let item: ReviewItem
    let kind: ReviewKind
    let setStatus: (ReviewStatus) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                setStatus(item.status.isClosed ? .open : .done)
            } label: {
                Image(systemName: item.status == .done ? "checkmark.circle.fill" : item.status == .wontfix ? "xmark.circle" : "circle")
                    .foregroundStyle(item.status == .done ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                    .font(.title3)
            }
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
    let label: String
    let symbol: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: symbol)
                .font(.callout)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 10).padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .glassEffect(isOn ? .regular.tint(.accentColor.opacity(0.45)).interactive() : .regular.interactive(), in: .capsule)
    }
}

// MARK: - Inspector

struct ReviewItemInspector: View {
    let item: ReviewItem
    let kinds: [ReviewKind]
    let topics: [ProjectModel.Entry<RuleTopic>]
    /// Topic slugs gating this item (explicit + global + matching target file).
    let required: [String]
    let problems: [String]
    let mutate: (String, @escaping (inout ReviewItem) -> Void) -> Void

    var body: some View {
        Form {
            Section("Item") {
                CommitTextField("Título", value: item.title) { v in
                    guard !v.isEmpty else { return }
                    mutate("Editar título") { $0.title = v }
                }
                CommitTextField("Detalhes", value: item.details ?? "", axis: .vertical) { v in
                    mutate("Editar detalhes") { $0.details = v.isEmpty ? nil : v }
                }
                .lineLimit(3...10)
                Picker("Tipo", selection: binding(\.kind, "Alterar tipo")) {
                    ForEach(kinds) { Label($0.label, systemImage: $0.symbol ?? "tag").tag($0.id) }
                    if !kinds.contains(where: { $0.id == item.kind }) { Text(item.kind).tag(item.kind) }
                }
                Picker("Status", selection: binding(\.status, "Alterar status")) {
                    ForEach(ReviewStatus.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Picker("Prioridade", selection: binding(\.priority, "Alterar prioridade")) {
                    ForEach(ReviewPriority.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            }
            Section("Onde") {
                targetField("Arquivo", \.file)
                targetField("Rota / tela", \.route)
                targetField("Componente", \.component)
                targetField("Seletor", \.selector)
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
                })) {
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
        CommitTextField(label, value: item.target?[keyPath: keyPath] ?? "") { v in
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
    let title: String
    let value: String
    var axis: Axis = .horizontal
    let commit: (String) -> Void
    @State private var draft = ""
    @FocusState private var focused: Bool

    init(_ title: String, value: String, axis: Axis = .horizontal, commit: @escaping (String) -> Void) {
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
            .onChange(of: focused) { _, isFocused in if !isFocused { submit() } }
    }

    private func submit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != value { commit(trimmed) }
    }
}
