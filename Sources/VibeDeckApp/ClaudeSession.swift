import Foundation
import Observation
import VibeDeckCore

/// Conversations for both providers. Wire protocols live in the Core transports; workflow transitions
/// are driven by VibeDeck and saved on disk. Legacy chat storage remains compatible.
@Observable @MainActor
final class AISession {
    struct IdeaRequest: Identifiable {
        let id = UUID()
        let actionID = VDLog.actionID
        let ideaID: UUID
        var mode: IdeaImplementation.ChatIntent.Mode = .ask
        var workflow: String?
    }
    var ideaRequest: IdeaRequest?
    @ObservationIgnored private var ideaIntentTask: Task<Void, Never>?

    func requestIdeaImplementation(_ idea: Idea) {
        guard !isWorking, IdeaImplementation.isEligible(idea) else { return }
        ideaRequest = IdeaRequest(ideaID: idea.id)
    }

    /// Resolve intent before sending anything to a writing-capable conversation.
    private func inspectIdeaRequest(_ text: String, mentions: [UUID], attachments: [URL]) {
        let project = ProjectStore(root: root)
        isWorking = true
        ideaIntentTask = Task {
            defer { ideaIntentTask = nil }
            do {
                let ideas = try project.listIdeas()
                let workflows = try project.listWorkflows()
                let context = entries.suffix(8).compactMap { entry -> String? in
                    switch entry.kind { case .user(let t), .assistant(let t): return t; default: return nil }
                }.joined(separator: "\n")
                let intent = try await AIReadOnlyOperation.run(root: root, provider: provider,
                    operation: "Identificar implementação de ideia",
                    prompt: IdeaImplementation.intentPrompt(text, context: context, ideas: ideas.map { ($0.slug, $0.idea) }, workflows: workflows),
                    schema: IdeaImplementation.intentSchema) { data in
                        let intent = try VDJSON.decoder.decode(IdeaImplementation.ChatIntent.self, from: data)
                        guard intent.mode == .none || ideas.contains(where: { $0.idea.id.uuidString == intent.idea }) else {
                            throw VibeDeckError.discoverFailed("Referência de ideia inválida.")
                        }
                        guard intent.workflow == nil || workflows.contains(where: { $0.slug == intent.workflow }) else {
                            throw VibeDeckError.discoverFailed("Referência de workflow inválida.")
                        }
                        return intent
                    }
                try Task.checkCancellation()
                isWorking = false
                if intent.mode != .none, let ref = intent.idea {
                    let idea = try project.loadIdea(project.resolveIdeaSlug(ref))
                    guard IdeaImplementation.isEligible(idea) else {
                        fail("A ideia precisa estar aprovada e ter uma avaliação viável atual antes de implementar.")
                        return
                    }
                    ideaRequest = IdeaRequest(ideaID: idea.id, mode: intent.mode, workflow: intent.workflow)
                } else {
                    send(text, mentions: mentions, attachments: attachments, inspectIdeas: false)
                }
            } catch is CancellationError {} catch { isWorking = false; fail(error.localizedDescription) }
        }
    }
    struct Entry: Identifiable, Equatable {
        enum Kind: Equatable {
            case user(String)
            case assistant(String)
            case tool(name: String, summary: String, result: String?, isError: Bool)
            case notice(String)
            case error(String)
        }

        let id = UUID()
        var kind: Kind
        var toolUseId: String?
        /// User messages: chats mentioned (sent as JSON).
        var mentions: [UUID] = []
        /// User messages: absolute paths of attached files (only referenced in the prompt).
        var attachments: [String] = []
    }

    private(set) var provider: AIProvider = .claude
    private var codexDefaultModel: String?
    private(set) var codexModels: [CodexModel] = []
    private(set) var codexSkills: [CodexSkill] = []
    var codexModel = UserDefaults.standard.string(forKey: "codexModel") ?? "" {
        didSet { UserDefaults.standard.set(codexModel, forKey: "codexModel") }
    }
    var codexEffort = UserDefaults.standard.string(forKey: "codexEffort") ?? "" {
        didSet { UserDefaults.standard.set(codexEffort, forKey: "codexEffort") }
    }
    /// Local permission preference, shared with future Codex conversations.
    var codexAutoReview = UserDefaults.standard.bool(forKey: "codexAutoReview") {
        didSet { UserDefaults.standard.set(codexAutoReview, forKey: "codexAutoReview") }
    }
    private(set) var codexLimits: [CodexRateLimit] = []
    private(set) var codexStatus: String?
    @ObservationIgnored private var codexTransport: CodexConversationTransport?
    private var codex: CodexRPC? { codexTransport?.rpc }
    @ObservationIgnored private var codexStarting: Task<Void, Error>?
    @ObservationIgnored private var codexTurn: String?
    @ObservationIgnored private var codexTask: Task<Void, Never>?
    @ObservationIgnored private var workflowTask: Task<Void, Never>?
    @ObservationIgnored private var turnWaiter: CheckedContinuation<String, Error>?
    @ObservationIgnored private var turnOutput = ""
    @ObservationIgnored private var workflowQuestions: [String: Int] = [:]
    @ObservationIgnored private var activeUsage: AIUsageRecord?
    @ObservationIgnored private var codexUsageTotals: [String: AITokenUsage] = [:]
    @ObservationIgnored private var codexUsageBaseline: AITokenUsage?
    private(set) var usageError: String?

    @ObservationIgnored private var usageAction: String?

    private func beginUsage(_ text: String, model: String?) {
        usageAction = VDLog.actionID
        VDLog.info("ai.request_started", "Chamada de IA iniciada", project: root, component: .ai, context: ["provider": provider.rawValue])
        var record = AIUsageRecord(taskID: workflowRef ?? UUID().uuidString,
            operation: workflowRef.map { "Workflow " + $0 } ?? "Chat", provider: provider, model: model, prompt: text)
        record.coverage = "provider-reported; external calls may be absent"
        activeUsage = record
        if provider == .codex, let thread = current?.sessionId { codexUsageBaseline = codexUsageTotals[thread] }
    }

