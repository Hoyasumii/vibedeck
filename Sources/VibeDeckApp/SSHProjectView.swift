import SwiftUI

struct SSHProjectSheet: View {
    let onOpen: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var host = ""
    @State private var user = NSUserName()
    @State private var port = "22"
    @State private var alias = ""
    @State private var password = ""
    @State private var remember = false
    @State private var destination: SSHDestination?
    @State private var path = "/"
    @State private var directories: [String] = []
    @State private var busy = false
    @State private var error: String?
    @State private var keys: String?
    @State private var fingerprints = ""
    @State private var initialize = false
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Abrir projeto via SSH", systemImage: "network").font(.title2)
            if destination == nil {
                Form {
                    Picker("Destino SSH", selection: $alias.logging(control: "ssh.destination", label: "Destino SSH", project: nil)) {
                        Text("Configuração manual").tag("")
                        ForEach(SSHConnection.aliases(), id: \.self) { Text($0).tag($0) }
                    }
                    .onChange(of: alias) { _, value in
                        guard !value.isEmpty else { return }
                        perform {
                            let resolved = try await VDLog.detached { try SSHConnection.configuration(alias: value) }.value
                            host = value; user = resolved.user; port = String(resolved.port)
                        }
                    }
                    LoggedTextField("Servidor", text: $host).loggedField(control: "ssh.host", label: "Servidor")
                    LoggedTextField("Porta", text: $port).loggedField(control: "ssh.port", label: "Porta")
                    LoggedTextField("Usuário", text: $user).loggedField(control: "ssh.user", label: "Usuário")
                    SecureField("Senha ou frase secreta (opcional)", text: $password)
                    Toggle("Guardar senha no Chaves do macOS", isOn: $remember.logging(control: "ssh.remember", label: "Guardar senha no Chaves do macOS", project: nil))
                    Text("Sem senha, usa as chaves e o agente SSH configurados neste Mac.").font(.caption).foregroundStyle(.secondary)
                }
                LoggedButton("Conectar") { connect() }.loggedControl(control: "ssh.connect", label: "Conectar")
                    .disabled(host.isEmpty || busy)
            } else {
                Text(destination?.title ?? "").font(.caption).textSelection(.enabled)
                HStack {
                    LoggedTextField("Diretório remoto", text: $path).loggedField(control: "ssh.path", label: "Diretório remoto")
                        .onSubmit { navigate(path) }
                    LoggedButton("Ir") { navigate(path) }.loggedControl(control: "ssh.navigate", label: "Ir")
                    LoggedButton("Pasta pai") { navigate(((destination?.directory ?? path) as NSString).deletingLastPathComponent) }.loggedControl(control: "ssh.parent", label: "Pasta pai")
                }
                List(directories, id: \.self) { directory in
                    LoggedButton { navigate(((destination?.directory ?? path) as NSString).appendingPathComponent(directory)) } label: {
                        Label(directory, systemImage: "folder").frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.loggedControl(control: "ssh.directory", label: "Abrir diretório").buttonStyle(.plain)
                }.frame(height: 220)
                LoggedButton("Abrir esta pasta") { openSelected() }.loggedControl(control: "ssh.open", label: "Abrir esta pasta")
                    .disabled(busy)
            }
            if busy { ProgressView("Conectando e carregando…") }
            if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            HStack { Spacer(); LoggedButton("Cancelar", role: .cancel) { dismiss() }.loggedControl(control: "ssh.cancel", label: "Cancelar") }
        }
        .padding(24).frame(width: 560)
        .disabled(busy)
        .confirmationDialog("Confiar neste servidor SSH?", isPresented: Binding(get: { keys != nil }, set: { if !$0 { keys = nil } }), titleVisibility: .visible) {
            LoggedButton("Confiar e conectar") {
                guard let keys else { return }; self.keys = nil
                perform { try SSHConnection.trust(keys); connect() }
            }.loggedControl(control: "ssh.trust", label: "Confiar e conectar")
            LoggedButton("Cancelar", role: .cancel) { keys = nil }.loggedControl(control: "ssh.trust_cancel", label: "Cancelar")
        } message: { Text(fingerprints + "\nConfirme a impressão digital com o administrador do servidor.") }
        .sheet(isPresented: $initialize) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Nenhum projeto VibeDeck nesta pasta").font(.headline)
                Text("Criar vibedeck.json e .vibedeck/ em \(path)?")
                LoggedTextField("Nome do projeto", text: $name).loggedField(control: "ssh.project_name", label: "Nome do projeto")
                HStack {
                    LoggedButton("Cancelar", role: .cancel) { initialize = false }.loggedControl(control: "ssh.init_cancel", label: "Cancelar")
                    LoggedButton("Inicializar projeto") { initialize = false; openSelected(create: true) }.loggedControl(control: "ssh.initialize", label: "Inicializar projeto")
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }.padding(24).frame(width: 440)
        }
    }
    private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        busy = true; error = nil
        Task { do { try await operation() } catch { self.error = error.localizedDescription }; busy = false }
    }
    private func connect() {
        perform {
            guard let port = Int(port) else { throw VibeDeckError.ssh("Informe uma porta entre 1 e 65535.") }
            let target: SSHDestination
            if !alias.isEmpty && alias == host {
                let selectedAlias = alias
                let resolved = try await VDLog.detached { try SSHConnection.configuration(alias: selectedAlias) }.value
                target = try SSHDestination(host: resolved.host, port: port, user: user, alias: alias)
            } else { target = try SSHDestination(host: host, port: port, user: user) }
            let connection = SSHConnection(target)
            if let candidate = try await VDLog.detached(operation: { try connection.unknownHostKeys() }).value {
                fingerprints = try SSHConnection.fingerprints(candidate); keys = candidate; return
            }
            let secret = password.isEmpty ? SSHCredentials.password(for: target) : password
            try await VDLog.detached { try connection.connect(password: secret) }.value
            if remember, let secret { try SSHCredentials.store(secret, for: target) }
            password = ""
            let home = String(decoding: try await VDLog.detached { try connection.run("printf '%s' \"$HOME\"") }.value, as: UTF8.self)
            destination = target
            navigate(home)
        }
    }
    private func navigate(_ requested: String) {
        guard let destination else { return }
        perform {
            let resolved = try await VDLog.detached { try SSHConnection(destination).resolved(directory: requested) }.value
            let folders = try await VDLog.detached { try SSHConnection(resolved).directories() }.value
            self.destination = resolved; path = resolved.directory; directories = folders
        }
    }
    private func openSelected(create: Bool = false) {
        guard let currentDestination = destination else { return }
        let requestedPath = path
        perform {
            // Clicking Open also commits a typed path, even without pressing Return or Go.
            let destination = try await VDLog.detached {
                try SSHConnection(currentDestination).resolved(directory: requestedPath)
            }.value
            self.destination = destination; path = destination.directory
            let workspace = try RemoteWorkspace.open(destination)
            let transport = SSHFileTransport(destination)
            let snapshot = try await VDLog.detached { try transport.snapshot() }.value
            if snapshot["vibedeck.json"] == nil && !create {
                name = (path as NSString).lastPathComponent; initialize = true; return
            }
            if create {
                guard snapshot["vibedeck.json"] == nil else { throw VibeDeckError.ssh("Já existe um projeto nessa pasta. Abra novamente.") }
                try CoreStore.initialize(at: workspace.root, name: name)
            }
            try await VDLog.detached { try workspace.synchronize(using: transport) }.value
            onOpen(workspace.root); dismiss()
        }
    }
}

