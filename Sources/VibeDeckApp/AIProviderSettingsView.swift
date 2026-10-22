import SwiftUI

struct AIProviderSettingsView: View {
    @Environment(\.logProject) private var providerRoot
    let settings: [String: AIProviderSettings]?
    let save: (String, AIProviderSettings) -> Void
    var body: some View {
        DisclosureGroup("Configurações por provedor") {
            ForEach(AIProvider.installed(in: providerRoot), id: \.self) { provider in
                HStack {
                    Text(provider.title).frame(width: 65, alignment: .leading)
                    CommitTextField(control: "aiprovidersettingsview.field_1", "Modelo herdado", value: settings?[provider.rawValue]?.model ?? "") { value in
                        var next = settings?[provider.rawValue] ?? AIProviderSettings()
                        next.model = value.isEmpty ? nil : value
                        save(provider.rawValue, next)
                    }
                    CommitTextField(control: "aiprovidersettingsview.field_2", "Esforço padrão", value: settings?[provider.rawValue]?.effort ?? "") { value in
                        var next = settings?[provider.rawValue] ?? AIProviderSettings()
                        next.effort = value.isEmpty ? nil : value
                        save(provider.rawValue, next)
                    }
                }
                .textFieldStyle(.roundedBorder)
            }
        }
        .font(.caption)
    }
}

struct AIUsageView: View {
    @Environment(\.logProject) private var providerRoot
    private enum Sheet: String, Identifiable {
        case history, guide
        var id: String { rawValue }
    }

