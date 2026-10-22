import Foundation

// Cliente MCP (JSON-RPC 2.0, uma mensagem JSON por linha) do binário Rust `vibedeck mcp`.
// Decisão A3: o app não tem ABI/FFI com o Core; ele fala o mesmo contrato MCP que a IA usa,
// por stdio, localmente (`vibedeck mcp -C <raiz>`) ou por SSH (`ssh host vibedeck mcp -C <raiz>`).

// MARK: - Erros

enum CoreError: Error, LocalizedError {
    case binaryNotFound
    case launchFailed(String)
    case disconnected(String)
    case timeout(String)
    case protocolError(String)
    case rpc(code: Int, message: String)
    /// A tool respondeu `isError: true`; o texto é a mensagem do Core (já em português).
    case tool(String)
    /// O Core Rust ainda não oferece a tool/campo (ver PEDIDO-CORE em .vibedeck/runs/mestre-12/app/pedidos-core.md).
    case unsupported(String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "Binário `vibedeck` não encontrado. Ele deve estar em Contents/MacOS do app ou no PATH."
        case .launchFailed(let detail):
            return "Não foi possível iniciar o Core: \(detail)"
        case .disconnected(let detail):
            return "Conexão com o Core encerrada. \(detail)"
        case .timeout(let what):
            return "Tempo esgotado esperando o Core (\(what))."
        case .protocolError(let detail):
            return "Resposta inválida do Core: \(detail)"
        case .rpc(_, let message):
            return message
        case .tool(let message):
            return message
        case .unsupported(let what):
            return "O Core ainda não oferece esta operação (\(what))."
        case .decoding(let detail):
            return "Não foi possível ler a resposta do Core: \(detail)"
        }
    }
}

// MARK: - Onde o Core roda

/// Como iniciar o servidor MCP. Para SSH o chamador monta os argumentos completos do `/usr/bin/ssh`
/// (ver `CoreLocation.ssh(connection:)`), de modo que o cliente não conhece SSH.
enum CoreLocation: Equatable {
    case local(root: URL)
    case ssh(arguments: [String], remoteRoot: String)

    /// Raiz do projeto como o Core a enxerga (caminho remoto no caso SSH).
    var coreRootPath: String {
        switch self {
        case .local(let root): return root.path
        case .ssh(_, let remoteRoot): return remoteRoot
        }
    }

    var isRemote: Bool {
        if case .ssh = self { return true }
        return false
    }
}

struct CoreInvocation {
    var executable: URL
    var arguments: [String]
    var environment: [String: String]
}

enum CoreLocator {
    /// Procura o `vibedeck`: variável VIBEDECK_BIN, bundle (`Contents/MacOS/vibedeck`), depois PATH e pastas usuais.
    static func binary() -> URL? {
        let fm = FileManager.default
        if let override = ProcessInfo.processInfo.environment["VIBEDECK_BIN"], fm.isExecutableFile(atPath: override) {
            return URL(fileURLWithPath: override)
        }
        if let executable = Bundle.main.executableURL {
            let sibling = executable.deletingLastPathComponent().appendingPathComponent("vibedeck")
            if sibling.path != executable.path, fm.isExecutableFile(atPath: sibling.path) { return sibling }
        }
        var directories: [String] = []
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            directories += path.split(separator: ":").map(String.init)
        }
        let home = fm.homeDirectoryForCurrentUser.path
        directories += [home + "/.local/bin", home + "/.cargo/bin", "/opt/homebrew/bin", "/usr/local/bin"]
        for directory in directories {
            let candidate = directory + "/vibedeck"
            if fm.isExecutableFile(atPath: candidate) { return URL(fileURLWithPath: candidate) }
        }
        return nil
    }

    static func invocation(for location: CoreLocation) throws -> CoreInvocation {
        switch location {
        case .local(let root):
            guard let binary = binary() else { throw CoreError.binaryNotFound }
            return CoreInvocation(executable: binary, arguments: ["mcp", "-C", root.path], environment: ProcessInfo.processInfo.environment)
        case .ssh(let arguments, _):
            return CoreInvocation(executable: URL(fileURLWithPath: "/usr/bin/ssh"), arguments: arguments, environment: ProcessInfo.processInfo.environment)
        }
    }
}