@Observable @MainActor
final class RemoteProjectStatus {
    let workspace: RemoteWorkspace
    var message = "Desconectado"
    var error: String?
    var busy = false
    var pending = 0
    var conflicts: [RemoteWorkspace.Conflict] = []
    var password = ""
    var remember = false
    var credentials = false
    private var nextAttempt = Date.distantPast
    private var delay: TimeInterval = 2
    init(_ workspace: RemoteWorkspace) { self.workspace = workspace }
    func synchronize(force: Bool = false) async {
        guard !busy else { return }
        pending = workspace.pendingCount; conflicts = workspace.conflicts
        if !conflicts.isEmpty { message = "Conflito" }
        else if pending > 0 && error == nil { message = "Alterações pendentes" }
        guard force || Date() >= nextAttempt else { return }
        busy = true; message = "Sincronizando…"
        defer { busy = false; pending = workspace.pendingCount; conflicts = workspace.conflicts }
        do {
            let workspace = workspace
            let secret = password.isEmpty ? SSHCredentials.password(for: workspace.destination) : password
            try await VDLog.detached {
                try SSHConnection(workspace.destination).connect(password: secret)
                try workspace.synchronize(using: SSHFileTransport(workspace.destination))
            }.value
            password = ""; error = nil; delay = 2
            message = workspace.conflicts.isEmpty ? (workspace.pendingCount == 0 ? "Sincronizado" : "Alterações pendentes") : "Conflito"
            nextAttempt = Date().addingTimeInterval(2)
        } catch {
            self.error = error.localizedDescription
            message = "Desconectado · \(workspace.pendingCount) pendência(s)"
            nextAttempt = Date().addingTimeInterval(delay); delay = min(60, delay * 2)
        }
    }
    func resolve(_ conflict: RemoteWorkspace.Conflict, keepLocal: Bool) async {
        guard !busy else { return }; busy = true
        do {
            let workspace = workspace
            try await VDLog.detached { try workspace.resolve(conflict.path, keepLocal: keepLocal, using: SSHFileTransport(workspace.destination)) }.value
            error = nil
        } catch { self.error = error.localizedDescription }
        busy = false; await synchronize(force: true)
    }
}

