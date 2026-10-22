import Foundation

// Fachada assíncrona do app sobre o Core Rust (`CoreClient`). Substitui o `ProjectStore` do VibeDeckCore.
// Leitura: recursos `vibedeck://` (arquivo cru do registro, mesmo JSON do disco) e tools de listagem.
// Escrita: tools MCP. O que o Core ainda não oferece lança `CoreError.unsupported` (ver pedidos-core.md).

struct CoreEntry<Value> {
    var slug: String
    var value: Value
}

/// Tipos de registro JSON um-por-arquivo. `rawValue` é o segmento de `vibedeck://<kind>/<slug>` e a pasta em `.vibedeck/`.
enum CoreRecordKind: String, CaseIterable {
    case review = "reviews"
    case rule = "rules"
    case idea = "ideas"
    case agent = "agents"
    case command = "commands"
    case skill = "skills"
    case workflow = "workflows"

    var resourcePrefix: String { "vibedeck://" + rawValue + "/" }
}

/// Tudo que o app mantém em memória, lido de uma vez.
struct CoreSnapshot {
    var project: Project
    var docs: [DocInfo]
    var groups: [CoreEntry<ReviewGroup>]
    var topics: [CoreEntry<RuleTopic>]
    var ideas: [CoreEntry<Idea>]
    var agents: [CoreEntry<Agent>]
    var commands: [CoreEntry<Command>]
    var skills: [CoreEntry<Skill>]
    var workflows: [CoreEntry<Workflow>]
}

final class CoreStore: @unchecked Sendable {
    static let manifestName = "vibedeck.json"
    static let dataDirName = ".vibedeck"

    /// Raiz do projeto: pasta local, ou `ssh://[usuário@]host[:porta]/dir` para projetos remotos.
    let root: URL
    let location: CoreLocation
    let client: CoreClient

    init(root: URL) throws {
        self.root = root
        if let workspace = RemoteWorkspace.existing(at: root) {
            self.location = try CoreStore.sshLocation(for: workspace)
        } else {
            self.location = .local(root: root)
        }
        self.client = CoreClient(location: location)
    }

    var isRemote: Bool { location.isRemote }

    func close() { client.close() }

    // MARK: Caminhos (puros; só fazem sentido para projetos locais: Finder, base de markdown)

    var manifestURL: URL { root.appending(path: Self.manifestName) }
    var dataDir: URL { root.appending(path: Self.dataDirName, directoryHint: .isDirectory) }
    var docsDir: URL { dataDir.appending(path: "docs", directoryHint: .isDirectory) }
    var reviewsDir: URL { dataDir.appending(path: "reviews", directoryHint: .isDirectory) }
    var rulesDir: URL { dataDir.appending(path: "rules", directoryHint: .isDirectory) }
    var ideasDir: URL { dataDir.appending(path: "ideas", directoryHint: .isDirectory) }
    var agentDefsDir: URL { dataDir.appending(path: "agents", directoryHint: .isDirectory) }
    var commandsDir: URL { dataDir.appending(path: "commands", directoryHint: .isDirectory) }
    var skillsDir: URL { dataDir.appending(path: "skills", directoryHint: .isDirectory) }
    var workflowsDir: URL { dataDir.appending(path: "workflows", directoryHint: .isDirectory) }
    var runsDir: URL { dataDir.appending(path: "runs", directoryHint: .isDirectory) }
    var checksDir: URL { dataDir.appending(path: "checks", directoryHint: .isDirectory) }
    var attachmentsDir: URL { dataDir.appending(path: "attachments", directoryHint: .isDirectory) }

    func docURL(_ slug: String) -> URL { docsDir.appending(path: "\(slug).md") }
    func groupURL(_ slug: String) -> URL { reviewsDir.appending(path: "\(slug).json") }
    func topicURL(_ slug: String) -> URL { rulesDir.appending(path: "\(slug).json") }
    func ideaURL(_ slug: String) -> URL { ideasDir.appending(path: "\(slug).json") }
    func agentURL(_ slug: String) -> URL { agentDefsDir.appending(path: "\(slug).json") }
    func commandURL(_ slug: String) -> URL { commandsDir.appending(path: "\(slug).json") }
    func skillURL(_ slug: String) -> URL { skillsDir.appending(path: "\(slug).json") }
    func workflowURL(_ slug: String) -> URL { workflowsDir.appending(path: "\(slug).json") }

    /// `<workflow>/<execução>` -> pasta da execução.
    func runDir(_ ref: String) -> URL { runsDir.appending(path: ref, directoryHint: .isDirectory) }
    func runURL(_ ref: String) -> URL { runDir(ref).appending(path: "run.json") }

