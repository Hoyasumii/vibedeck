import MarkdownUI
import SwiftUI
import VibeDeckCore

/// Claude Code conversation, shown as a page (and tab) of the detail column.
struct ClaudeChatPage: View {
    @Environment(AISession.self) private var claude
    @State private var pickingMention = false
    @State private var pickingFiles = false
    @State private var droppingFiles = false
    @State private var launchingCloud = false
    @State private var showingUsage = false
    @State private var selection = 0
    /// Draft whose suggestions were dismissed with Esc.
    @State private var dismissed: String?
    @FocusState private var inputFocused: Bool

    /// Readable line length for the transcript and composer in a wide detail column.
    private static let columnWidth: CGFloat = 760

    private var draft: String {
        get { claude.draft }
        nonmutating set { claude.draft = newValue }
    }

    private var mentions: [UUID] {
        get { claude.draftMentions }
        nonmutating set { claude.draftMentions = newValue }
    }

    private var attachments: [URL] {
        get { claude.draftAttachments }
        nonmutating set { claude.draftAttachments = newValue }
    }

    private var canSend: Bool {
        if isShellMode { return draft != "!" }
        return !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
    }

    var body: some View {
        Group {
            if claude.current == nil {
                ClaudeChatList()
            } else {
                chat
            }
        }
        .background(.background)
        .toolbar {
            ToolbarItemGroup {
                Button { showingUsage = true } label: { Label("Consumo de IA", systemImage: "chart.bar") }
                if !mentions.isEmpty {
                    Toggle("Incluir conversas completas", isOn: Binding(get: { claude.includeFullMentions }, set: { claude.includeFullMentions = $0 }))
                        .help("Desligado: a IA recebe referências e lê trechos conforme necessário")
                }
                if claude.isWorking {
                    Button { claude.interrupt() } label: { Label("Parar", systemImage: "stop.fill") }
                        .help("Interromper a resposta")
                }
                if claude.current != nil {
                    Button { claude.leaveChat() } label: { Label("Conversas", systemImage: "bubble.left.and.text.bubble.right") }
                        .help("Ver todas as conversas")
                }
                Button { launchingCloud = true } label: { Label("Sessão na nuvem", systemImage: "cloud") }
                    .help("Criar uma sessão na nuvem com o provedor selecionado")
                Button { claude.newChat() } label: { Label("Nova conversa", systemImage: "square.and.pencil") }
                    .help("Começar uma nova conversa")
            }
        }
        .sheet(isPresented: $showingUsage) { AIUsageHistoryView(root: claude.root) }
        .sheet(isPresented: $launchingCloud) { CloudLaunchSheet(root: claude.root, provider: claude.provider) }
        .onChange(of: claude.current?.id) { inputFocused = true }
    }

    private var chat: some View {
        VStack(spacing: 0) {
            ClaudeChatHeader()
            Divider()
            transcript
            if let request = claude.pending.first {
                Group {
                    if request.isQuestion {
                        QuestionCard(request: request)
                    } else if request.isPlanApproval {
                        PlanCard(request: request)
                    } else {
                        PermissionCard(request: request)
                    }
                }
                .id(request.id)
                .padding([.horizontal, .top], 10)
                .frame(maxWidth: Self.columnWidth)
            }
            if let error = claude.usageError { Text(error).font(.caption).foregroundStyle(.red) }
            composer
        }
        .onAppear { inputFocused = true; claude.loadProjectFiles() }
    }