struct RemoteProjectBar: View {
    @State private var status: RemoteProjectStatus
    @State private var conflict: RemoteWorkspace.Conflict?
    @Environment(AISession.self) private var session
    init(workspace: RemoteWorkspace) { _status = State(initialValue: RemoteProjectStatus(workspace)) }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(status.message, systemImage: status.busy ? "arrow.triangle.2.circlepath" : "network")
            Text(status.workspace.destination.title).font(.caption).textSelection(.enabled)
            if status.pending > 0 { Text("\(status.pending) alteração(ões) pendente(s)").font(.caption) }
            HStack {
                LoggedButton("Reconectar") { Task { await status.synchronize(force: true) } }.loggedControl(control: "ssh.reconnect", label: "Reconectar")
                LoggedButton("Senha…") { status.credentials = true }.loggedControl(control: "ssh.password", label: "Senha")
                LoggedButton("Terminal SSH") { session.openTerminal() }.loggedControl(control: "ssh.terminal", label: "Terminal SSH")
            }
            Text("Para autenticar a IA, abra o Terminal SSH e execute claude ou codex no servidor.").font(.caption).foregroundStyle(.secondary)
            ForEach(status.conflicts) { item in
                LoggedButton("Resolver: \(item.path)") { conflict = item }.loggedControl(control: "ssh.conflict", label: "Resolver conflito")
            }
            if let error = status.error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
        }
        .padding(8)
        .task {
            while !Task.isCancelled {
                await status.synchronize()
                do { try await Task.sleep(for: .seconds(1)) } catch { break }
            }
        }
        .sheet(item: $conflict) { item in
            VStack(alignment: .leading, spacing: 12) {
                Text("Conflito: \(item.path)").font(.headline)
                HStack(alignment: .top) {
                    version("Versão local", data: item.local)
                    version("Versão remota", data: item.remote)
                }
                HStack {
                    LoggedButton("Preservar local") { Task { await status.resolve(item, keepLocal: true); conflict = nil } }.loggedControl(control: "ssh.keep_local", label: "Preservar local")
                    LoggedButton("Preservar remota") { Task { await status.resolve(item, keepLocal: false); conflict = nil } }.loggedControl(control: "ssh.keep_remote", label: "Preservar remota")
                    LoggedButton("Decidir depois", role: .cancel) { conflict = nil }.loggedControl(control: "ssh.conflict_cancel", label: "Decidir depois")
                }.disabled(status.busy)
            }.padding(24).frame(width: 780, height: 520)
        }
        .sheet(isPresented: $status.credentials) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Reconectar ao servidor").font(.headline)
                SecureField("Senha ou frase secreta", text: $status.password)
                Toggle("Guardar no Chaves do macOS", isOn: $status.remember.logging(control: "ssh.reconnect_remember", label: "Guardar no Chaves do macOS", project: status.workspace.root))
                LoggedButton("Conectar") {
                    Task {
                        do { try SSHCredentials.store(status.remember ? status.password : nil, for: status.workspace.destination) }
                        catch { status.error = error.localizedDescription; return }
                        await status.synchronize(force: true); status.credentials = false
                    }
                }.loggedControl(control: "ssh.password_connect", label: "Conectar")
            }.padding(24).frame(width: 420)
        }
    }
    private func version(_ title: String, data: Data?) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.headline)
            ScrollView {
                Text(data.map { String(data: $0, encoding: .utf8) ?? "Arquivo binário (\($0.count) bytes)\n" + $0.base64EncodedString() } ?? "Arquivo excluído")
                    .font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