    @Environment(AISession.self) private var session
    @Environment(ProjectModel.self) private var model
    @State private var sheet: Sheet?
    @State private var message: String?
    /// Provider waiting on the "take the conversation as reference" choice.
    @State private var providerReference: AIProvider?
    /// Direction of the last carousel move, so the card slides the right way.
    @State private var forward = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            carouselHeader
            HStack {
                LoggedButton("Consumo por tarefa") { sheet = .history }.loggedControl(control: "aiprovider_settings_view.button_1", label: "Consumo por tarefa")
                Spacer()
                LoggedButton("Guia de IA") { sheet = .guide }.loggedControl(control: "aiprovider_settings_view.button_2", label: "Guia de IA")
            }.font(.caption).buttonStyle(.borderless)
            usage
                .id(session.provider)
                .transition(.push(from: forward ? .trailing : .leading))
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .history: AIUsageHistoryView(root: session.root)
            case .guide: AIGuideView()
            }
        }
        .clipped()
        .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { drag in
            if abs(drag.translation.width) > abs(drag.translation.height) { step(drag.translation.width < 0 ? 1 : -1) }
        })
        .confirmationDialog("Nova conversa em outro provedor", isPresented: Binding(get: { providerReference != nil }, set: { if !$0 { providerReference = nil } })) {
            LoggedButton("Levar conversa anterior como referência") { if let providerReference { activate(providerReference, referencing: true) }; providerReference = nil }.loggedControl(control: "aiprovider_settings_view.button_3", label: "Levar conversa anterior como referência")
            LoggedButton("Começar sem referência") { if let providerReference { activate(providerReference) }; providerReference = nil }.loggedControl(control: "aiprovider_settings_view.button_4", label: "Começar sem referência")
            LoggedButton("Cancelar", role: .cancel) { providerReference = nil }.loggedControl(control: "aiprovider_settings_view.button_5", label: "Cancelar")
        }
    }

    /// `‹ Claude Code ›` with one dot per provider; moving to another card switches the active AI.
    private var carouselHeader: some View {
        VStack(spacing: 4) {
            HStack {
                LoggedButton { step(-1) } label: { Image(systemName: "chevron.left") }.loggedControl(control: "aiprovider_settings_view.button_6", label: "Ativar controle")
                    .disabled(!canStep)
                Spacer()
                Label(Self.name(session.provider), systemImage: Self.symbol(session.provider))
                    .font(.callout.weight(.semibold))
                    .id(session.provider)
                    .transition(.push(from: forward ? .trailing : .leading))
                Spacer()
                LoggedButton { step(1) } label: { Image(systemName: "chevron.right") }.loggedControl(control: "aiprovider_settings_view.button_7", label: "Ativar controle")
                    .disabled(!canStep)
            }
            .buttonStyle(.borderless)
            HStack(spacing: 5) {
                ForEach(AIProvider.installed(in: providerRoot), id: \.self) { provider in
                    LoggedButton { select(provider) } label: {
                        Circle()
                            .fill(provider == session.provider ? AnyShapeStyle(.primary) : AnyShapeStyle(.quaternary))
                            .frame(width: 6, height: 6)
                    }.loggedControl(control: "aiprovider_settings_view.button_8", label: "Ativar controle")
                    .buttonStyle(.plain)
                    .disabled(session.isWorking)
                    .help(Self.name(provider))
                }
            }
        }
        .help(session.isWorking ? "Aguarde a resposta terminar para trocar de IA" : "Trocar de IA")
    }

    private var canStep: Bool { !session.isWorking && AIProvider.installed(in: providerRoot).count > 1 }

    /// Next installed provider in `direction`, wrapping around.
    private func step(_ direction: Int) {
        guard canStep else { return }
        let all = AIProvider.allCases
        guard var index = all.firstIndex(of: session.provider) else { return }
        for _ in all.indices {
            index = (index + direction + all.count) % all.count
            if AIProvider.installed(in: providerRoot).contains(all[index]) { break }
        }
        select(all[index], forward: direction > 0)
    }

    private func select(_ provider: AIProvider, forward: Bool? = nil) {
        guard provider != session.provider, AIProvider.installed(in: providerRoot).contains(provider), !session.isWorking else { return }
        let all = AIProvider.allCases
        self.forward = forward ?? ((all.firstIndex(of: provider) ?? 0) > (all.firstIndex(of: session.provider) ?? 0))
        if session.current?.messages.isEmpty == false { providerReference = provider }
        else { activate(provider) }
    }

    private func activate(_ provider: AIProvider, referencing: Bool = false) {
        withAnimation(.snappy(duration: 0.25)) { session.selectProvider(provider, referencing: referencing) }
    }

    private static func name(_ provider: AIProvider) -> String { provider == .claude ? "Claude Code" : provider.title }
    private static func symbol(_ provider: AIProvider) -> String { provider == .claude ? "sparkles" : "terminal" }

    private var usage: some View {
        VStack(alignment: .leading, spacing: 6) {
            if session.provider == .claude, AIProvider.claude.isInstalled, RemoteWorkspace.existing(at: session.root) == nil { ClaudeUsageView() }
            if session.provider == .codex {
                ForEach(session.codexLimits) { limit in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Codex · \(Int(limit.minutes)) min")
                            Spacer()
                            Text("\(Int(limit.usedPercent))%")
                        }
                        ProgressView(value: min(100, max(0, limit.usedPercent)), total: 100)
                        if let reset = limit.resetsAt { Text("Reinicia \(reset.formatted(date: .abbreviated, time: .shortened))").foregroundStyle(.secondary) }
                    }
                }
                if session.codexLimits.isEmpty { Text(session.codexStatus ?? "Consultando limites do Codex…").foregroundStyle(.secondary) }
            }
            Menu("Integrações de \(session.provider.title)") {
                LoggedButton("Instalar MCP neste projeto") {
                    do {
                        guard let cli = ClaudeUsageView.cliPath else { throw CodexRPCError.server("Instale o CLI vibedeck para conectar o MCP.") }
                        if session.provider == .codex { try CodexMCP.install(root: model.store.root, cli: cli, force: true); message = "MCP instalado. Reinicie o cliente externo; o chat integrado conecta automaticamente." }
                        else { session.openTerminal(running: "vibedeck mcp install --scope project") }
                    } catch { message = error.localizedDescription }
                }.loggedControl(control: "aiprovider_settings_view.button_9", label: "Instalar MCP neste projeto")
                LoggedButton("Instalar hook de regras") {
                    do {
                        let file = model.store.root.appending(path: session.provider == .codex ? ".codex/hooks.json" : ".claude/settings.local.json")
                        try ClaudeCode.installStopHook(executable: ClaudeUsageView.cliPath ?? "vibedeck", settings: file, sessionStart: session.provider == .codex)
                        message = session.provider == .codex ? "Hook instalado. Aprove-o com /hooks no Codex antes de usar." : "Hook instalado."
                    } catch { message = error.localizedDescription }
                }.loggedControl(control: "aiprovider_settings_view.button_10", label: "Instalar hook de regras")
            }
            .menuStyle(.borderlessButton)
        }
        .font(.caption)
        .task(id: session.provider) {
            if session.provider == .codex { session.refreshCodex() }
            while !Task.isCancelled {
                if session.provider == .codex { await session.updateCodexLimits() }
                do { try await Task.sleep(for: .seconds(30)) } catch { break }
            }
        }
        .alert("Integrações", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { LoggedButton("OK") { message = nil }.loggedControl(control: "aiprovider_settings_view.button_11", label: "OK") } message: { Text(message ?? "") }
    }
}