    // MARK: Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if claude.entries.isEmpty {
                        emptyState
                    }
                    ForEach(claude.entries) { entry in
                        EntryView(entry: entry)
                    }
                    if claude.isWorking, claude.pending.isEmpty {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text(claude.isThinking ? "Pensando…" : "Trabalhando…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(12)
                .textSelection(.enabled)
                .frame(maxWidth: Self.columnWidth)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: claude.entries) { proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: claude.pending.count) { proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.largeTitle)
                .foregroundStyle(.tint)
            Text("Converse com \(claude.provider.title) neste projeto")
                .font(.headline)
            Text("Ele lê o código, segue as regras do VibeDeck e pede sua permissão antes de editar arquivos ou rodar comandos.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !mentions.isEmpty {
                MentionChips(mentions: Bindable(claude).draftMentions)
                    .padding(.horizontal, 4)
            }
            if !attachments.isEmpty {
                AttachmentChips(files: Bindable(claude).draftAttachments)
                    .padding(.horizontal, 4)
            }
            if !suggestions.isEmpty {
                SuggestionList(suggestions: suggestions, selection: $selection, onPick: accept)
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField(isShellMode ? "Comando de terminal (roda no projeto)" : "Pergunte ou peça algo à IA (/ comandos, @ arquivos e conversas, ! terminal)", text: Bindable(claude).draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...8)
                    .focused($inputFocused)
                    .onSubmit(send)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .glassEffect(isShellMode ? .regular.tint(.orange.opacity(0.35)) : .regular, in: .rect(cornerRadius: 12))
                    .onChange(of: draft) { selection = 0 }
                    .onKeyPress(.upArrow) { moveSelection(-1) }
                    .onKeyPress(.downArrow) { moveSelection(1) }
                    .onKeyPress(.tab) { accept() }
                    .onKeyPress(.return) { suggestions.isEmpty ? .ignored : accept() }
                    .onKeyPress(.escape) { dismissSuggestions() }
                    .popover(isPresented: $pickingMention, arrowEdge: .top) {
                        MentionPicker(mentions: Bindable(claude).draftMentions) {
                            if draft.hasSuffix("@") { draft.removeLast() }
                            pickingMention = false
                            inputFocused = true
                        }
                    }
                Button { pickingFiles = true } label: { Image(systemName: "paperclip") }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .help("Anexar arquivos: a IA recebe o caminho deles (nada é copiado). Também dá para arrastar.")
                    .fileImporter(isPresented: $pickingFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                        if case .success(let urls) = result { addAttachments(urls) }
                    }
                Button { pickingMention = true } label: { Image(systemName: "at") }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .help("Mencionar outra conversa (vai inteira, em JSON, como referência)")
                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .fontWeight(.semibold)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .disabled(!canSend)
                .keyboardShortcut(.return, modifiers: .command)
                .help("Enviar (↩)")
            }
            // One compressible row: labels truncate so a narrow detail column never overflows.
            HStack(spacing: 10) {
                pickers
                Text("⌥↩ quebra linha")
                    .lineLimit(1)
                    .layoutPriority(-1)
                Spacer(minLength: 0)
                if let cost = claude.lastCost {
                    Text(cost, format: .currency(code: "USD").precision(.fractionLength(2...4)))
                        .help("Custo acumulado desta conversa")
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 4)
        }
        .padding(10)
        .frame(maxWidth: Self.columnWidth)
        .overlay {
            if droppingFiles {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(.tint, style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            addAttachments(files)
            return !files.isEmpty
        } isTargeted: { droppingFiles = $0 }
    }

    private func addAttachments(_ urls: [URL]) {
        attachments += urls.filter { !attachments.contains($0) }
        inputFocused = true
    }

    @ViewBuilder
    private var pickers: some View {
        modePicker
        if claude.provider == .codex {
            Toggle("Auto", isOn: Bindable(claude).codexAutoReview)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .fixedSize()
                .disabled(claude.isWorking)
                .accessibilityLabel("Aprovação automática do Codex")
                .help("O Codex revisa automaticamente os pedidos de permissão, mantendo as restrições de acesso. A escolha é salva para as próximas conversas. Altere entre respostas.")
            Menu {
                Picker("Modelo", selection: Bindable(claude).codexModel) {
                    Text("Automático").tag("")
                    ForEach(claude.codexModels) { Text($0.title).tag($0.id) }
                }
            } label: { Label(claude.codexModel.isEmpty ? "Automático" : claude.codexModel, systemImage: "cpu") }
            .menuStyle(.button).buttonStyle(.plain).lineLimit(1)
            Menu {
                Picker("Esforço", selection: Bindable(claude).codexEffort) {
                    Text("Automático").tag("")
                    ForEach(claude.availableCodexEfforts, id: \.self) { Text($0).tag($0) }
                }
            } label: { Label(claude.codexEffort.isEmpty ? "Automático" : claude.codexEffort, systemImage: "gauge.with.dots.needle.50percent") }
            .menuStyle(.button).buttonStyle(.plain).lineLimit(1)
        } else {
            modelPicker
            effortPicker
        }
    }

    private var modePicker: some View {
        Menu {
            Picker("Modo", selection: Binding(get: { claude.permissionMode }, set: { claude.setPermissionMode($0) })) {
                ForEach(ClaudePermissionMode.allCases.filter { claude.provider == .claude || $0 != .auto }, id: \.self) { mode in
                    Label(mode.label, systemImage: mode.symbol).tag(mode)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label(claude.permissionMode.label, systemImage: claude.permissionMode.symbol)
                .foregroundStyle(claude.permissionMode == .default ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .lineLimit(1)
        .help(claude.provider == .claude ? claude.permissionMode.help : claude.permissionMode == .plan ? "Explora em modo somente leitura e propõe um plano" : "Pode editar o projeto; comandos seguem as aprovações e restrições do Codex")
    }

    private var modelPicker: some View {
        Menu {
            Picker("Modelo", selection: Binding(get: { claude.chosenModel }, set: { claude.setModel($0) })) {
                ForEach(ClaudeModel.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            Label(claude.chosenModel.label, systemImage: "cpu")
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .lineLimit(1)
        .help("Modelo do Claude (vale a partir da próxima mensagem)")
    }

    private var effortPicker: some View {
        Menu {
            Picker("Effort", selection: Binding(get: { claude.effort }, set: { claude.setEffort($0) })) {
                ForEach(ClaudeEffort.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            Label(claude.effort.label, systemImage: "gauge.with.dots.needle.50percent")
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .lineLimit(1)
        .help("Esforço de raciocínio (vale a partir da próxima mensagem)")
    }

    // MARK: Autocomplete

    /// `!` at the start of the draft runs it in the terminal instead of sending it to Claude.
    private var isShellMode: Bool { draft.hasPrefix("!") }

    private var trigger: ClaudeTrigger? { isShellMode || dismissed == draft ? nil : ClaudeCompletion.trigger(in: draft) }

    private var suggestions: [ClaudeSuggestion] {
        guard let trigger else { return [] }
        let list = claude.suggestions(for: trigger, mentioned: mentions)
        // Nothing left to complete once the command is typed in full.
        if trigger.kind == .command, list.count == 1, list[0].name == draft { return [] }
        return list
    }

    private func moveSelection(_ delta: Int) -> KeyPress.Result {
        let count = suggestions.count
        guard count > 0 else { return .ignored }
        selection = (selection + delta + count) % count
        return .handled
    }

    private func dismissSuggestions() -> KeyPress.Result {
        guard !suggestions.isEmpty else { return .ignored }
        dismissed = draft
        return .handled
    }

    private func accept() -> KeyPress.Result {
        let list = suggestions
        guard let trigger, list.indices.contains(selection) else { return .ignored }
        accept(list[selection], trigger: trigger)
        return .handled
    }

    private func accept(_ suggestion: ClaudeSuggestion) {
        if let trigger { accept(suggestion, trigger: trigger) }
    }

    private func accept(_ suggestion: ClaudeSuggestion, trigger: ClaudeTrigger) {
        switch suggestion.kind {
        case .command: draft.replaceSubrange(trigger.range, with: suggestion.name + " ")
        case .file: draft.replaceSubrange(trigger.range, with: "@" + suggestion.name + (suggestion.name.hasSuffix("/") ? "" : " "))
        case .chat:
            draft.removeSubrange(trigger.range)
            if let id = suggestion.chatId, !mentions.contains(id) { mentions.append(id) }
        }
        inputFocused = true
    }

    private func send() {
        if !suggestions.isEmpty, accept() == .handled { return }
        let text = draft
        guard canSend else { return }
        draft = ""
        if text.hasPrefix("!") {
            claude.runShell(String(text.dropFirst()))
            return
        }
        if text.trimmingCharacters(in: .whitespacesAndNewlines) == "/clear", let id = claude.current?.id {
            claude.clear(id)
            mentions = []
            attachments = []
            return
        }
        claude.send(text, mentions: mentions, attachments: attachments)
        mentions = []
        attachments = []
    }
}

extension ClaudePermissionMode {
    var label: String {
        switch self {
        case .default: "Normal"
        case .plan: "Planejar"
        case .acceptEdits: "Aceitar edições"
        case .auto: "Auto"
        }
    }

    var symbol: String {
        switch self {
        case .default: "hand.raised"
        case .plan: "list.bullet.clipboard"
        case .acceptEdits: "pencil.and.outline"
        case .auto: "sparkles"
        }
    }

    var help: String {
        switch self {
        case .default: "Normal: o Claude pede permissão antes de editar arquivos ou rodar comandos"
        case .plan: "Planejar: o Claude só lê e pesquisa, e apresenta um plano para você aprovar antes de mudar algo"
        case .acceptEdits: "Aceitar edições: edições de arquivo passam direto; comandos ainda pedem permissão"
        case .auto: "Auto: o Claude roda edições e comandos sem perguntar, mas ainda pede confirmação em ações arriscadas"
        }
    }
}

extension ClaudeModel {
    var label: String {
        switch self {
        case .automatic: "Modelo padrão"
        case .fable: "Fable"
        case .opus: "Opus"
        case .sonnet: "Sonnet"
        case .haiku: "Haiku"
        }
    }
}

extension ClaudeEffort {
    var label: String {
        switch self {
        case .automatic: "Effort padrão"
        case .low: "Baixo"
        case .medium: "Médio"
        case .high: "Alto"
        case .xhigh: "Muito alto"
        case .max: "Máximo"
        }
    }
}

extension Theme {
    /// Compact theme for the chat: system body size, no page background, light code styling.
    @MainActor static let chat = Theme()
        .text {
            FontSize(NSFont.systemFontSize)
        }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(.em(0.9))
            BackgroundColor(Color.secondary.opacity(0.15))
        }
        .strong { FontWeight(.semibold) }
        .link { ForegroundColor(.accentColor) }
        .heading1 { heading($0, size: 1.3) }
        .heading2 { heading($0, size: 1.2) }
        .heading3 { heading($0, size: 1.1) }
        .heading4 { heading($0, size: 1) }
        .heading5 { heading($0, size: 1) }
        .heading6 { heading($0, size: 1) }
        .paragraph { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .relativeLineSpacing(.em(0.15))
                .markdownMargin(top: 0, bottom: 8)
        }
        .blockquote { configuration in
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(.quaternary)
                    .frame(width: 3)
                configuration.label
                    .markdownTextStyle { ForegroundColor(.secondary) }
                    .padding(.leading, 8)
            }
            .fixedSize(horizontal: false, vertical: true)
            .markdownMargin(top: 0, bottom: 8)
        }
        .codeBlock { configuration in
            ScrollView(.horizontal) {
                configuration.label
                    .fixedSize(horizontal: false, vertical: true)
                    .relativeLineSpacing(.em(0.2))
                    .markdownTextStyle {
                        FontFamilyVariant(.monospaced)
                        FontSize(.em(0.9))
                    }
                    .padding(8)
            }
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 6))
            .markdownMargin(top: 0, bottom: 8)
        }
        .listItem { configuration in
            configuration.label.markdownMargin(top: .em(0.2))
        }
        .table { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .markdownTableBorderStyle(.init(color: .secondary.opacity(0.3)))
                .markdownMargin(top: 0, bottom: 8)
        }
        .tableCell { configuration in
            configuration.label
                .markdownTextStyle { if configuration.row == 0 { FontWeight(.semibold) } }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
        }
        .thematicBreak {
            Divider().markdownMargin(top: 8, bottom: 8)
        }

    @MainActor private static func heading(_ configuration: BlockConfiguration, size: Double) -> some View {
        configuration.label
            .markdownMargin(top: 12, bottom: 6)
            .markdownTextStyle {
                FontWeight(.semibold)
                FontSize(.em(size))
            }
    }
}

// MARK: - Entries

private struct EntryView: View {
    @Environment(AISession.self) private var claude
    let entry: AISession.Entry

    var body: some View {
        switch entry.kind {
        case .user(let text):
            HStack {
                Spacer(minLength: 32)
                VStack(alignment: .trailing, spacing: 4) {
                    ForEach(entry.mentions, id: \.self) { id in
                        Label("@" + (claude.title(of: id) ?? "conversa apagada"), systemImage: "bubble.left.and.text.bubble.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    ForEach(entry.attachments, id: \.self) { path in
                        Label(URL(fileURLWithPath: path).lastPathComponent, systemImage: "paperclip")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .help(path)
                    }
                    if !text.isEmpty { Text(text) }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.tint.opacity(0.15), in: .rect(cornerRadius: 12))
            }
        case .assistant(let text):
            Markdown(text)
                .markdownTheme(.chat)
        case .tool(let name, let summary, let result, let isError):
            ToolRow(name: name, summary: summary, result: result, isError: isError)
        case .notice(let text):
            Label(text, systemImage: "clock.arrow.circlepath")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .error(let text):
            Label(text, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.red)
        }
    }
}

private struct ToolRow: View {
    let name: String
    let summary: String
    let result: String?
    let isError: Bool
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button { expanded.toggle() } label: {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .foregroundStyle(isError ? .red : .secondary)
                        .frame(width: 14)
                    Text(name).fontWeight(.medium)
                    Text(summary)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                    if result != nil {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                    }
                }
                .font(.caption)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(result == nil)
            .help(summary)

            if expanded, let result {
                ScrollView {
                    Text(result.isEmpty ? "(sem saída)" : result)
                        .font(.caption.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(maxHeight: 180)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
            }
        }
    }

    private var icon: String {
        if result == nil { return "circle.dotted" }
        if isError { return "xmark.circle" }
        return "checkmark.circle"
    }
}

// MARK: - Pending requests

private struct PermissionCard: View {
    @Environment(AISession.self) private var claude
    let request: ClaudePermissionRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("\(claude.provider.title) quer usar \(AISession.toolTitle(request.toolName))", systemImage: "hand.raised.fill")
                .font(.callout.weight(.semibold))
            if let description = request.description, !description.isEmpty {
                Text(description).font(.callout).foregroundStyle(.secondary)
            }
            detail
            HStack {
                Button("Negar", role: .cancel) { claude.decide(request, .deny) }
                    .keyboardShortcut(.escape, modifiers: [])
                Spacer()
                Menu("Sempre") {
                    Button("Nesta sessão") { claude.decide(request, .allowSession) }
                        .help(rules(.session))
                    if claude.canRemember(request) { Button("Em todas as sessões") { claude.decide(request, .allowAlways) }
                        .help(claude.provider == .claude ? "Grava em .claude/settings.local.json: " + rules(.localSettings) : "Salva a regra de comando proposta pelo Codex") }
                }
                .fixedSize()
                .help("Libera sem perguntar de novo: " + rules(.session))
                Button("Permitir") { claude.decide(request, .allowOnce) }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }

    private func rules(_ scope: ClaudeInput.RuleScope) -> String {
        ClaudeInput.ruleLabels(for: request, scope: scope).joined(separator: ", ")
    }

    @ViewBuilder
    private var detail: some View {
        let input = request.input
        if let changes = input["changes"]?.array, !changes.isEmpty {
            ForEach(Array(changes.enumerated()), id: \.offset) { _, change in
                Text(change["path"]?.string ?? "Arquivo").font(.caption.monospaced())
                code(change["diff"]?.string ?? "")
            }
        } else if let permissions = input["permissions"] {
            code(String(decoding: (try? JSONEncoder().encode(permissions)) ?? Data(), as: UTF8.self))
        } else if let command = input["command"]?.string {
            code(command)
        } else if let path = input["file_path"]?.string {
            VStack(alignment: .leading, spacing: 4) {
                Text(AISession.summary(["file_path": .string(path)], root: claude.root))
                    .font(.caption.monospaced())
                if let old = input["old_string"]?.string, let new = input["new_string"]?.string {
                    code(old, prefix: "−", color: .red)
                    code(new, prefix: "+", color: .green)
                } else if let content = input["content"]?.string {
                    code(content)
                }
            }
        } else {
            Text(AISession.summary(input, root: claude.root))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
    }

    private func code(_ text: String, prefix: String? = nil, color: Color? = nil) -> some View {
        ScrollView {
            Text(text.split(separator: "\n", omittingEmptySubsequences: false).map { "\(prefix.map { "\($0) " } ?? "")\($0)" }.joined(separator: "\n"))
                .font(.caption.monospaced())
                .foregroundStyle(color ?? .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
        }
        .frame(maxHeight: 140)
        .fixedSize(horizontal: false, vertical: true)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
    }
}

private struct PlanCard: View {
    @Environment(AISession.self) private var claude
    let request: ClaudePermissionRequest
    @State private var askingChanges = false
    @State private var feedback = ""
    @FocusState private var feedbackFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Plano pronto para aprovação", systemImage: "list.bullet.clipboard.fill")
                .font(.callout.weight(.semibold))
            ScrollView {
                Markdown(request.plan ?? "")
                    .markdownTheme(.chat)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 340)
            .fixedSize(horizontal: false, vertical: true)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))

            if askingChanges {
                TextField("O que mudar no plano?", text: $feedback, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...6)
                    .focused($feedbackFocused)
                    .onAppear { feedbackFocused = true }
                HStack {
                    Button("Voltar", role: .cancel) { askingChanges = false }
                    Spacer()
                    Button("Enviar mudanças") { claude.requestPlanChanges(request, feedback: feedback) }
                        .buttonStyle(.glassProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } else {
                HStack {
                    Button("Pedir mudanças") { askingChanges = true }
                    Spacer()
                    Button("Aprovar") { claude.approvePlan(request, then: nil) }
                        .help("Executa o plano, pedindo permissão para cada edição e comando")
                    Button("Aprovar e aceitar edições") { claude.approvePlan(request, then: .acceptEdits) }
                        .help("Executa o plano sem pedir permissão para cada edição de arquivo (comandos ainda pedem)")
                    Button("Aprovar em modo auto") { claude.approvePlan(request, then: .auto) }
                        .buttonStyle(.glassProminent)
                        .keyboardShortcut(.defaultAction)
                        .help("Executa o plano em modo auto: edições e comandos rodam sem perguntar, só ações arriscadas pedem confirmação")
                }
            }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }
}

private struct QuestionCard: View {
    @Environment(AISession.self) private var claude
    let request: ClaudePermissionRequest
    /// Chosen labels per question text.
    @State private var chosen: [String: Set<String>] = [:]
    /// Free-text answer per question text ("Outro").
    @State private var other: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("\(claude.provider.title) tem uma pergunta", systemImage: "questionmark.bubble.fill")
                .font(.callout.weight(.semibold))
            ForEach(request.questions, id: \.question) { question in
                VStack(alignment: .leading, spacing: 6) {
                    if let header = question.header {
                        Text(header.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    Text(question.question).font(.callout)
                    ForEach(question.options, id: \.label) { option in
                        optionButton(option, in: question)
                    }
                    TextField("Outro…", text: Binding(
                        get: { other[question.question, default: ""] },
                        set: { value in
                            other[question.question] = value
                            if !question.multiSelect, !value.isEmpty { chosen[question.question] = [] }
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.callout)
                }
            }
            HStack {
                Button("Não responder", role: .cancel) { claude.decline(request) }
                Spacer()
                Button("Responder") { claude.answer(request, answers) }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(answers.count < request.questions.count)
            }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }

    private func optionButton(_ option: ClaudeQuestion.Option, in question: ClaudeQuestion) -> some View {
        let selected = chosen[question.question, default: []].contains(option.label)
        return Button {
            var set = chosen[question.question, default: []]
            if question.multiSelect {
                if selected { set.remove(option.label) } else { set.insert(option.label) }
            } else {
                set = [option.label]
                other[question.question] = ""
            }
            chosen[question.question] = set
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: question.multiSelect
                    ? (selected ? "checkmark.square.fill" : "square")
                    : (selected ? "largecircle.fill.circle" : "circle"))
                    .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label)
                    if let description = option.description {
                        Text(description).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .background(selected ? AnyShapeStyle(.tint.opacity(0.12)) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Answers in question order: chosen options (in the order offered) plus the free text, if any.
    private var answers: [String: [String]] {
        var result: [String: [String]] = [:]
        for question in request.questions {
            let picked = question.options.map(\.label).filter { chosen[question.question, default: []].contains($0) }
            let free = other[question.question, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
            let all = picked + (free.isEmpty ? [] : [free])
            if !all.isEmpty { result[question.question] = all }
        }
        return result
    }
}


/// Autocomplete list shown above the composer, in the style of the Claude Code terminal.
private struct SuggestionList: View {
    let suggestions: [ClaudeSuggestion]
    @Binding var selection: Int
    let onPick: (ClaudeSuggestion) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, item in
                Button { onPick(item) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: symbol(item.kind))
                            .frame(width: 14)
                            .foregroundStyle(.secondary)
                        Text(item.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if let detail = item.detail {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(index == selection ? Color.accentColor.opacity(0.25) : .clear, in: .rect(cornerRadius: 6))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }

    private func symbol(_ kind: ClaudeSuggestion.Kind) -> String {
        switch kind {
        case .command: "slash.circle"
        case .file: "doc"
        case .chat: "bubble.left"
        }
    }
}
