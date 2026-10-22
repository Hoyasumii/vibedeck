import Foundation
import Observation
import SwiftUI

enum SidebarSection: String, CaseIterable, Hashable {
    case docs, groups, topics, ideas, agents, commands, skills, workflows

    var title: String {
        switch self {
        case .docs: "Docs"
        case .groups: "Revisões"
        case .topics: "Regras"
        case .ideas: "Ideias"
        case .agents: "Agentes"
        case .commands: "Comandos"
        case .skills: "Skills"
        case .workflows: "Workflows"
        }
    }

    var symbol: String {
        switch self {
        case .docs: "doc.text"
        case .groups: "checklist"
        case .topics: "checkmark.shield"
        case .ideas: "sparkle"
        case .agents: "person.crop.rectangle.stack"
        case .commands: "command"
        case .skills: "wand.and.stars"
        case .workflows: "point.3.connected.trianglepath.dotted"
        }
    }

    var emptyMessage: String {
        switch self {
        case .docs: "Sem documentos"
        case .groups: "Sem grupos de revisão"
        case .topics: "Sem tópicos de regras"
        case .ideas: "Sem ideias"
        case .agents: "Sem agentes"
        case .commands: "Sem comandos"
        case .skills: "Sem skills"
        case .workflows: "Sem workflows"
        }
    }
}

enum SidebarItem: Hashable {
    case stack
    case patterns
    case links
    case claudeItems
    case graph
    case integrations
    case usage
    case checksHistory
    case claude
    case terminal(UUID)
    case section(SidebarSection)
    case doc(String)
    case group(String)
    case topic(String)
    case idea(String)
    case agent(String)
    case command(String)
    case skill(String)
    case workflow(String)

    var storageKey: String {
        switch self {
        case .stack: "stack"
        case .patterns: "patterns"
        case .links: "links"
        case .claudeItems: "claudeItems"
        case .graph: "graph"
        case .integrations: "integrations"
        case .usage: "usage"
        case .checksHistory: "checksHistory"
        case .claude: "claude"
        case .terminal(let id): "terminal:\(id.uuidString)"
        case .section(let section): "section:\(section.rawValue)"
        case .doc(let slug): "doc:\(slug)"
        case .group(let slug): "group:\(slug)"
        case .topic(let slug): "topic:\(slug)"
        case .idea(let slug): "idea:\(slug)"
        case .agent(let slug): "agent:\(slug)"
        case .command(let slug): "command:\(slug)"
        case .skill(let slug): "skill:\(slug)"
        case .workflow(let slug): "workflow:\(slug)"
        }
    }

    init?(storageKey: String?) {
        guard let key = storageKey else { return nil }
        if key == "stack" { self = .stack }
        else if key == "patterns" { self = .patterns }
        else if key == "links" { self = .links }
        else if key == "claudeItems" { self = .claudeItems }
        else if key == "graph" { self = .graph }
        else if key == "integrations" { self = .integrations }
        else if key == "usage" { self = .usage }
        else if key == "checksHistory" { self = .checksHistory }
        else if key == "claude" { self = .claude }
        else if key.hasPrefix("terminal:") {
            guard let id = UUID(uuidString: String(key.dropFirst(9))) else { return nil }
            self = .terminal(id)
        }
        else if key.hasPrefix("section:") {
            guard let section = SidebarSection(rawValue: String(key.dropFirst(8))) else { return nil }
            self = .section(section)
        }
        else if key.hasPrefix("doc:") { self = .doc(String(key.dropFirst(4))) }
        else if key.hasPrefix("group:") { self = .group(String(key.dropFirst(6))) }
        else if key.hasPrefix("topic:") { self = .topic(String(key.dropFirst(6))) }
        else if key.hasPrefix("idea:") { self = .idea(String(key.dropFirst(5))) }
        else if key.hasPrefix("agent:") { self = .agent(String(key.dropFirst(6))) }
        else if key.hasPrefix("command:") { self = .command(String(key.dropFirst(8))) }
        else if key.hasPrefix("skill:") { self = .skill(String(key.dropFirst(6))) }
        else if key.hasPrefix("workflow:") { self = .workflow(String(key.dropFirst(9))) }
        else { return nil }
    }

    var isTerminal: Bool {
        if case .terminal = self { true } else { false }
    }

    /// The sidebar section this item lives in (expanded while it is selected).
    var section: SidebarSection? {
        switch self {
        case .stack, .patterns, .links, .claudeItems, .graph, .integrations, .usage, .checksHistory, .claude, .terminal: nil
        case .section(let section): section
        case .doc: .docs
        case .group: .groups
        case .topic: .topics
        case .idea: .ideas
        case .agent: .agents
        case .command: .commands
        case .skill: .skills
        case .workflow: .workflows
        }
    }
}

/// One child of a sidebar section, as shown in the section's list page.
struct SectionRow: Identifiable, Hashable {
    var id: SidebarItem
    var title: String
    var symbol: String
    var detail: String
    var count: String
    var tags: [String]
    var dimmed = false
}

/// Espelho em memória de um projeto. Leitura e escrita passam pelo Core Rust (MCP, via `CoreStore`): a UI
/// altera a memória na hora (otimista), a gravação vai para uma fila serial, e uma alteração externa
/// (CLI, IA, outro app) é relida pelo FSEvents (projeto local) ou por polling (SSH).
@MainActor
@Observable
final class ProjectModel {
    let docGenerator: DocGenerateRunner
    let itemAI: ItemAIRunner
    /// "Resolver" in reviews: one run per project at a time.
    let resolver = ReviewResolveRunner()
    let graphRunner: GraphRunner
    let store: CoreStore
    /// Conexão com o servidor de um projeto SSH (nil em projeto local). Desconectado = somente leitura.
    var link: RemoteLink?
    var project: Project
    var docs: [DocInfo] = []
    var groups: [GroupEntry] = []
    var topics: [Entry<RuleTopic>] = []
    var ideas: [Entry<Idea>] = []
    var agents: [Entry<Agent>] = []
    var commands: [Entry<Command>] = []
    var skills: [Entry<Skill>] = []
    var workflows: [Entry<Workflow>] = []
    /// Workflow runs, newest first (`slug` = `<workflow>/<run>`).
    var runs: [Entry<WorkflowRun>] = []
    /// All recorded rule checks, newest first.
    var checks: [RuleCheck] = []
    /// Last "Rodar testes" outcome per rule (in memory only; checks are what gets recorded).
    var testRuns: [UUID: RuleTestOutcome] = [:]
    /// Topics whose scripts are running right now.
    var runningTests: Set<String> = []
    var ruleExecution: RuleExecutionModel?
    var directoryGroups: [ItemConcept: [String]] = [:]
    var latestPathMoves: [SidebarItem: SidebarItem] = [:]
    var moveRevision = 0
    @ObservationIgnored private var docViewIdentities: [String: UUID] = [:]
    /// Última leitura completa do servidor (projeto SSH): base do modo offline e do cache em disco.
    @ObservationIgnored private var lastReadCache: RemoteCache?
    @ObservationIgnored private var cacheCaptureQueued = false

    var errorMessage: String? {
        didSet {
            if errorMessage != nil { VDLog.error("store.operation_failed", "Falha na operação do projeto", project: store.root, component: .app) }
        }
    }

    /// Bumped whenever a doc file changes on disk from outside the app.
    var externalDocChange: [String: Int] = [:]

    struct GroupEntry: Identifiable, Equatable {
        var slug: String
        var group: ReviewGroup
        var id: String { slug }
    }

    struct Entry<Value: Equatable>: Identifiable, Equatable {
        var slug: String
        var value: Value
        var id: String { slug }
    }

    /// Áreas que podem ser relidas do Core.
    enum Area: Hashable {
        case project, docs, groups, topics, ideas, agents, commands, skills, workflows, runs, checks
    }

    @ObservationIgnored private var watcher: FileWatcher?
    /// Fila serial de gravações: a ordem das edições é a ordem no Core.
    @ObservationIgnored private var writeChain: Task<Void, Never>?
    @ObservationIgnored private var pendingWrites = 0
    /// Revisão do Core (`project_revision`) logo depois da última gravação do próprio app: o eco do FSEvents tem a mesma.
    @ObservationIgnored private var ownRevision: String?
    @ObservationIgnored private var capturingOwnRevision = false
    /// Releituras pedidas enquanto havia gravação em andamento (reler antes de gravar traria o dado velho).
    @ObservationIgnored private var deferredReloads = Set<Area>()
    /// Texto mais recente dos docs: cache de leitura e filtro das mudanças que o próprio app causou.
    @ObservationIgnored private var docTexts: [String: String] = [:]
    @ObservationIgnored private var docWriteQueued = Set<String>()

    /// `try?` that logs the failure instead of hiding it; behavior is unchanged (nil on error).
    @discardableResult
    static func logged<T>(_ event: String, root: URL, _ body: () throws -> T) -> T? {
        do { return try body() } catch {
            VDLog.error(error, event: event, project: root, component: .app)
            return nil
        }
    }

    private init(store: CoreStore, snapshot: CoreSnapshot, connected: Bool = true) {
        self.store = store
        self.docGenerator = DocGenerateRunner.shared(root: store.root)
        self.itemAI = ItemAIRunner.shared(root: store.root)
        self.graphRunner = GraphRunner.shared(root: store.root)
        self.project = snapshot.project
        self.docs = snapshot.docs
        self.groups = snapshot.groups.map { GroupEntry(slug: $0.slug, group: $0.value) }
        self.topics = snapshot.topics.map { Entry(slug: $0.slug, value: $0.value) }
        self.ideas = snapshot.ideas.map { Entry(slug: $0.slug, value: $0.value) }
        self.agents = snapshot.agents.map { Entry(slug: $0.slug, value: $0.value) }
        self.commands = snapshot.commands.map { Entry(slug: $0.slug, value: $0.value) }
        self.skills = snapshot.skills.map { Entry(slug: $0.slug, value: $0.value) }
        self.workflows = snapshot.workflows.map { Entry(slug: $0.slug, value: $0.value) }
        for doc in snapshot.docs { docViewIdentities[doc.slug] = UUID() }
        if let workspace = RemoteWorkspace.existing(at: store.root) {
            let link = RemoteLink(workspace: workspace, store: store, connected: connected)
            link.onReconnected = { [weak self] in self?.remoteChanged() }
            link.onRemoteChanged = { [weak self] in self?.remoteChanged() }
            self.link = link
        }
    }

    /// Somente leitura: projeto SSH sem conexão. A UI mostra a última leitura e desabilita a edição.
    var isReadOnly: Bool {
        guard let link = link else { return false }
        return !link.isConnected
    }

    static let offlineMessage = "O projeto está offline e somente leitura. Reconecte ao servidor para editar."

    /// O servidor mudou (ou a conexão voltou): relê tudo e solta ideias órfãs.
    private func remoteChanged() {
        reloadAll()
        releaseOrphans()
    }

    deinit {
        store.close()
    }

    /// Abre o projeto: inicia o Core (local ou SSH), lê tudo e devolve o modelo pronto. Lança se o Core não responde.
    static func open(root: URL) async throws -> ProjectModel {
        let store = try CoreStore(root: root)
        do {
            let snapshot = try await store.loadSnapshot()
            let model = ProjectModel(store: store, snapshot: snapshot)
            await model.refresh(.runs)
            await model.refresh(.checks)
            for concept in ItemConcept.allCases { await model.refreshDirectoryGroups(concept) }
            model.link?.noteRead()
            model.scheduleCacheCapture()
            model.releaseOrphans()
            return model
        } catch {
            // Projeto SSH inalcançável: abre a última leitura em modo offline (somente leitura) e reconecta sozinho.
            if let workspace = RemoteWorkspace.existing(at: root), let cache = RemoteCache.load(for: workspace) {
                let model = ProjectModel(store: store, snapshot: cache.snapshot, connected: false)
                model.apply(runs: cache.runs, checks: cache.checks, docTexts: cache.docTexts)
                model.lastReadCache = cache
                model.link?.lastRead = cache.savedAt
                model.link?.error = error.localizedDescription
                return model
            }
            store.close()
            throw error
        }
    }