    private func finishUsage(_ status: String, result: ClaudeResult? = nil) {
        guard var usage = activeUsage else { return }
        activeUsage = nil
        VDLog.$actionID.withValue(usageAction) {
            VDLog.info("ai.request_finished", "Chamada de IA encerrada", project: root, component: .ai, context: ["provider": provider.rawValue, "status": status])
        }
        usageAction = nil
        if provider == .claude, let result { usage.tokens = result.tokens; usage.costUSD = result.costUSD }
        usage.model = model ?? usage.model
        usage.finish(status)
        do { try AIUsageStore(root: root).save(usage) }
        catch { usageError = "Não foi possível registrar o consumo: " + error.localizedDescription }
    }

    private var workflowRef: String?
    private var workflowProject: ProjectStore?
    private var selectedProviderKey: String { "aiProvider.\(store.dir.lastPathComponent)" }
    let root: URL
    private(set) var entries: [Entry] = []
    /// All saved chats of the project, most recent first.
    private(set) var chats: [ClaudeChat] = []
    /// The open chat; nil shows the chat list. A new chat is only saved on its first message.
    private(set) var current: ClaudeChat? {
        didSet {
            if oldValue?.id != current?.id { UserDefaults.standard.set(current?.id.uuidString, forKey: currentKey) }
        }
    }
    /// Permission prompts and questions waiting for the user, oldest first.
    private(set) var pending: [ClaudePermissionRequest] = []
    /// A turn is in progress (between sending a message and its result).
    private(set) var isWorking = false
    private(set) var isThinking = false
    private(set) var lastCost: Double?
    private(set) var model: String?
    /// Chosen in the composer; Claude Code also changes it (approving a plan returns to `.default`).
    private(set) var permissionMode: ClaudePermissionMode = .default
    /// Model and effort only apply at launch, so changing them restarts the process (resuming the
    /// conversation) before the next message.
    private(set) var chosenModel: ClaudeModel {
        didSet { UserDefaults.standard.set(chosenModel.rawValue, forKey: "claudeModel") }
    }
    private(set) var effort: ClaudeEffort {
        didSet { UserDefaults.standard.set(effort.rawValue, forKey: "claudeEffort") }
    }
    enum Page: Equatable { case chat, terminal(UUID) }

    /// Set to ask the window to show the conversation or a terminal tab; the window clears it.
    var requestedPage: Page?
    /// Composer text, mentioned chats and attached files, kept here so they survive switching tabs.
    var includeFullMentions = false
    var draft = ""
    var draftMentions: [UUID] = []
    var draftAttachments: [URL] = []
    /// Interactive shells of the project, one per terminal tab. A shell lives exactly as long as its tab.
    private(set) var terminals: [UUID: ProjectTerminal] = [:]

    /// Slash commands the running Claude Code reported at init (plugins included).
    private(set) var reportedCommands: [String] = []
    /// Project files for `@` completion, listed once in the background.
    private(set) var projectFiles: [String] = []
    /// Terminal commands (`!`) run since the last message; sent along with the next one as context.
    @ObservationIgnored private var shellContext: [String] = []

    @ObservationIgnored private let store: ClaudeChatStore
    @ObservationIgnored private var claudeTransport: ClaudeConversationTransport?
    @ObservationIgnored private var activeClaudeSettings: AIProviderSettings?
    @ObservationIgnored private var starting: Task<Void, Never>?
    @ObservationIgnored private var acceptingEvents = true
    @ObservationIgnored private var needsRestart = false
    private let currentKey: String

    init(root: URL, projectId: UUID) {
        self.root = root
        store = ClaudeChatStore.forProject(projectId)
        currentKey = "claudeChat.\(projectId.uuidString)"
        chosenModel = ClaudeModel(rawValue: UserDefaults.standard.string(forKey: "claudeModel") ?? "") ?? .automatic
        effort = ClaudeEffort(rawValue: UserDefaults.standard.string(forKey: "claudeEffort") ?? "") ?? .automatic
        provider = AIProvider(rawValue: UserDefaults.standard.string(forKey: selectedProviderKey) ?? "") ?? RemoteExecution.providers(root: root).first ?? .claude
        migrateLegacySession(key: "claudeSession.\(projectId.uuidString)")
        chats = store.list()
        if let id = UserDefaults.standard.string(forKey: currentKey).flatMap(UUID.init(uuidString:)), let chat = store.load(id) {
            show(chat)
        } else if chats.isEmpty {
            current = ClaudeChat(title: ClaudeChat.untitled, provider: provider)
        }
    }

    /// Before chats existed, only the session id of a single conversation was kept.
    private func migrateLegacySession(key: String) {
        guard let sessionId = UserDefaults.standard.string(forKey: key) else { return }
        let chat = ClaudeChat(title: "Conversa anterior", sessionId: sessionId, messages: [
            ClaudeChatMessage(role: .notice, text: "O histórico desta conversa ficou no Claude Code; mande uma mensagem para continuar."),
        ])
        try? store.save(chat)
        UserDefaults.standard.set(chat.id.uuidString, forKey: currentKey)
        UserDefaults.standard.removeObject(forKey: key)
    }

    // MARK: Chats

    func newChat() {
        stop()
        draft = ""; draftMentions = []; draftAttachments = []
        show(ClaudeChat(title: ClaudeChat.untitled, provider: provider))
    }

    func open(_ id: UUID) {
        guard id != current?.id else { return }
        stop()
        if let chat = store.load(id) { draft = ""; draftMentions = []; draftAttachments = []; show(chat) }
    }

    /// Back to the chat list; the chat can be reopened later.
    func leaveChat() {
        stop()
        current = nil
        entries = []
        lastCost = nil
    }

    func rename(_ id: UUID, to title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        if id == current?.id {
            current?.title = title
            persist()
        } else {
            update(id) { $0.title = title }
        }
    }

    /// Erases the messages and the Claude Code session, keeping the chat and its name.
    func clear(_ id: UUID) {
        if id == current?.id {
            stop()
            entries = []
            lastCost = nil
            current?.sessionId = nil
            current?.messages = []
            if var chat = current, store.load(id) != nil {
                chat.updatedAt = .now
                save(chat)
            }
        } else {
            update(id) { $0.messages = []; $0.sessionId = nil }
        }
    }

    func delete(_ id: UUID) {
        if id == current?.id { leaveChat() }
        try? store.delete(id)
        chats.removeAll { $0.id == id }
    }

    /// Deletes every chat of the project.
    func clearHistory() {
        leaveChat()
        try? store.deleteAll()
        chats = []
    }

