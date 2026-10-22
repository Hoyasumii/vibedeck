import SwiftUI

/// Indicador de ambiente SSH da barra de status (prancha 19): SSH conectado, Reconectando (próxima tentativa em Ns)
/// ou Offline (somente leitura). O Core roda no servidor (MCP por SSH); o estado vem do `RemoteLink` do modelo.
struct V2RemoteEnvironmentSegment: View {
    let link: RemoteLink
    @State private var showing = false
    @Environment(AISession.self) private var claude

    private var host: String { link.host }

    private func seconds(until date: Date, now: Date) -> Int {
        max(0, Int(date.timeIntervalSince(now).rounded(.up)))
    }

    private func detail(now: Date) -> String {
        switch link.state {
        case .connected: return "conectado"
        case .connecting: return "reconectando…"
        case .waiting(let until): return "reconectando · próxima tentativa em \(seconds(until: until, now: now))s"
        case .offline: return "offline (somente leitura)"
        }
    }

    private var dot: Color {
        link.isConnected ? DesignTokens.Colors.done : DesignTokens.Colors.brand
    }

    private var tint: Color {
        link.isConnected ? DesignTokens.Colors.inkMuted : DesignTokens.Colors.brandText
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            segment(now: context.date)
        }
        .foregroundStyle(tint)
        .popover(isPresented: $showing) { panel }
        .sheet(isPresented: credentialsBinding) { credentialsSheet }
    }

    private func segment(now: Date) -> some View {
        V2StatusSegment(control: "v2_status_bar.environment", label: "Estado da conexão SSH") {
            showing.toggle()
        } content: {
            VDIcon(.terminal, size: 13)
            Text("SSH · " + host)
            HStack(spacing: DesignTokens.Space.s1) {
                Circle().fill(dot).frame(width: 6, height: 6)
                Text(detail(now: now))
            }
        }
        .accessibilityLabel("Ambiente: SSH em \(host), \(detail(now: now))")
    }

    private var credentialsBinding: Binding<Bool> {
        Binding(get: { link.credentials }, set: { link.credentials = $0 })
    }

    private var passwordBinding: Binding<String> {
        Binding(get: { link.password }, set: { link.password = $0 })
    }

    private var rememberBinding: Binding<Bool> {
        Binding(get: { link.remember }, set: { link.remember = $0 })
    }

    // MARK: Painel de estado

    private var summary: String {
        switch link.state {
        case .connected: return "Conectado. O Core roda no servidor e as edições são gravadas lá."
        case .connecting: return "Conectando…"
        case .waiting: return "Sem conexão. Reconectando automaticamente (1, 2, 4… até 60 s). Somente leitura até reconectar."
        case .offline: return "Offline. Somente leitura: a última leitura está em cache neste Mac."
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.s2) {
            Text(link.workspace.destination.title)
                .font(DesignTokens.Typography.headline)
                .textSelection(.enabled)
            Text(summary).font(DesignTokens.Typography.callout)
            actions
            if let error = link.error {
                Text(error)
                    .font(DesignTokens.Typography.callout)
                    .foregroundStyle(DesignTokens.Colors.fix)
                    .textSelection(.enabled)
            }
            Text("Para autenticar a IA, abra o Terminal SSH e execute claude ou codex no servidor.")
                .font(DesignTokens.Typography.callout)
                .foregroundStyle(DesignTokens.Colors.inkMuted)
        }
        .padding(DesignTokens.Space.s3)
        .frame(width: 380)
    }

    private var actions: some View {
        HStack {
            LoggedButton("Reconectar") { link.reconnectNow() }
                .loggedControl(control: "v2_ssh.reconnect", label: "Reconectar")
                .disabled(link.isConnected)
            LoggedButton("Senha…") { link.credentials = true }
                .loggedControl(control: "v2_ssh.password", label: "Senha")
            LoggedButton("Terminal SSH") { claude.openTerminal() }
                .loggedControl(control: "v2_ssh.terminal", label: "Terminal SSH")
        }
    }

    private var credentialsSheet: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.s4) {
            Text("Reconectar ao servidor").font(DesignTokens.Typography.headline)
            SecureField("Senha ou frase secreta", text: passwordBinding)
            Toggle("Guardar no Chaves do macOS", isOn: rememberBinding.logging(control: "v2_ssh.remember", label: "Guardar no Chaves do macOS", project: link.workspace.root))
            LoggedButton("Conectar") {
                do { try SSHCredentials.store(link.remember ? link.password : nil, for: link.workspace.destination) }
                catch { link.error = error.localizedDescription; return }
                link.credentials = false
                link.reconnectNow()
            }
            .loggedControl(control: "v2_ssh.connect", label: "Conectar")
        }
        .padding(DesignTokens.Space.s6)
        .frame(width: 420)
    }
}

/// Aviso do modo offline: leitura da última cópia, edição desabilitada até reconectar.
struct V2OfflineBanner: View {
    let link: RemoteLink

    private var readTime: String {
        guard let date = link.lastRead else { return "" }
        return " (lida em " + date.formatted(date: .abbreviated, time: .shortened) + ")"
    }

    var body: some View {
        HStack(spacing: DesignTokens.Space.s2) {
            VDIcon(.terminal, size: 13)
            Text("Sem conexão com \(link.host): somente leitura. Mostrando a última leitura\(readTime). Edição desabilitada até reconectar.")
                .font(DesignTokens.Typography.callout)
                .lineLimit(2)
            Spacer(minLength: DesignTokens.Space.s2)
            LoggedButton("Reconectar") { link.reconnectNow() }
                .loggedControl(control: "v2_offline_banner.reconnect", label: "Reconectar")
                .buttonStyle(.glass)
        }
        .foregroundStyle(DesignTokens.Colors.brandText)
        .padding(.horizontal, DesignTokens.Space.s3)
        .padding(.vertical, DesignTokens.Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.Colors.brand.opacity(0.12))
        .accessibilityElement(children: .combine)
    }
}