    private func apply(runs: [RemoteCache.Record<WorkflowRun>], checks: [RuleCheck], docTexts: [String: String]) {
        self.runs = runs.map { Entry(slug: $0.slug, value: $0.value) }
        self.checks = checks
        self.docTexts = docTexts
    }

    /// Modelo em memória para testes de interface (as gravações vão ao Core e falham sem o binário, sem afetar a memória).
    static func forTesting(root: URL, project: Project = Project(name: "Teste"), groups: [GroupEntry] = []) throws -> ProjectModel {
        let store = try CoreStore(root: root)
        let snapshot = CoreSnapshot(project: project, docs: [], groups: groups.map { CoreEntry(slug: $0.slug, value: $0.group) },
                                    topics: [], ideas: [], agents: [], commands: [], skills: [], workflows: [])
        return ProjectModel(store: store, snapshot: snapshot)
    }

    // MARK: Gravação e releitura

    /// Enfileira uma gravação no Core. Falha: mostra o erro e relê tudo (a memória otimista não vale mais).
    private func persist(_ work: @escaping () async throws -> Void) {
        if isReadOnly {
            errorMessage = Self.offlineMessage
            restoreLastRead()
            return
        }
        pendingWrites += 1
        let previous = writeChain
        writeChain = Task { [weak self] in
            await previous?.value
            do { try await work() } catch { self?.persistFailed(error) }
            self?.persistFinished()
        }
    }

    private func persistFailed(_ error: Error) {
        errorMessage = error.localizedDescription
        link?.noteFailure(error)
        deferredReloads.formUnion([.project, .docs, .groups, .topics, .ideas, .agents, .commands, .skills, .workflows, .runs])
        // Sem conexão a memória otimista não vale mais e não dá para reler: volta à última leitura.
        if isReadOnly { restoreLastRead() }
    }

    private func persistFinished() {
        pendingWrites = max(0, pendingWrites - 1)
        if pendingWrites == 0 {
            scheduleCacheCapture()
            captureOwnRevision()
        }
        guard pendingWrites == 0, !deferredReloads.isEmpty, !isReadOnly else { return }
        let areas = deferredReloads
        deferredReloads = []
        for area in areas { Task { await self.refresh(area) } }
    }

    /// Relê uma área (agora, ou depois das gravações pendentes).
    private func schedule(_ area: Area) {
        if pendingWrites > 0 { deferredReloads.insert(area); return }
        Task { await self.refresh(area) }
    }

    func reloadAll() {
        for area in [Area.project, .docs, .groups, .topics, .ideas, .agents, .commands, .skills, .workflows, .runs, .checks] { schedule(area) }
    }

    func refresh(_ area: Area) async {
        if isReadOnly { return }
        defer { scheduleCacheCapture() }
        switch area {
        case .project: await refreshProject()
        case .docs: await refreshDocs()
        case .groups: await refreshGroups()
        case .topics: await refreshTopics()
        case .ideas: await refreshIdeas()
        case .agents: await refreshAgents()
        case .commands: await refreshCommands()
        case .skills: await refreshSkills()
        case .workflows: await refreshWorkflows()
        case .runs: await refreshRuns()
        case .checks: await refreshChecks()
        }
    }

    /// Aplica o resultado de uma leitura, a menos que uma gravação tenha começado enquanto se lia.
    private func applicable(_ area: Area) -> Bool {
        if pendingWrites > 0 { deferredReloads.insert(area); return false }
        return true
    }

    private func logReadFailure(_ event: String, _ error: Error) {
        VDLog.error(error, event: event, project: store.root, component: .app)
    }

    /// Guarda a revisão do Core depois de uma gravação do app: base para reconhecer o eco do FSEvents.
    private func captureOwnRevision() {
        capturingOwnRevision = true
        Task { [weak self] in
            guard let self = self else { return }
            let text = try? await self.store.call("project_revision", timeout: 15)
            if self.pendingWrites == 0 { self.ownRevision = text }
            self.capturingOwnRevision = false
        }
    }

    /// Verdadeiro quando o disco está como o app deixou na última gravação (o evento é só o eco dela).
    private func isOwnEcho() async -> Bool {
        guard let own = ownRevision else { return false }
        guard let now = try? await store.call("project_revision", timeout: 15) else { return false }
        return now == own
    }

    func startWatching() {
        if link == nil, ownRevision == nil { captureOwnRevision() }
        if let link = link {
            // SSH: o RemoteLink sonda `project_revision` a cada 6 s e reconecta com intervalo crescente.
            link.start()
            return
        }
        guard watcher == nil else { return }
        let watcher = FileWatcher(root: store.root) { [weak self] urls in
            Task { @MainActor in self?.handleExternalChanges(urls) }
        }
        watcher.start()
        self.watcher = watcher
    }

    func stopWatching() {
        watcher?.stop()
        watcher = nil
        link?.stop()
    }

    func reloadDirectoryGroups(_ concept: ItemConcept) {
        Task { await self.refreshDirectoryGroups(concept) }
    }

    private func refreshDirectoryGroups(_ concept: ItemConcept) async {
        if isReadOnly { return }
        do {
            let paths = try await store.listItemDirectories(concept.rawValue)
            if directoryGroups[concept] != paths { directoryGroups[concept] = paths }
        } catch {
            if directoryGroups[concept] == nil { directoryGroups[concept] = [] }
        }
    }

    private func recordPathMoves(_ moved: [SidebarItem: SidebarItem]) {
        guard !moved.isEmpty else { return }
        var current = latestPathMoves.filter { !exists($0.key) }
        for (old, new) in moved { current[old] = new }
        latestPathMoves = current
        moveRevision += 1
        for (old, new) in moved {
            if let oldRef = old.groupedReference, let newRef = new.groupedReference {
                let prefix = old.section == .ideas ? "idea:" : ""
                if old.section == .docs, let identity = docViewIdentities.removeValue(forKey: oldRef) { docViewIdentities[newRef] = identity }
                if let manager = docUndoManagers.removeValue(forKey: prefix + oldRef) { docUndoManagers[prefix + newRef] = manager }
                if old.section == .docs, let text = docTexts.removeValue(forKey: oldRef) { docTexts[newRef] = text }
            }
        }
    }

    func contentIdentity(for item: SidebarItem?) -> String {
        guard let original = item else { return "empty" }
        let item = exists(original) ? original : latestPathMoves[original] ?? original
        switch item {
        case .doc(let ref): return "doc:" + (docViewIdentities[ref]?.uuidString ?? ref)
        case .idea(let ref): return "idea:" + (idea(ref)?.id.uuidString ?? ref)
        case .group(let ref): return "review:" + (groups.first { $0.slug == ref }?.group.id.uuidString ?? ref)
        case .skill(let ref): return "skill:" + (skill(ref)?.id.uuidString ?? ref)
        default: return item.storageKey
        }
    }

    func reloadGroupedConcept(_ concept: ItemConcept) {
        switch concept {
        case .docs: reloadDocs()
        case .ideas: reloadIdeas()
        case .reviews: reloadGroups()
        case .skills: reloadSkills(); reloadAgents(); reloadCommands(); reloadWorkflows()
        }
    }

    // MARK: Grupos (diretórios)

    func createDirectoryGroup(_ concept: ItemConcept, path: String, undo: UndoManager? = nil) {
        Task {
            do {
                let created = try await store.itemGroups(concept: concept.rawValue, action: "create", path: path)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                await refreshDirectoryGroups(concept)
                undo?.registerUndo(withTarget: self) { model in model.deleteDirectoryGroup(concept, path: created, confirmed: false, undo: undo) }
                undo?.setActionName("Criar grupo")
            } catch { errorMessage = error.localizedDescription }
        }
    }