    func title(of id: UUID) -> String? {
        chats.first { $0.id == id }?.title
    }

    private func show(_ chat: ClaudeChat) {
        provider = chat.provider
        if !provider.capabilities.permissionModes.contains(permissionMode) { permissionMode = .default }
        current = chat
        if provider == .codex { refreshCodex() }
        entries = chat.messages.map(Entry.init)
        lastCost = nil
        if provider == .codex, let plan = chat.pendingPlan {
            permissionMode = .plan
            pending = [.init(requestId: "codex-plan-" + UUID().uuidString, toolName: "ExitPlanMode", input: ["plan": .string(plan)])]
        }
    }

    private func update(_ id: UUID, _ change: (inout ClaudeChat) -> Void) {
        guard var chat = store.load(id) else { return }
        change(&chat)
        chat.updatedAt = .now
        save(chat)
    }

    /// Saves the open chat with the current transcript, once it has something to keep.
    private func persist() {
        guard var chat = current else { return }
        chat.messages = entries.compactMap(\.message)
        guard !chat.messages.isEmpty || chat.sessionId != nil || store.load(chat.id) != nil else {
            current = chat
            return
        }
        chat.updatedAt = .now
        current = chat
        save(chat)
    }

    private func save(_ chat: ClaudeChat) {
        do { try store.save(chat) } catch { entries.append(Entry(kind: .error("Não foi possível salvar a conversa: \(error.localizedDescription)"))) }
        chats.removeAll { $0.id == chat.id }
        chats.insert(chat, at: 0)
    }

    // MARK: Actions

    /// Shows the conversation and sends `prompt`, for buttons elsewhere in the app.
    func ask(_ prompt: String, inspectIdeas: Bool = true) {
        requestedPage = .chat
        send(prompt, inspectIdeas: inspectIdeas)
    }

