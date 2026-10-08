import SwiftUI
import VibeDeckCore

/// List page for a sidebar section (Docs, Revisões, Regras, Ideias, Agentes): its children in a table,
/// filterable by free text and by tags (`#tag` tokens or the tag bar).
struct SectionListView: View {
    let section: SidebarSection
    let onOpen: (SidebarItem) -> Void
    let onOpenInNewTab: (SidebarItem) -> Void
    let onAdd: () -> Void
    @Environment(ProjectModel.self) private var model
    @Environment(\.undoManager) private var undo
    @State private var selection = Set<SidebarItem>()
    @State private var search = ""
    @State private var tokens: [TagToken] = []
    @State private var editingTags: SectionRow?
    @State private var importedCount: Int?

    struct TagToken: Identifiable, Hashable {
        var tag: String
        var id: String { tag }
    }

    private var allRows: [SectionRow] { model.rows(for: section) }

    private var allTags: [String] {
        Array(Set(allRows.flatMap(\.tags))).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var rows: [SectionRow] {
        let q = search.trimmingCharacters(in: .whitespaces)
        let required = tokens.map(\.tag)
        return allRows.filter { row in
            required.allSatisfy { tag in row.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame } }
                && (q.isEmpty || row.title.localizedCaseInsensitiveContains(q) || row.detail.localizedCaseInsensitiveContains(q)
                    || row.tags.contains { $0.localizedCaseInsensitiveContains(q.hasPrefix("#") ? String(q.dropFirst()) : q) })
        }
    }

    private var suggestedTokens: [TagToken] {
        guard search.hasPrefix("#") else { return [] }
        let q = search.dropFirst()
        return allTags
            .filter { tag in q.isEmpty || tag.localizedCaseInsensitiveContains(q) }
            .filter { tag in !tokens.contains { $0.tag == tag } }
            .map(TagToken.init)
    }

    var body: some View {
        VStack(spacing: 0) {
            if !allTags.isEmpty { tagBar }
            content
        }
        .navigationTitle(section.title)
        .searchable(text: $search, tokens: $tokens, suggestedTokens: .constant(suggestedTokens),
                    placement: .toolbar, prompt: "Filtrar \(section.title.lowercased()) (#tag)") { token in
            Text("#\(token.tag)")
        }
        .toolbar {
            if section == .agents, ClaudeCode.isInstalled {
                ToolbarItem {
                    Button { importedCount = model.importClaudeAgents() } label: { Label("Importar do Claude Code", systemImage: "square.and.arrow.down") }
                        .help("Importa os agentes de .claude/agents (projeto e usuário)")
                }
            }
            ToolbarItem {
                Button(action: onAdd) { Label("Novo", systemImage: "plus") }
            }
        }
        .alert("Importação concluída", isPresented: Binding(get: { importedCount != nil }, set: { if !$0 { importedCount = nil } })) {
            Button("OK") { importedCount = nil }
        } message: {
            Text(importedCount == 0 ? "Nenhum agente novo encontrado." : "\(importedCount ?? 0) agente(s) importado(s).")
        }
        .sheet(item: $editingTags) { row in
            TagsEditor(title: row.title, tags: row.tags) { model.setTags($0, for: row.id, undo: undo) }
        }
    }

    @ViewBuilder
    private var content: some View {
        if allRows.isEmpty {
            ContentUnavailableView {
                Label(section.emptyMessage, systemImage: section.symbol)
            } actions: {
                Button("Adicionar", action: onAdd).buttonStyle(.glass)
            }
            .frame(maxHeight: .infinity)
        } else if rows.isEmpty {
            ContentUnavailableView.search(text: search.isEmpty ? tokens.map { "#\($0.tag)" }.joined(separator: " ") : search)
                .frame(maxHeight: .infinity)
        } else {
            table
        }
    }

    private var table: some View {
        Table(rows, selection: $selection) {
            TableColumn("Título") { row in
                Label {
                    Text(row.title).fontWeight(.medium)
                } icon: {
                    Image(systemName: row.symbol).foregroundStyle(.tint)
                }
                .foregroundStyle(row.dimmed ? .secondary : .primary)
            }
            TableColumn("Detalhe") { row in
                Text(row.detail).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
            }
            TableColumn("") { row in
                Text(row.count).foregroundStyle(.secondary).monospacedDigit()
            }
            .width(min: 60, ideal: 110)
            TableColumn("Tags") { row in
                TagChips(tags: row.tags, onTap: toggle)
            }
            .width(min: 80, ideal: 180)
        }
        .contextMenu(forSelectionType: SidebarItem.self) { ids in
            if ids.count == 1, let id = ids.first, let row = allRows.first(where: { $0.id == id }) {
                Button("Abrir") { onOpen(id) }
                Button("Abrir em Nova Aba") { onOpenInNewTab(id) }
                Button("Editar tags…") { editingTags = row }
                if let url = model.fileURL(for: id) {
                    Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }
                Divider()
            }
            Button("Mover para o Lixo", role: .destructive) { remove(ids) }
        } primaryAction: { ids in
            if let id = ids.first { onOpen(id) }
        }
        .onDeleteCommand { remove(selection) }
    }

    private var tagBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(allTags, id: \.self) { tag in
                    let on = tokens.contains { $0.tag == tag }
                    Button { toggle(tag) } label: {
                        Text("#\(tag)").font(.callout)
                    }
                    .buttonStyle(.glass)
                    .tint(on ? .accentColor : nil)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
    }

    private func toggle(_ tag: String) {
        withAnimation(.snappy) {
            if let i = tokens.firstIndex(where: { $0.tag == tag }) { tokens.remove(at: i) }
            else { tokens.append(TagToken(tag: tag)) }
        }
    }

    private func remove(_ ids: Set<SidebarItem>) {
        ids.forEach(model.delete)
        selection.subtract(ids)
    }
}

private struct TagsEditor: View {
    let title: String
    let tags: [String]
    let onSave: ([String]) -> Void
    @State private var text = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            TextField("Tags (separadas por vírgula)", text: $text)
        }
        .formStyle(.grouped)
        .navigationTitle(title)
        .frame(width: 420)
        .onAppear { text = tags.joined(separator: ", ") }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Salvar") { onSave(Tags.parse(text)); dismiss() }
            }
        }
    }
}
