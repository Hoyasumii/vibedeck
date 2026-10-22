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
            let connection = SSHConnection(destination)
            let probe = try await VDLog.detached { try connection.run("test -f vibedeck.json && printf yes || printf no") }.value
            let exists = String(decoding: probe, as: UTF8.self) == "yes"
            if !exists && !create {
                name = (path as NSString).lastPathComponent; initialize = true; return
            }
            if create {
                guard !exists else { throw VibeDeckError.ssh("Já existe um projeto nessa pasta. Abra novamente.") }
                // O `vibedeck` do servidor cria vibedeck.json e .vibedeck/ (mesmo binário que roda o MCP).
                let command = RemoteExecution.launcher("vibedeck", arguments: ["init", "--name", name, destination.directory])
                _ = try await VDLog.detached { try connection.run(command, timeout: 60) }.value
            }
            onOpen(RemoteWorkspace.rootURL(for: destination)); dismiss()
        }
    }
}
