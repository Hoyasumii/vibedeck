import SwiftUI
import VibeDeckCore

/// Indicador de ambiente SSH da barra de status (prancha 19): conectado, offline com pendências ou com conflito.
/// Também executa o laço de sincronização do projeto remoto (uma única vez por janela) e abre o estado da conexão.
struct V2RemoteEnvironmentSegment: View {
    @State private var status: RemoteProjectStatus
    @State private var showing = false
    @Environment(AISession.self) private var claude

    init(workspace: RemoteWorkspace) {
        _status = State(initialValue: RemoteProjectStatus(workspace))
    }

    private enum Kind { case connecting, connected, offline, conflict }

    private var kind: Kind {
        if !status.conflicts.isEmpty { return .conflict }
        if status.error != nil { return .offline }
        if status.message == "Desconectado" { return .connecting }
        return .connected
    }

    private var host: String {
        let destination = status.workspace.destination
        return destination.user + "@" + destination.host
    }

    private var pendingLabel: String {
        status.pending == 1 ? "1 alteração pendente" : "\(status.pending) alterações pendentes"
    }

    private var detail: String {
        switch kind {
        case .connecting: return "conectando…"
        case .connected: return "conectado"
        case .offline: return status.pending > 0 ? "offline · " + pendingLabel : "offline"
        case .conflict: return "conflito ao sincronizar"
        }
    }

    private var dot: Color {
        switch kind {
        case .connecting: return DesignTokens.Colors.inkFaint
        case .connected: return DesignTokens.Colors.done
        case .offline: return DesignTokens.Colors.brand
        case .conflict: return DesignTokens.Colors.fix
        }
    }

    private var tint: Color {
        switch kind {
        case .offline, .conflict: return DesignTokens.Colors.brandText
        default: return DesignTokens.Colors.inkMuted
        }
    }

    var body: some View {
        V2StatusSegment(control: "v2_status_bar.environment", label: "Estado da conexão SSH") {
            showing.toggle()
        } content: {
            VDIcon(.terminal, size: 13)
            Text("SSH · " + host)
            HStack(spacing: DesignTokens.Space.s1) {
                Circle().fill(dot).frame(width: 6, height: 6)
                Text(detail)
            }
        }
        .foregroundStyle(tint)
        .accessibilityLabel("Ambiente: SSH em \(host), \(detail)")
        .popover(isPresented: $showing) { panel }
        .sheet(isPresented: $status.credentials) { credentialsSheet }
        .task {
            while !Task.isCancelled {
                await status.synchronize()
                do { try await Task.sleep(for: .seconds(1)) } catch { break }
            }
        }
    }

    // MARK: Painel de estado

    private var panel: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.s2) {
            Text(status.workspace.destination.title)
                .font(DesignTokens.Typography.headline)
                .textSelection(.enabled)
            Text(status.message).font(DesignTokens.Typography.callout)
            if status.pending > 0 {
                Text(pendingLabel).font(DesignTokens.Typography.callout)
            }
            actions
            ForEach(status.conflicts) { item in
                conflictRow(item)
            }
            if let error = status.error {
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
            LoggedButton("Reconectar") { Task { await status.synchronize(force: true) } }
                .loggedControl(control: "v2_ssh.reconnect", label: "Reconectar")
            LoggedButton("Senha…") { status.credentials = true }
                .loggedControl(control: "v2_ssh.password", label: "Senha")
            LoggedButton("Terminal SSH") { claude.openTerminal() }
                .loggedControl(control: "v2_ssh.terminal", label: "Terminal SSH")
        }
    }

    private func conflictRow(_ item: RemoteWorkspace.Conflict) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.s1) {
            Text("Conflito: " + item.path)
                .font(DesignTokens.Typography.callout)
                .foregroundStyle(DesignTokens.Colors.fix)
            HStack {
                LoggedButton("Preservar local") { Task { await status.resolve(item, keepLocal: true) } }
                    .loggedControl(control: "v2_ssh.keep_local", label: "Preservar local")
                LoggedButton("Preservar remota") { Task { await status.resolve(item, keepLocal: false) } }
                    .loggedControl(control: "v2_ssh.keep_remote", label: "Preservar remota")
            }
            .disabled(status.busy)
        }
    }

    private var credentialsSheet: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.s4) {
            Text("Reconectar ao servidor").font(DesignTokens.Typography.headline)
            SecureField("Senha ou frase secreta", text: $status.password)
            Toggle("Guardar no Chaves do macOS", isOn: $status.remember.logging(control: "v2_ssh.remember", label: "Guardar no Chaves do macOS", project: status.workspace.root))
            LoggedButton("Conectar") {
                Task {
                    do { try SSHCredentials.store(status.remember ? status.password : nil, for: status.workspace.destination) }
                    catch { status.error = error.localizedDescription; return }
                    await status.synchronize(force: true)
                    status.credentials = false
                }
            }
            .loggedControl(control: "v2_ssh.connect", label: "Conectar")
        }
        .padding(DesignTokens.Space.s6)
        .frame(width: 420)
    }
}
