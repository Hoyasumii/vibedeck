import SwiftUI

/// Coluna de conteúdo de um espaço: título, seletor de conceito, filtro no topo (texto e #tag, chips de tag)
/// e a lista do conceito. Os itens abrem no detalhe.
struct V2ContentColumn: View {
    let space: V2Space
    @Binding var concept: V2Concept
    @Binding var selection: SidebarItem?
    @Binding var filter: V2ListFilter
    let focusRequest: Int
    let onAdd: (SidebarSection) -> Void

    @Environment(ProjectModel.self) private var model
    @Environment(\.undoManager) private var undo
    @State private var editingTags: SectionRow?
    @FocusState private var filterFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            conceptPicker
            filterField
            tagBar
            Divider()
            list
        }
        .onChange(of: concept) { _, _ in filter.reset() }
        .onChange(of: focusRequest) { _, _ in filterFocused = true }
        .sheet(item: $editingTags) { row in
            TagsEditor(title: row.title, tags: row.tags) { model.setTags($0, for: row.id, undo: undo) }
        }
    }

    // MARK: Cabeçalho

    private var header: some View {
        HStack(spacing: DesignTokens.Space.s2) {
            Text(space.title).font(DesignTokens.Typography.title)
            Spacer()
            if let section = concept.section {
                LoggedButton { selection = nil } label: { VDIcon(.all, size: 14) }
                    .loggedControl(control: "v2_content_column.table", label: "Ver tabela e ações da seção")
                    .buttonStyle(.borderless)
                    .help("Ver a tabela e as ações de \(concept.title)")
                    .accessibilityLabel("Ver tabela e ações de \(concept.title)")
                LoggedButton { onAdd(section) } label: { VDIcon(.plus, size: 14) }
                    .loggedControl(control: "v2_content_column.add", label: "Novo")
                    .buttonStyle(.borderless)
                    .help("Novo item em \(concept.title)")
                    .accessibilityLabel("Novo item em \(concept.title)")
                    .disabled(model.isReadOnly)
            }
        }
        .padding(.horizontal, DesignTokens.Space.s3)
        .padding(.top, DesignTokens.Space.s2)
        .padding(.bottom, DesignTokens.Space.s1)
    }

    @ViewBuilder
    private var conceptPicker: some View {
        if space.concepts.count > 1 {
            ScrollView(.horizontal) {
                HStack(spacing: DesignTokens.Space.s2) {
                    ForEach(space.concepts) { item in
                        VDFilterChip(title: item.title, icon: nil, tone: nil, count: count(item), isOn: chipBinding(item))
                    }
                }
                .padding(.horizontal, DesignTokens.Space.s3)
                .padding(.vertical, DesignTokens.Space.s1)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func chipBinding(_ item: V2Concept) -> Binding<Bool> {
        Binding(get: { concept == item }, set: { isOn in if isOn { concept = item } })
    }

    private func count(_ item: V2Concept) -> Int? {
        item.section.map { model.count($0) }
    }

    // MARK: Filtro

    private var filterField: some View {
        HStack(spacing: DesignTokens.Space.s2) {
            VDIcon(.search, size: 13).foregroundStyle(DesignTokens.Colors.inkMuted)
            LoggedTextField("Filtrar \(concept.title.lowercased()) (#tag)", text: $filter.search)
                .loggedField(control: "v2_content_column.filter", label: "Filtrar lista")
                .textFieldStyle(.plain)
                .focused($filterFocused)
                .accessibilityLabel("Filtrar por texto e tag")
            if !filter.search.isEmpty {
                LoggedButton { filter.search = "" } label: { VDIcon(.close, size: 11) }
                    .loggedControl(control: "v2_content_column.clear_filter", label: "Limpar filtro")
                    .buttonStyle(.plain)
                    .help("Limpar filtro")
                    .accessibilityLabel("Limpar filtro")
            }
        }
        .padding(.horizontal, DesignTokens.Space.s3)
        .frame(height: 32)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                .fill(DesignTokens.Colors.surface200)
        )
        .padding(.horizontal, DesignTokens.Space.s3)
        .padding(.vertical, DesignTokens.Space.s2)
    }

    private var allRows: [SectionRow] {
        concept.section.map { model.rows(for: $0) } ?? []
    }

    private var allTags: [String] {
        Array(Set(allRows.flatMap(\.tags))).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var isFiltering: Bool { filter.isActive }

    private var rows: [SectionRow] { allRows.filter { filter.matches($0) } }

    @ViewBuilder
    private var tagBar: some View {
        if !allTags.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: DesignTokens.Space.s2) {
                    ForEach(allTags, id: \.self) { tag in
                        VDFilterChip(title: "#" + tag, icon: nil, tone: nil, count: nil, isOn: tagBinding(tag))
                    }
                }
                .padding(.horizontal, DesignTokens.Space.s3)
                .padding(.bottom, DesignTokens.Space.s2)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func tagBinding(_ tag: String) -> Binding<Bool> {
        Binding(get: { filter.tags.contains(tag) }, set: { isOn in
            if isOn { filter.tags.insert(tag) } else { filter.tags.remove(tag) }
        })
    }

    // MARK: Lista

    @ViewBuilder
    private var list: some View {
        if let section = concept.section {
            sectionList(section)
        } else {
            pageList
        }
    }

    @ViewBuilder
    private func sectionList(_ section: SidebarSection) -> some View {
        if let grouped = section.groupedConcept {
            List {
                GroupTreeView(concept: grouped, rows: rows, filtering: isFiltering, selected: selection,
                              onOpen: { selection = $0 }, onOpenInNewTab: { selection = $0 })
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        } else if allRows.isEmpty {
            ContentUnavailableView {
                Label(section.emptyMessage, systemImage: section.symbol)
            } actions: {
                LoggedButton("Adicionar") { onAdd(section) }
                    .loggedControl(control: "v2_content_column.empty_add", label: "Adicionar")
                    .buttonStyle(.glass)
                    .disabled(model.isReadOnly)
            }
            .frame(maxHeight: .infinity)
        } else if rows.isEmpty {
            ContentUnavailableView.search(text: filter.summary)
                .frame(maxHeight: .infinity)
        } else {
            rowList
        }
    }

    private var rowList: some View {
        List(rows, selection: $selection) { row in
            V2ListRow(row: row)
                .contextMenu { rowMenu(row) }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func rowMenu(_ row: SectionRow) -> some View {
        LoggedButton("Abrir") { selection = row.id }
            .loggedControl(control: "v2_content_column.open", label: "Abrir")
        LoggedButton("Editar tags…") { editingTags = row }
            .loggedControl(control: "v2_content_column.edit_tags", label: "Editar tags")
            .disabled(model.isReadOnly)
        if let url = model.fileURL(for: row.id) {
            LoggedButton("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                .loggedControl(control: "v2_content_column.reveal", label: "Mostrar no Finder")
        }
        Divider()
        LoggedButton("Mover para o Lixo", role: .destructive) {
            if selection == row.id { selection = nil }
            model.delete(row.id)
        }
        .loggedControl(control: "v2_content_column.trash", label: "Mover para o Lixo")
        .disabled(model.isReadOnly)
    }

    // MARK: Lista de páginas (Referências, Projeto)

    private var visiblePages: [V2Page] {
        let text = filter.parsed.text
        return concept.pages.filter { page in
            (page != .claudeItems || !model.project.claude.isEmpty)
                && (text.isEmpty || page.title.localizedCaseInsensitiveContains(text))
        }
    }

    private var pageSelection: Binding<V2Page?> {
        Binding(
            get: {
                if let item = selection { return V2Page(item: item) }
                return concept == .project ? V2Page.overview : nil
            },
            set: { page in selection = page?.item }
        )
    }

    private func pageCount(_ page: V2Page) -> Int? {
        switch page {
        case .stack: return model.project.stack.count
        case .patterns: return model.project.patterns.count
        case .links: return model.project.links.count
        case .claudeItems: return model.project.claude.count
        case .checksHistory: return model.checks.count
        case .overview, .graph, .integrations, .usage: return nil
        }
    }

    private var pageList: some View {
        VStack(spacing: 0) {
            List(visiblePages, selection: pageSelection) { page in
                HStack(spacing: DesignTokens.Space.s2) {
                    Image(systemName: page.symbol)
                        .foregroundStyle(DesignTokens.Colors.brandText)
                        .frame(width: 18)
                    Text(page.title).font(DesignTokens.Typography.body).lineLimit(1)
                    Spacer()
                    if let count = pageCount(page) {
                        Text("\(count)")
                            .font(DesignTokens.Typography.callout)
                            .monospacedDigit()
                            .foregroundStyle(DesignTokens.Colors.inkMuted)
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            if concept == .project { projectFooter }
        }
    }

    private var projectFooter: some View {
        HStack(spacing: DesignTokens.Space.s2) {
            VDIcon(.folder, size: 13)
            Text(model.store.root.path(percentEncoded: false))
                .font(DesignTokens.Typography.mono)
                .lineLimit(1)
                .truncationMode(.head)
        }
        .foregroundStyle(DesignTokens.Colors.inkMuted)
        .padding(DesignTokens.Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .help("Pasta do projeto")
    }
}

private struct V2ListRow: View {
    let row: SectionRow

    private var subtitle: String {
        [row.detail, row.count].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var tagsText: String {
        row.tags.map { "#" + $0 }.joined(separator: " ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: DesignTokens.Space.s2) {
            Image(systemName: row.symbol)
                .foregroundStyle(DesignTokens.Colors.brandText)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(row.dimmed ? DesignTokens.Colors.inkMuted : DesignTokens.Colors.ink)
                    .lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(DesignTokens.Typography.callout)
                        .foregroundStyle(DesignTokens.Colors.inkMuted)
                        .lineLimit(1)
                }
                if !tagsText.isEmpty {
                    Text(tagsText)
                        .font(DesignTokens.Typography.callout)
                        .foregroundStyle(DesignTokens.Colors.inkFaint)
                        .lineLimit(1)
                }
            }
        }
        .help(row.title)
    }
}