    /// Apaga o grupo (o Core recusa se tiver itens sem `confirmed`). Sem desfazer: o Core não devolve o conteúdo apagado.
    func deleteDirectoryGroup(_ concept: ItemConcept, path: String, confirmed: Bool, undo: UndoManager? = nil) {
        Task {
            do {
                _ = try store.normalizedGroupPath(path)
                _ = try await store.itemGroups(concept: concept.rawValue, action: "delete", path: path, confirmed: confirmed)
                reloadGroupedConcept(concept)
                await refreshDirectoryGroups(concept)
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func moveDirectoryGroup(_ concept: ItemConcept, from: String, to: String, undo: UndoManager?) {
        Task {
            do {
                _ = try await store.itemGroups(concept: concept.rawValue, action: "move", from: from, to: to)
                if concept == .docs {
                    var moved: [SidebarItem: SidebarItem] = [:]
                    for doc in docs where doc.slug.hasPrefix(from + "/") {
                        moved[.doc(doc.slug)] = .doc(to + String(doc.slug.dropFirst(from.count)))
                    }
                    recordPathMoves(moved)
                }
                reloadGroupedConcept(concept)
                await refreshDirectoryGroups(concept)
                undo?.registerUndo(withTarget: self) { model in model.moveDirectoryGroup(concept, from: to, to: from, undo: undo) }
                undo?.setActionName("Mover grupo")
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func moveGroupedItem(_ item: SidebarItem, to group: String, undo: UndoManager?) {
        guard let concept = item.section?.groupedConcept, let reference = item.groupedReference else { return }
        Task {
            do {
                let destination = try await store.itemGroups(concept: concept.rawValue, action: "move_item", to: group, reference: reference)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard destination != reference, !destination.isEmpty else { return }
                if concept == .docs { recordPathMoves([item: .doc(destination)]) }
                reloadGroupedConcept(concept)
                undo?.registerUndo(withTarget: self) { model in
                    model.moveGroupedItem(Self.sidebarItem(concept, destination), to: CoreStore.groupPath(of: reference), undo: undo)
                }
                undo?.setActionName("Mover item")
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private static func sidebarItem(_ concept: ItemConcept, _ reference: String) -> SidebarItem {
        switch concept {
        case .docs: return .doc(reference)
        case .ideas: return .idea(reference)
        case .reviews: return .group(reference)
        case .skills: return .skill(reference)
        }
    }

    // MARK: Mudanças externas

    /// Eventos do FSEvents: o eco das gravações do próprio app (revisão igual à guardada) é ignorado e não vira log
    /// "external". Durante uma gravação o evento ainda é aplicado (a releitura espera), mas não é logado como externo.
    private func handleExternalChanges(_ allURLs: [URL]) {
        // Origem de doc vinculado (.md na raiz): a revisão do Core só vê o link, então o texto é comparado direto.
        let rootPath = store.root.resolvingSymlinksInPath().path
        let rootMarkdown = allURLs.filter { FileWatcher.isRootMarkdown($0.resolvingSymlinksInPath().path, rootPath: rootPath) }
        if !rootMarkdown.isEmpty { linkedOriginsChanged(rootMarkdown.map { $0.lastPathComponent }) }
        let urls = allURLs.filter { !FileWatcher.isRootMarkdown($0.resolvingSymlinksInPath().path, rootPath: rootPath) }
        if urls.isEmpty { return }
        if pendingWrites > 0 || capturingOwnRevision {
            applyExternalChanges(urls, logAsExternal: false)
            return
        }
        Task { [weak self] in
            guard let self = self else { return }
            if await self.isOwnEcho() { return }
            self.applyExternalChanges(urls, logAsExternal: true)
            self.captureOwnRevision()
        }
    }

    private func applyExternalChanges(_ urls: [URL], logAsExternal: Bool) {
        var docSlugs = Set<String>()
        var groupsChanged = false, projectChanged = false
        var topicsChanged = false, ideasChanged = false, agentsChanged = false, commandsChanged = false, skillsChanged = false, workflowsChanged = false, runsChanged = false, checksChanged = false
        let docsPrefix = store.docsDir.resolvingSymlinksInPath().path + "/"
        for url in Set(urls.map { $0.resolvingSymlinksInPath().path }) {
            let prefix = store.root.resolvingSymlinksInPath().path + "/"
            if logAsExternal, url.hasPrefix(prefix) {
                VDLog.info("store.external_changed", "Mudança externa aplicada", project: store.root, component: .app,
                           context: ["file": String(url.dropFirst(prefix.count)), "origin": "external"])
            }
            if url.contains("/\(CoreStore.dataDirName)/runs/") {
                // Before the others: the steps' artifacts inside a run may have any name.
                runsChanged = true
            } else if url.hasSuffix("/" + CoreStore.manifestName) {
                projectChanged = true
            } else if url.contains("/docs/") || url.hasSuffix("/docs") {
                if url.hasPrefix(docsPrefix) {
                    docSlugs.insert(String(URL(fileURLWithPath: url).deletingPathExtension().path.dropFirst(docsPrefix.count - 1)).trimmingCharacters(in: CharacterSet(charactersIn: "/")))
                }
            } else if url.contains("/reviews/") || url.hasSuffix("/reviews") {
                groupsChanged = true
            } else if url.contains("/rules/") {
                topicsChanged = true
            } else if url.contains("/ideas/") || url.hasSuffix("/ideas") {
                ideasChanged = true
            } else if url.contains("/agents/") {
                agentsChanged = true
            } else if url.contains("/commands/") {
                commandsChanged = true
            } else if url.contains("/skills/") || url.hasSuffix("/skills") {
                skillsChanged = true
            } else if url.contains("/workflows/") {
                workflowsChanged = true
            } else if url.contains("/checks/") {
                checksChanged = true
            }
        }
        if !docSlugs.isEmpty {
            schedule(.docs)
            for slug in docSlugs where !slug.isEmpty { noteExternalDocChange(slug) }
        }
        if projectChanged { schedule(.project) }
        if groupsChanged { schedule(.groups) }
        if topicsChanged { schedule(.topics); schedule(.ideas); schedule(.project) }
        if ideasChanged { schedule(.ideas) }
        if agentsChanged { schedule(.agents) }
        if commandsChanged { schedule(.commands) }
        if skillsChanged { schedule(.skills) }
        if workflowsChanged { schedule(.workflows) }
        if runsChanged { schedule(.runs) }
        if checksChanged { schedule(.checks) }
        if topicsChanged || ideasChanged || projectChanged { releaseOrphans() }
    }

    /// Um Markdown da raiz mudou: os docs vinculados a ele recebem o aviso de mudança externa (se o texto difere).
    private func linkedOriginsChanged(_ names: [String]) {
        let slugs = docs.filter { doc in
            guard let target = doc.link?.target else { return false }
            return names.contains(target)
        }.map(\.slug)
        for slug in slugs { noteExternalDocChange(slug) }
    }

    /// Ideias (e padrões) promovidos para um tópico que não existe mais voltam a rascunho: tool `release_orphaned` do Core.
    private func releaseOrphans() {
        Task {
            await Task.yield()
            guard !isReadOnly, pendingWrites == 0 else { return }
            do {
                if try await store.releaseOrphaned() { reloadAll() }
            } catch {
                logReadFailure("model.release_orphaned_failed", error)
            }
        }
    }

    // MARK: Cache da última leitura (projeto SSH)

    /// Agenda (com atraso) a captura da leitura atual: base do modo offline e do cache em Application Support.
    private func scheduleCacheCapture() {
        guard let link = link, !cacheCaptureQueued else { return }
        cacheCaptureQueued = true
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard let self = self else { return }
            self.cacheCaptureQueued = false
            guard self.pendingWrites == 0, self.deferredReloads.isEmpty, !self.isReadOnly else { return }
            let cache = self.currentCache()
            self.lastReadCache = cache
            link.noteRead()
            if let data = try? VDJSON.compactEncoder.encode(cache) { RemoteCache.save(data, for: link.workspace) }
        }
    }

    private func currentCache() -> RemoteCache {
        RemoteCache(
            savedAt: Date(), project: project, docs: docs,
            groups: groups.map { RemoteCache.Record(slug: $0.slug, value: $0.group) },
            topics: topics.map { RemoteCache.Record(slug: $0.slug, value: $0.value) },
            ideas: ideas.map { RemoteCache.Record(slug: $0.slug, value: $0.value) },
            agents: agents.map { RemoteCache.Record(slug: $0.slug, value: $0.value) },
            commands: commands.map { RemoteCache.Record(slug: $0.slug, value: $0.value) },
            skills: skills.map { RemoteCache.Record(slug: $0.slug, value: $0.value) },
            workflows: workflows.map { RemoteCache.Record(slug: $0.slug, value: $0.value) },
            runs: runs.map { RemoteCache.Record(slug: $0.slug, value: $0.value) },
            checks: checks, docTexts: docTexts)
    }

    /// Descarta edições otimistas que não chegaram ao servidor e volta à última leitura.
    private func restoreLastRead() {
        guard let cache = lastReadCache else { return }
        let snapshot = cache.snapshot
        project = snapshot.project
        docs = snapshot.docs
        groups = snapshot.groups.map { GroupEntry(slug: $0.slug, group: $0.value) }
        topics = snapshot.topics.map { Entry(slug: $0.slug, value: $0.value) }
        ideas = snapshot.ideas.map { Entry(slug: $0.slug, value: $0.value) }
        agents = snapshot.agents.map { Entry(slug: $0.slug, value: $0.value) }
        commands = snapshot.commands.map { Entry(slug: $0.slug, value: $0.value) }
        skills = snapshot.skills.map { Entry(slug: $0.slug, value: $0.value) }
        workflows = snapshot.workflows.map { Entry(slug: $0.slug, value: $0.value) }
        apply(runs: cache.runs, checks: cache.checks, docTexts: cache.docTexts)
    }

    /// Um doc mudou no disco: só avisa o editor se o texto difere do que o próprio app gravou por último.
    private func noteExternalDocChange(_ slug: String) {
        Task {
            guard let text = try? await store.readDoc(slug) else { return }
            if pendingWrites > 0 || docWriteQueued.contains(slug) { return }
            if docTexts[slug] == text { return }
            docTexts[slug] = text
            externalDocChange[slug, default: 0] += 1
        }
    }

    // MARK: Leituras

    func reloadProject() { schedule(.project) }
    func reloadTopics() { schedule(.topics) }
    func reloadIdeas() { schedule(.ideas) }
    func reloadAgents() { schedule(.agents) }
    func reloadCommands() { schedule(.commands) }
    func reloadSkills() { schedule(.skills) }
    func reloadWorkflows() { schedule(.workflows) }
    func reloadRuns() { schedule(.runs) }
    func reloadChecks() { schedule(.checks) }
    func reloadDocs() { schedule(.docs) }
    func reloadGroups() { schedule(.groups) }

    private func refreshProject() async {
        do {
            let loaded = try await store.loadProject()
            guard applicable(.project) else { return }
            if loaded != project { project = loaded }
        } catch { logReadFailure("model.load_project_failed", error) }
    }

    private func refreshTopics() async {
        do {
            let list = try await store.listTopics().map { Entry(slug: $0.slug, value: $0.value) }
            guard applicable(.topics) else { return }
            if list != topics { topics = list }
        } catch { logReadFailure("model.load_topics_failed", error) }
    }

    private func refreshIdeas() async {
        do {
            let list = try await store.listIdeas().map { Entry(slug: $0.slug, value: $0.value) }
            guard applicable(.ideas) else { return }
            let oldPaths = Dictionary(ideas.map { ($0.value.id, $0.slug) }, uniquingKeysWith: { first, _ in first })
            var moved: [SidebarItem: SidebarItem] = [:]
            for entry in list { if let old = oldPaths[entry.value.id], old != entry.slug { moved[.idea(old)] = .idea(entry.slug) } }
            if list != ideas { ideas = list }
            recordPathMoves(moved)
            await refreshDirectoryGroups(.ideas)
        } catch { logReadFailure("model.load_ideas_failed", error) }
    }

    private func refreshAgents() async {
        do {
            let list = try await store.listAgents().map { Entry(slug: $0.slug, value: $0.value) }
            guard applicable(.agents) else { return }
            if list != agents { agents = list }
        } catch { logReadFailure("model.load_agents_failed", error) }
    }

    private func refreshCommands() async {
        do {
            let list = try await store.listCommands().map { Entry(slug: $0.slug, value: $0.value) }
            guard applicable(.commands) else { return }
            if list != commands { commands = list }
        } catch { logReadFailure("model.load_commands_failed", error) }
    }

    private func refreshSkills() async {
        do {
            let list = try await store.listSkills().map { Entry(slug: $0.slug, value: $0.value) }
            guard applicable(.skills) else { return }
            let oldPaths = Dictionary(skills.map { ($0.value.id, $0.slug) }, uniquingKeysWith: { first, _ in first })
            var moved: [SidebarItem: SidebarItem] = [:]
            for entry in list { if let old = oldPaths[entry.value.id], old != entry.slug { moved[.skill(old)] = .skill(entry.slug) } }
            if list != skills { skills = list }
            recordPathMoves(moved)
            await refreshDirectoryGroups(.skills)
        } catch { logReadFailure("model.load_skills_failed", error) }
    }

    private func refreshWorkflows() async {
        do {
            let list = try await store.listWorkflows().map { Entry(slug: $0.slug, value: $0.value) }
            guard applicable(.workflows) else { return }
            if list != workflows { workflows = list }
        } catch { logReadFailure("model.load_workflows_failed", error) }
    }

    private func refreshRuns() async {
        do {
            let list = try await store.listRuns().map { Entry(slug: $0.slug, value: $0.value) }
            guard applicable(.runs) else { return }
            if list != runs { runs = list }
        } catch { logReadFailure("model.load_runs_failed", error) }
    }

    private func refreshChecks() async {
        do {
            let list = try await store.listChecks()
            guard applicable(.checks) else { return }
            if list != checks { checks = list }
        } catch { logReadFailure("model.load_checks_failed", error) }
    }

    private func refreshDocs() async {
        do {
            let list = try await store.listDocs()
            guard applicable(.docs) else { return }
            for doc in list where docViewIdentities[doc.slug] == nil { docViewIdentities[doc.slug] = UUID() }
            docViewIdentities = docViewIdentities.filter { entry in list.contains { $0.slug == entry.key } }
            if list != docs { docs = list }
            await refreshDirectoryGroups(.docs)
        } catch { logReadFailure("model.load_docs_failed", error) }
    }

    private func refreshGroups() async {
        do {
            let list = try await store.listGroups().map { GroupEntry(slug: $0.slug, group: $0.value) }
            guard applicable(.groups) else { return }
            let oldPaths = Dictionary(groups.map { ($0.group.id, $0.slug) }, uniquingKeysWith: { first, _ in first })
            var moved: [SidebarItem: SidebarItem] = [:]
            for entry in list { if let old = oldPaths[entry.group.id], old != entry.slug { moved[.group(old)] = .group(entry.slug) } }
            if list != groups { groups = list }
            recordPathMoves(moved)
            await refreshDirectoryGroups(.reviews)
        } catch { logReadFailure("model.load_groups_failed", error) }
    }

    // MARK: Project / links

    func mutateProject(_ actionName: String, undo: UndoManager?, _ change: (inout Project) -> Void) {
        let old = project
        change(&project)
        guard project != old else { return }
        saveProject()
        undo?.registerUndo(withTarget: self) { model in
            model.mutateProject(actionName, undo: undo) { $0 = old }
        }
        undo?.setActionName(actionName)
    }

    /// Changes the stack like `mutateProject`. O Core mantém o badge do README ao gravar o projeto.
    func mutateStack(_ actionName: String, undo: UndoManager?, _ change: (inout [StackItem]) -> Void) {
        let old = project.stack
        var new = old
        change(&new)
        guard new != old else { return }
        project.stack = new
        saveProject()
        undo?.registerUndo(withTarget: self) { model in
            model.mutateStack(actionName, undo: undo) { $0 = old }
        }
        undo?.setActionName(actionName)
    }

    /// Último problema ao atualizar o README.md (mostrado na página Stack); o Core avisa na resposta de `add_stack`.
    var readmeWarning: String?

    private func saveProject() {
        persist { [weak self] in
            guard let self = self else { return }
            try await self.store.saveProject(self.project)
        }
    }

    // MARK: Patterns

    /// The patterns plus the rule topics they enforce: what a pattern change touches, so undo can put it back.
    struct PatternsSnapshot {
        var patterns: [ProjectPattern]
        var topics: [String: RuleTopic]
    }

    private func patternsSnapshot() -> PatternsSnapshot {
        var files: [String: RuleTopic] = [:]
        for entry in topics where entry.value.sourcePattern != nil { files[entry.slug] = entry.value }
        return PatternsSnapshot(patterns: project.patterns, topics: files)
    }

    /// Writes a snapshot back: pattern topics not in it are deleted, the others rewritten, the patterns restored.
    private func restorePatterns(_ snapshot: PatternsSnapshot, _ actionName: String, undo: UndoManager?) {
        let current = patternsSnapshot()
        project.patterns = snapshot.patterns
        topics = topics.filter { snapshot.topics[$0.slug] != nil || current.topics[$0.slug] == nil }
        for (slug, topic) in snapshot.topics {
            if let index = topics.firstIndex(where: { $0.slug == slug }) { topics[index].value = topic } else { topics.append(Entry(slug: slug, value: topic)) }
        }
        persist { [weak self] in
            guard let self = self else { return }
            for slug in current.topics.keys where snapshot.topics[slug] == nil { try await self.store.deleteRecord(.rule, slug: slug) }
            for (slug, topic) in snapshot.topics where current.topics[slug] != topic { try await self.store.saveRecord(.rule, slug: slug, value: topic) }
            try await self.store.saveProject(self.project)
        }
        undo?.registerUndo(withTarget: self) { model in model.restorePatterns(current, actionName, undo: undo) }
        undo?.setActionName(actionName)
    }

    /// Runs a pattern change through the Core (it also writes the pattern's rule topic), then refreshes both.
    /// Undo restores the patterns and their topics as they were.
    func changePatterns(_ actionName: String, undo: UndoManager?, _ change: @escaping (CoreStore) async throws -> Void) {
        let before = patternsSnapshot()
        Task {
            do {
                // Termina as gravações pendentes antes: a mudança de padrão relê o projeto no Core.
                await writeChain?.value
                try await change(store)
                await refreshProject()
                await refreshTopics()
                undo?.registerUndo(withTarget: self) { model in model.restorePatterns(before, actionName, undo: undo) }
                undo?.setActionName(actionName)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Moves a pattern (order only lives in vibedeck.json, so it can be undone).
    func movePatterns(from source: IndexSet, to destination: Int, undo: UndoManager?) {
        mutateProject("Reordenar padrões", undo: undo) { $0.patterns.move(fromOffsets: source, toOffset: destination) }
    }

    // MARK: Docs

    /// All chosen documents are one undoable action. O Core grava tudo ou nada (`doc_generate_apply`, author=ai);
    /// a validação de limites já foi feita pelo Core e a folha só entrega propostas aceitáveis.
    @discardableResult
    func acceptGeneratedDocs(_ proposed: [DocGenerate.Document], undo: UndoManager?, group: String = "") -> Bool {
        guard !proposed.isEmpty else { return false }
        if isReadOnly { errorMessage = Self.offlineMessage; return false }
        Task {
            do {
                let created = try await store.docGenerateApply(proposed, group: group)
                var snapshot: [String: String] = [:]
                for slug in created { snapshot[slug] = try await store.readDoc(slug) }
                await refreshDocs()
                undo?.registerUndo(withTarget: self) { model in model.toggleGeneratedDocs(snapshot, remove: true, undo: undo) }
                undo?.setActionName("Gerar documentos")
            } catch {
                await refreshDocs()
                errorMessage = error.localizedDescription
            }
        }
        return true
    }

    private func toggleGeneratedDocs(_ snapshot: [String: String], remove: Bool, undo: UndoManager?) {
        Task {
            do {
                // Preserve documents edited externally after acceptance, and avoid overwriting on redo.
                for (slug, text) in snapshot {
                    if remove {
                        guard try await store.readDoc(slug) == text else {
                            throw VibeDeckError.discoverFailed("Um documento mudou após o aceite; não foi possível desfazer o lote.")
                        }
                    } else if docs.contains(where: { $0.slug == slug }) {
                        throw VibeDeckError.discoverFailed("Um documento ocupa o destino; não foi possível refazer o lote.")
                    }
                }
                for (slug, text) in snapshot {
                    if remove { try await store.deleteDoc(slug) }
                    else { try await store.writeDoc(slug, text: text) }
                }
                await refreshDocs()
                undo?.registerUndo(withTarget: self) { model in model.toggleGeneratedDocs(snapshot, remove: !remove, undo: undo) }
                undo?.setActionName("Gerar documentos")
            } catch { errorMessage = error.localizedDescription; await refreshDocs() }
        }
    }

    /// Cria o doc já na memória (slug escolhido aqui) e grava no Core com a mesma referência.
    func createDoc(title: String, reference: String? = nil) -> String? {
        guard let name = title.trimmed.nonEmpty else { errorMessage = VibeDeckError.invalidName.localizedDescription; return nil }
        do {
            let slug = try newSlug(title: name, reference: reference, existing: docs.map(\.slug))
            let text = "# \(name)\n\n"
            docs.append(DocInfo(slug: slug, title: name, tags: [], modified: Date()))
            docViewIdentities[slug] = UUID()
            docTexts[slug] = text
            persist { [weak self] in
                guard let self = self else { return }
                let created = try await self.store.createDoc(title: name, reference: slug)
                if created != slug { self.reloadDocs() }
            }
            return slug
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Slug livre entre os existentes (`a/b` quando há caminho de grupo), como o Core faria.
    private func newSlug(title: String, reference: String?, existing: [String]) throws -> String {
        let base = try store.normalizedGroupPath(reference ?? Slug.make(title))
        let wanted = base.contains("/") ? base : Slug.make(base)
        var slug = wanted
        var n = 2
        let taken = Set(existing)
        while taken.contains(slug) {
            slug = "\(wanted)-\(n)"
            n += 1
        }
        return slug
    }

    /// One undo history per doc, so Cmd+Z never crosses documents and survives switching between them.
    @ObservationIgnored private var docUndoManagers: [String: UndoManager] = [:]

    func undoManager(forDoc slug: String) -> UndoManager {
        if let existing = docUndoManagers[slug] { return existing }
        let manager = UndoManager()
        docUndoManagers[slug] = manager
        return manager
    }

    /// Texto do doc já conhecido (vazio se ainda não foi lido; use `loadDoc`).
    func readDoc(_ slug: String) -> String {
        docTexts[slug] ?? ""
    }

    /// Lê o doc no Core, guarda no cache e devolve o texto.
    func loadDoc(_ slug: String) async -> String {
        if isReadOnly { return docTexts[slug] ?? "" }
        if let cached = docTexts[slug], docWriteQueued.contains(slug) { return cached }
        do {
            let text = try await store.readDoc(slug)
            docTexts[slug] = text
            return text
        } catch {
            errorMessage = error.localizedDescription
            return docTexts[slug] ?? ""
        }
    }

    func saveDoc(_ slug: String, text: String) {
        docTexts[slug] = text
        let title = MarkdownText.title(of: text) ?? slug
        if let i = docs.firstIndex(where: { $0.slug == slug }), docs[i].title != title {
            docs[i].title = title
        }
        guard docWriteQueued.insert(slug).inserted else { return }
        persist { [weak self] in
            guard let self = self else { return }
            self.docWriteQueued.remove(slug)
            guard let latest = self.docTexts[slug] else { return }
            try await self.store.writeDoc(slug, text: latest)
        }
    }

    /// Copies files dropped/picked into a doc or idea to `.vibedeck/attachments/`; returns their markdown links.
    /// PEDIDO-CORE (import_attachment): o Core ainda não recebe anexos.
    func importAttachments(_ urls: [URL], owner: String) -> [String] {
        if !urls.isEmpty { errorMessage = CoreError.unsupported("import_attachment").localizedDescription }
        return []
    }

    /// Saves pasted image data as an attachment; returns its markdown link.
    func importAttachment(data: Data, name: String, owner: String) -> String? {
        errorMessage = CoreError.unsupported("import_attachment").localizedDescription
        return nil
    }

    func setDocTags(_ slug: String, _ tags: [String]) {
        persist { [weak self] in
            guard let self = self else { return }
            try await self.store.setTags(kind: "doc", ref: slug, tags: tags)
            let text = try await self.store.readDoc(slug)
            self.docTexts[slug] = text
            self.externalDocChange[slug, default: 0] += 1
            self.reloadDocs()
        }
    }

    /// Re-vincula um .md da raiz (`link_doc`); o desvínculo (`deleteDoc`) persiste no Core.
    func linkDoc(file: String) {
        persist { [weak self] in
            guard let self = self else { return }
            try await self.store.linkDoc(file: file)
            self.reloadDocs()
        }
    }

    func deleteDoc(_ slug: String) {
        docs.removeAll { $0.slug == slug }
        docTexts.removeValue(forKey: slug)
        persist { [weak self] in
            guard let self = self else { return }
            try await self.store.deleteDoc(slug)
            self.reloadDocs()
        }
    }

    // MARK: Review groups

    func group(_ slug: String) -> ReviewGroup? {
        groups.first { $0.slug == slug }?.group
    }

    func createGroup(title: String, reference: String? = nil) -> String? {
        guard let name = title.trimmed.nonEmpty else { errorMessage = VibeDeckError.invalidName.localizedDescription; return nil }
        do {
            let slug = try newSlug(title: name, reference: reference, existing: groups.map(\.slug))
            let group = ReviewGroup(title: name)
            groups.append(GroupEntry(slug: slug, group: group))
            persist { [weak self] in
                guard let self = self else { return }
                try await self.store.saveRecord(.review, slug: slug, value: group)
            }
            return slug
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func deleteGroup(_ slug: String) {
        groups.removeAll { $0.slug == slug }
        persist { [weak self] in
            guard let self = self else { return }
            try await self.store.deleteRecord(.review, slug: slug)
        }
    }

    /// Mutates a group, saves it, and registers an undo that restores the previous value
    /// (undoing registers the inverse, so Cmd+Shift+Z redoes).
    func mutateGroup(_ slug: String, _ actionName: String, undo: UndoManager?, _ change: (inout ReviewGroup) -> Void) {
        guard let index = groups.firstIndex(where: { $0.slug == slug }) else { return }
        let old = groups[index].group
        var new = old
        change(&new)
        guard new != old else { return }
        groups[index].group = new
        persist { [weak self] in
            guard let self = self else { return }
            try await self.store.saveRecord(.review, slug: slug, value: new)
        }
        undo?.registerUndo(withTarget: self) { model in
            model.mutateGroup(slug, actionName, undo: undo) { $0 = old }
        }
        undo?.setActionName(actionName)
    }

    func mutateItem(_ slug: String, _ id: ReviewItem.ID, _ actionName: String, undo: UndoManager?, _ change: @escaping (inout ReviewItem) -> Void) {
        mutateGroup(slug, actionName, undo: undo) { group in
            guard let i = group.items.firstIndex(where: { $0.id == id }) else { return }
            var item = group.items[i]
            change(&item)
            if item != group.items[i] {
                item.updatedAt = .now
                group.items[i] = item
            }
        }
    }

    // MARK: Rules

    func topic(_ slug: String) -> RuleTopic? {
        topics.first { $0.slug == slug }?.value
    }

    func createTopic(title: String) -> String? {
        guard let name = title.trimmed.nonEmpty else { errorMessage = VibeDeckError.invalidName.localizedDescription; return nil }
        let base = Slug.make(name)
        var slug = base
        var n = 2
        let taken = Set(topics.map(\.slug))
        while taken.contains(slug) {
            slug = "\(base)-\(n)"
            n += 1
        }
        let topic = RuleTopic(title: name)
        topics.append(Entry(slug: slug, value: topic))
        persist { [weak self] in
            guard let self = self else { return }
            try await self.store.saveRecord(.rule, slug: slug, value: topic)
        }
        return slug
    }

    /// Apaga o tópico; o Core solta a ideia e o padrão que ele impunha.
    func deleteTopic(_ slug: String) {
        topics.removeAll { $0.slug == slug }
        persist { [weak self] in
            guard let self = self else { return }
            try await self.store.deleteRecord(.rule, slug: slug)
            self.reloadTopics()
            self.reloadIdeas()
            self.reloadProject()
        }
    }

    func mutateTopic(_ slug: String, _ actionName: String, undo: UndoManager?, _ change: @escaping (inout RuleTopic) -> Void) {
        mutate(\.topics, .rule, slug, actionName, undo: undo, change)
    }

    /// Runs the scripts of a topic's rules off the main thread and keeps each outcome in `testRuns`.
    func runTests(topic slug: String) {
        startRuleExecution(topic: slug)
    }

    func runAllTests() {
        startRuleExecution()
    }

    enum TestGeneration: Equatable {
        case queued, running, done
        case failed(String)
        var isActive: Bool { self == .queued || self == .running }
    }

    /// Background test generation per topic (see `generateAllTests`); finished entries stay until the next batch.
    var generatingTests: [String: TestGeneration] = [:]
    private var generationTask: Task<Void, Never>?
    var isGeneratingTests: Bool { generatingTests.values.contains(where: \.isActive) }

    /// Writes the tests of `selection` for every topic that has such rules, one background `claude -p` per
    /// topic, at most `maxConcurrent` at a time. The scripts register themselves through the CLI, so the
    /// topics reload from disk as each job ends.
    func generateAllTests(_ selection: RuleTestPrompt.Selection, provider: AIProvider = .claude, maxConcurrent: Int = 3) {
        guard !isGeneratingTests, ruleExecution?.active != true else { return }
        let cli = ClaudeUsageView.cliPath ?? "vibedeck"
        let jobs = topics.compactMap { entry -> (slug: String, prompt: String, rules: [Rule])? in
            guard !RuleTestPrompt.rules(entry.value, selection).isEmpty else { return nil }
            return (entry.slug, RuleTestPrompt.generate(slug: entry.slug, topic: entry.value, selection: selection, headless: cli), RuleTestPrompt.rules(entry.value, selection))
        }
        guard !jobs.isEmpty else { return }
        generatingTests = Dictionary(uniqueKeysWithValues: jobs.map { ($0.slug, .queued) })
        let root = store.root
        let store = store
        generationTask = Task {
            await withTaskGroup(of: (String, String?).self) { group in
                var queue = jobs[...]
                var active = 0
                while true {
                    while active < maxConcurrent, !Task.isCancelled, let job = queue.popFirst() {
                        generatingTests[job.slug] = .running
                        active += 1
                        group.addTask {
                            do {
                                try await RuleTestGenerator.run(root: root, store: store, prompt: job.prompt, provider: provider,
                                    operation: "Gerar testes · " + job.slug, topic: job.slug, expectedRules: job.rules)
                                return (job.slug, nil)
                            }
                            catch { return (job.slug, error.localizedDescription) }
                        }
                    }
                    guard let (slug, failure) = await group.next() else { break }
                    active -= 1
                    reloadTopics()
                    guard !Task.isCancelled else { continue }
                    generatingTests[slug] = failure.map(TestGeneration.failed) ?? .done
                    if let failure, let title = topic(slug)?.title { errorMessage = "Testes de \"\(title)\": \(failure)" }
                }
            }
            generationTask = nil
        }
    }

    /// Stops the batch: running `claude` processes are terminated and queued topics dropped.
    func cancelTestGeneration() {
        generationTask?.cancel()
        generatingTests = generatingTests.filter { !$0.value.isActive }
    }

    /// Checks that verified at least one rule of the topic, newest first.
    func checks(forTopic slug: String) -> [RuleCheck] {
        checks.filter { $0.topics.contains(slug) }
    }

    /// Topics that apply to files/explicit refs (slug, id or title): global ones, glob matches and named ones.
    func applicableTopics(files: [String], explicit: [String] = []) -> [Entry<RuleTopic>] {
        let relative = files.map(store.relativePath)
        let named = Set(explicit.compactMap { ref -> String? in
            let lowered = ref.lowercased()
            return topics.first { $0.slug == ref || $0.value.id.uuidString.lowercased() == lowered || $0.value.title.caseInsensitiveCompare(ref) == .orderedSame }?.slug
        })
        return topics.filter { entry in
            entry.value.isGlobal || named.contains(entry.slug) || relative.contains { entry.value.matches(file: $0) }
        }
    }

    /// Why a review item can't be considered verified yet (empty = verified or not gated).
    /// Mesma regra do Core (`update_review_item` recusa `done` sem check aprovado); calculada na memória para o selo da UI.
    func verificationProblems(for item: ReviewItem) -> [String] {
        let required = applicableTopics(files: [item.target?.file].compactMap { $0 }, explicit: item.rules)
        let rules = required.flatMap { entry in entry.value.rules.map { (entry.slug, $0) } }
        guard !rules.isEmpty else { return [] }
        guard let check = checks.first(where: { $0.reviewItem == item.id }) else {
            return ["Nenhum check registrado para este item (tópicos: \(required.map(\.slug).joined(separator: ", ")))."]
        }
        if !check.passed {
            return check.failures.map { "Falhou no último check: \($0)" }
        }
        let answered = Set(check.results.map(\.ruleId))
        var problems: [String] = []
        for (slug, rule) in rules where !answered.contains(rule.id) {
            if !rule.testState.needsAgent {
                problems.append("Regra nova desde o último check: [\(slug)] \(rule.text)")
            } else if rule.severity == .must {
                problems.append("Regra manual obrigatória sem verificação: [\(slug)] \(rule.text) (envie o check com as regras manuais respondidas)")
            }
        }
        return problems
    }

    func requiredTopics(for item: ReviewItem) -> [String] {
        applicableTopics(files: [item.target?.file].compactMap { $0 }, explicit: item.rules).map(\.slug)
    }

    /// Tags already used by docs, review groups, topics and ideas: the vocabulary the rules Descubra prefers.
    var tagVocabulary: [String] {
        let all = docs.flatMap(\.tags) + groups.flatMap(\.group.tags) + topics.flatMap(\.value.tags) + ideas.flatMap(\.value.tags)
        return Array(Set(all)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Rules of the other topics, so the Descubra can flag duplicates and conflicts.
    func knownTopics(excluding slug: String? = nil) -> [RuleDiscover.KnownTopic] {
        topics.filter { $0.slug != slug }.map { .init(slug: $0.slug, title: $0.value.title, rules: $0.value.rules.map(\.text)) }
    }


    // MARK: Ideas

    /// A ideia que pode ser implementada agora, relida do Core (a memória pode estar um passo atrás): o gate único
    /// para implementar (padrão ou workflow, app ou chat). Lança todos os motivos pelos quais não pode agora.
    func currentImplementationIdea(_ id: UUID) async throws -> (slug: String, idea: Idea) {
        try await store.implementableIdea(id.uuidString)
    }

    /// Dependencies that keep the idea from being implemented, from the loaded ideas.
    func ideaDependencyBlockers(_ idea: Idea) -> [IdeaDependencyBlocker] {
        IdeaImplementation.dependencyBlockers(of: idea, in: ideas.map { (slug: $0.slug, idea: $0.value) })
    }

    /// Ideas that depend directly on `id`, derived from the other ideas' dependencies.
    func ideaDependents(_ id: UUID) -> [IdeaLink] {
        IdeaImplementation.dependents(of: id, in: ideas.map { (slug: $0.slug, idea: $0.value) })
    }

    /// Writes through the Core validation (`update_idea`); undo restores the previous list (validated again).
    func setIdeaDependencies(_ slug: String, _ ids: [UUID], _ actionName: String, undo: UndoManager?) {
        guard let old = idea(slug)?.dependencies, old != ids else { return }
        Task {
            do {
                await writeChain?.value
                _ = try await store.call("update_idea", ["idea": slug, "dependencies": ids.map(\.uuidString)])
                await refreshIdeas()
                VDLog.info("idea.dependencies_changed", "Dependências da ideia alteradas", project: store.root, component: .app,
                           context: ["slug": slug, "count": String(ids.count)])
                undo?.registerUndo(withTarget: self) { $0.setIdeaDependencies(slug, old, actionName, undo: undo) }
                undo?.setActionName(actionName)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private struct IdeaImplementationState {
        var slug: String
        var idea: Idea
        var topicSlug: String
        var topic: RuleTopic?
        var runRef: String?
    }

    private func restoreImplementation(_ state: IdeaImplementationState, undo: UndoManager?, registerUndo: Bool = true) {
        let inverse = IdeaImplementationState(slug: state.slug, idea: idea(state.slug) ?? state.idea,
                                              topicSlug: state.topicSlug, topic: topic(state.topicSlug), runRef: state.runRef)
        if let index = ideas.firstIndex(where: { $0.slug == state.slug }) { ideas[index].value = state.idea }
        if let restored = state.topic {
            if let index = topics.firstIndex(where: { $0.slug == state.topicSlug }) { topics[index].value = restored }
            else { topics.append(Entry(slug: state.topicSlug, value: restored)) }
        } else {
            topics.removeAll { $0.slug == state.topicSlug }
        }
        persist { [weak self] in
            guard let self = self else { return }
            try await self.store.saveRecord(.idea, slug: state.slug, value: state.idea)
            if let restored = state.topic { try await self.store.saveRecord(.rule, slug: state.topicSlug, value: restored) }
            else { try? await self.store.deleteRecord(.rule, slug: state.topicSlug) }
            self.reloadIdeas(); self.reloadTopics(); self.reloadRuns()
        }
        if registerUndo {
            undo?.registerUndo(withTarget: self) { $0.restoreImplementation(inverse, undo: undo) }
            undo?.setActionName("Implementar ideia")
        }
    }

    /// A execução de workflow ligada à ideia (mesma entrada estável), se já existe.
    func ideaRun(_ idea: Idea, workflow: String) -> Entry<WorkflowRun>? {
        let input = IdeaImplementation.workflowInput(idea)
        return runs.first { $0.value.workflow == workflow && $0.value.input == input }
    }

    func prepareIdeaImplementation(_ id: UUID, workflow: String? = nil, restart: Bool = false,
                                   skippingPaths: Set<String> = [], provider: AIProvider, undo: UndoManager?) async throws
        -> (prompt: String, execution: (ref: String, run: WorkflowRun)?) {
        let (slug, idea) = try await currentImplementationIdea(id)
        let previousTopic = idea.promotedTopic.flatMap { self.topic($0) }
        var workflowSlug: String?
        if let workflow {
            guard let found = self.workflow(workflow) else { throw VibeDeckError.workflowNotFound(workflow) }
            guard !found.steps.isEmpty else { throw VibeDeckError.invalidWorkflow("o workflow não tem etapas.") }
            workflowSlug = workflow
            if let run = ideaRun(idea, workflow: workflow)?.value, run.provider != provider {
                throw VibeDeckError.invalidWorkflow("a execução pertence a outro provedor. Selecione \(run.provider.title) antes de continuar.")
            }
        }
        guard let topic = await promoteIdea(slug, skippingPaths: skippingPaths, forImplementation: false) else {
            throw VibeDeckError.invalidWorkflow("não foi possível promover as regras da ideia.")
        }
        let previousValue: RuleTopic? = idea.promotedTopic == topic ? previousTopic : nil
        var before = IdeaImplementationState(slug: slug, idea: idea, topicSlug: topic, topic: previousValue, runRef: nil)
        do {
            var execution: (ref: String, run: WorkflowRun)?
            if let workflowSlug {
                let existing = ideaRun(idea, workflow: workflowSlug)
                if let existing {
                    // Retoma a mesma execução (uma parada volta a andar) ou reinicia da primeira etapa.
                    let run: WorkflowRun
                    if restart { run = try await store.restartRun(existing.slug) } else { run = try await store.resumeRun(existing.slug) }
                    execution = (existing.slug, run)
                } else {
                    let started = try await store.startRun(workflowSlug, input: IdeaImplementation.workflowInput(idea), provider: provider)
                    let run = try await store.loadRun(started.ref)
                    execution = (started.ref, run)
                    before.runRef = started.ref
                }
            }
            await refreshIdeas(); await refreshTopics(); await refreshRuns()
            undo?.registerUndo(withTarget: self) { $0.restoreImplementation(before, undo: undo) }
            undo?.setActionName("Implementar ideia")
            return (IdeaImplementation.prompt(slug: slug, idea: idea, topic: topic), execution)
        } catch {
            restoreImplementation(before, undo: undo, registerUndo: false)
            throw error
        }
    }

    func idea(_ slug: String) -> Idea? {
        ideas.first { $0.slug == slug }?.value
    }

    func createIdea(title: String, reference: String? = nil) -> String? {
        guard let name = title.trimmed.nonEmpty else { errorMessage = VibeDeckError.invalidName.localizedDescription; return nil }
        do {
            let slug = try newSlug(title: name, reference: reference, existing: ideas.map(\.slug))
            let value = Idea(title: name, body: nil, tags: [], author: .human)
            ideas.append(Entry(slug: slug, value: value))
            persist { [weak self] in
                guard let self = self else { return }
                try await self.store.saveRecord(.idea, slug: slug, value: value)
            }
            return slug
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Apaga a ideia. (O commit automático da remoção em repositórios git deixou de existir: ver PEDIDO-CORE.)
    func deleteIdea(_ slug: String) {
        ideas.removeAll { $0.slug == slug }
        persist { [weak self] in
            guard let self = self else { return }
            try await self.store.deleteRecord(.idea, slug: slug)
        }
    }

    func mutateIdea(_ slug: String, _ actionName: String, undo: UndoManager?, _ change: @escaping (inout Idea) -> Void) {
        mutate(\.ideas, .idea, slug, actionName, undo: undo) { idea in
            let before = idea
            change(&idea)
            if idea != before { idea.updatedAt = .now }
        }
    }

    // MARK: Agents

    /// Adiciona itens do catálogo de kits (`add_kit`). Um único passo de desfazer remove (e refaz) os itens criados.
    @discardableResult
    func addKitItems(_ refs: [String], undo: UndoManager?) -> Bool {
        let name = "Adicionar itens do catálogo"
        Task {
            do {
                await writeChain?.value
                let before = kitKeys()
                _ = try await store.call("add_kit", ["items": refs, "author": "human"])
                await refresh(.agents); await refresh(.commands); await refresh(.skills); await refresh(.workflows)
                var toggles: [(Bool) -> Void] = []
                for entry in agents where !before.contains("agent/" + entry.slug) {
                    let slug = entry.slug, value = entry.value
                    toggles.append { [weak self] remove in self?.toggleCreatedItem(.agent, slug, value, remove: remove, name: name, undo: nil) }  // undo agrupado: o passo único é registrado pelo chamador
                }
                for entry in commands where !before.contains("command/" + entry.slug) {
                    let slug = entry.slug, value = entry.value
                    toggles.append { [weak self] remove in self?.toggleCreatedItem(.command, slug, value, remove: remove, name: name, undo: nil) }  // undo agrupado: o passo único é registrado pelo chamador
                }
                for entry in skills where !before.contains("skill/" + entry.slug) {
                    let slug = entry.slug, value = entry.value
                    toggles.append { [weak self] remove in self?.toggleCreatedItem(.skill, slug, value, remove: remove, name: name, undo: nil) }  // undo agrupado: o passo único é registrado pelo chamador
                }
                for entry in workflows where !before.contains("workflow/" + entry.slug) {
                    let slug = entry.slug, value = entry.value
                    toggles.append { [weak self] remove in self?.toggleCreatedItem(.workflow, slug, value, remove: remove, name: name, undo: nil) }  // undo agrupado: o passo único é registrado pelo chamador
                }
                reloadKitItems()
                if !toggles.isEmpty {
                    // Um único passo de undo: desfaz remove os itens novos; o redo os recria (registerKitUndo).
                    undo?.registerUndo(withTarget: self) { model in
                        for toggle in toggles { toggle(true) }
                        model.registerKitUndo(toggles, remove: false, name: name, undo: undo)
                    }
                    undo?.setActionName(name)
                }
            } catch {
                VDLog.error(error, event: "store.kit_add_failed", project: store.root, component: .app)
                errorMessage = error.localizedDescription
            }
        }
        return true
    }

    private func kitKeys() -> Set<String> {
        var keys = Set<String>()
        for entry in agents { keys.insert("agent/" + entry.slug) }
        for entry in commands { keys.insert("command/" + entry.slug) }
        for entry in skills { keys.insert("skill/" + entry.slug) }
        for entry in workflows { keys.insert("workflow/" + entry.slug) }
        return keys
    }

    private func registerKitUndo(_ toggles: [(Bool) -> Void], remove: Bool, name: String, undo: UndoManager?) {
        guard let undo = undo else { return }
        undo.registerUndo(withTarget: self) { model in
            for toggle in toggles { toggle(remove) }
            model.registerKitUndo(toggles, remove: !remove, name: name, undo: undo)
        }
        undo.setActionName(name)
    }

    private func reloadKitItems() {
        reloadAgents(); reloadCommands(); reloadSkills(); reloadWorkflows()
    }

    func agent(_ slug: String) -> Agent? {
        agents.first { $0.slug == slug }?.value
    }

    func createAgent(title: String) -> String? {
        guard let name = title.trimmed.nonEmpty else { errorMessage = VibeDeckError.invalidName.localizedDescription; return nil }
        let slug = freeSlug(Slug.make(name), existing: agents.map(\.slug))
        let value = Agent(title: name, summary: nil, model: nil, tools: [], prompt: "", tags: [], author: .human)
        agents.append(Entry(slug: slug, value: value))
        persist { [weak self] in
            guard let self = self else { return }
            try await self.store.saveRecord(.agent, slug: slug, value: value)
        }
        return slug
    }

    func deleteAgent(_ slug: String) {
        agents.removeAll { $0.slug == slug }
        persist { [weak self] in
            guard let self = self else { return }
            try await self.store.deleteRecord(.agent, slug: slug)
        }
    }

    func mutateAgent(_ slug: String, _ actionName: String, undo: UndoManager?, _ change: @escaping (inout Agent) -> Void) {
        mutate(\.agents, .agent, slug, actionName, undo: undo) { agent in
            let before = agent
            change(&agent)
            if agent != before { agent.updatedAt = .now }
        }
    }

    /// Imports Claude Code agents as VibeDeck agents. Returns how many were created.
    func importClaudeAgents() async -> Int {
        await importResources("import_agents", provider: .claude, reload: { self.reloadAgents() })
    }

    /// Importa de `.claude`/`.codex` com a tool `import_*`; devolve quantos itens foram criados.
    func importResources(_ tool: String, provider: AIProvider, reload: () -> Void) async -> Int {
        do {
            await writeChain?.value
            let result = try await store.importRecords(tool, provider: provider)
            reload()
            return result.slugs.count
        } catch {
            errorMessage = error.localizedDescription
            return 0
        }
    }

    // MARK: Commands

    func command(_ slug: String) -> Command? {
        commands.first { $0.slug == slug }?.value
    }

    func createCommand(title: String) -> String? {
        guard let name = title.trimmed.nonEmpty else { errorMessage = VibeDeckError.invalidName.localizedDescription; return nil }
        let slug = freeSlug(Slug.make(name), existing: commands.map(\.slug))
        let value = Command(title: name, summary: nil, argumentHint: nil, model: nil, tools: [], prompt: "", tags: [], author: .human)
        commands.append(Entry(slug: slug, value: value))
        persist { [weak self] in
            guard let self = self else { return }
            try await self.store.saveRecord(.command, slug: slug, value: value)
        }
        return slug
    }

    func deleteCommand(_ slug: String) {
        commands.removeAll { $0.slug == slug }
        persist { [weak self] in
            guard let self = self else { return }
            try await self.store.deleteRecord(.command, slug: slug)
        }
    }

    func mutateCommand(_ slug: String, _ actionName: String, undo: UndoManager?, _ change: @escaping (inout Command) -> Void) {
        mutate(\.commands, .command, slug, actionName, undo: undo) { command in
            let before = command
            change(&command)
            if command != before { command.updatedAt = .now }
        }
    }

    /// Imports Claude Code slash commands as VibeDeck commands. Returns how many were created.
    func importClaudeCommands() async -> Int {
        await importResources("import_commands", provider: .claude, reload: { self.reloadCommands() })
    }

    // MARK: Skills

    func skill(_ slug: String) -> Skill? {
        skills.first { $0.slug == slug }?.value
    }

    func createSkill(title: String, reference: String? = nil) -> String? {
        guard let name = title.trimmed.nonEmpty else { errorMessage = VibeDeckError.invalidName.localizedDescription; return nil }
        do {
            let slug = try newSlug(title: name, reference: reference, existing: skills.map(\.slug))
            let value = Skill(title: name, summary: nil, model: nil, tools: [], prompt: "", tags: [], author: .human)
            skills.append(Entry(slug: slug, value: value))
            persist { [weak self] in
                guard let self = self else { return }
                try await self.store.saveRecord(.skill, slug: slug, value: value)
            }
            return slug
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func deleteSkill(_ slug: String) {
        skills.removeAll { $0.slug == slug }
        persist { [weak self] in
            guard let self = self else { return }
            try await self.store.deleteRecord(.skill, slug: slug)
        }
    }

    func mutateSkill(_ slug: String, _ actionName: String, undo: UndoManager?, _ change: @escaping (inout Skill) -> Void) {
        mutate(\.skills, .skill, slug, actionName, undo: undo) { skill in
            let before = skill
            change(&skill)
            if skill != before { skill.updatedAt = .now }
        }
    }

    /// Imports Claude Code skills (`SKILL.md`) as VibeDeck skills. Returns how many were created.
    func importClaudeSkills() async -> Int {
        await importResources("import_skills", provider: .claude, reload: { self.reloadSkills() })
    }

    // MARK: Workflows

    func workflow(_ slug: String) -> Workflow? {
        workflows.first { $0.slug == slug }?.value
    }

    func createWorkflow(title: String) -> String? {
        guard let name = title.trimmed.nonEmpty else { errorMessage = VibeDeckError.invalidName.localizedDescription; return nil }
        let slug = freeSlug(Slug.make(name), existing: workflows.map(\.slug))
        let value = Workflow(title: name, summary: nil, input: nil, maxSteps: nil, tags: [], author: .human)
        workflows.append(Entry(slug: slug, value: value))
        persist { [weak self] in
            guard let self = self else { return }
            try await self.store.saveRecord(.workflow, slug: slug, value: value)
        }
        return slug
    }

    func deleteWorkflow(_ slug: String) {
        workflows.removeAll { $0.slug == slug }
        persist { [weak self] in
            guard let self = self else { return }
            try await self.store.deleteRecord(.workflow, slug: slug)
        }
    }

    func mutateWorkflow(_ slug: String, _ actionName: String, undo: UndoManager?, _ change: @escaping (inout Workflow) -> Void) {
        mutate(\.workflows, .workflow, slug, actionName, undo: undo) { workflow in
            let before = workflow
            change(&workflow)
            if workflow != before { workflow.updatedAt = .now }
        }
    }

    func runs(of workflow: String) -> [Entry<WorkflowRun>] {
        runs.filter { $0.value.workflow == workflow }
    }

    /// Starts (or resumes, with the same input) a run and returns the orchestrator prompt for the chat.
    func startRun(_ workflow: String, input: String?, from: String? = nil) async -> String? {
        do {
            await writeChain?.value
            let started = try await store.startRun(workflow, input: input, from: from)
            await refreshRuns()
            if !started.prompt.isEmpty { return started.prompt }
            if let run = runs.first(where: { $0.slug == started.ref })?.value { return orchestratorPrompt(started.ref, run) }
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Prompt that makes the chat continue orchestrating an existing run.
    func orchestratorPrompt(_ ref: String, _ run: WorkflowRun) -> String {
        WorkflowOrchestration.orchestratorPrompt(
            ref: ref, title: workflow(run.workflow)?.title ?? run.workflow, input: run.input, cli: ClaudeUsageView.cliPath ?? "vibedeck", provider: run.provider
        )
    }

    func stopRun(_ ref: String) {
        Task {
            do {
                try await store.stopRun(ref)
                await refreshRuns()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func deleteRun(_ ref: String) {
        runs.removeAll { $0.slug == ref }
        Task {
            do {
                try await store.deleteRun(ref)
            } catch {
                errorMessage = error.localizedDescription
            }
            await refreshRuns()
        }
    }

    /// The workflow's plan with the agents, commands and skills currently loaded.
    func workflowPlan(_ slug: String, input: String? = nil) -> WorkflowPlan? {
        workflow(slug).map {
            WorkflowPlan.build(
                slug: slug, workflow: $0, input: input, agents: agents.map { ($0.slug, $0.value) },
                commands: commands.map { ($0.slug, $0.value) }, skills: skills.map { ($0.slug, $0.value) }
            )
        }
    }

    /// Promotes the idea's rules to an enforced topic (`promote_idea`). Returns the topic slug.
    /// `forImplementation`: relê as dependências no Core primeiro; uma reaberta enquanto o diálogo estava aberto bloqueia aqui.
    func promoteIdea(_ slug: String, skippingPaths: Set<String> = [], forImplementation: Bool = false) async -> String? {
        if forImplementation, !(await ideaDependenciesMetFresh(slug)) { return nil }
        do {
            await writeChain?.value
            let reply = try await store.call("promote_idea", ["idea": slug])
            let marker = "tópico de regras: "
            guard let range = reply.range(of: marker) else { throw CoreError.protocolError("promote_idea: \(reply)") }
            let line = reply[range.upperBound...].split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? ""
            let topicSlug = line.trimmingCharacters(in: .whitespaces)
            await refreshTopics()
            await refreshIdeas()
            if !skippingPaths.isEmpty, topic(topicSlug) != nil {
                mutateTopic(topicSlug, "Promover ideia", undo: nil) { $0.paths.removeAll { skippingPaths.contains($0) } }  // undo agrupado: o passo único é registrado pelo chamador
            }
            return topicSlug
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Check of the dependencies against the ideas in memory; a pending one shows the error.
    func ideaDependenciesMet(_ slug: String) -> Bool {
        guard let current = self.idea(slug) else { return true }
        let blockers = ideaDependencyBlockers(current)
        guard blockers.isEmpty else {
            errorMessage = VibeDeckError.ideaNotImplementable(blockers.map(\.message)).localizedDescription
            return false
        }
        return true
    }

    /// Mesma checagem, relendo as ideias no Core.
    private func ideaDependenciesMetFresh(_ slug: String) async -> Bool {
        do {
            let fresh = try await store.listIdeas()
            guard let found = fresh.first(where: { $0.slug == slug }) else { return true }
            let blockers = IdeaImplementation.dependencyBlockers(of: found.value, in: fresh.map { (slug: $0.slug, idea: $0.value) })
            guard blockers.isEmpty else {
                errorMessage = VibeDeckError.ideaNotImplementable(blockers.map(\.message)).localizedDescription
                return false
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Deletes the idea's topic and releases the idea (draft rules stay). Undo restores both records.
    func unpromoteIdea(_ slug: String, undo: UndoManager?) {
        guard let idea = self.idea(slug) else { return }
        let topicSlug = idea.promotedTopic
        let topicValue = topicSlug.flatMap { self.topic($0) }
        Task {
            do {
                await writeChain?.value
                _ = try await store.call("unpromote_idea", ["idea": slug])
                await refreshTopics()
                await refreshIdeas()
                undo?.registerUndo(withTarget: self) { model in
                    if let topicSlug, let topicValue {
                        if let index = model.topics.firstIndex(where: { $0.slug == topicSlug }) { model.topics[index].value = topicValue }
                        else { model.topics.append(Entry(slug: topicSlug, value: topicValue)) }
                    }
                    if let index = model.ideas.firstIndex(where: { $0.slug == slug }) { model.ideas[index].value = idea }
                    model.persist {
                        if let topicSlug, let topicValue { try await model.store.saveRecord(.rule, slug: topicSlug, value: topicValue) }
                        try await model.store.saveRecord(.idea, slug: slug, value: idea)
                    }
                    undo?.registerUndo(withTarget: model) { $0.unpromoteIdea(slug, undo: undo) }
                    undo?.setActionName("Despromover ideia")
                }
                undo?.setActionName("Despromover ideia")
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Slug livre (sem checar caminho de grupo) entre os existentes.
    private func freeSlug(_ base: String, existing: [String]) -> String {
        var slug = base
        var n = 2
        let taken = Set(existing)
        while taken.contains(slug) {
            slug = "\(base)-\(n)"
            n += 1
        }
        return slug
    }

    // MARK: Sections

    /// Visibility and search belong only to the sidebar; section pages keep all rows.
    func sidebarRows(for section: SidebarSection, search: String = "") -> [SectionRow] {
        let hidden: Set<SidebarItem>
        switch section {
        case .groups:
            hidden = Set(groups.filter { $0.group.openCount == 0 }.map { .group($0.slug) })
        case .ideas:
            hidden = Set(ideas.filter { $0.value.status == .done }.map { .idea($0.slug) })
        default:
            hidden = []
        }
        let terms = search.split(whereSeparator: { $0.isWhitespace })
        let tags = terms.filter { $0.hasPrefix("#") }.map { String($0.dropFirst()) }
        let text = terms.filter { !$0.hasPrefix("#") }.joined(separator: " ")
        return rows(for: section).filter { row in
            !hidden.contains(row.id)
                && tags.allSatisfy { tag in row.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame } }
                && (text.isEmpty || row.title.localizedCaseInsensitiveContains(text)
                    || row.detail.localizedCaseInsensitiveContains(text)
                    || row.tags.contains { $0.localizedCaseInsensitiveContains(text) })
        }
    }

    func count(_ section: SidebarSection) -> Int {
        switch section {
        case .docs: docs.count
        case .groups: groups.count
        case .topics: topics.count
        case .ideas: ideas.count
        case .agents: agents.count
        case .commands: commands.count
        case .skills: skills.count
        case .workflows: workflows.count
        }
    }

    /// Ícone do doc: vínculo (`link`), vínculo quebrado (aviso) ou doc comum.
    private static func docSymbol(_ doc: DocInfo) -> String {
        if doc.isBroken { return "exclamationmark.triangle" }
        return doc.isLinked ? "link" : "doc.text"
    }

    private static func docDetail(_ doc: DocInfo) -> String {
        guard let link = doc.link else { return doc.modified.formatted(.relative(presentation: .named)) }
        return link.broken ? "Vínculo quebrado · \(link.target)" : "Vinculado · \(link.target)"
    }

    /// A coluna de conteúdo omite grupos de revisão sem item aberto (`openCount == 0`) e ideias Implementadas (`done`).
    /// A tabela do detalhe (`rows(for:)`) continua com todos.
    func isOmittedFromColumn(_ item: SidebarItem) -> Bool {
        switch item {
        case .group(let slug): return (group(slug)?.openCount ?? 0) == 0
        case .idea(let slug): return idea(slug)?.status == .done
        default: return false
        }
    }

    /// Linhas da coluna de conteúdo. O item aberto no detalhe nunca some, mesmo que mudar de status o omitiria.
    func columnRows(for section: SidebarSection, keeping selected: SidebarItem?) -> [SectionRow] {
        rows(for: section).filter { $0.id == selected || !isOmittedFromColumn($0.id) }
    }

    func rows(for section: SidebarSection) -> [SectionRow] {
        switch section {
        case .docs:
            docs.map { doc in
                SectionRow(id: .doc(doc.slug), title: doc.title, symbol: Self.docSymbol(doc),
                           detail: Self.docDetail(doc), count: "", tags: doc.tags, dimmed: doc.isBroken)
            }
        case .groups:
            groups.map {
                SectionRow(id: .group($0.slug), title: $0.group.title, symbol: "checklist",
                           detail: $0.group.description ?? "",
                           count: "\($0.group.openCount) de \($0.group.items.count) abertos", tags: $0.group.tags)
            }
        case .topics:
            topics.map {
                SectionRow(id: .topic($0.slug), title: $0.value.title, symbol: $0.value.isGlobal ? "checkmark.shield" : "scope",
                           detail: $0.value.isGlobal ? "Global" : $0.value.paths.joined(separator: ", "),
                           count: "\($0.value.rules.count) regra(s)", tags: $0.value.tags)
            }
        case .ideas:
            ideas.map {
                SectionRow(id: .idea($0.slug), title: $0.value.title, symbol: $0.value.status.symbol,
                           detail: $0.value.status.label, count: "\($0.value.rules.count) regra(s)",
                           tags: $0.value.tags, dimmed: $0.value.status.isClosed)
            }
        case .agents:
            agents.map {
                SectionRow(id: .agent($0.slug), title: $0.value.title, symbol: "person.crop.rectangle",
                           detail: $0.value.model ?? "Modelo herdado",
                           count: $0.value.nextSteps.isEmpty ? "" : "\($0.value.nextSteps.count) próximo(s) passo(s)", tags: $0.value.tags)
            }
        case .commands:
            commands.map {
                SectionRow(id: .command($0.slug), title: $0.value.title, symbol: "command",
                           detail: $0.value.summary ?? $0.value.argumentHint ?? "",
                           count: $0.value.nextSteps.isEmpty ? "" : "\($0.value.nextSteps.count) próximo(s) passo(s)", tags: $0.value.tags)
            }
        case .skills:
            skills.map {
                SectionRow(id: .skill($0.slug), title: $0.value.title, symbol: "wand.and.stars",
                           detail: $0.value.summary ?? "",
                           count: $0.value.nextSteps.isEmpty ? "" : "\($0.value.nextSteps.count) próximo(s) passo(s)", tags: $0.value.tags)
            }
        case .workflows:
            workflows.map {
                SectionRow(id: .workflow($0.slug), title: $0.value.title, symbol: "point.3.connected.trianglepath.dotted",
                           detail: $0.value.summary ?? "", count: "\($0.value.steps.count) etapa(s)", tags: $0.value.tags)
            }
        }
    }

    func fileURL(for item: SidebarItem) -> URL? {
        switch item {
        case .doc(let slug): store.docURL(slug)
        case .group(let slug): store.groupURL(slug)
        case .topic(let slug): store.topicURL(slug)
        case .idea(let slug): store.ideaURL(slug)
        case .agent(let slug): store.agentURL(slug)
        case .command(let slug): store.commandURL(slug)
        case .skill(let slug): store.skillURL(slug)
        case .workflow(let slug): store.workflowURL(slug)
        case .stack, .patterns, .links, .claudeItems, .graph, .integrations, .usage, .checksHistory, .claude, .terminal, .section: nil
        }
    }

    /// Display title for a tab showing `item`.
    func title(for item: SidebarItem) -> String {
        switch item {
        case .stack: "Stack"
        case .patterns: "Padrões"
        case .links: "Links"
        case .claudeItems: "Claude"
        case .graph: "Grafo"
        case .integrations: "Integrações"
        case .usage: "Consumo de IA"
        case .checksHistory: "Histórico"
        case .claude: "IA"
        case .terminal: "Terminal"
        case .section(let section): section.title
        case .doc(let slug): docs.first { $0.slug == slug }?.title ?? slug
        case .group(let slug): group(slug)?.title ?? slug
        case .topic(let slug): topic(slug)?.title ?? slug
        case .idea(let slug): idea(slug)?.title ?? slug
        case .agent(let slug): agent(slug)?.title ?? slug
        case .command(let slug): command(slug)?.title ?? slug
        case .skill(let slug): skill(slug)?.title ?? slug
        case .workflow(let slug): workflow(slug)?.title ?? slug
        }
    }

    /// SF Symbol for a tab showing `item`.
    func symbol(for item: SidebarItem) -> String {
        switch item {
        case .stack: "square.stack.3d.up"
        case .patterns: "building.columns"
        case .links: "link"
        case .claudeItems: "square.stack"
        case .graph: "point.3.connected.trianglepath.dotted"
        case .integrations: "shippingbox"
        case .usage: "clock"
        case .checksHistory: "clock"
        case .claude: "sparkles"
        case .terminal: "terminal"
        case .section(let section): section.symbol
        case .doc: "doc.text"
        case .group: "checklist"
        case .topic(let slug): topic(slug)?.isGlobal == false ? "scope" : "checkmark.shield"
        case .idea(let slug): idea(slug)?.status.symbol ?? "sparkle"
        case .agent: "person.crop.rectangle"
        case .command: "command"
        case .skill: "wand.and.stars"
        case .workflow: "point.3.connected.trianglepath.dotted"
        }
    }

    /// Whether `item` still exists in the project (pages always do; files may have been deleted).
    func exists(_ item: SidebarItem) -> Bool {
        switch item {
        case .stack, .patterns, .links, .claudeItems, .graph, .integrations, .usage, .checksHistory, .terminal, .section: true
        case .claude: !RemoteExecution.providers(root: store.root).isEmpty
        case .doc(let slug): docs.contains { $0.slug == slug }
        case .group(let slug): group(slug) != nil
        case .topic(let slug): topic(slug) != nil
        case .idea(let slug): idea(slug) != nil
        case .agent(let slug): agent(slug) != nil
        case .command(let slug): command(slug) != nil
        case .skill(let slug): skill(slug) != nil
        case .workflow(let slug): workflow(slug) != nil
        }
    }

    func delete(_ item: SidebarItem) {
        switch item {
        case .doc(let slug): deleteDoc(slug)
        case .group(let slug): deleteGroup(slug)
        case .topic(let slug): deleteTopic(slug)
        case .idea(let slug): deleteIdea(slug)
        case .agent(let slug): deleteAgent(slug)
        case .command(let slug): deleteCommand(slug)
        case .skill(let slug): deleteSkill(slug)
        case .workflow(let slug): deleteWorkflow(slug)
        case .stack, .patterns, .links, .claudeItems, .graph, .integrations, .usage, .checksHistory, .claude, .terminal, .section: break
        }
    }

    func setTags(_ tags: [String], for item: SidebarItem, undo: UndoManager?) {
        switch item {
        case .doc(let slug): setDocTags(slug, tags)
        case .group(let slug): mutateGroup(slug, "Editar tags", undo: undo) { $0.tags = tags }
        case .topic(let slug): mutateTopic(slug, "Editar tags", undo: undo) { $0.tags = tags }
        case .idea(let slug): mutateIdea(slug, "Editar tags", undo: undo) { $0.tags = tags }
        case .agent(let slug): mutateAgent(slug, "Editar tags", undo: undo) { $0.tags = tags }
        case .command(let slug): mutateCommand(slug, "Editar tags", undo: undo) { $0.tags = tags }
        case .skill(let slug): mutateSkill(slug, "Editar tags", undo: undo) { $0.tags = tags }
        case .workflow(let slug): mutateWorkflow(slug, "Editar tags", undo: undo) { $0.tags = tags }
        case .stack, .patterns, .links, .claudeItems, .graph, .integrations, .usage, .checksHistory, .claude, .terminal, .section: break
        }
    }


    // MARK: Criar/editar com IA

    func itemURL(_ kind: ItemDiscover.Kind, _ slug: String) -> URL {
        switch kind {
        case .agent: store.agentURL(slug)
        case .command: store.commandURL(slug)
        case .skill: store.skillURL(slug)
        case .workflow: store.workflowURL(slug)
        }
    }

    private func reloadItems(_ kind: ItemDiscover.Kind) {
        switch kind {
        case .agent: reloadAgents()
        case .command: reloadCommands()
        case .skill: reloadSkills()
        case .workflow: reloadWorkflows()
        }
    }

    /// Conteúdo atual do item ao vivo (nil se não existe mais).
    func itemProposal(_ kind: ItemDiscover.Kind, slug: String) -> ItemDiscover.Proposal? {
        switch kind {
        case .agent: agent(slug).map { .init($0) }
        case .command: command(slug).map { .init($0) }
        case .skill: skill(slug).map { .init($0) }
        case .workflow: workflow(slug).map { .init($0) }
        }
    }

    /// Aceite de uma proposta da IA: um único passo de undo, tanto para editar (`slug`) quanto para criar.
    @discardableResult
    func acceptItemAI(_ kind: ItemDiscover.Kind, slug: String?, _ proposal: ItemDiscover.Proposal, undo: UndoManager?) -> Bool {
        guard let proposal = ItemDiscover.validated(kind, proposal) else {
            errorMessage = VibeDeckError.invalidName.localizedDescription
            return false
        }
        let name = slug == nil ? "Criar \(kind.title) com IA" : "Editar \(kind.title) com IA"
        if let slug {
            guard itemProposal(kind, slug: slug) != nil else {
                errorMessage = "O \(kind.title) não existe mais; a proposta foi descartada."
                return false
            }
            switch kind {
            case .agent: mutateAgent(slug, name, undo: undo) { ItemDiscover.apply(proposal, to: &$0) }
            case .command: mutateCommand(slug, name, undo: undo) { ItemDiscover.apply(proposal, to: &$0) }
            case .skill: mutateSkill(slug, name, undo: undo) { ItemDiscover.apply(proposal, to: &$0) }
            case .workflow: mutateWorkflow(slug, name, undo: undo) { ItemDiscover.apply(proposal, to: &$0) }
            }
            return true
        }
        // Criação: o item nasce com autor `ai` e o conteúdo da proposta.
        let created = Slug.make(proposal.title)
        switch kind {
        case .agent:
            var value = Agent(title: proposal.title, summary: nil, model: nil, tools: [], prompt: "", tags: [], author: .ai)
            ItemDiscover.apply(proposal, to: &value)
            let unique = freeSlug(created, existing: agents.map(\.slug))
            agents.append(Entry(slug: unique, value: value))
            persistCreated(.agent, unique, value, name: name, undo: undo)
        case .command:
            var value = Command(title: proposal.title, summary: nil, argumentHint: nil, model: nil, tools: [], prompt: "", tags: [], author: .ai)
            ItemDiscover.apply(proposal, to: &value)
            let unique = freeSlug(created, existing: commands.map(\.slug))
            commands.append(Entry(slug: unique, value: value))
            persistCreated(.command, unique, value, name: name, undo: undo)
        case .skill:
            var value = Skill(title: proposal.title, summary: nil, model: nil, tools: [], prompt: "", tags: [], author: .ai)
            ItemDiscover.apply(proposal, to: &value)
            let unique = freeSlug(created, existing: skills.map(\.slug))
            skills.append(Entry(slug: unique, value: value))
            persistCreated(.skill, unique, value, name: name, undo: undo)
        case .workflow:
            var value = Workflow(title: proposal.title, summary: nil, input: nil, maxSteps: nil, tags: [], author: .ai)
            ItemDiscover.apply(proposal, to: &value)
            let unique = freeSlug(created, existing: workflows.map(\.slug))
            workflows.append(Entry(slug: unique, value: value))
            persistCreated(.workflow, unique, value, name: name, undo: undo)
        }
        return true
    }

    private func persistCreated<V: Encodable & Equatable>(_ kind: CoreRecordKind, _ slug: String, _ value: V, name: String, undo: UndoManager?) {
        persist { [weak self] in
            guard let self = self else { return }
            try await self.store.saveRecord(kind, slug: slug, value: value)
        }
        undo?.registerUndo(withTarget: self) { model in model.toggleCreatedItem(kind, slug, value, remove: true, name: name, undo: undo) }
        undo?.setActionName(name)
    }

    private func toggleCreatedItem<V: Encodable & Equatable>(_ kind: CoreRecordKind, _ slug: String, _ value: V, remove: Bool, name: String, undo: UndoManager?) {
        if remove {
            removeEntry(kind, slug)
            persist { [weak self] in
                guard let self = self else { return }
                try await self.store.deleteRecord(kind, slug: slug)
            }
        } else {
            if entryExists(kind, slug) {
                errorMessage = "Um item ocupa o destino; não foi possível refazer a criação."
                return
            }
            persist { [weak self] in
                guard let self = self else { return }
                try await self.store.saveRecord(kind, slug: slug, value: value)
                self.reloadAll()
            }
        }
        undo?.registerUndo(withTarget: self) { model in model.toggleCreatedItem(kind, slug, value, remove: !remove, name: name, undo: undo) }
        undo?.setActionName(name)
    }

    private func entryExists(_ kind: CoreRecordKind, _ slug: String) -> Bool {
        switch kind {
        case .agent: return agents.contains { $0.slug == slug }
        case .command: return commands.contains { $0.slug == slug }
        case .skill: return skills.contains { $0.slug == slug }
        case .workflow: return workflows.contains { $0.slug == slug }
        case .idea: return ideas.contains { $0.slug == slug }
        case .rule: return topics.contains { $0.slug == slug }
        case .review: return groups.contains { $0.slug == slug }
        }
    }

    private func removeEntry(_ kind: CoreRecordKind, _ slug: String) {
        switch kind {
        case .agent: agents.removeAll { $0.slug == slug }
        case .command: commands.removeAll { $0.slug == slug }
        case .skill: skills.removeAll { $0.slug == slug }
        case .workflow: workflows.removeAll { $0.slug == slug }
        case .idea: ideas.removeAll { $0.slug == slug }
        case .rule: topics.removeAll { $0.slug == slug }
        case .review: groups.removeAll { $0.slug == slug }
        }
    }

    // MARK: Generic helpers

    /// Same contract as `mutateGroup`: write through, undo restores the previous value.
    private func mutate<V: Equatable & Encodable>(
        _ entries: ReferenceWritableKeyPath<ProjectModel, [Entry<V>]>, _ kind: CoreRecordKind, _ slug: String,
        _ actionName: String, undo: UndoManager?, _ change: @escaping (inout V) -> Void
    ) {
        guard let index = self[keyPath: entries].firstIndex(where: { $0.slug == slug }) else { return }
        let old = self[keyPath: entries][index].value
        var new = old
        change(&new)
        guard new != old else { return }
        self[keyPath: entries][index].value = new
        persist { [weak self] in
            guard let self = self else { return }
            try await self.store.saveRecord(kind, slug: slug, value: new)
        }
        undo?.registerUndo(withTarget: self) { model in
            model.mutate(entries, kind, slug, actionName, undo: undo) { $0 = old }
        }
        undo?.setActionName(actionName)
    }
}


extension ProjectModel {
    /// Notifica os caminhos movidos por uma reorganização e relê tudo.
    func reloadAfterReorganization(_ paths: [String: String]) {
        func item(_ path: String) -> SidebarItem? {
            let parts = path.split(separator: "/")
            guard parts.count >= 3, parts[0] == ".vibedeck" else { return nil }
            let slug = String(parts.dropFirst(2).joined(separator: "/").dropLast(parts[1] == "docs" ? 3 : 5))
            switch parts[1] {
            case "docs": return .doc(slug)
            case "rules": return .topic(slug)
            case "ideas": return .idea(slug)
            case "reviews": return .group(slug)
            default: return nil
            }
        }
        var moved: [SidebarItem: SidebarItem] = [:]
        for (old, new) in paths { if let a = item(old), let b = item(new), a != b { moved[a] = b } }
        notePathMoves(moved)
        reloadAll()
    }

    /// Registra movimentos de caminho (abas e seleção acompanham).
    func notePathMoves(_ moved: [SidebarItem: SidebarItem]) {
        guard !moved.isEmpty else { return }
        var current = latestPathMoves
        for (old, new) in moved { current[old] = new }
        latestPathMoves = current
        moveRevision += 1
    }
}

extension ProjectModel {
    /// Globs da ideia que já não casam com nenhum arquivo do projeto (renomeado ou apagado desde a sugestão).
    /// Só projetos locais: em SSH a lista de arquivos não está disponível e nada é considerado obsoleto.
    func unmatchedIdeaPaths(_ slug: String) -> [String] {
        guard let current = self.idea(slug), !current.paths.isEmpty, !store.isRemote else { return [] }
        let files = ClaudeCompletion.projectFiles(root: store.root, limit: RuleDiscover.fileLimit).filter { !$0.hasSuffix("/") }
        return current.paths.filter { glob in !files.contains { Glob.matches(glob, path: $0) } }
    }
}
