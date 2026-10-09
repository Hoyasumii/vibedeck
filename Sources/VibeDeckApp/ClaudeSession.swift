import Foundation
import Observation
import VibeDeckCore

/// The Claude Code conversations of a project, driven over `claude -p` stream-json. One per project
/// window: chats are saved as JSON outside the project (`ClaudeChatStore`), and the open one keeps a
/// process alive between turns, resumed with `--resume` when the chat is reopened.
@Observable @MainActor
final class AISession {
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
    @ObservationIgnored private var codex: CodexRPC?
    @ObservationIgnored private var codexStarting: Task<Void, Error>?
    @ObservationIgnored private var codexItems: [String: JSONValue] = [:]
    @ObservationIgnored private var codexRequests: [String: (id: JSONValue, method: String, params: JSONValue)] = [:]
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

    private func beginUsage(_ text: String, model: String?) {
        var record = AIUsageRecord(taskID: workflowRef ?? UUID().uuidString,
            operation: workflowRef.map { "Workflow " + $0 } ?? "Chat", provider: provider, model: model, prompt: text)
        record.coverage = "provider-reported; external calls may be absent"
        activeUsage = record
        if provider == .codex, let thread = current?.sessionId { codexUsageBaseline = codexUsageTotals[thread] }
    }

    private func finishUsage(_ status: String, result: ClaudeResult? = nil) {
        guard var usage = activeUsage else { return }
        activeUsage = nil
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
    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var stdin: FileHandle?
    @ObservationIgnored private var starting: Task<Void, Never>?
    @ObservationIgnored private var readers: [Task<Void, Never>] = []
    @ObservationIgnored private var stderrTail = ""
    @ObservationIgnored private var resumedWithoutInit = false
    @ObservationIgnored private var needsRestart = false
    private let currentKey: String

    init(root: URL, projectId: UUID) {
        self.root = root
        store = ClaudeChatStore.forProject(projectId)
        currentKey = "claudeChat.\(projectId.uuidString)"
        chosenModel = ClaudeModel(rawValue: UserDefaults.standard.string(forKey: "claudeModel") ?? "") ?? .automatic
        effort = ClaudeEffort(rawValue: UserDefaults.standard.string(forKey: "claudeEffort") ?? "") ?? .automatic
        provider = AIProvider(rawValue: UserDefaults.standard.string(forKey: selectedProviderKey) ?? "") ?? AIProvider.installed.first ?? .claude
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
        current = chat
        if provider == .codex { refreshCodex() }
        entries = chat.messages.map(Entry.init)
        lastCost = nil
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
    func ask(_ prompt: String) {
        requestedPage = .chat
        send(prompt)
    }

    /// Sends `text`; `mentions` are other chats, included in full as JSON (their sessions aren't resumed);
    /// `attachments` are files referenced by absolute path in the prompt (nothing is copied).
    func send(_ text: String, mentions: [UUID] = [], attachments: [URL] = []) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isWorking else { return }
        if provider == .codex, handleLocalCommand(text) { return }
        let paths = attachments.map(\.path)
        guard !text.isEmpty || !paths.isEmpty else { return }
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
        let expanded = provider == .codex ? ((try? ProjectStore(root: root).expandAICommand(text)) ?? text) : text
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
            Task {
                await ensureStarted()
                guard current?.id == chatId else { return }
                beginUsage(wire, model: model ?? chosenModel.rawValue)
                write(ClaudeInput.userMessage(wire))
            }
        }
    }

    // MARK: Autocomplete

    func loadProjectFiles() {
        guard projectFiles.isEmpty else { return }
        let root = root
        Task {
            projectFiles = await Task.detached { ClaudeCompletion.projectFiles(root: root) }.value
        }
    }

