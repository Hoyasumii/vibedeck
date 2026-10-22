import SwiftUI
import UniformTypeIdentifiers

struct ClaudeItemsView: View {
    @Environment(\.logProject) private var logProject
    @Environment(ProjectModel.self) private var model
    @Environment(\.undoManager) private var undo
    @Environment(\.openURL) private var openURL
    @State private var selection = Set<UUID>()
    @State private var editing: ClaudeItem?
    @State private var search = ""
    @State private var kind: ClaudeItemKind?

    private var items: [ClaudeItem] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.project.claude.filter { item in
            (kind == nil || item.kind == kind) && (query.isEmpty ||
                (query.hasPrefix("#") ? item.tags.contains { $0.localizedCaseInsensitiveContains(String(query.dropFirst())) } :
                    item.title.localizedCaseInsensitiveContains(query) || item.url.localizedCaseInsensitiveContains(query) ||
                    item.tags.contains { $0.localizedCaseInsensitiveContains(query) }))
        }
    }

    var body: some View {
        Group {
            if model.project.claude.isEmpty {
                ContentUnavailableView {
                    Label("Nada do Claude ainda", systemImage: "square.stack")
                } description: {
                    Text("Adicione artefatos e docs escolhidos por você, ou cole um link do Claude (⌘V).")
                } actions: {
                    LoggedButton("Adicionar do Claude", action: add).loggedControl(control: "claude_items_view.button_1", label: "Adicionar do Claude").buttonStyle(.glass)
                }
            } else {
                Table(items, selection: $selection.logging(control: "claude_items_view.selection_10", label: "Seleção", project: logProject)) {
                    TableColumn("Tipo") { item in
                        Text(item.kind.title)
                            .font(.caption)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .glassEffect(.regular, in: .capsule)
                    }.width(min: 70, ideal: 90)
                    TableColumn("Título") { item in Text(item.title).fontWeight(.medium) }
                    TableColumn("Data") { item in Text(item.addedAt, style: .date).foregroundStyle(.secondary) }
                    TableColumn("Tags") { item in TagChips(tags: item.tags) { search = "#\($0)" } }
                        .width(min: 80, ideal: 160)
                }
                .contextMenu(forSelectionType: UUID.self) { ids in
                    if let id = ids.first, let item = model.project.claude.first(where: { $0.id == id }) {
                        LoggedButton("Abrir") { open(item) }.loggedControl(control: "claude_items_view.button_2", label: "Abrir")
                        LoggedButton("Copiar URL") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(item.url, forType: .string)
                        }.loggedControl(control: "claude_items_view.button_3", label: "Copiar URL")
                        LoggedButton("Editar…") { editing = item }.loggedControl(control: "claude_items_view.button_4", label: "Editar…")
                        Divider()
                    }
                    LoggedButton("Remover da coleção", role: .destructive) { remove(ids) }.loggedControl(control: "claude_items_view.button_5", label: "Remover da coleção")
                } primaryAction: { ids in
                    model.project.claude.filter { ids.contains($0.id) }.forEach(open)
                }
                .onDeleteCommand { remove(selection) }
            }
        }
        .navigationTitle("Claude")
        .searchable(text: $search, placement: .toolbar, prompt: "Filtrar Claude (#tag)")
        .toolbar {
            ToolbarItem {
                Picker("Tipo", selection: $kind.logging(control: "claude_items_view.selection_11", label: "Tipo", project: logProject)) {
                    Text("Todos").tag(ClaudeItemKind?.none)
                    Text("Artefatos").tag(ClaudeItemKind?.some(.artifact))
                    Text("Docs").tag(ClaudeItemKind?.some(.doc))
                }.pickerStyle(.segmented)
            }
            ToolbarItem {
                LoggedButton(action: add) { Label("Adicionar do Claude", systemImage: "plus") }.loggedControl(control: "claude_items_view.button_6", label: "Adicionar do Claude")
            }
        }
        .onPasteCommand(of: [.url, .plainText]) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: NSString.self) { string, _ in
                    guard let text = (string as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                          ClaudeItem.accepts(text) else { return }
                    Task { @MainActor in
                        editing = ClaudeItem(title: ClaudeItem.suggestedTitle(for: text), url: text, kind: .artifact)
                    }
                }
            }
        }
        .sheet(item: $editing) { item in
            ClaudeItemEditor(item: item, isNew: !model.project.claude.contains { $0.id == item.id }) { saved in
                model.mutateProject("Editar coleção do Claude", undo: undo) { project in
                    if let index = project.claude.firstIndex(where: { $0.id == saved.id }) {
                        project.claude[index] = saved
                    } else { project.claude.append(saved) }
                }
            }
        }
    }

    private func add() { editing = ClaudeItem(title: "", url: "", kind: .artifact) }

    private func open(_ item: ClaudeItem) {
        if ClaudeItem.accepts(item.url), let url = URL(string: item.url) { openURL(url) }
    }

    private func remove(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        model.mutateProject("Remover da coleção do Claude", undo: undo) { $0.claude.removeAll { ids.contains($0.id) } }
        selection.subtract(ids)
    }
}