    /// Sends `text`; `mentions` are other chats, included in full as JSON (their sessions aren't resumed);
    /// `attachments` are files referenced by absolute path in the prompt (nothing is copied).
    func send(_ text: String, mentions: [UUID] = [], attachments: [URL] = [], inspectIdeas: Bool = true) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isWorking, ideaRequest == nil else { return }
        do { try RemoteWorkspace.existing(at: root)?.requireSynchronized() }
        catch { fail(error.localizedDescription); return }
        if provider == .codex, handleLocalCommand(text) { return }
        let paths = attachments.map(\.path)
        guard !text.isEmpty || !paths.isEmpty else { return }
        if inspectIdeas, !text.isEmpty {
            do {
                if try !ProjectStore(root: root).listIdeas().isEmpty {
                    inspectIdeaRequest(text, mentions: mentions, attachments: attachments)
                    return
                }
            } catch { fail(error.localizedDescription); return }
        }
        if needsRestart, !isWorking { stop() }
        if current == nil { current = ClaudeChat(title: ClaudeChat.untitled, provider: provider) }
        guard let chatId = current?.id else { return }
        if current?.title == ClaudeChat.untitled, !entries.contains(where: { if case .user = $0.kind { true } else { false } }) {
            current?.title = ClaudeChat.title(from: text.isEmpty ? attachments.map(\.lastPathComponent).joined(separator: ", ") : text)
        }
        let mentioned = mentions.filter { $0 != chatId }.compactMap(store.load)
        entries.append(Entry(kind: .user(text), mentions: mentioned.map(\.id), attachments: paths))
        isWorking = true
        persist()
        let expanded: String
        do { expanded = try ProjectStore(root: root).expandAICommand(text) }
        catch { fail(error.localizedDescription); return }
        var wire = ClaudeChat.wireText(expanded, mentioning: mentioned, attachments: paths, provider: provider, contextStore: AIContextStore(root: root), includeFullChats: includeFullMentions)
        if !shellContext.isEmpty {
            wire = shellContext.joined(separator: "\n") + "\n\n" + wire
            shellContext = []
        }
        if provider == .codex {
            let wireCommand = text
            let words = text.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            let command = words.first.map(String.init) ?? ""
            if let skill = codexSkills.first(where: { "/" + $0.name == command }), expanded == text {
                wire = "Use a skill em \(skill.path).\n" + wire
            }
            let text = wire
            codexTask = Task {
                do {
                    try await connectCodex()
                    let options = try ProjectStore(root: root).commandProviderSettings(wireCommand, provider: .codex, availableModels: codexModels.map(\.id), fallback: effectiveCodexModel)
                    if let warning = options?.warning { entries.append(Entry(kind: .notice(warning))) }
                    try await prepareCodexThread(settings: options?.settings)
                    guard current?.id == chatId else { return }
                    try await launchCodexTurn(text, settings: options?.settings)
                } catch is CancellationError {} catch { fail(error.localizedDescription) }
            }
        } else {
            starting = Task {
                do {
                    let options = try ProjectStore(root: root).commandProviderSettings(text, provider: .claude, availableModels: [], fallback: nil)
                    try await prepareClaude(settings: options?.settings)
                    guard current?.id == chatId else { return }
                    turnOutput = ""; acceptingEvents = true
                    beginUsage(wire, model: activeClaudeSettings?.model ?? model)
                    _ = try await claudeTransport?.send(wire, configuration: conversationConfiguration(settings: activeClaudeSettings), schema: nil)
                } catch is CancellationError {} catch { fail(error.localizedDescription) }
            }
        }
    }

    // MARK: Autocomplete

    func loadProjectFiles() {
        guard projectFiles.isEmpty else { return }
        let root = root
        Task {
            projectFiles = await VDLog.detached { ClaudeCompletion.projectFiles(root: root) }.value
        }
    }

    /// Suggestions for what is being typed: `/commands`, or project files and other chats after `@`.
    func suggestions(for trigger: ClaudeTrigger, mentioned: [UUID]) -> [ClaudeSuggestion] {
        switch trigger.kind {
        case .command:
            let all = provider == .claude ? ClaudeCompletion.commands(root: root, reported: reportedCommands) + registeredSuggestions() : codexSuggestions()
            return ClaudeCompletion.rank(all, query: trigger.query)
        case .mention:
            let chats = chats.filter { $0.id != current?.id && !mentioned.contains($0.id) }
                .map { ClaudeSuggestion(kind: .chat, name: $0.title, detail: "conversa", chatId: $0.id) }
            let files = projectFiles.map { ClaudeSuggestion(kind: .file, name: $0) }
            return ClaudeCompletion.rank(chats + files, query: trigger.query)
        }
    }

    // MARK: Terminals

    /// Starts a new shell in the project folder and asks the window to show it in a new tab.
    /// When the shell exits, the terminal is dropped and the window closes its tab.
    func openTerminal(running command: String? = nil) {
        let id = UUID()
        let used = Set(terminals.values.map(\.number))
        let number = (1...).first { !used.contains($0) }!
        let terminal = ProjectTerminal(root: root, number: number) { [weak self] in
            self?.terminals[id] = nil
        }
        terminals[id] = terminal
        if let command { terminal.run(command) } else { terminal.start() }
        requestedPage = .terminal(id)
    }

    /// Ends the shell of a terminal whose tab was closed.
    func closeTerminal(_ id: UUID) {
        terminals.removeValue(forKey: id)?.terminate()
    }

    // MARK: Terminal commands

    /// Runs `command` in the project like the `!` prompt of Claude Code, shows the output in the
    /// transcript and hands it to Claude with the next message. Programs that need a keyboard (editors,
    /// pagers, REPLs, ssh) go to the terminal page instead.
    func runShell(_ command: String) {
        let command = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        if ShellCommand.isInteractive(command) {
            openTerminal(running: command)
            return
        }
        if current == nil { current = ClaudeChat(title: ClaudeChat.untitled, provider: provider) }
        let entry = Entry(kind: .tool(name: "Terminal", summary: command, result: nil, isError: false), toolUseId: "shell-\(UUID().uuidString)")
        entries.append(entry)
        let root = root
        Task {
            let result = await VDLog.detached { Self.execute(command, in: root) }.value
            if let i = entries.firstIndex(where: { $0.id == entry.id }) {
                entries[i].kind = .tool(name: "Terminal", summary: command, result: result.output, isError: result.status != 0)
            }
            var context = "<bash-input>\(command)</bash-input>\n<bash-stdout>\(result.output)</bash-stdout>"
            if result.status != 0 { context += "\n<bash-exit-code>\(result.status)</bash-exit-code>" }
            shellContext.append(context)
            persist()
        }
    }

    nonisolated private static func execute(_ command: String, in root: URL) -> (output: String, status: Int32) {
        ShellRunner.run(command, in: root)
    }

    func interrupt() {
        guard isWorking || !pending.isEmpty else { return }
        acceptingEvents = false
        ideaIntentTask?.cancel(); ideaIntentTask = nil
        current?.pendingPlan = nil
        if let ref = workflowRef, let store = workflowProject {
            if !turnOutput.isEmpty, let run = try? store.loadRun(ref), let step = run.current, run.checkpoint?.completed != true,
               let output = try? store.saveRunOutput(ref, output: turnOutput) {
                try? store.checkpointRun(ref, checkpoint: .init(step: step, output: output, completed: false))
            }
            _ = try? store.stopRun(ref, reason: "Interrompido pelo usuário")
        }
        workflowTask?.cancel(); workflowTask = nil
        codexTask?.cancel(); codexTask = nil
        starting?.cancel(); starting = nil
        codexStarting?.cancel(); codexStarting = nil
        for request in pending where provider == .claude { write(ClaudeInput.deny(request, message: "Interrompido pelo usuário.")) }
        let transport: (any AIConversationTransport)? = provider == .claude ? claudeTransport : codexTransport
        Task { try? await transport?.interrupt(); transport?.stop() }
        claudeTransport = nil; activeClaudeSettings = nil; codexTransport = nil
        finishUsage("cancelled")
        pending = []; isWorking = false; isThinking = false
        turnWaiter?.resume(throwing: CancellationError()); turnWaiter = nil
        workflowRef = nil; workflowProject = nil; workflowQuestions = [:]
        persist()
    }

    /// Applies to the running process right away, or to the next one when idle.
    func setPermissionMode(_ mode: ClaudePermissionMode) {
        guard mode != permissionMode, provider.capabilities.permissionModes.contains(mode), !isWorking else { return }
        permissionMode = mode
        if provider == .claude, claudeTransport?.isConnected == true { write(ClaudeInput.setPermissionMode(mode)) }
    }

    func setModel(_ model: ClaudeModel) {
        guard model != chosenModel else { return }
        chosenModel = model
        needsRestart = claudeTransport?.isConnected == true
    }

    func setEffort(_ effort: ClaudeEffort) {
        guard effort != self.effort else { return }
        self.effort = effort
        needsRestart = claudeTransport?.isConnected == true
    }

    /// Ends the process, saving the transcript so far.
    func stop() {
        ideaIntentTask?.cancel(); ideaIntentTask = nil
        ideaRequest = nil
        finishUsage("cancelled")
        persist()
        codexTask?.cancel(); codexTask = nil
        workflowTask?.cancel(); workflowTask = nil
        codexStarting?.cancel(); codexStarting = nil
        codexTransport?.stop(); codexTransport = nil
        turnWaiter?.resume(throwing: CancellationError()); turnWaiter = nil
        codexTurn = nil
        workflowRef = nil; workflowProject = nil; workflowQuestions = [:]
        starting?.cancel(); starting = nil
        claudeTransport?.stop(); claudeTransport = nil; activeClaudeSettings = nil
        acceptingEvents = false
        pending.removeAll()
        isWorking = false
        isThinking = false
    }

    // MARK: Answering requests

    typealias Decision = AIPermissionDecision
    private var transport: (any AIConversationTransport)? { provider == .claude ? claudeTransport : codexTransport }

    func decide(_ request: AIPermissionRequest, _ decision: Decision) {
        guard pending.contains(where: { $0.id == request.id }), let transport else { return }
        do { try transport.respond(to: request, decision: decision) }
        catch { fail(error.localizedDescription); return }
        pending.removeAll { $0.id == request.id }
    }

    func answer(_ request: AIPermissionRequest, _ answers: [String: [String]]) {
        if request.id == "workflow-questions" { answerWorkflow(request, answers); return }
        guard pending.contains(where: { $0.id == request.id }), let transport else { return }
        do { try transport.answer(request, answers: answers) }
        catch { fail(error.localizedDescription); return }
        pending.removeAll { $0.id == request.id }
    }

    func approvePlan(_ request: ClaudePermissionRequest, then mode: ClaudePermissionMode?) {
        guard pending.contains(where: { $0.id == request.id }) else { return }
        if provider == .codex {
            guard let plan = request.plan, !plan.isEmpty else { fail(AIIntegrationError.invalidPlan.localizedDescription); return }
            pending.removeAll { $0.id == request.id }
            current?.pendingPlan = nil
            setPermissionMode(.default)
            send("O usuário aprovou este plano. Execute-o respeitando as permissões desta sessão:\n" + plan)
            return
        }
        write(ClaudeInput.approvePlan(request, then: mode))
        pending.removeAll { $0.id == request.id }
    }

    /// Keeps Claude planning, with the user's feedback as the reason.
    func requestPlanChanges(_ request: ClaudePermissionRequest, feedback: String) {
        let feedback = feedback.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = feedback.isEmpty
            ? "O usuário não aprovou o plano. Continue planejando e pergunte o que mudar."
            : "O usuário não aprovou o plano e pediu mudanças:\n\(feedback)\nRevise o plano e apresente-o de novo."
        if provider == .codex {
            guard pending.contains(where: { $0.id == request.id }) else { return }
            pending.removeAll { $0.id == request.id }
            current?.pendingPlan = nil
            setPermissionMode(.plan)
            send(message + "\nPlano anterior:\n" + (request.plan ?? ""))
            return
        }
        write(ClaudeInput.deny(request, message: message))
        if !feedback.isEmpty { entries.append(Entry(kind: .user(feedback))) }
        pending.removeAll { $0.id == request.id }
    }

    func decline(_ request: ClaudePermissionRequest) {
        if request.id == "workflow-questions" { interrupt(); return }
        if provider == .codex, request.isPlanApproval {
            pending.removeAll { $0.id == request.id }; current?.pendingPlan = nil; persist(); return
        }
        if provider == .codex {
            if request.requestId == "workflow-questions" { interrupt() }
            else { answer(request, [:]) }
            return
        }
        write(ClaudeInput.deny(request, message: "O usuário preferiu não responder."))
        pending.removeAll { $0.id == request.id }
    }

    // MARK: Provider transports

    private func conversationConfiguration(settings: AIProviderSettings? = nil, sessionID: String? = nil) -> AIConversationConfiguration {
        .init(root: root, sessionID: sessionID ?? current?.sessionId, settings: settings ?? .init(), mode: permissionMode,
              instructions: "Você trabalha no VibeDeck. Leia .vibedeck/AGENTS.md. Use provider: \(provider.rawValue) no MCP. " + AIPromptPolicy.instructions + (permissionMode == .plan ? "\n" + AIPlan.instructions : ""),
              config: provider == .codex ? CodexMCP.sessionConfig(root: root, cli: ClaudeUsageView.cliPath) : [:], autoReview: codexAutoReview)
    }

    private func prepareClaude(settings: AIProviderSettings? = nil, fresh: Bool = false) async throws {
        let sessionSettings = AIReadOnlyOperation.settings(.claude)
        let resolved = try AISettingsResolver.resolve(provider: .claude, resource: settings, session: sessionSettings)
        if fresh || needsRestart || activeClaudeSettings != resolved {
            claudeTransport?.stop(); claudeTransport = nil
        }
        if fresh { current?.sessionId = nil }
        if claudeTransport?.isConnected == true { return }
        try Task.checkCancellation()
        let transport = ClaudeConversationTransport()
        transport.onEvent = { [weak self, weak transport] event in
            guard let self, self.claudeTransport === transport, self.acceptingEvents else { return }
            self.handle(event)
        }
        transport.onDisconnect = { [weak self, weak transport] message in
            guard let self, self.claudeTransport === transport else { return }
            if transport?.resumeFailed == true { self.current?.sessionId = nil }
            self.claudeTransport = nil
            self.fail(message)
        }
        claudeTransport = transport; acceptingEvents = true
        do { _ = try await transport.prepare(conversationConfiguration(settings: resolved)) }
        catch { transport.stop(); if claudeTransport === transport { claudeTransport = nil }; throw error }
        activeClaudeSettings = resolved; needsRestart = false
    }

    private func write(_ data: Data) {
        do { try claudeTransport?.write(data) } catch { fail(error.localizedDescription) }
    }

    private func fail(_ message: String) {
        VDLog.$actionID.withValue(usageAction ?? VDLog.actionID) {
            VDLog.error("ai.request_failed", "Chamada de IA falhou", project: root, component: .ai, context: ["provider": provider.rawValue])
        }
        finishUsage("failed")
        let waiter = turnWaiter; turnWaiter = nil
        waiter?.resume(throwing: VibeDeckError.discoverFailed(message))
        entries.append(Entry(kind: .error(message)))
        isWorking = false
        isThinking = false
        persist()
    }

    // MARK: Events

    private func handle(_ event: ClaudeEvent) {
        switch event {
        case .initialized(let id, let model, let commands):
            if !commands.isEmpty { reportedCommands = commands }
            current?.sessionId = id
            self.model = model

        case .permissionModeChanged(let mode):
            permissionMode = mode
        case .thinking:
            isThinking = true
        case .textStarted:
            if !turnOutput.isEmpty { turnOutput += "\n" }
            isThinking = false
            entries.append(Entry(kind: .assistant("")))
        case .textDelta(let text):
            turnOutput += text
            isThinking = false
            if let last = entries.indices.last, case .assistant(let current) = entries[last].kind {
                entries[last].kind = .assistant(current + text)
            } else {
                entries.append(Entry(kind: .assistant(text)))
            }
        case .toolUse(let use):
            isThinking = false
            entries.append(Entry(kind: .tool(name: Self.toolTitle(use.name), summary: Self.summary(use.input, root: root), result: nil, isError: false), toolUseId: use.id))
        case .toolResult(let id, let content, let isError):
            if let i = entries.lastIndex(where: { $0.toolUseId == id }), case .tool(let name, let summary, _, _) = entries[i].kind {
                entries[i].kind = .tool(name: name, summary: summary, result: content, isError: isError)
            }
        case .permission(let request):
            pending.append(request)
        case .unsupportedControl(let requestId):
            write(ClaudeInput.unsupported(requestId: requestId))
        case .result(let result):
            let finalOutput = result.text ?? turnOutput
            if turnOutput.isEmpty, !result.isError, !finalOutput.isEmpty { entries.append(Entry(kind: .assistant(finalOutput))) }
            finishUsage(result.isInterrupted ? "cancelled" : result.isError ? "failed" : "completed", result: result)
            isWorking = workflowRef != nil
            isThinking = false
            pending.removeAll()
            if provider == .codex, permissionMode == .plan, workflowRef == nil, !result.isError, !result.isInterrupted,
               let request = AIPlan.request(finalOutput, id: "codex-plan-" + UUID().uuidString) {
                current?.pendingPlan = request.plan; pending.append(request)
            }
            let waiter = turnWaiter; turnWaiter = nil
            if result.isInterrupted { waiter?.resume(throwing: CancellationError()) }
            else if result.isError { waiter?.resume(throwing: VibeDeckError.discoverFailed(result.text ?? "A etapa falhou.")) }
            else { waiter?.resume(returning: finalOutput) }
            lastCost = result.costUSD
            if result.isError, let text = result.text, !text.isEmpty { entries.append(Entry(kind: .error(text))) }
            persist()
        case .ignored:
            break
        }
    }

    // MARK: Display helpers

    /// `mcp__vibedeck__rules_for` → `vibedeck · rules_for`.
    static func toolTitle(_ name: String) -> String {
        let parts = name.components(separatedBy: "__")
        guard parts.count >= 3, parts[0] == "mcp" else { return name }
        return "\(parts[1]) · \(parts[2...].joined(separator: "__"))"
    }

    /// One line describing a tool call: the command, path or pattern, with project paths made relative.
    static func summary(_ input: [String: JSONValue], root: URL) -> String {
        let keys = ["command", "file_path", "path", "pattern", "url", "query", "description", "prompt"]
        let value = keys.lazy.compactMap { input[$0]?.string }.first
            ?? input["questions"]?.array?.first?["question"]?.string
            ?? input.values.lazy.compactMap(\.string).first
            ?? ""
        let prefix = root.path + "/"
        let relative = value.replacingOccurrences(of: prefix, with: "")
        return relative.split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init) ?? relative
    }
}

