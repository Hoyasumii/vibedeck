import Foundation

// Projeto SSH (decisão D16): o Core roda no servidor e o app é só cliente MCP.
// Conexão perdida => reconexão automática com intervalo crescente (1, 2, 4, 8… até 60 s) e modo offline
// SOMENTE LEITURA: a UI mostra a última leitura (memória + cache em disco por projeto), sem edição offline.

/// Intervalos da reconexão automática.
enum RemoteBackoff {
    static let maximum: TimeInterval = 60

    /// `attempt` começa em 0: 1 s, 2 s, 4 s, 8 s, 16 s, 32 s, 60 s, 60 s…
    static func delay(attempt: Int) -> TimeInterval {
        var value: TimeInterval = 1
        var step = 0
        while step < attempt && value < maximum {
            value *= 2
            step += 1
        }
        return min(value, maximum)
    }
}

/// Estado da conexão com o servidor de um projeto SSH.
@Observable @MainActor
final class RemoteLink {
    enum State: Equatable {
        /// Core respondendo.
        case connected
        /// Tentando conectar agora.
        case connecting
        /// Desconectado; a próxima tentativa automática é em `until`.
        case waiting(until: Date)
        /// Desconectado e sem tentativa agendada (laço parado).
        case offline
    }

    let workspace: RemoteWorkspace
    private(set) var state: State
    /// Último erro de conexão (mostrado no painel).
    var error: String?
    /// Instante da última leitura bem-sucedida (mostrado no aviso offline).
    var lastRead: Date?
    var password = ""
    var remember = false
    var credentials = false

    @ObservationIgnored private let store: CoreStore
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var attempt = 0
    @ObservationIgnored private var forceNow = false
    @ObservationIgnored private var nextProbe = Date.distantPast
    @ObservationIgnored private var lastRevision: String?
    /// Chamado ao reconectar (o modelo relê tudo).
    @ObservationIgnored var onReconnected: (() -> Void)?
    /// Chamado quando o servidor mudou (revisão diferente) ou, sem `project_revision`, a cada sondagem.
    @ObservationIgnored var onRemoteChanged: (() -> Void)?

    init(workspace: RemoteWorkspace, store: CoreStore, connected: Bool) {
        self.workspace = workspace
        self.store = store
        self.state = connected ? .connected : .offline
    }

    var isConnected: Bool { state == .connected }

    var host: String { workspace.destination.user + "@" + workspace.destination.host }

    // MARK: Laço

    func start() {
        guard loop == nil else { return }
        if state == .offline { scheduleNext() }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { return }
                await self.tick()
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
    }

    /// Botão Reconectar: tenta agora, sem esperar o intervalo.
    func reconnectNow() {
        if state == .connected { return }
        forceNow = true
        if loop == nil { start() }
    }

    /// Uma chamada do app falhou: se foi a conexão, entra em offline já, sem esperar a próxima sondagem.
    func noteFailure(_ error: Error) {
        guard state == .connected, RemoteLink.isConnectionLoss(error) else { return }
        lose(error)
    }

    static func isConnectionLoss(_ error: Error) -> Bool {
        guard let core = error as? CoreError else { return false }
        switch core {
        case .disconnected, .timeout, .launchFailed: return true
        default: return false
        }
    }

    private func tick() async {
        switch state {
        case .connected:
            guard Date() >= nextProbe else { return }
            nextProbe = Date().addingTimeInterval(6)
            await probe()
        case .waiting(let until):
            if forceNow || Date() >= until { await connect() }
        case .offline:
            scheduleNext()
        case .connecting:
            return
        }
    }

    private func scheduleNext() {
        let delay = RemoteBackoff.delay(attempt: attempt)
        state = .waiting(until: Date().addingTimeInterval(delay))
    }

    private func lose(_ error: Error) {
        self.error = error.localizedDescription
        store.client.reset()
        attempt = 0
        scheduleNext()
    }

    /// Sondagem barata: `project_revision` também detecta mudanças externas no servidor.
    private func probe() async {
        do {
            let text = try await store.call("project_revision", timeout: 15, idempotent: false)
            if let previous = lastRevision, previous != text { onRemoteChanged?() }
            lastRevision = text
        } catch let failure as CoreError {
            if RemoteLink.isConnectionLoss(failure) { lose(failure); return }
            if case .unsupported = failure {
                onRemoteChanged?()
            }
        } catch {
            // Erro de tool: o Core respondeu, a conexão está viva.
        }
    }

    private func connect() async {
        forceNow = false
        state = .connecting
        let destination = workspace.destination
        let secret = password.isEmpty ? SSHCredentials.password(for: destination) : password
        do {
            try await VDLog.detached { try SSHConnection(destination).connect(password: secret) }.value
            store.client.reset()
            try await store.client.connect()
            password = ""
            error = nil
            attempt = 0
            lastRevision = nil
            nextProbe = Date().addingTimeInterval(6)
            state = .connected
            onReconnected?()
        } catch {
            self.error = error.localizedDescription
            attempt += 1
            forceNow = false
            scheduleNext()
        }
    }

    /// Marca a leitura mais recente (cache e aviso offline).
    func noteRead() { lastRead = Date() }
}

// MARK: - Cache da última leitura

/// Última leitura de um projeto SSH, guardada em Application Support/VibeDeck/RemoteCache/<id>.json.
struct RemoteCache: Codable {
    struct Record<Value: Codable>: Codable {
        var slug: String
        var value: Value
    }

    var savedAt: Date
    var project: Project
    var docs: [DocInfo]
    var groups: [Record<ReviewGroup>]
    var topics: [Record<RuleTopic>]
    var ideas: [Record<Idea>]
    var agents: [Record<Agent>]
    var commands: [Record<Command>]
    var skills: [Record<Skill>]
    var workflows: [Record<Workflow>]
    var runs: [Record<WorkflowRun>]
    var checks: [RuleCheck]
    var docTexts: [String: String]

    var snapshot: CoreSnapshot {
        CoreSnapshot(
            project: project, docs: docs,
            groups: groups.map { CoreEntry(slug: $0.slug, value: $0.value) },
            topics: topics.map { CoreEntry(slug: $0.slug, value: $0.value) },
            ideas: ideas.map { CoreEntry(slug: $0.slug, value: $0.value) },
            agents: agents.map { CoreEntry(slug: $0.slug, value: $0.value) },
            commands: commands.map { CoreEntry(slug: $0.slug, value: $0.value) },
            skills: skills.map { CoreEntry(slug: $0.slug, value: $0.value) },
            workflows: workflows.map { CoreEntry(slug: $0.slug, value: $0.value) })
    }

    static func url(for workspace: RemoteWorkspace) -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return base.appending(path: "VibeDeck", directoryHint: .isDirectory)
            .appending(path: "RemoteCache", directoryHint: .isDirectory)
            .appending(path: workspace.destination.id + ".json")
    }

    static func load(for workspace: RemoteWorkspace) -> RemoteCache? {
        guard let url = url(for: workspace), let data = try? Data(contentsOf: url) else { return nil }
        return try? VDJSON.decoder.decode(RemoteCache.self, from: data)
    }

    /// Codifica e grava fora da thread principal. Falhas de disco não interrompem o app.
    static func save(_ data: Data, for workspace: RemoteWorkspace) {
        guard let url = url(for: workspace) else { return }
        DispatchQueue.global(qos: .utility).async {
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
            } catch {
                VDLog.error(error, event: "remote.cache_write_failed", project: workspace.root, component: .app)
            }
        }
    }
}
