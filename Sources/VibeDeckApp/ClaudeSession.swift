import Foundation
import Observation
import VibeDeckCore

/// The Claude Code conversations of a project, driven over `claude -p` stream-json. One per project
/// window: chats are saved as JSON outside the project (`ClaudeChatStore`), and the open one keeps a
/// process alive between turns, resumed with `--resume` when the chat is reopened.
@Observable @MainActor
final class ClaudeSession {
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
        migrateLegacySession(key: "claudeSession.\(projectId.uuidString)")
        chats = store.list()
        if let id = UserDefaults.standard.string(forKey: currentKey).flatMap(UUID.init(uuidString:)), let chat = store.load(id) {
            show(chat)
        } else if chats.isEmpty {
            current = ClaudeChat(title: ClaudeChat.untitled)
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
        show(ClaudeChat(title: ClaudeChat.untitled))
    }

    func open(_ id: UUID) {
        guard id != current?.id else { return }
        stop()
        if let chat = store.load(id) { show(chat) }
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
        current = chat
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
        let paths = attachments.map(\.path)
        guard !text.isEmpty || !paths.isEmpty else { return }
        if needsRestart, !isWorking { stop() }
        if current == nil { current = ClaudeChat(title: ClaudeChat.untitled) }
        guard let chatId = current?.id else { return }
        if current?.title == ClaudeChat.untitled, !entries.contains(where: { if case .user = $0.kind { true } else { false } }) {
            current?.title = ClaudeChat.title(from: text.isEmpty ? attachments.map(\.lastPathComponent).joined(separator: ", ") : text)
        }
        let mentioned = mentions.filter { $0 != chatId }.compactMap(store.load)
        entries.append(Entry(kind: .user(text), mentions: mentioned.map(\.id), attachments: paths))
        isWorking = true
        persist()
        var wire = ClaudeChat.wireText(text, mentioning: mentioned, attachments: paths)
        if !shellContext.isEmpty {
            wire = shellContext.joined(separator: "\n") + "\n\n" + wire
            shellContext = []
        }
        Task {
            await ensureStarted()
            guard current?.id == chatId else { return }
            write(ClaudeInput.userMessage(wire))
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
            let all = ClaudeCompletion.commands(root: root, reported: reportedCommands)
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
        if current == nil { current = ClaudeChat(title: ClaudeChat.untitled) }
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
        for request in pending { write(ClaudeInput.deny(request, message: "Interrompido pelo usuário.")) }
        pending.removeAll()
        write(ClaudeInput.interrupt())
    }

    /// Applies to the running process right away, or to the next one when idle.
    func setPermissionMode(_ mode: ClaudePermissionMode) {
        guard mode != permissionMode else { return }
        permissionMode = mode
        if process != nil { write(ClaudeInput.setPermissionMode(mode)) }
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
        persist()
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
        switch decision {
        case .allowOnce: write(ClaudeInput.allow(request))
        case .allowSession: write(ClaudeInput.allow(request, always: .session))
        case .allowAlways: write(ClaudeInput.allow(request, always: .localSettings))
        case .deny: write(ClaudeInput.deny(request, message: "O usuário negou esta ação no VibeDeck."))
        }
        pending.removeAll { $0.id == request.id }
    }

    func answer(_ request: ClaudePermissionRequest, _ answers: [String: [String]]) {
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

extension ClaudeSession.Entry {
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