// MARK: - Recurso listado

struct CoreResource: Equatable {
    var uri: String
    var name: String
    var mimeType: String?
    var detail: String?
}

// MARK: - Cliente

/// Cliente MCP por stdio. Seguro para chamadas concorrentes (várias requisições em voo, casadas por id).
/// Reconecta sozinho na próxima chamada depois que o processo morre. Estado protegido por `lock`.
final class CoreClient: @unchecked Sendable {
    let location: CoreLocation
    static let protocolVersion = "2025-06-18"

    private final class Session {
        let id: Int
        let process: Process
        let input: FileHandle
        private let lock = NSLock()
        private var stderrBytes = Data()
        private var alive = true
        init(id: Int, process: Process, input: FileHandle) {
            self.id = id
            self.process = process
            self.input = input
        }
        var isAlive: Bool { lock.withLock { alive } }
        func markDead() { lock.withLock { alive = false } }
        func appendStderr(_ data: Data) {
            lock.withLock {
                stderrBytes.append(data)
                if stderrBytes.count > 8192 { stderrBytes = stderrBytes.suffix(8192) }
            }
        }
        var stderrText: String {
            let data = lock.withLock { stderrBytes }
            return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private struct Pending {
        var session: Int
        var continuation: CheckedContinuation<Data, Error>
        var timer: Task<Void, Never>?
    }

    private let lock = NSLock()
    private var current: Session?
    private var startTask: Task<Session, Error>?
    private var nextRequestID = 0
    private var nextSessionID = 0
    private var pending: [Int: Pending] = [:]
    private var closed = false
    private var notificationHandler: (@Sendable (String, [String: Any]) -> Void)?
    private(set) var serverInstructions: String?

    /// Para testes: inicia este executável em vez do binário `vibedeck`.
    private let invocationOverride: CoreInvocation?

    init(location: CoreLocation, invocationOverride: CoreInvocation? = nil) {
        self.location = location
        self.invocationOverride = invocationOverride
        // Escrever num pipe fechado não pode derrubar o app.
        signal(SIGPIPE, SIG_IGN)
    }

    deinit { shutdownNow() }

    /// Recebe notificações do servidor (sem id), p.ex. `notifications/resources/list_changed`.
    func setNotificationHandler(_ handler: (@Sendable (String, [String: Any]) -> Void)?) {
        lock.withLock { notificationHandler = handler }
    }

    // MARK: API pública

    /// Faz o handshake se ainda não houver conexão. Útil para validar o binário ao abrir um projeto.
    func connect() async throws {
        _ = try await activeSession()
    }

    /// Requisição JSON-RPC; devolve o objeto `result` serializado. Reconecta e repete uma vez se
    /// `idempotent` e a conexão cair antes da resposta.
    func request(_ method: String, params: [String: Any]? = nil, timeout: TimeInterval = 60, idempotent: Bool = false) async throws -> Data {
        do {
            let session = try await activeSession()
            return try await send(on: session, method: method, params: params, timeout: timeout)
        } catch let error as CoreError {
            guard idempotent, case .disconnected = error else { throw error }
            let session = try await activeSession()
            return try await send(on: session, method: method, params: params, timeout: timeout)
        }
    }

    /// `tools/call`: devolve o texto de `content[0]`. `isError: true` vira `CoreError.tool`.
    func callTool(_ name: String, arguments: [String: Any] = [:], timeout: TimeInterval = 120, idempotent: Bool = false) async throws -> String {
        let data = try await request("tools/call", params: ["name": name, "arguments": arguments], timeout: timeout, idempotent: idempotent)
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw CoreError.protocolError("tools/call sem objeto de resultado")
        }
        var texts: [String] = []
        if let content = object["content"] as? [[String: Any]] {
            for block in content {
                if let text = block["text"] as? String { texts.append(text) }
            }
        }
        let text = texts.joined(separator: "\n")
        if (object["isError"] as? Bool) == true { throw CoreError.tool(text.isEmpty ? "Falha em \(name)." : text) }
        return text
    }

