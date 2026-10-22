import SwiftUI

/// List page for a sidebar section (Docs, Revisões, Regras, Ideias, Agentes): its children in a table,
/// filtered by the V2 content column filter (free text, `#tag` tokens and tag chips); it has no filter field of its own.
struct SectionListView: View {
    @Environment(\.logProject) private var providerRoot
    @Environment(\.logProject) private var logProject
    let section: SidebarSection
    /// Filtro compartilhado com a coluna de conteúdo (campo e chips ficam lá; esta tabela só o aplica).
    @Binding var filter: V2ListFilter
    let onOpen: (SidebarItem) -> Void
    let onOpenInNewTab: (SidebarItem) -> Void
    let onAdd: () -> Void
    @Environment(AISession.self) private var session
    @Environment(ProjectModel.self) private var model
    @Environment(\.undoManager) private var undo
    @LoggedSelection(control: "section_list_view.selection_18", label: "Seleção") private var selection = Set<SidebarItem>()
    @State private var editingTags: SectionRow?
    @State private var importedCount: Int?
    @State private var showingDocGeneration = false

    private var allRows: [SectionRow] { model.rows(for: section) }

    private var rows: [SectionRow] { allRows.filter { filter.matches($0) } }

    var body: some View {
        VStack(spacing: 0) {
            if section == .topics, let execution = model.ruleExecution {
                RuleExecutionPanel(execution: execution).id(execution.id)
            }
            content
        }
        .navigationTitle(section.title)
        .toolbar {
            if [.topics, .docs, .ideas, .groups].contains(section), !AIProvider.installed(in: providerRoot).isEmpty {
                ToolbarItem { ReorganizeButton() }
            }
            if [.agents, .commands, .skills, .workflows].contains(section) {
                ToolbarItem { KitCatalogButton() }
                ToolbarItem {
                    CreateWithAIButton(kind: section == .agents ? .agent : section == .commands ? .command : section == .skills ? .skill : .workflow)
                }
            }
            // Importing reads the provider's own files, so it only shows for installed providers.
            if [.agents, .commands, .skills].contains(section), !AIProvider.installed(in: providerRoot).isEmpty {
                ToolbarItem {
                    Menu("Importar", systemImage: "square.and.arrow.down") {
                        ForEach(AIProvider.installed(in: providerRoot), id: \.self) { provider in
                            LoggedButton("Importar de " + provider.title) {
                                Task {
                                    do {
                                        guard AIProvider.installed(in: model.store.root).contains(provider),
                                              RemoteExecution.available(provider, root: model.store.root) else { return }
                                        let result: AIImportResult
                                        switch section {
                                        case .agents: result = try await model.store.importRecords("import_agents", provider: provider)
                                        case .commands: result = try await model.store.importRecords("import_commands", provider: provider)
                                        default: result = try await model.store.importRecords("import_skills", provider: provider)
                                        }
                                        model.reloadAgents(); model.reloadCommands(); model.reloadSkills()
                                        importedCount = result.slugs.count
                                        if !result.warnings.isEmpty { model.errorMessage = result.warnings.joined(separator: "\n") }
                                    } catch { model.errorMessage = error.localizedDescription }
                                }
                            }.loggedControl(control: "section_list_view.button_1", label: "Importar de ")
                        }
                    }
                }
            }
            if section == .docs, !AIProvider.installed(in: providerRoot).isEmpty {
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
                        LoggedButton(model.docGenerator.isRunning ? "Cancelar geração" : "Revisar proposta") {
                            if model.docGenerator.isRunning { model.docGenerator.cancel() }
                            else { showingDocGeneration = true }
                        }.loggedControl(control: "section_list_view.button_3", label: "Ativar controle")
                    }
                }
            }
            if section == .topics {
                ToolbarItemGroup {
                    if !AIProvider.installed(in: providerRoot).isEmpty { generateMenu.disabled(model.ruleExecution?.active == true) }
                    RuleExecutionControls()
                }
            }
            ToolbarItem {
                LoggedButton(action: onAdd) { Label("Novo", systemImage: "plus") }.loggedControl(control: "section_list_view.button_4", label: "Novo")
            }
        }
        .alert("Importação concluída", isPresented: Binding(get: { importedCount != nil }, set: { if !$0 { importedCount = nil } })) {
            LoggedButton("OK") { importedCount = nil }.loggedControl(control: "section_list_view.button_5", label: "OK")
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
                LoggedButton("Cancelar geração", role: .destructive) { model.cancelTestGeneration() }.loggedControl(control: "section_list_view.button_6", label: "Cancelar geração")
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
                ForEach(AIProvider.installed(in: providerRoot), id: \.self) { provider in
                    Menu(provider.title) {
                        LoggedButton("Só as que faltam (\(count(.missing)))") { model.generateAllTests(.missing, provider: provider) }.loggedControl(control: "section_list_view.button_7", label: "Ativar controle")
                            .disabled(count(.missing) == 0)
                        LoggedButton("Só as desatualizadas (\(count(.stale)))") { model.generateAllTests(.stale, provider: provider) }.loggedControl(control: "section_list_view.button_8", label: "Ativar controle")
                            .disabled(count(.stale) == 0)
                        LoggedButton("Regenerar todas (\(count(.all)))") { model.generateAllTests(.all, provider: provider) }.loggedControl(control: "section_list_view.button_9", label: "Ativar controle")
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
        if let concept = section.groupedConcept {
            List { GroupTreeView(concept: concept, rows: rows, filtering: filter.isActive, onOpen: onOpen, onOpenInNewTab: onOpenInNewTab) }
        } else if allRows.isEmpty {
            ContentUnavailableView {
                Label(section.emptyMessage, systemImage: section.symbol)
            } actions: {
                LoggedButton("Adicionar", action: onAdd).loggedControl(control: "section_list_view.button_10", label: "Adicionar").buttonStyle(.glass)
            }
            .frame(maxHeight: .infinity)
        } else if rows.isEmpty {
            ContentUnavailableView.search(text: filter.summary)
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
                LoggedButton("Abrir") { onOpen(id) }.loggedControl(control: "section_list_view.button_11", label: "Abrir")
                LoggedButton("Abrir em Nova Aba") { onOpenInNewTab(id) }.loggedControl(control: "section_list_view.button_12", label: "Abrir em Nova Aba")
                LoggedButton("Editar tags…") { editingTags = row }.loggedControl(control: "section_list_view.button_13", label: "Editar tags…")
                if let url = model.fileURL(for: id) {
                    LoggedButton("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }.loggedControl(control: "section_list_view.button_14", label: "Mostrar no Finder")
                }
                Divider()
            }
            LoggedButton("Mover para o Lixo", role: .destructive) { remove(ids) }.loggedControl(control: "section_list_view.button_15", label: "Mover para o Lixo")
        } primaryAction: { ids in
            if let id = ids.first { onOpen(id) }
        }
        .onDeleteCommand { remove(selection) }
    }

    private func toggle(_ tag: String) {
        filter.toggle(tag: tag)
    }

    private func remove(_ ids: Set<SidebarItem>) {
        ids.forEach(model.delete)
        selection.subtract(ids)
    }
}

struct TagsEditor: View {
    @Environment(\.logProject) private var providerRoot
    @Environment(\.logProject) private var logProject
    let title: String
    let tags: [String]
    let onSave: ([String]) -> Void
    @State private var text = ""
    @State private var saved: [String] = []
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            LoggedTextField("Tags (separadas por vírgula)", text: $text, onCommit: commit).loggedField(control: "sectionlistview.text_1", label: "Tags (separadas por vírgula)")
                .focused($focused)

        }
        .formStyle(.grouped)
        .navigationTitle(title)
        .frame(width: 420)
        .onAppear { text = tags.joined(separator: ", "); saved = tags }
        .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                LoggedButton("Concluído") { commit(); dismiss() }.loggedControl(control: "section_list_view.button_17", label: "Concluído")
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