// MARK: - Saved messages

extension AISession.Entry {
    init(_ message: ClaudeChatMessage) {
        switch message.role {
        case .user: self.init(kind: .user(message.text), mentions: message.mentions ?? [], attachments: message.attachments ?? [])
        case .assistant: self.init(kind: .assistant(message.text))
        case .tool: self.init(kind: .tool(name: message.toolName ?? message.text, summary: message.summary ?? "", result: message.result, isError: message.isError ?? false))
        case .notice: self.init(kind: .notice(message.text))
        case .error: self.init(kind: .error(message.text))
        }
    }

    /// Nil for an assistant message that never got text.
    var message: ClaudeChatMessage? {
        switch kind {
        case .user(let text):
            ClaudeChatMessage(role: .user, text: text, mentions: mentions.isEmpty ? nil : mentions, attachments: attachments.isEmpty ? nil : attachments)
        case .assistant(let text): text.isEmpty ? nil : ClaudeChatMessage(role: .assistant, text: text)
        case .tool(let name, let summary, let result, let isError):
            ClaudeChatMessage(role: .tool, text: name, toolName: name, summary: summary, result: result, isError: isError ? true : nil)
        case .notice(let text): ClaudeChatMessage(role: .notice, text: text)
        case .error(let text): ClaudeChatMessage(role: .error, text: text)
        }
    }
}