    /// Suggestions for what is being typed: `/commands`, or project files and other chats after `@`.
    func suggestions(for trigger: ClaudeTrigger, mentioned: [UUID]) -> [ClaudeSuggestion] {
        switch trigger.kind {
        case .command:
            let all = provider == .claude ? ClaudeCompletion.commands(root: root, reported: reportedCommands) : codexSuggestions()
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
            let result = await Task.detached { Self.execute(command, in: root) }.value
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

    /// Starts the process once, even when several messages are sent before it is up.
    private func ensureStarted() async {
        if process != nil { return }
        if let starting { return await starting.value }
        let task = Task { await start() }
        starting = task
        await task.value
        starting = nil
    }

    func interrupt() {
        guard isWorking else { return }
        if provider == .codex {
            if let ref = workflowRef, let store = workflowProject { _ = try? store.stopRun(ref, reason: "Interrompido pelo usuário") }
            if let thread = current?.sessionId, let turn = codexTurn, let codex {
                Task { _ = try? await codex.request("turn/interrupt", params: ["threadId": .string(thread), "turnId": .string(turn)]) }
            }
            if codexTurn == nil, pending.first?.id != "workflow-questions" { stop(); return }
            workflowTask?.cancel(); workflowTask = nil
            codexRequests = [:]; pending = []; isWorking = false
            turnWaiter?.resume(throwing: CancellationError()); turnWaiter = nil
            return
        }
        for request in pending { write(ClaudeInput.deny(request, message: "Interrompido pelo usuário.")) }
        pending.removeAll()
        write(ClaudeInput.interrupt())
    }

    /// Applies to the running process right away, or to the next one when idle.
    func setPermissionMode(_ mode: ClaudePermissionMode) {
        guard mode != permissionMode else { return }
        permissionMode = mode
        if provider == .claude, process != nil { write(ClaudeInput.setPermissionMode(mode)) }
    }

    func setModel(_ model: ClaudeModel) {
        guard model != chosenModel else { return }
        chosenModel = model
        needsRestart = process != nil
    }

    func setEffort(_ effort: ClaudeEffort) {
        guard effort != self.effort else { return }
        self.effort = effort
        needsRestart = process != nil
    }

    /// Ends the process, saving the transcript so far.
    func stop() {
        finishUsage("cancelled")
        persist()
        codexTask?.cancel(); codexTask = nil
        workflowTask?.cancel(); workflowTask = nil
        codexStarting?.cancel(); codexStarting = nil
        codex?.stop(); codex = nil
        turnWaiter?.resume(throwing: CancellationError()); turnWaiter = nil
        codexRequests = [:]; codexItems = [:]; codexTurn = nil
        workflowRef = nil; workflowProject = nil; workflowQuestions = [:]
        readers.forEach { $0.cancel() }
        readers.removeAll()
        process?.terminationHandler = nil
        if process?.isRunning == true { process?.terminate() }
        process = nil
        stdin = nil
        pending.removeAll()
        isWorking = false
        isThinking = false
    }

    // MARK: Answering requests

    enum Decision {
        case allowOnce, allowSession, allowAlways, deny
    }

    func decide(_ request: ClaudePermissionRequest, _ decision: Decision) {
        if provider == .codex { decideCodex(request, decision); return }
        switch decision {
        case .allowOnce: write(ClaudeInput.allow(request))
        case .allowSession: write(ClaudeInput.allow(request, always: .session))
        case .allowAlways: write(ClaudeInput.allow(request, always: .localSettings))
        case .deny: write(ClaudeInput.deny(request, message: "O usuário negou esta ação no VibeDeck."))
        }
        pending.removeAll { $0.id == request.id }
    }

    func answer(_ request: ClaudePermissionRequest, _ answers: [String: [String]]) {
        if provider == .codex { answerCodex(request, answers); return }
        write(ClaudeInput.answer(request, answers))
        pending.removeAll { $0.id == request.id }
    }

    func approvePlan(_ request: ClaudePermissionRequest, then mode: ClaudePermissionMode?) {
        write(ClaudeInput.approvePlan(request, then: mode))
        pending.removeAll { $0.id == request.id }
    }

    /// Keeps Claude planning, with the user's feedback as the reason.
    func requestPlanChanges(_ request: ClaudePermissionRequest, feedback: String) {
        let feedback = feedback.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = feedback.isEmpty
            ? "O usuário não aprovou o plano. Continue planejando e pergunte o que mudar."
            : "O usuário não aprovou o plano e pediu mudanças:\n\(feedback)\nRevise o plano e apresente-o de novo."
        write(ClaudeInput.deny(request, message: message))
        if !feedback.isEmpty { entries.append(Entry(kind: .user(feedback))) }
        pending.removeAll { $0.id == request.id }
    }

    func decline(_ request: ClaudePermissionRequest) {
        if provider == .codex {
            if request.requestId == "workflow-questions" { interrupt() }
            else { answerCodex(request, [:]) }
            return
        }
        write(ClaudeInput.deny(request, message: "O usuário preferiu não responder."))
        pending.removeAll { $0.id == request.id }
    }

    // MARK: Process

    private func start() async {
        guard let executable = ClaudeCode.executable else {
            fail("Claude Code não encontrado. Instale-o e reabra o VibeDeck.")
            return
        }
        let path = await Task.detached { ClaudeCode.childPATH() }.value

        let process = Process()
        process.executableURL = executable
        process.currentDirectoryURL = root
        process.arguments = ClaudeLaunch.arguments(mode: permissionMode, model: chosenModel, effort: effort, resume: current?.sessionId)
        needsRestart = false
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = path
        process.environment = environment

        let input = Pipe(), output = Pipe(), errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        process.terminationHandler = { [weak self] p in
            let status = p.terminationStatus
            Task { @MainActor in self?.ended(p, status: status) }
        }
        do {
            try process.run()
        } catch {
            fail("Não foi possível iniciar o Claude Code: \(error.localizedDescription)")
            return
        }
        self.process = process
        stdin = input.fileHandleForWriting
        stderrTail = ""
        resumedWithoutInit = current?.sessionId != nil

        readers = [
            Task.detached { [weak self] in
                for await line in ClaudeStream.lines(from: output.fileHandleForReading) {
                    let event = ClaudeStream.parse(line)
                    await self?.handle(event)
                }
            },
            Task.detached { [weak self] in
                for await line in ClaudeStream.lines(from: errors.fileHandleForReading) {
                    await self?.appendStderr(line)
                }
            },
        ]
    }

    private func write(_ data: Data) {
        guard let stdin else { return }
        do { try stdin.write(contentsOf: data) } catch { fail("O Claude Code parou de responder.") }
    }

    private func appendStderr(_ line: String) {
        stderrTail = String((stderrTail + line + "\n").suffix(2000))
    }

    private func ended(_ ended: Process, status: Int32) {
        guard ended === process else { return }
        let resumeFailed = resumedWithoutInit
        stop()
        if resumeFailed {
            // The saved conversation no longer exists: start fresh next time.
            current?.sessionId = nil
            fail("Não foi possível retomar a conversa anterior; a próxima mensagem começa uma nova.")
        } else if status != 0 {
            let detail = stderrTail.trimmingCharacters(in: .whitespacesAndNewlines)
            fail("O Claude Code terminou com erro (\(status))." + (detail.isEmpty ? "" : "\n\(detail)"))
        }
    }

    private func fail(_ message: String) {
        finishUsage("failed")
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
            resumedWithoutInit = false
        case .permissionModeChanged(let mode):
            permissionMode = mode
        case .thinking:
            isThinking = true
        case .textStarted:
            isThinking = false
            entries.append(Entry(kind: .assistant("")))
        case .textDelta(let text):
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
            finishUsage(result.isError ? "failed" : "completed", result: result)
            isWorking = false
            isThinking = false
            pending.removeAll()
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
        if value == .codex, permissionMode == .auto { permissionMode = .default }
        UserDefaults.standard.set(value.rawValue, forKey: selectedProviderKey)
        newChat()
        draft = ""
        draftMentions = referencing ? previous.map { [$0] } ?? [] : []
        draftAttachments = []
        if value == .codex { refreshCodex() }
    }

    func refreshCodex() {
        guard provider == .codex, AIProvider.codex.isInstalled else { return }
        Task {
            do { try await connectCodex() }
            catch { codexStatus = error.localizedDescription }
        }
    }

    private func connectCodex() async throws {
        if let starting = codexStarting { return try await starting.value }
        if codex != nil { return }
        let task = Task { @MainActor [self] in
            let rpc = CodexRPC()
            rpc.onNotification = { [weak self] method, params in self?.codexNotification(method, params) }
            rpc.onRequest = { [weak self, weak rpc] id, method, params in
                guard let self, self.provider == .codex,
                      params["threadId"]?.string == self.current?.sessionId else {
                    rpc?.reject(id: id, message: "Solicitação fora da conversa ativa")
                    return
                }
                var detail = params.object ?? [:]
                if let itemId = params["itemId"]?.string, let item = self.codexItems[itemId] {
                    detail["changes"] = item["changes"]
                }
                guard let request = CodexProtocol.permission(id: id, method: method, params: .object(detail)) else {
                    rpc?.reject(id: id, message: "Solicitação não suportada pelo VibeDeck")
                    return
                }
                self.codexRequests[request.id] = (id, method, params)
                self.pending.append(request)
            }
            rpc.onDisconnect = { [weak self] message in
                guard let self else { return }
                self.codex = nil
                self.pending = []; self.codexRequests = [:]
                self.turnWaiter?.resume(throwing: CodexRPCError.server(message)); self.turnWaiter = nil
                self.fail(message)
            }
            do { try await rpc.start(root: root); try Task.checkCancellation() }
            catch { rpc.stop(); throw error }
            codex = rpc
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
                codexDefaultModel = configured.flatMap { chosen in models.contains { $0.id == chosen } ? chosen : nil } ?? models.first(where: \.isDefault)?.id
            } catch { codexStatus = error.localizedDescription }
            do {
                codexSkills = CodexSkill.list(try await rpc.request("skills/list", params: ["cwds": .array([.string(root.path)])]))
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
        return codexDefaultModel ?? codexModels.first(where: \.isDefault)?.id ?? codexModels.first?.id
    }

    private func prepareCodexThread(fresh: Bool = false, settings: AIProviderSettings? = nil) async throws {
        try await connectCodex()
        try Task.checkCancellation()
        guard let rpc = codex else { throw CodexRPCError.disconnected }
        var params = CodexProtocol.threadParameters(root: root, mode: permissionMode, model: settings?.model ?? effectiveCodexModel, autoReview: codexAutoReview)
        params["config"] = .object(CodexMCP.sessionConfig(root: root, cli: ClaudeUsageView.cliPath))
        params["developerInstructions"] = .string("Você trabalha no VibeDeck. Leia .vibedeck/AGENTS.md. Use provider: codex no MCP. " + AIPromptPolicy.instructions)
        let method: String
        if !fresh, let id = current?.sessionId { method = "thread/resume"; params["threadId"] = .string(id) }
        else { method = "thread/start" }
        let response = try await rpc.request(method, params: params)
        guard let thread = response["thread"]?["id"]?.string else { throw CodexRPCError.invalidResponse }
        current?.sessionId = thread
        if method == "thread/start" { codexUsageTotals[thread] = .init(input: 0, output: 0, cachedInput: 0, cacheWrite: 0, reasoningOutput: 0) }
        model = response["model"]?.string ?? settings?.model ?? effectiveCodexModel
        persist()
    }

    private func launchCodexTurn(_ text: String, settings: AIProviderSettings? = nil, schema: JSONValue? = nil) async throws {
        guard let rpc = codex, let thread = current?.sessionId else { throw CodexRPCError.disconnected }
        let chosen = settings?.model ?? effectiveCodexModel
        var effort = settings?.effort ?? (codexEffort.isEmpty ? nil : codexEffort)
        if let value = effort, let item = codexModels.first(where: { $0.id == chosen }), !item.efforts.contains(value) {
            entries.append(Entry(kind: .notice("Esforço \(value) indisponível para \(item.title); usando o padrão do modelo.")))
            effort = nil
        }
        var params = CodexProtocol.turnParameters(thread: thread, text: text, mode: permissionMode, model: chosen, effort: effort, autoReview: codexAutoReview)
        if let schema { params["outputSchema"] = schema }
        beginUsage(text, model: chosen)
        turnOutput = ""; codexTurn = nil
        let response = try await rpc.request("turn/start", params: params)
        if isWorking { codexTurn = response["turn"]?["id"]?.string }
    }

    private func codexNotification(_ method: String, _ params: JSONValue) {
        if method == "account/rateLimits/updated" { codexLimits = CodexRateLimit.list(params); return }
        if method == "skills/changed" {
            Task { if let codex { codexSkills = CodexSkill.list((try? await codex.request("skills/list", params: ["cwds": .array([.string(root.path)]), "forceReload": .bool(true)])) ?? .null) } }
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
        if method == "item/started", let id = params["item"]?["id"]?.string { codexItems[id] = params["item"] }
        if method == "turn/started" { codexTurn = params["turn"]?["id"]?.string; isWorking = true }
        if method == "serverRequest/resolved", let id = params["requestId"] {
            let key = CodexProtocol.key(id); pending.removeAll { $0.id == key }; codexRequests[key] = nil
        }
        if method == "item/agentMessage/delta" { turnOutput += params["delta"]?.string ?? "" }
        if method == "item/completed", params["item"]?["type"]?.string == "agentMessage", turnOutput.isEmpty {
            let text = params["item"]?["text"]?.string ?? ""
            turnOutput = text
            if !text.isEmpty { handle(.textDelta(text)) }
        }
        let event = CodexProtocol.event(method, params)
        handle(event)
        if case .result(let result) = event {
            let waiter = turnWaiter; turnWaiter = nil
            if result.isError { waiter?.resume(throwing: CodexRPCError.server(result.text ?? "A etapa falhou")) }
            else if params["turn"]?["status"]?.string == "interrupted" { waiter?.resume(throwing: CancellationError()) }
            else { waiter?.resume(returning: turnOutput) }
            codexRequests = [:]; codexTurn = nil
            Task { await updateCodexLimits() }
        }
    }

    func canRemember(_ request: ClaudePermissionRequest) -> Bool {
        provider == .claude || codexRequests[request.id]?.params["proposedExecpolicyAmendment"]?.array?.isEmpty == false
    }

    private func decideCodex(_ request: ClaudePermissionRequest, _ decision: Decision) {
        guard let original = codexRequests.removeValue(forKey: request.id), let codex else { return }
        let value: JSONValue
        switch original.method {
        case "item/permissions/requestApproval":
            value = .object(["permissions": decision == .deny ? .object([:]) : original.params["permissions"] ?? .object([:]), "scope": .string(decision == .allowSession ? "session" : "turn")])
        case "item/tool/requestApproval":
            value = .object(["decision": .string(decision == .deny ? "decline" : decision == .allowSession ? "acceptForSession" : "accept")])
        default:
            let choice: JSONValue
            if decision == .allowAlways, let amendment = original.params["proposedExecpolicyAmendment"], amendment.array?.isEmpty == false {
                choice = .object(["acceptWithExecpolicyAmendment": .object(["execpolicy_amendment": amendment])])
            } else { choice = .string(decision == .deny ? "decline" : decision == .allowSession ? "acceptForSession" : "accept") }
            value = .object(["decision": choice])
        }
        do { try codex.respond(id: original.id, result: value) } catch { fail(error.localizedDescription) }
        pending.removeAll { $0.id == request.id }
    }

    private func answerCodex(_ request: ClaudePermissionRequest, _ answers: [String: [String]]) {
        if request.id == "workflow-questions" {
            guard let ref = workflowRef, let store = workflowProject else { return }
            do {
                for (text, number) in workflowQuestions {
                    guard let selected = answers[text], !selected.isEmpty else { continue }
                    _ = try store.answerRun(ref, number: number, answer: selected.joined(separator: ", "))
                }
                pending.removeAll { $0.id == request.id }
                workflowTask = Task { await continueCodexWorkflow(ref, store: store) }
            } catch { fail(error.localizedDescription) }
            return
        }
        guard let original = codexRequests.removeValue(forKey: request.id), let codex else { return }
        do { try codex.respond(id: original.id, result: CodexProtocol.answer(params: original.params, answers: answers)) }
        catch { fail(error.localizedDescription) }
        pending.removeAll { $0.id == request.id }
    }

    private func codexSuggestions() -> [ClaudeSuggestion] {
        var suggestions = [ClaudeSuggestion(kind: .command, name: "/clear", detail: "Limpar esta conversa"), ClaudeSuggestion(kind: .command, name: "/compact", detail: "Compactar o contexto"), ClaudeSuggestion(kind: .command, name: "/context", detail: "Informações da sessão")]
        suggestions += codexSkills.map { ClaudeSuggestion(kind: .command, name: "/" + $0.name, detail: $0.description) }
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

    // The VibeDeck engine owns transitions; each Codex step starts a clean thread.
    func executeWorkflow(_ workflow: String, input: String?, from: String? = nil, store: ProjectStore) {
        do {
            let (ref, run, _) = try store.startRun(workflow, input: input, from: from, provider: provider)
            resumeWorkflow(ref, run: run, store: store)
        } catch { fail(error.localizedDescription) }
    }
    func resumeWorkflow(_ ref: String, run: WorkflowRun, store: ProjectStore) {
        guard !isWorking else { return }
        if provider != run.provider { selectProvider(run.provider) }
        guard run.provider.isInstalled else { fail("\(run.provider.title) não está instalado; esta execução pertence a ele."); return }
        if run.provider == .claude {
            ask(WorkflowOrchestration.orchestratorPrompt(ref: ref, title: (try? store.loadWorkflow(run.workflow).title) ?? run.workflow, input: run.input, cli: ClaudeUsageView.cliPath ?? "vibedeck"))
        } else {
            newChat()
            current?.title = "Workflow · \((try? store.loadWorkflow(run.workflow).title) ?? run.workflow)"
            requestedPage = .chat
            workflowRef = ref; workflowProject = store
            workflowTask = Task { await continueCodexWorkflow(ref, store: store) }
        }
    }

    private func workflowTurn(_ text: String, settings: AIProviderSettings? = nil, schema: JSONValue? = nil, operation: String = "Transição") async throws -> String {
        try Task.checkCancellation()
        isWorking = true
        try await prepareCodexThread(fresh: true, settings: settings)
        return try await withCheckedThrowingContinuation { continuation in
            turnWaiter = continuation
            codexTask = Task {
                do { try await launchCodexTurn(text, settings: settings, schema: schema)
                    activeUsage?.operation = "Workflow · " + operation }
                catch { let waiter = turnWaiter; turnWaiter = nil; waiter?.resume(throwing: error) }
            }
        }
    }

    private func continueCodexWorkflow(_ ref: String, store: ProjectStore) async {
        do {
            isWorking = true
            try await connectCodex()
            while true {
                try Task.checkCancellation()
                let action = try store.nextRunAction(ref)
                switch action.action {
                case .done, .stop:
                    let run = try store.loadRun(ref)
                    let rows = run.history.enumerated().map { "\($0.offset + 1) | \($0.element.step) | \($0.element.verdict ?? "—")" }.joined(separator: "\n")
                    entries.append(Entry(kind: .notice("Workflow \(run.status.rawValue): \(action.reason)\n\(rows)")))
                    isWorking = false; persist(); workflowRef = nil; return
                case .ask:
                    workflowQuestions = [:]
                    let questions: [JSONValue] = (action.questions ?? []).map { q in
                        workflowQuestions[q.question] = q.number
                        return .object(["question": .string(q.question), "header": .string("\(q.step) \(q.number)"), "multiSelect": .bool(q.multiple), "options": .array(q.options.map { .object(["label": .string($0.label), "description": .string($0.description ?? "")]) })])
                    }
                    pending = [ClaudePermissionRequest(requestId: "workflow-questions", toolName: "AskUserQuestion", input: ["questions": .array(questions)], description: nil, suggestions: [])]
                    isWorking = true; persist(); return
                case .runStep:
                    entries.append(Entry(kind: .notice("▶ Etapa \(action.step ?? "") — \(action.title ?? "")")))
                    let settings = try store.runProviderSettings(ref, availableModels: codexModels.map(\.id), fallback: effectiveCodexModel)
                    if let warning = settings.warning { entries.append(Entry(kind: .notice(warning))) }
                    let prompt = try store.runStepPrompt(ref, cli: ClaudeUsageView.cliPath ?? "vibedeck")
                    let output = try await workflowTurn(prompt, settings: settings.settings, operation: action.title ?? action.step ?? "Etapa")
                    let verdict = output.split(whereSeparator: \.isNewline).last.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    guard !verdict.isEmpty else { throw CodexRPCError.server("A etapa terminou sem veredito.") }
                    if verdict == "PERGUNTA" {
                        guard !(try store.loadRun(ref)).openQuestions.isEmpty else { throw CodexRPCError.server("A etapa retornou PERGUNTA sem registrar perguntas.") }
                        continue
                    }
                    let outputReference = try store.saveRunOutput(ref, output: output)
                    var next = try store.recordRun(ref, verdict: verdict, summary: outputReference)
                    if next.action == .decide {
                        let candidates = String(decoding: try VDJSON.encode(next.candidates ?? []), as: UTF8.self)
                        let schema: JSONValue = .object(["type": .string("object"), "properties": .object(["to": .object(["type": .array([.string("string"), .string("null")])])]), "required": .array([.string("to")]), "additionalProperties": .bool(false)])
                        let choice = try await workflowTurn("Avalie as condições na ordem sobre a saída da etapa. Retorne {\"to\":\"id\"} para a primeira condição verdadeira, ou {\"to\":null}.\nCondições: \(candidates)\nSaída: \(outputReference). Leia a fonte para avaliar; ausência de evidência não torna uma condição verdadeira.", schema: schema)
                        let value = try JSONDecoder().decode(JSONValue.self, from: Data(choice.utf8))
                        guard let target = value["to"] else { throw CodexRPCError.invalidResponse }
                        next = try store.recordRun(ref, verdict: verdict, summary: outputReference, to: target.string, noneHolds: target == .null)
                    }
                    _ = next
                case .decide: throw CodexRPCError.server("Transição pendente sem saída da etapa.")
                }
            }
        } catch is CancellationError { isWorking = false }
        catch { fail(error.localizedDescription) }
    }
}