    func url(for kind: CoreRecordKind, slug: String) -> URL {
        switch kind {
        case .review: return groupURL(slug)
        case .rule: return topicURL(slug)
        case .idea: return ideaURL(slug)
        case .agent: return agentURL(slug)
        case .command: return commandURL(slug)
        case .skill: return skillURL(slug)
        case .workflow: return workflowURL(slug)
        }
    }

    static func isProject(_ dir: URL) -> Bool {
        if RemoteWorkspace.existing(at: dir) != nil { return true }
        return FileManager.default.fileExists(atPath: dir.appending(path: manifestName).path)
    }

    /// Diretório (caminho de grupo) de uma referência `a/b/slug` -> `a/b`.
    static func groupPath(of reference: String) -> String {
        reference.split(separator: "/").dropLast().joined(separator: "/")
    }

    /// Reescreve `../attachments/` de um markdown para a profundidade do registro agrupado.
    static func markdownForGroupedRecord(_ text: String, reference: String) -> String {
        let prefix = String(repeating: "../", count: reference.split(separator: "/").count)
        guard let regex = try? NSRegularExpression(pattern: #"(?<=\()(?:(?:\.\./)+)attachments/"#) else { return text }
        return regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: prefix + "attachments/")
    }

    // MARK: Chamadas genéricas

    /// Chama uma tool e devolve o texto. Tool ausente no Core vira `CoreError.unsupported`.
    func call(_ tool: String, _ arguments: [String: Any] = [:], timeout: TimeInterval = 120, idempotent: Bool = false) async throws -> String {
        do {
            return try await client.callTool(tool, arguments: arguments, timeout: timeout, idempotent: idempotent)
        } catch let error as CoreError {
            if case .tool(let message) = error, message.contains("Tool desconhecida") { throw CoreError.unsupported(tool) }
            throw error
        }
    }

    /// Chama uma tool cujo texto é JSON e decodifica com o decoder de datas do VibeDeck.
    func callJSON<T: Decodable>(_ tool: String, _ arguments: [String: Any] = [:], as type: T.Type = T.self,
                                timeout: TimeInterval = 120, idempotent: Bool = false) async throws -> T {
        let text = try await call(tool, arguments, timeout: timeout, idempotent: idempotent)
        return try CoreStore.decode(type, from: text, what: tool)
    }

    static func decode<T: Decodable>(_ type: T.Type, from text: String, what: String) throws -> T {
        do {
            return try VDJSON.decoder.decode(type, from: Data(text.utf8))
        } catch {
            throw CoreError.decoding("\(what): \(error.localizedDescription)")
        }
    }