// MARK: - Codex and provider selection
extension AISession {
    func selectProvider(_ value: AIProvider, referencing: Bool = false) {
        guard value != provider else { return }
        let previous = current?.id
        stop()
        provider = value
        if !value.capabilities.permissionModes.contains(permissionMode) { permissionMode = .default }
        UserDefaults.standard.set(value.rawValue, forKey: selectedProviderKey)
        newChat()
        draft = ""
        draftMentions = referencing ? previous.map { [$0] } ?? [] : []
        draftAttachments = []
        if value == .codex { refreshCodex() }
    }

    func refreshCodex() {
        guard provider == .codex, RemoteExecution.available(.codex, root: root) else { return }
        Task {
            do { try await connectCodex() }
            catch { codexStatus = error.localizedDescription }
        }
    }

    private func connectCodex() async throws {
        if let starting = codexStarting { return try await starting.value }
        if codex != nil { return }
        let task = Task { @MainActor [self] in
            let transport = CodexConversationTransport()
            let rpc = transport.rpc
            transport.onEvent = { [weak self, weak transport] event in
                guard let self, self.codexTransport === transport, self.acceptingEvents else { return }
                self.handle(event)
            }
            transport.onNotification = { [weak self] method, params in self?.codexNotification(method, params) }
            transport.onDisconnect = { [weak self] message in
                guard let self else { return }
                self.codexTransport = nil
                self.pending = []
                self.turnWaiter?.resume(throwing: CodexRPCError.server(message)); self.turnWaiter = nil
                self.fail(message)
            }
            do { try await rpc.start(root: root); try Task.checkCancellation() }
            catch { rpc.stop(); throw error }
            codexTransport = transport
            // Catalog and quota failures should not prevent conversations from starting.
            do {
                var models: [CodexModel] = [], cursor: String?
                repeat {
                    var params: [String: JSONValue] = ["limit": .number(100)]
                    if let cursor { params["cursor"] = .string(cursor) }
                    let page = try await rpc.request("model/list", params: params)
                    models += CodexModel.list(page); cursor = page["nextCursor"]?.string
                } while cursor != nil
                codexModels = models
                let config = try await rpc.request("config/read", params: ["includeLayers": .bool(false)])
                let configured = config["config"]?["model"]?.string
                codexDefaultModel = configured ?? models.first(where: \.isDefault)?.id
            } catch { codexStatus = error.localizedDescription }
            do {
                codexSkills = CodexSkill.list(try await rpc.request("skills/list", params: ["cwds": .array([.string(RemoteExecution.path(for: root))])]))
            } catch { codexStatus = error.localizedDescription }
            await updateCodexLimits()
        }
        codexStarting = task
        defer { codexStarting = nil }
        try await task.value
    }