struct ClaudeItemEditor: View {
    @Environment(\.logProject) private var logProject
    @State var item: ClaudeItem
    let isNew: Bool
    let onSave: (ClaudeItem) -> Void
    @State private var kind: ClaudeItemKind?
    @State private var tagsText = ""
    @State private var original: ClaudeItem?
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            LoggedTextField("URL do claude.ai", text: $item.url, onCommit: commit).loggedField(control: "claudeitemsview.text_1", label: "URL do claude.ai")
            Picker("Tipo", selection: $kind.logging(control: "claude_items_view.selection_12", label: "Tipo", project: logProject)) {
                Text("Escolha o tipo").tag(ClaudeItemKind?.none)
                ForEach(ClaudeItemKind.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
            }
            LoggedTextField("Título", text: $item.title, onCommit: commit).loggedField(control: "claudeitemsview.text_2", label: "Título")
            LoggedTextField("Tags (separadas por vírgula)", text: $tagsText, onCommit: commit).loggedField(control: "claudeitemsview.text_3", label: "Tags (separadas por vírgula)")
            if !item.url.isEmpty && !ClaudeItem.accepts(item.url) {
                Text("Informe uma URL http ou https do claude.ai.").foregroundStyle(.red)
            }
            Text("Escolha Artefato ou Doc: a URL não informa o tipo. Remover tira apenas da coleção.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .focused($focused)
        .formStyle(.grouped)
        .frame(width: 460)
        .onAppear {
            kind = isNew ? nil : item.kind
            tagsText = item.tags.joined(separator: ", ")
            original = item
        }
        .onChange(of: item.url) { old, new in
            if item.title.isEmpty || item.title == ClaudeItem.suggestedTitle(for: old) {
                item.title = ClaudeItem.suggestedTitle(for: new)
            }
        }
        .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
        .onChange(of: kind) { _, _ in commit() }
        .toolbar {
            if isNew {
                ToolbarItem(placement: .cancellationAction) { LoggedButton("Cancelar") { dismiss() }.loggedControl(control: "claude_items_view.button_7", label: "Cancelar") }
                ToolbarItem(placement: .confirmationAction) {
                    LoggedButton("Adicionar") {
                        if let saved = normalized { onSave(saved); dismiss() }
                    }.loggedControl(control: "claude_items_view.button_8", label: "Adicionar").disabled(normalized == nil)
                }
            } else {
                ToolbarItem(placement: .confirmationAction) {
                    LoggedButton("Concluído") { commit(); dismiss() }.loggedControl(control: "claude_items_view.button_9", label: "Concluído").disabled(normalized == nil)
                }
            }
        }
    }

    private var normalized: ClaudeItem? {
        guard let kind, var saved = try? ClaudeItem.make(url: item.url, kind: kind, title: item.title, tags: Tags.parse(tagsText)) else { return nil }
        saved.id = item.id
        saved.addedAt = item.addedAt
        return saved
    }

    private func commit() {
        guard !isNew, let saved = normalized, saved != original else { return }
        original = saved
        onSave(saved)
    }
}