    /// `resources/read`: devolve o texto do primeiro conteúdo.
    func readResource(_ uri: String, timeout: TimeInterval = 60) async throws -> String {
        let data = try await request("resources/read", params: ["uri": uri], timeout: timeout, idempotent: true)
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let contents = object["contents"] as? [[String: Any]],
              let first = contents.first,
              let text = first["text"] as? String else {
            throw CoreError.protocolError("resources/read sem texto para \(uri)")
        }
        return text
    }

    /// `resources/list` (sem paginação no servidor).
    func listResources(timeout: TimeInterval = 60) async throws -> [CoreResource] {
        let data = try await request("resources/list", params: [:], timeout: timeout, idempotent: true)
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let list = object["resources"] as? [[String: Any]] else {
            throw CoreError.protocolError("resources/list sem lista")
        }
        var result: [CoreResource] = []
        for item in list {
            guard let uri = item["uri"] as? String else { continue }
            result.append(CoreResource(uri: uri, name: item["name"] as? String ?? uri,
                                       mimeType: item["mimeType"] as? String, detail: item["description"] as? String))
        }
        return result
    }

    /// Encerra o servidor: fecha stdin (EOF encerra o `vibedeck mcp` com 0) e, se demorar, termina o processo.
    func close() {
        shutdownNow()
    }

    // MARK: Conexão

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    private func activeSession() async throws -> Session {
        enum Step {
            case ready(Session)
            case wait(Task<Session, Error>)
            case closed
        }
        var created: Task<Session, Error>?
        let step: Step = locked {
            if closed { return .closed }
            if let session = current, session.isAlive { return .ready(session) }
            if let task = startTask { return .wait(task) }
            let task = Task<Session, Error> { try await self.startSession() }
            startTask = task
            created = task
            return .wait(task)
        }
        switch step {
        case .closed:
            throw CoreError.disconnected("O cliente foi encerrado.")
        case .ready(let session):
            return session
        case .wait(let task):
            do {
                let session = try await task.value
                if created != nil { locked { startTask = nil } }
                return session
            } catch {
                if created != nil { locked { startTask = nil } }
                throw error
            }
        }
    }