    func updateCodexLimits() async {
        guard let codex else { return }
        do {
            codexLimits = CodexRateLimit.list(try await codex.request("account/rateLimits/read"))
            codexStatus = codexLimits.isEmpty ? "Esta conta não informa limites de uso." : nil
        } catch { codexStatus = error.localizedDescription }
    }

    var availableCodexEfforts: [String] { codexModels.first(where: { $0.id == effectiveCodexModel })?.efforts ?? [] }

    private var effectiveCodexModel: String? {
        if !codexModel.isEmpty { return codexModel }
        return codexDefaultModel ?? codexModels.first(where: \.isDefault)?.id
    }

    private func prepareCodexThread(fresh: Bool = false, settings: AIProviderSettings? = nil) async throws {
        try await connectCodex()
        try Task.checkCancellation()
        guard codex != nil else { throw CodexRPCError.disconnected }
        let chosen = settings?.model ?? (codexModel.isEmpty ? nil : codexModel)
        let resolved = try AISettingsResolver.resolve(provider: .codex, resource: settings,
            session: .init(model: chosen), availableModels: codexModels.isEmpty ? nil : codexModels.map(\.id))
        var configuration = conversationConfiguration(settings: .init(model: resolved.model ?? effectiveCodexModel, effort: resolved.effort))
        if fresh { configuration.sessionID = nil }
        acceptingEvents = true
        guard let thread = try await codexTransport?.prepare(configuration) else { throw CodexRPCError.invalidResponse }
        current?.sessionId = thread
        if fresh { codexUsageTotals[thread] = .init(input: 0, output: 0, cachedInput: 0, cacheWrite: 0, reasoningOutput: 0) }
        persist()
    }

    private func launchCodexTurn(_ text: String, settings: AIProviderSettings? = nil, schema: JSONValue? = nil) async throws {
        guard codex != nil, current?.sessionId != nil else { throw CodexRPCError.disconnected }
        let chosen = settings?.model ?? effectiveCodexModel
        let requestedEffort = settings?.effort ?? (codexEffort.isEmpty ? nil : codexEffort)
        let resolved = try AISettingsResolver.resolve(provider: .codex, resource: .init(model: chosen, effort: requestedEffort),
            availableModels: codexModels.isEmpty ? nil : codexModels.map(\.id),
            supportedEfforts: codexModels.first(where: { $0.id == chosen })?.efforts)
        beginUsage(text, model: chosen)
        turnOutput = ""; codexTurn = nil; acceptingEvents = true
        let turn = try await codexTransport?.send(text, configuration: conversationConfiguration(settings: resolved), schema: schema)
        if isWorking { codexTurn = turn }
    }

    private func codexNotification(_ method: String, _ params: JSONValue) {
        if method == "account/rateLimits/updated" { codexLimits = CodexRateLimit.list(params); return }
        if method == "skills/changed" {
            Task { if let codex { codexSkills = CodexSkill.list((try? await codex.request("skills/list", params: ["cwds": .array([.string(RemoteExecution.path(for: root))]), "forceReload": .bool(true)])) ?? .null) } }
            return
        }
        guard let thread = params["threadId"]?.string, thread == current?.sessionId else { return }
        if method == "thread/tokenUsage/updated" {
            let total = AITokenUsage.codex(params["tokenUsage"]?["total"])
            if activeUsage != nil {
                if codexUsageBaseline == nil {
                    codexUsageBaseline = total.since(.codex(params["tokenUsage"]?["last"]))
                    activeUsage?.coverage = "partial: resumed thread without initial usage"
                }
                activeUsage?.tokens = total.since(codexUsageBaseline ?? .init())
            }
            codexUsageTotals[thread] = total
            return
        }
        if method == "turn/started" { codexTurn = params["turn"]?["id"]?.string; isWorking = true }
        if method == "serverRequest/resolved", let id = params["requestId"] {
            let key = CodexProtocol.key(id); pending.removeAll { $0.id == key }
        }
        if method == "turn/completed" {
            codexTurn = nil
            Task { await updateCodexLimits() }
        }
    }

    func canDecide(_ request: AIPermissionRequest, _ decision: AIPermissionDecision) -> Bool { transport?.decisions(for: request).contains(decision) == true }
    func canRemember(_ request: AIPermissionRequest) -> Bool { transport?.decisions(for: request).contains(.allowAlways) == true }
    func canAllowSession(_ request: AIPermissionRequest) -> Bool { transport?.decisions(for: request).contains(.allowSession) == true }

    private func answerWorkflow(_ request: ClaudePermissionRequest, _ answers: [String: [String]]) {
        if request.id == "workflow-questions" {
            guard let ref = workflowRef, let store = workflowProject else { return }
            do {
                for (text, number) in workflowQuestions {
                    guard let selected = answers[text], !selected.isEmpty else { continue }
                    _ = try store.answerRun(ref, number: number, answer: selected.joined(separator: ", "))
                }
                pending.removeAll { $0.id == request.id }
                workflowTask = Task { await continueWorkflow(ref, store: store) }
            } catch { fail(error.localizedDescription) }
            return
        }
    }

    private func codexSuggestions() -> [ClaudeSuggestion] {
        var suggestions = [ClaudeSuggestion(kind: .command, name: "/clear", detail: "Limpar esta conversa"), ClaudeSuggestion(kind: .command, name: "/compact", detail: "Compactar o contexto"), ClaudeSuggestion(kind: .command, name: "/context", detail: "Informações da sessão")]
        suggestions += codexSkills.map { ClaudeSuggestion(kind: .command, name: "/" + $0.name, detail: $0.description) }
        suggestions += registeredSuggestions()
        return suggestions
    }

    private func registeredSuggestions() -> [ClaudeSuggestion] {
        var suggestions: [ClaudeSuggestion] = []
        do {
            let store = ProjectStore(root: root)
            suggestions += ((try? store.listCommands()) ?? []).map { ClaudeSuggestion(kind: .command, name: "/" + $0.slug, detail: $0.command.summary) }
            suggestions += ((try? store.listSkills()) ?? []).map { ClaudeSuggestion(kind: .command, name: "/" + $0.slug, detail: $0.skill.summary) }
            suggestions += ((try? store.listAgents()) ?? []).map { ClaudeSuggestion(kind: .command, name: "/agent:" + $0.slug, detail: $0.agent.summary) }
        }
        return suggestions
    }