    static func encodeString<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try VDJSON.encode(value), as: UTF8.self)
    }

    // MARK: Leitura

    func loadProject() async throws -> Project {
        let text = try await client.readResource("vibedeck://project")
        return try CoreStore.decode(Project.self, from: text, what: "vibedeck.json")
    }

    private struct DocRow: Decodable {
        var slug: String
        var title: String
        var tags: [String]?
        /// PEDIDO-CORE: `list_docs` ainda não devolve a data de modificação.
        var modified: Date?
    }

    func listDocs() async throws -> [DocInfo] {
        let rows: [DocRow] = try await callJSON("list_docs", idempotent: true)
        return rows.map { DocInfo(slug: $0.slug, title: $0.title, tags: $0.tags ?? [], modified: $0.modified ?? Date(timeIntervalSince1970: 0)) }
    }

    func readDoc(_ slug: String) async throws -> String {
        try await call("read_doc", ["slug": slug], idempotent: true)
    }

    /// Lê todos os registros de um tipo a partir da lista de recursos já obtida (ordem: criação, depois slug).
    func readRecords<T: Decodable>(_ kind: CoreRecordKind, resources: [CoreResource], as type: T.Type = T.self,
                                   created: @escaping (T) -> Date) async throws -> [CoreEntry<T>] {
        let prefix = kind.resourcePrefix
        let uris = resources.map(\.uri).filter { $0.hasPrefix(prefix) }
        let client = self.client
        var loaded: [CoreEntry<T>] = []
        var index = 0
        // Em lotes, para não abrir centenas de leituras de uma vez (principalmente por SSH).
        while index < uris.count {
            let batch = Array(uris[index..<min(index + 16, uris.count)])
            index += batch.count
            let results: [CoreEntry<T>?] = await withTaskGroup(of: CoreEntry<T>?.self) { group in
                for uri in batch {
                    group.addTask {
                        do {
                            let text = try await client.readResource(uri)
                            let value = try VDJSON.decoder.decode(T.self, from: Data(text.utf8))
                            return CoreEntry(slug: String(uri.dropFirst(prefix.count)), value: value)
                        } catch {
                            VDLog.warning("core.record_skipped", "Registro ignorado: \(uri)", context: ["error": String(describing: error)])
                            return nil
                        }
                    }
                }
                var all: [CoreEntry<T>?] = []
                for await item in group { all.append(item) }
                return all
            }
            loaded += results.compactMap { $0 }
        }
        return loaded.sorted { (created($0.value), $0.slug) < (created($1.value), $1.slug) }
    }

    func listGroups(resources: [CoreResource]? = nil) async throws -> [CoreEntry<ReviewGroup>] {
        try await readRecords(.review, resources: try await resourceList(resources), created: { $0.createdAt })
    }

    func listTopics(resources: [CoreResource]? = nil) async throws -> [CoreEntry<RuleTopic>] {
        try await readRecords(.rule, resources: try await resourceList(resources), created: { $0.createdAt })
    }

    func listIdeas(resources: [CoreResource]? = nil) async throws -> [CoreEntry<Idea>] {
        try await readRecords(.idea, resources: try await resourceList(resources), created: { $0.createdAt })
    }

    func listAgents(resources: [CoreResource]? = nil) async throws -> [CoreEntry<Agent>] {
        try await readRecords(.agent, resources: try await resourceList(resources), created: { $0.createdAt })
    }

    func listCommands(resources: [CoreResource]? = nil) async throws -> [CoreEntry<Command>] {
        try await readRecords(.command, resources: try await resourceList(resources), created: { $0.createdAt })
    }

    func listSkills(resources: [CoreResource]? = nil) async throws -> [CoreEntry<Skill>] {
        try await readRecords(.skill, resources: try await resourceList(resources), created: { $0.createdAt })
    }

    func listWorkflows(resources: [CoreResource]? = nil) async throws -> [CoreEntry<Workflow>] {
        try await readRecords(.workflow, resources: try await resourceList(resources), created: { $0.createdAt })
    }

    private func resourceList(_ given: [CoreResource]?) async throws -> [CoreResource] {
        if let given = given { return given }
        return try await client.listResources()
    }

    func loadSnapshot() async throws -> CoreSnapshot {
        let project = try await loadProject()
        let docs = try await listDocs()
        let resources = try await client.listResources()
        return CoreSnapshot(
            project: project,
            docs: docs,
            groups: try await listGroups(resources: resources),
            topics: try await listTopics(resources: resources),
            ideas: try await listIdeas(resources: resources),
            agents: try await listAgents(resources: resources),
            commands: try await listCommands(resources: resources),
            skills: try await listSkills(resources: resources),
            workflows: try await listWorkflows(resources: resources)
        )
    }

    // MARK: Execuções de workflow e checks

    private struct RunRow: Decodable {
        var ref: String
    }

    /// Execuções, da mais recente para a mais antiga (`slug` = `<workflow>/<execução>`).
    func listRuns() async throws -> [CoreEntry<WorkflowRun>] {
        let rows: [RunRow] = try await callJSON("workflow_run_list", idempotent: true)
        var runs: [CoreEntry<WorkflowRun>] = []
        for row in rows {
            if let run = try? await loadRun(row.ref) { runs.append(CoreEntry(slug: row.ref, value: run)) }
        }
        return runs.sorted { $0.value.updatedAt > $1.value.updatedAt }
    }

    func loadRun(_ ref: String) async throws -> WorkflowRun {
        try await callJSON("workflow_run_show", ["run": ref], idempotent: true)
    }

    /// PEDIDO-CORE (list_checks): histórico de checks, mais recente primeiro. Sem a tool, a lista fica vazia.
    func listChecks() async throws -> [RuleCheck] {
        do {
            return try await callJSON("list_checks", idempotent: true)
        } catch let error as CoreError {
            if case .unsupported = error { return [] }
            throw error
        }
    }

    // MARK: Escrita

    /// PEDIDO-CORE (put_project): grava `vibedeck.json` inteiro, no formato canônico do Core.
    func saveProject(_ project: Project) async throws {
        _ = try await call("put_project", ["project": try CoreStore.encodeString(project)])
    }

    /// PEDIDO-CORE (put_record): grava o registro inteiro `<kind>/<slug>.json` (autor e datas vêm do próprio registro).
    func saveRecord<T: Encodable>(_ kind: CoreRecordKind, slug: String, value: T) async throws {
        _ = try await call("put_record", ["kind": kind.rawValue, "slug": slug, "record": try CoreStore.encodeString(value)])
    }

    /// PEDIDO-CORE (delete_record).
    func deleteRecord(_ kind: CoreRecordKind, slug: String) async throws {
        _ = try await call("delete_record", ["kind": kind.rawValue, "slug": slug])
    }

    /// Grava o markdown inteiro do doc (`write_doc` com slug existente).
    func writeDoc(_ slug: String, text: String) async throws {
        _ = try await call("write_doc", ["slug": slug, "content": text])
    }

    /// Cria um doc; devolve o slug escolhido pelo Core (`Criado: <slug>`). `reference` é caminho/slug desejado.
    func createDoc(title: String, body: String = "", reference: String? = nil, generated: Bool = false) async throws -> String {
        var args: [String: Any] = ["title": title, "content": "# \(title)\n\n\(body)"]
        if let reference = reference { args["reference"] = reference }
        if generated { args["generated"] = true; args["content"] = body }
        let reply = try await call("write_doc", args)
        let prefix = "Criado: "
        guard reply.hasPrefix(prefix) else { throw CoreError.protocolError("write_doc: \(reply)") }
        return String(reply.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// PEDIDO-CORE (delete_doc).
    func deleteDoc(_ slug: String) async throws {
        _ = try await call("delete_doc", ["slug": slug])
    }

    /// Tags de qualquer tipo suportado por `set_tags` (`doc`, `review`, `rule`, `idea`, `agent`, ...). Sem tags remove todas.
    func setTags(kind: String, ref: String, tags: [String]) async throws {
        _ = try await call("set_tags", ["kind": kind, "ref": ref, "tags": tags])
    }

    // MARK: Grupos (diretórios de ideias, revisões, docs e skills)

    struct ItemGroupRow: Decodable {
        var path: String
    }

    /// `item_groups`: ações `list`, `create`, `move`, `rename`, `move_item`, `delete`. Devolve o texto da tool.
    func itemGroups(concept: String, action: String, path: String? = nil, from: String? = nil, to: String? = nil,
                    reference: String? = nil, confirmed: Bool? = nil) async throws -> String {
        var args: [String: Any] = ["concept": concept, "action": action]
        if let path = path { args["path"] = path }
        if let from = from { args["from"] = from }
        if let to = to { args["to"] = to }
        if let reference = reference { args["reference"] = reference }
        if let confirmed = confirmed { args["confirmed"] = confirmed }
        return try await call("item_groups", args)
    }

    func listItemDirectories(_ concept: String) async throws -> [String] {
        let text = try await itemGroups(concept: concept, action: "list")
        let rows = try CoreStore.decode([ItemGroupRow].self, from: text, what: "item_groups")
        return rows.map(\.path)
    }

    // MARK: Projeto novo

    /// `vibedeck init` (comando do mesmo binário; ainda não há tool MCP para criar o projeto).
    static func initializeProject(at directory: URL, name: String) async throws {
        guard let binary = CoreLocator.binary() else { throw CoreError.binaryNotFound }
        let result = try await CoreStore.runCLI(binary, ["init", "--name", name, directory.path])
        guard result.status == 0 else { throw CoreError.tool(result.output.isEmpty ? "vibedeck init falhou." : result.output) }
    }

    /// Executa o binário uma vez (CLI) e junta stdout/stderr.
    static func runCLI(_ binary: URL, _ arguments: [String]) async throws -> (status: Int32, output: String) {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(status: Int32, output: String), Error>) in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = binary
                process.arguments = arguments
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                do {
                    try process.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(returning: (process.terminationStatus, text))
                } catch {
                    continuation.resume(throwing: CoreError.launchFailed(error.localizedDescription))
                }
            }
        }
    }

    // MARK: SSH

    /// `ssh <opções> host 'vibedeck mcp -C <dir>'`, achando o binário no servidor pelas pastas usuais (RemoteExecution).
    static func sshLocation(for workspace: RemoteWorkspace) throws -> CoreLocation {
        let connection = SSHConnection(workspace.destination)
        let body = RemoteExecution.launcher("vibedeck", arguments: ["mcp", "-C", workspace.destination.directory])
        let login = "exec \"${SHELL:-/bin/sh}\" -lc " + SSHConnection.quote(body)
        return .ssh(arguments: connection.commandArguments(login), remoteRoot: workspace.destination.directory)
    }
}

// Leitura de um registro pelo slug (arquivo cru do disco).
extension CoreStore {
    func loadRecord<T: Decodable>(_ kind: CoreRecordKind, slug: String, as type: T.Type = T.self) async throws -> T {
        let text = try await client.readResource(kind.resourcePrefix + slug)
        return try CoreStore.decode(type, from: text, what: kind.rawValue + "/" + slug)
    }

    func loadTopic(_ slug: String) async throws -> RuleTopic { try await loadRecord(.rule, slug: slug) }
    func loadIdea(_ slug: String) async throws -> Idea { try await loadRecord(.idea, slug: slug) }
    func loadWorkflow(_ slug: String) async throws -> Workflow { try await loadRecord(.workflow, slug: slug) }
    func loadGroup(_ slug: String) async throws -> ReviewGroup { try await loadRecord(.review, slug: slug) }
}