    private func startSession() async throws -> Session {
        let invocation = try invocationOverride ?? CoreLocator.invocation(for: location)
        let process = Process()
        process.executableURL = invocation.executable
        process.arguments = invocation.arguments
        process.environment = invocation.environment
        let inPipe = Pipe()
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardInput = inPipe
        process.standardOutput = outPipe
        process.standardError = errPipe

        let sessionID: Int = locked {
            nextSessionID += 1
            return nextSessionID
        }
        let session = Session(id: sessionID, process: process, input: inPipe.fileHandleForWriting)
        let streamPair = AsyncStream<Data>.makeStream()
        let continuation = streamPair.continuation
        let splitter = LineSplitter()

        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                if let rest = splitter.flush() { continuation.yield(rest) }
                continuation.finish()
                return
            }
            for line in splitter.feed(data) { continuation.yield(line) }
        }
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            session.appendStderr(data)
        }

        do {
            try process.run()
        } catch {
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            throw CoreError.launchFailed(error.localizedDescription)
        }

        Task { [weak self] in
            for await line in streamPair.stream {
                self?.handle(line: line)
            }
            self?.sessionEnded(session)
        }

        do {
            let initParams: [String: Any] = [
                "protocolVersion": CoreClient.protocolVersion,
                "capabilities": [String: Any](),
                "clientInfo": ["name": "VibeDeck", "version": "2"],
            ]
            let data = try await send(on: session, method: "initialize", params: initParams, timeout: 30)
            if let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                let instructions = object["instructions"] as? String
                locked { serverInstructions = instructions }
            }
            try write(on: session, object: ["jsonrpc": "2.0", "method": "notifications/initialized"])
        } catch {
            let detail = session.stderrText
            terminate(session)
            if case CoreError.disconnected = error, !detail.isEmpty { throw CoreError.disconnected(detail) }
            throw error
        }
        locked { current = session }
        return session
    }

    // MARK: Envio e recepção

    private func send(on session: Session, method: String, params: [String: Any]?, timeout: TimeInterval) async throws -> Data {
        let id: Int = locked {
            nextRequestID += 1
            return nextRequestID
        }
        var message: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method]
        if let params = params { message["params"] = params }
        guard JSONSerialization.isValidJSONObject(message) else {
            throw CoreError.protocolError("argumentos não serializáveis em \(method)")
        }
        let payload = try JSONSerialization.data(withJSONObject: message)
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            let timer = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self?.expire(id: id, what: method, session: session)
            }
            locked { pending[id] = Pending(session: session.id, continuation: continuation, timer: timer) }
            do {
                try writeLine(on: session, payload: payload)
            } catch {
                if let entry = takePending(id) {
                    entry.timer?.cancel()
                    entry.continuation.resume(throwing: error)
                }
            }
        }
    }

    private func write(on session: Session, object: [String: Any]) throws {
        let payload = try JSONSerialization.data(withJSONObject: object)
        try writeLine(on: session, payload: payload)
    }

    private func writeLine(on session: Session, payload: Data) throws {
        guard session.isAlive else { throw CoreError.disconnected(session.stderrText) }
        var line = payload
        line.append(0x0A)
        do {
            try session.input.write(contentsOf: line)
        } catch {
            throw CoreError.disconnected(session.stderrText.isEmpty ? error.localizedDescription : session.stderrText)
        }
    }

    private func takePending(_ id: Int) -> Pending? {
        locked { pending.removeValue(forKey: id) }
    }

    private func expire(id: Int, what: String, session: Session) {
        guard let entry = takePending(id) else { return }
        entry.continuation.resume(throwing: CoreError.timeout(what))
        // Avisa o servidor; um servidor que ignora notifications/cancelled só descarta a resposta tardia.
        try? write(on: session, object: ["jsonrpc": "2.0", "method": "notifications/cancelled", "params": ["requestId": id]])
    }

    private func handle(line: Data) {
        guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { return }
        if let id = object["id"] as? Int, object["method"] == nil {
            guard let entry = takePending(id) else { return }
            entry.timer?.cancel()
            if let error = object["error"] as? [String: Any] {
                let code = error["code"] as? Int ?? -32603
                let message = error["message"] as? String ?? "Erro do Core"
                entry.continuation.resume(throwing: CoreError.rpc(code: code, message: message))
                return
            }
            let result: Any = object["result"] ?? [String: Any]()
            if JSONSerialization.isValidJSONObject(result), let data = try? JSONSerialization.data(withJSONObject: result) {
                entry.continuation.resume(returning: data)
            } else {
                entry.continuation.resume(throwing: CoreError.protocolError("resultado sem objeto JSON"))
            }
            return
        }
        if let method = object["method"] as? String, object["id"] == nil {
            let handler = locked { notificationHandler }
            handler?(method, object["params"] as? [String: Any] ?? [:])
        }
    }

    private func sessionEnded(_ session: Session) {
        session.markDead()
        let detail = session.stderrText
        let failed: [Pending] = locked {
            if current === session { current = nil }
            var result: [Pending] = []
            for (id, entry) in pending where entry.session == session.id {
                result.append(entry)
                pending.removeValue(forKey: id)
            }
            return result
        }
        for entry in failed {
            entry.timer?.cancel()
            entry.continuation.resume(throwing: CoreError.disconnected(detail))
        }
    }

    private func terminate(_ session: Session) {
        session.markDead()
        try? session.input.close()
        if session.process.isRunning { session.process.terminate() }
    }

    private func shutdownNow() {
        let session: Session? = locked {
            closed = true
            let s = current
            current = nil
            return s
        }
        guard let session = session else { return }
        session.markDead()
        try? session.input.close()
        let process = session.process
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) {
            if process.isRunning { process.terminate() }
        }
    }
}

// MARK: - Separador de linhas

/// Junta pedaços de stdout em linhas completas (o servidor escreve uma mensagem JSON por linha).
final class LineSplitter: @unchecked Sendable {
    private var buffer = Data()

    func feed(_ data: Data) -> [Data] {
        buffer.append(data)
        var lines: [Data] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer.subdata(in: buffer.startIndex..<newline)
            buffer.removeSubrange(buffer.startIndex...newline)
            if !line.isEmpty { lines.append(line) }
        }
        return lines
    }

    func flush() -> Data? {
        defer { buffer = Data() }
        return buffer.isEmpty ? nil : buffer
    }
}