    private func handleLocalCommand(_ text: String) -> Bool {
        if text == "/clear" { if let id = current?.id { clear(id) }; return true }
        if text == "/context" {
            entries.append(Entry(kind: .notice("Codex · \(model ?? "modelo padrão") · \(current?.sessionId ?? "nova sessão")"))); persist(); return true
        }
        if text == "/compact" {
            guard let codex, let thread = current?.sessionId else { return true }
            Task {
                do { _ = try await codex.request("thread/compact/start", params: ["threadId": .string(thread)]); entries.append(Entry(kind: .notice("Compactação solicitada ao Codex."))); persist() }
                catch { fail(error.localizedDescription) }
            }
            return true
        }
        return false
    }

    // The VibeDeck engine owns transitions for both providers; each step starts a clean session.
    func executeWorkflow(_ workflow: String, input: String?, from: String? = nil, store: ProjectStore) {
        do {
            try RemoteWorkspace.existing(at: root)?.requireSynchronized()
            let (ref, run, _) = try store.startRun(workflow, input: input, from: from, provider: provider)
            resumeWorkflow(ref, run: run, store: store)
        } catch { fail(error.localizedDescription) }
    }
    func resumeWorkflow(_ ref: String, run: WorkflowRun, store: ProjectStore) {
        guard !isWorking else { return }
        if provider != run.provider { selectProvider(run.provider) }
        guard RemoteExecution.available(run.provider, root: root) else { fail("\(run.provider.title) não está instalado; esta execução pertence a ele."); return }
        newChat()
        current?.title = "Workflow · \((try? store.loadWorkflow(run.workflow).title) ?? run.workflow)"
        requestedPage = .chat
        workflowRef = ref; workflowProject = store
        isWorking = true
        workflowTask = Task { await continueWorkflow(ref, store: store) }
    }

    private func workflowTurn(_ text: String, settings: AIProviderSettings? = nil, schema: JSONValue? = nil, operation: String = "Transição") async throws -> String {
        try Task.checkCancellation()
        turnOutput = ""
        isWorking = true
        try await RemoteExecution.synchronize(root: root)
        if provider == .codex { try await prepareCodexThread(fresh: true, settings: settings) }
        else { try await prepareClaude(settings: settings, fresh: true) }
        turnOutput = ""; acceptingEvents = true
        return try await withCheckedThrowingContinuation { continuation in
            turnWaiter = continuation
            codexTask = Task {
                do {
                    if provider == .codex { try await launchCodexTurn(text, settings: settings, schema: schema) }
                    else {
                        let prompt = schema.map { text + "\nRetorne somente JSON válido conforme este schema: " + String(decoding: (try? JSONEncoder().encode($0)) ?? Data(), as: UTF8.self) } ?? text
                        beginUsage(prompt, model: activeClaudeSettings?.model)
                        _ = try await claudeTransport?.send(prompt, configuration: conversationConfiguration(settings: activeClaudeSettings), schema: schema)
                    }
                    activeUsage?.operation = "Workflow · " + operation }
                catch { let waiter = turnWaiter; turnWaiter = nil; waiter?.resume(throwing: error) }
            }
        }
    }

    private func continueWorkflow(_ ref: String, store: ProjectStore) async {
        do {
            isWorking = true
            try await RemoteExecution.synchronize(root: root)
            if provider == .codex { try await connectCodex() }
            let action = try await AIWorkflowRunner.run(ref: ref, store: store, cli: ClaudeUsageView.cliPath ?? "vibedeck", settings: { ref in
                let session = AIReadOnlyOperation.settings(self.provider)
                let resource = try store.runProviderSettings(ref, availableModels: self.provider == .codex ? self.codexModels.map(\.id) : [], fallback: session.model).settings
                return try AISettingsResolver.resolve(provider: self.provider, resource: resource, session: session)
            }, execute: { prompt, settings, title in
                try await self.workflowTurn(prompt, settings: settings, operation: title)
            }, decide: { output, candidates in
                try await RemoteExecution.synchronize(root: self.root)
                let conditions = String(decoding: try VDJSON.encode(candidates), as: UTF8.self)
                let prompt = "Avalie as condições na ordem sobre a saída da etapa. Retorne {\"to\":\"id\"} para a primeira condição verdadeira, ou {\"to\":null}.\nCondições: \(conditions)\nSaída: \(output). Leia a fonte para avaliar; ausência de evidência não torna uma condição verdadeira."
                let schema = #"{"type":"object","properties":{"to":{"type":["string","null"]}},"required":["to"],"additionalProperties":false}"#
                return try await AIReadOnlyOperation.run(root: self.root, provider: self.provider, operation: "Workflow · Transição", prompt: prompt, schema: schema) { data in
                    let value = try JSONDecoder().decode(JSONValue.self, from: data)
                    guard let target = value["to"], target == .null || target.string != nil else { throw AIIntegrationError.invalidTransition }
                    if let id = target.string, !candidates.contains(where: { $0.to == id }) { throw AIIntegrationError.invalidTransition }
                    return target.string
                }
            }, onAction: { action in
                if action.action == .runStep {
                    self.entries.append(Entry(kind: .notice("▶ Etapa \(action.step ?? "") — \(action.title ?? "")")))
                }
            })
            if action.action == .ask {
                workflowQuestions = [:]
                let questions: [JSONValue] = (action.questions ?? []).map { q in
                    let key = String(q.number)
                    workflowQuestions[key] = q.number
                    return .object(["id": .string(key), "question": .string(q.question), "header": .string("\(q.step) \(q.number)"), "multiSelect": .bool(q.multiple), "options": .array(q.options.map { .object(["label": .string($0.label), "description": .string($0.description ?? "")]) })])
                }
                pending = [.init(requestId: "workflow-questions", toolName: "AskUserQuestion", input: ["questions": .array(questions)])]
                isWorking = true
            } else {
                let run = try store.loadRun(ref)
                let rows = run.history.enumerated().map { "\($0.offset + 1) | \($0.element.step) | \($0.element.verdict ?? "—")" }.joined(separator: "\n")
                entries.append(Entry(kind: .notice("Workflow \(run.status.rawValue): \(action.reason)\n\(rows)")))
                isWorking = false; workflowRef = nil; workflowProject = nil
            }
            persist()
        } catch is CancellationError { isWorking = false }
        catch { fail(error.localizedDescription); workflowRef = nil; workflowProject = nil }
    }
}
