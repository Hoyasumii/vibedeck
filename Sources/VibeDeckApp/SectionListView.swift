import SwiftUI
import VibeDeckCore

/// List page for a sidebar section (Docs, Revisões, Regras, Ideias, Agentes): its children in a table,
/// filterable by free text and by tags (`#tag` tokens or the tag bar).
struct SectionListView: View {
    let section: SidebarSection
    let onOpen: (SidebarItem) -> Void
    let onOpenInNewTab: (SidebarItem) -> Void
    let onAdd: () -> Void
    @Environment(AISession.self) private var session
    @Environment(ProjectModel.self) private var model
    @Environment(\.undoManager) private var undo
    @State private var selection = Set<SidebarItem>()
    @State private var search = ""
    @State private var tokens: [TagToken] = []
    @State private var editingTags: SectionRow?
    @State private var importedCount: Int?
    @State private var showingDocGeneration = false

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
            if section == .topics, let execution = model.ruleExecution {
                RuleExecutionPanel(execution: execution).id(execution.id)
            }
            if !allTags.isEmpty { tagBar }
            content
        }
        .navigationTitle(section.title)
        .searchable(text: $search, tokens: $tokens, suggestedTokens: .constant(suggestedTokens),
                    placement: .toolbar, prompt: "Filtrar \(section.title.lowercased()) (#tag)") { token in
            Text("#\(token.tag)")
        }
        .toolbar {
            // Importing reads the provider's own files, so it only shows for installed providers.
            if [.agents, .commands, .skills].contains(section), !AIProvider.installed.isEmpty {
                ToolbarItem {
                    Menu("Importar", systemImage: "square.and.arrow.down") {
                        ForEach(AIProvider.installed, id: \.self) { provider in
                            Button("Importar de " + provider.title) {
                                Task {
                                    do {
                                        guard provider.isInstalled else { return }
                                        let result: AIImportResult
                                        switch section {
                                        case .agents: result = try model.store.importAgents(provider: provider)
                                        case .commands: result = try model.store.importCommands(provider: provider)
                                        default: result = try await model.store.importSkills(provider: provider)
                                        }
                                        model.reloadAgents(); model.reloadCommands(); model.reloadSkills()
                                        importedCount = result.slugs.count
                                        if !result.warnings.isEmpty { model.errorMessage = result.warnings.joined(separator: "\n") }
                                    } catch { model.errorMessage = error.localizedDescription }
                                }
                            }
                        }
                    }
                }
            }
            if section == .docs, !AIProvider.installed.isEmpty {
                ToolbarItemGroup {
                    Button {
                        model.docGenerator.start(store: model.store, provider: session.provider)
                        showingDocGeneration = true
                    } label: {
                        Label("Gerar documentos", systemImage: "wand.and.stars")
                    }
                    .disabled(model.docGenerator.isActive)
                    if model.docGenerator.isActive {
                        if model.docGenerator.isRunning { ProgressView().controlSize(.small) }
                        Button(model.docGenerator.isRunning ? "Cancelar geração" : "Revisar proposta") {
                            if model.docGenerator.isRunning { model.docGenerator.cancel() }
                            else { showingDocGeneration = true }
                        }
                    }
                }
            }
            if section == .topics {
                ToolbarItemGroup {
                    if !AIProvider.installed.isEmpty { generateMenu.disabled(model.ruleExecution?.active == true) }
                    RuleExecutionControls()
                }
            }
            ToolbarItem {
                Button(action: onAdd) { Label("Novo", systemImage: "plus") }
            }
        }
        .alert("Importação concluída", isPresented: Binding(get: { importedCount != nil }, set: { if !$0 { importedCount = nil } })) {
            Button("OK") { importedCount = nil }
        } message: {
            let count = importedCount ?? 0
            switch section {
            case .skills: Text(count == 0 ? "Nenhuma skill nova encontrada." : "\(count) skill(s) importada(s).")
            case .commands: Text(count == 0 ? "Nenhum comando novo encontrado." : "\(count) comando(s) importado(s).")
            default: Text(count == 0 ? "Nenhum agente novo encontrado." : "\(count) agente(s) importado(s).")
            }
        }
        .sheet(isPresented: $showingDocGeneration, onDismiss: { model.docGenerator.cancel() }) {
            DocGenerateSheet(runner: model.docGenerator, model: model, undo: undo)
        }
        .sheet(item: $editingTags) { row in
            TagsEditor(title: row.title, tags: row.tags) { model.setTags($0, for: row.id, undo: undo) }
        }
    }

    // MARK: Rule tests (Regras)

    private func count(_ selection: RuleTestPrompt.Selection) -> Int {
        model.topics.reduce(0) { $0 + RuleTestPrompt.rules($1.value, selection).count }
    }

    private var scriptCount: Int {
        model.topics.reduce(0) { $0 + $1.value.rules.filter { $0.testState == .script }.count }
    }

    @ViewBuilder
    private var generateMenu: some View {
        if model.isGeneratingTests {
            let jobs = model.generatingTests.values
            Menu {
                Button("Cancelar geração", role: .destructive) { model.cancelTestGeneration() }
            } label: {
                Label {
                    Text("Gerando \(jobs.filter { !$0.isActive }.count)/\(jobs.count)…")
                } icon: {
                    ProgressView().controlSize(.small)
                }
                .labelStyle(.titleAndIcon)
            }
            .help("Gerando as verificações em segundo plano, até 3 tópicos por vez")
        } else {
            let pending = count(.pending)
            Menu {
                ForEach(AIProvider.installed, id: \.self) { provider in
                    Menu(provider.title) {
                        Button("Só as que faltam (\(count(.missing)))") { model.generateAllTests(.missing, provider: provider) }
                            .disabled(count(.missing) == 0)
                        Button("Só as desatualizadas (\(count(.stale)))") { model.generateAllTests(.stale, provider: provider) }
                            .disabled(count(.stale) == 0)
                        Button("Regenerar todas (\(count(.all)))") { model.generateAllTests(.all, provider: provider) }
                            .disabled(count(.all) == 0)
                    }
                }
            } label: {
                Label("Gerar verificações", systemImage: "wand.and.stars")
            }
            .badge(pending)
            .help(pending == 0 ? "Todas as regras já têm verificação" : "Gera as \(pending) verificação(ões) que faltam ou estão desatualizadas, em paralelo")
        }
    }

    @ViewBuilder
    private func generationStatus(_ row: SectionRow) -> some View {
        if case .topic(let slug) = row.id, let state = model.generatingTests[slug] {
            switch state {
            case .queued:
                Image(systemName: "clock").foregroundStyle(.secondary).help("Na fila para gerar as verificações")
            case .running:
                ProgressView().controlSize(.mini).help("Gerando as verificações…")
            case .done:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).help("Verificações geradas")
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).help(message)
            }
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
                HStack(spacing: 6) {
                    Text(row.count).foregroundStyle(.secondary).monospacedDigit()
                    generationStatus(row)
                }
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
    @State private var saved: [String] = []
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            TextField("Tags (separadas por vírgula)", text: $text)
                .focused($focused)
                .onSubmit(commit)
        }
        .formStyle(.grouped)
        .navigationTitle(title)
        .frame(width: 420)
        .onAppear { text = tags.joined(separator: ", "); saved = tags }
        .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Concluído") { commit(); dismiss() }
            }
        }
    }

    /// Writes the tags in place (one undo step) on Return, focus loss or "Concluído".
    private func commit() {
        let parsed = Tags.parse(text)
        guard parsed != saved else { return }
        saved = parsed
        onSave(parsed)
    }
}
