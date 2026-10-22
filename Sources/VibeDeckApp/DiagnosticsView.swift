import AppKit
import SwiftUI

/// Global window with the logs of every VibeDeck process (app, CLI, MCP): errors, failures and crashes.
struct DiagnosticsView: View {
    @Environment(\.logProject) private var logProject
    static let windowID = "diagnostics"

    enum Period: String, CaseIterable, Identifiable {
        case hour = "1h", day = "24h", week = "7d", all = "14d"
        var id: String { rawValue }
        var title: String {
            switch self {
            case .hour: "Última hora"
            case .day: "Últimas 24 horas"
            case .week: "Últimos 7 dias"
            case .all: "Últimos 14 dias"
            }
        }
    }

    @State private var entries: [LogEntry] = []
    @State private var selection: LogEntry.ID?
    @State private var period: Period = .day
    @State private var minLevel: LogLevel = .info
    @State private var component: LogComponent?
    @State private var project: String?
    @State private var search = ""
    @State private var action = ""
    @State private var showInspector = true

    private var filter: LogFilter {
        LogFilter(since: try? LogFilter.parseSince(period.rawValue), minLevel: minLevel, components: component.map { [$0] } ?? [],
                  project: project, search: search, action: action.isEmpty ? nil : action, limit: 2000)
    }

    private var projects: [String] {
        Array(Set(entries.compactMap(\.project))).sorted()
    }

    private var selected: LogEntry? { entries.first { $0.id == selection } }

    var body: some View {
        Table(entries, selection: $selection.logging(control: "diagnostics_view.selection_5", label: "Seleção", project: logProject)) {
            TableColumn("Quando") { entry in
                Text(entry.ts.formatted(date: .abbreviated, time: .standard)).monospacedDigit()
            }
            .width(min: 140, ideal: 160)
            TableColumn("Nível") { entry in
                Label(entry.level.title, systemImage: Self.symbol(entry.level)).foregroundStyle(Self.color(entry.level))
            }
            .width(min: 80, ideal: 90)
            TableColumn("Origem") { entry in Text(entry.component.rawValue) }
                .width(min: 50, ideal: 60)
            TableColumn("Evento") { entry in Text(entry.event).font(.callout.monospaced()) }
                .width(min: 120, ideal: 180)
            TableColumn("Mensagem") { entry in Text(entry.message).lineLimit(1) }
        }
        .overlay {
            if entries.isEmpty {
                ContentUnavailableView("Nada registrado", systemImage: "checkmark.seal",
                                       description: Text("Nenhuma entrada com esses filtros no período."))
            }
        }
        .searchable(text: $search, prompt: "Procurar no evento, na mensagem ou no contexto")
        .detailContext(isPresented: $showInspector) {
            detail
        }
        .toolbar { toolbar }
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .navigationTitle("Diagnóstico")
        .task(id: filter) {
            // Other processes append at any time: refresh while the window is open.
            while !Task.isCancelled {
                await reload()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Picker("Período", selection: $period.logging(control: "diagnostics_view.selection_6", label: "Período", project: logProject)) {
                ForEach(Period.allCases) { Text($0.title).tag($0) }
            }
            Picker("Nível mínimo", selection: $minLevel.logging(control: "diagnostics_view.selection_7", label: "Nível mínimo", project: logProject)) {
                ForEach(LogLevel.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Picker("Origem", selection: $component.logging(control: "diagnostics_view.selection_8", label: "Origem", project: logProject)) {
                Text("Todas as origens").tag(LogComponent?.none)
                ForEach(LogComponent.allCases, id: \.self) { Text($0.rawValue).tag(LogComponent?.some($0)) }
            }
            Picker("Projeto", selection: $project.logging(control: "diagnostics_view.selection_9", label: "Projeto", project: logProject)) {
                Text("Todos os projetos").tag(String?.none)
                ForEach(projects, id: \.self) { Text(URL(fileURLWithPath: $0).lastPathComponent).tag(String?.some($0)) }
            }
        }
        ToolbarItemGroup {
            LoggedTextField("Id da ação", text: $action).loggedField(control: "diagnosticsview.text_1", label: "Id da ação").frame(width: 180)
            LoggedButton("Copiar Relatório", systemImage: "doc.on.doc", action: copyReport).loggedControl(control: "diagnostics_view.button_1", label: "Copiar Relatório")
                .help("Copia as entradas filtradas como texto, para colar numa issue")
            LoggedButton("Mostrar no Finder", systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([LogStore.default.dir])
            }.loggedControl(control: "diagnostics_view.button_2", label: "Mostrar no Finder")
            LoggedButton("Detalhes", systemImage: "sidebar.trailing") { showInspector.toggle() }.loggedControl(control: "diagnostics_view.button_3", label: "Detalhes")
                .keyboardShortcut("i", modifiers: [.command, .option])
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let entry = selected {
            Form {
                Section("Entrada") {
                    LabeledContent("Quando", value: entry.ts.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
                    LabeledContent("Nível", value: entry.level.title)
                    LabeledContent("Origem", value: entry.component.rawValue)
                    LabeledContent("Evento", value: entry.event)
                    if let project = entry.project { LabeledContent("Projeto", value: project) }
                    if let version = entry.version { LabeledContent("Versão", value: version) }
                    if let pid = entry.pid { LabeledContent("Processo", value: String(pid)) }
                }
                if let id = entry.action {
                    Section("Ação e reações") {
                        LoggedButton("Filtrar esta ação") { action = id; minLevel = .info }.loggedControl(control: "diagnostics.filter_action", label: "Filtrar esta ação")
                        LoggedButton("Limpar filtro") { action = "" }.loggedControl(control: "diagnostics.clear_action", label: "Limpar filtro")
                    }
                }
                Section("Mensagem") {
                    Text(entry.message).textSelection(.enabled)
                }
                if !entry.context.isEmpty {
                    Section("Contexto") {
                        ForEach(entry.context.keys.sorted(), id: \.self) { key in
                            LabeledContent(key) { Text(entry.context[key] ?? "").textSelection(.enabled) }
                        }
                    }
                }
                if let report = entry.context["report"] {
                    Section("Relatório de crash") {
                        LoggedButton("Abrir no Console", systemImage: "exclamationmark.triangle") {
                            NSWorkspace.shared.open(URL(fileURLWithPath: report))
                        }.loggedControl(control: "diagnostics_view.button_4", label: "Abrir no Console")
                    }
                }
            }
            .formStyle(.grouped)
        } else {
            ContentUnavailableView("Selecione uma entrada", systemImage: "list.bullet.rectangle")
        }
    }

    private func reload() async {
        let filter = filter
        let loaded = await Task.detached { LogStore.default.entries(filter) }.value
        if loaded != entries { entries = loaded }
    }

    private func copyReport() {
        let text = LogStore.default.report(filter, header: "Relatório de diagnóstico do VibeDeck \(AppDelegate.version)")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static func symbol(_ level: LogLevel) -> String {
        switch level {
        case .debug: "ant"
        case .info: "info.circle"
        case .warning: "exclamationmark.triangle"
        case .error: "xmark.octagon"
        case .crash: "bolt.trianglebadge.exclamationmark"
        }
    }

    static func color(_ level: LogLevel) -> Color {
        switch level {
        case .debug, .info: .secondary
        case .warning: .orange
        case .error, .crash: .red
        }
    }
}
