import SwiftUI
import VibeDeckCore

struct AIProviderSettingsView: View {
    let settings: [String: AIProviderSettings]?
    let save: (String, AIProviderSettings) -> Void
    var body: some View {
        DisclosureGroup("Configurações por provedor") {
            ForEach(AIProvider.installed, id: \.self) { provider in
                HStack {
                    Text(provider.title).frame(width: 65, alignment: .leading)
                    CommitTextField("Modelo herdado", value: settings?[provider.rawValue]?.model ?? "") { value in
                        var next = settings?[provider.rawValue] ?? AIProviderSettings()
                        next.model = value.isEmpty ? nil : value
                        save(provider.rawValue, next)
                    }
                    CommitTextField("Esforço padrão", value: settings?[provider.rawValue]?.effort ?? "") { value in
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
    @Environment(AISession.self) private var session
    @Environment(ProjectModel.self) private var model
    @State private var message: String?
    /// Provider waiting on the "take the conversation as reference" choice.
    @State private var providerReference: AIProvider?
    /// Direction of the last carousel move, so the card slides the right way.
    @State private var forward = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            carouselHeader
            usage
                .id(session.provider)
                .transition(.push(from: forward ? .trailing : .leading))
        }
        .clipped()
        .gesture(DragGesture(minimumDistance: 30).onEnded { drag in
            if abs(drag.translation.width) > abs(drag.translation.height) { step(drag.translation.width < 0 ? 1 : -1) }
        })
        .confirmationDialog("Nova conversa em outro provedor", isPresented: Binding(get: { providerReference != nil }, set: { if !$0 { providerReference = nil } })) {
            Button("Levar conversa anterior como referência") { if let providerReference { activate(providerReference, referencing: true) }; providerReference = nil }
            Button("Começar sem referência") { if let providerReference { activate(providerReference) }; providerReference = nil }
            Button("Cancelar", role: .cancel) { providerReference = nil }
        }
    }

    /// `‹ Claude Code ›` with one dot per provider; moving to another card switches the active AI.
    private var carouselHeader: some View {
        VStack(spacing: 4) {
            HStack {
                Button { step(-1) } label: { Image(systemName: "chevron.left") }
                    .disabled(!canStep)
                Spacer()
                Label(Self.name(session.provider), systemImage: Self.symbol(session.provider))
                    .font(.callout.weight(.semibold))
                    .id(session.provider)
                    .transition(.push(from: forward ? .trailing : .leading))
                Spacer()
                Button { step(1) } label: { Image(systemName: "chevron.right") }
                    .disabled(!canStep)
            }
            .buttonStyle(.borderless)
            HStack(spacing: 5) {
                ForEach(AIProvider.installed, id: \.self) { provider in
                    Button { select(provider) } label: {
                        Circle()
                            .fill(provider == session.provider ? AnyShapeStyle(.primary) : AnyShapeStyle(.quaternary))
                            .frame(width: 6, height: 6)
                    }
                    .buttonStyle(.plain)
                    .disabled(session.isWorking)
                    .help(Self.name(provider))
                }
            }
        }
        .help(session.isWorking ? "Aguarde a resposta terminar para trocar de IA" : "Trocar de IA")
    }

    private var canStep: Bool { !session.isWorking && AIProvider.installed.count > 1 }

    /// Next installed provider in `direction`, wrapping around.
    private func step(_ direction: Int) {
        guard canStep else { return }
        let all = AIProvider.allCases
        guard var index = all.firstIndex(of: session.provider) else { return }
        for _ in all.indices {
            index = (index + direction + all.count) % all.count
            if all[index].isInstalled { break }
        }
        select(all[index], forward: direction > 0)
    }

    private func select(_ provider: AIProvider, forward: Bool? = nil) {
        guard provider != session.provider, provider.isInstalled, !session.isWorking else { return }
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
            if session.provider == .claude, AIProvider.claude.isInstalled { ClaudeUsageView() }
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
                Button("Instalar MCP neste projeto") {
                    do {
                        guard let cli = ClaudeUsageView.cliPath else { throw CodexRPCError.server("Instale o CLI vibedeck para conectar o MCP.") }
                        if session.provider == .codex { try CodexMCP.install(root: model.store.root, cli: cli, force: true); message = "MCP instalado. Reinicie o cliente externo; o chat integrado conecta automaticamente." }
                        else { session.openTerminal(running: "vibedeck mcp install --scope project") }
                    } catch { message = error.localizedDescription }
                }
                Button("Instalar hook de regras") {
                    do {
                        let file = model.store.root.appending(path: session.provider == .codex ? ".codex/hooks.json" : ".claude/settings.local.json")
                        try ClaudeCode.installStopHook(executable: ClaudeUsageView.cliPath ?? "vibedeck", settings: file, sessionStart: session.provider == .codex)
                        message = session.provider == .codex ? "Hook instalado. Aprove-o com /hooks no Codex antes de usar." : "Hook instalado."
                    } catch { message = error.localizedDescription }
                }
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
        .alert("Integrações", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("OK") { message = nil } } message: { Text(message ?? "") }
    }
}
