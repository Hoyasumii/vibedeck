import Foundation
import Synchronization
#if canImport(os)
import os
#endif

// MARK: - Entry

enum LogLevel: String, Codable, CaseIterable, Comparable, Sendable {
    case debug, info, warning, error, crash

    private var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }
    static func < (a: Self, b: Self) -> Bool { a.rank < b.rank }

    var title: String {
        switch self {
        case .debug: "Depuração"
        case .info: "Info"
        case .warning: "Aviso"
        case .error: "Erro"
        case .crash: "Crash"
        }
    }
}

enum LogComponent: String, Codable, CaseIterable, Sendable {
    case app, cli, mcp, core, rules, ai, hook
}

/// One line of the log. Only names, ids, sizes and codes go here: never the content of prompts,
/// docs, ideas or tool arguments. Text fields are truncated on creation.
struct LogEntry: Codable, Equatable, Identifiable, Sendable {
    static let maxField = 500
    static let maxContext = 20
    /// Crash stacks (`context["stack"]`) keep every frame: without them a layout loop can't be traced.
    static let maxStack = 16_000

    /// Stable across reloads (lists keep their selection); not stored.
    var id: String { "\(ts.timeIntervalSinceReferenceDate)|\(session ?? "")|\(pid ?? 0)|\(event)|\(message)" }
    var action: String? { context["action"] }
    var control: String? { context["control"] }
    var label: String? { context["label"] }
    var ts: Date
    var level: LogLevel
    var component: LogComponent
    var event: String
    var message: String
    var project: String?
    var session: String?
    var pid: Int32?
    var version: String?
    var context: [String: String]

    init(
        ts: Date = .now, level: LogLevel, component: LogComponent, event: String, message: String,
        project: String? = nil, session: String? = nil, pid: Int32? = nil, version: String? = nil, context: [String: String] = [:]
    ) {
        self.ts = ts
        self.level = level
        self.component = component
        self.event = Self.clip(event, 80)
        self.message = Self.clip(message, Self.maxField)
        self.project = project
        self.session = session
        self.pid = pid
        self.version = version
        self.context = Self.sanitized(context)
    }

    static func clip(_ text: String, _ limit: Int) -> String {
        text.count > limit ? String(text.prefix(limit)) + "…" : text
    }

    /// At most `maxContext` keys (sorted), keys and values truncated (`stack` up to `maxStack`).
    static func sanitized(_ context: [String: String]) -> [String: String] {
        var out: [String: String] = [:]
        for key in context.keys.sorted().prefix(maxContext) {
            out[clip(key, 60)] = clip(context[key] ?? "", key == "stack" ? maxStack : maxField)
        }
        return out
    }

    private enum CodingKeys: String, CodingKey {
        case ts, level, component, event, message, project, session, pid, version, context
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ts = try c.decodeIfPresent(Date.self, forKey: .ts) ?? .distantPast
        level = (try? c.decodeIfPresent(String.self, forKey: .level)).flatMap { $0 }.flatMap(LogLevel.init(rawValue:)) ?? .info
        component = (try? c.decodeIfPresent(String.self, forKey: .component)).flatMap { $0 }.flatMap(LogComponent.init(rawValue:)) ?? .core
        event = try c.decodeIfPresent(String.self, forKey: .event) ?? ""
        message = try c.decodeIfPresent(String.self, forKey: .message) ?? ""
        project = try c.decodeIfPresent(String.self, forKey: .project)
        session = try c.decodeIfPresent(String.self, forKey: .session)
        pid = try c.decodeIfPresent(Int32.self, forKey: .pid)
        version = try c.decodeIfPresent(String.self, forKey: .version)
        context = Self.sanitized((try? c.decode([String: String].self, forKey: .context)) ?? [:])
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        // Fractional seconds: several entries per second must keep their order.
        try c.encode(ts.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true)), forKey: .ts)
        try c.encode(level, forKey: .level)
        try c.encode(component, forKey: .component)
        try c.encode(event, forKey: .event)
        try c.encode(message, forKey: .message)
        try c.encodeIfPresent(project, forKey: .project)
        try c.encodeIfPresent(session, forKey: .session)
        try c.encodeIfPresent(pid, forKey: .pid)
        try c.encodeIfPresent(version, forKey: .version)
        if !context.isEmpty { try c.encode(context, forKey: .context) }
    }

    /// One readable line, used by the CLI and the report.
    var line: String {
        let stamp = ts.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
        let extra = context.keys.sorted().map { "\($0)=\(context[$0] ?? "")" }.joined(separator: " ")
        return "\(stamp) [\(level.rawValue)] \(component.rawValue) \(event): \(message)" + (extra.isEmpty ? "" : "  {\(extra)}")
    }
}

// MARK: - Filter

struct LogFilter: Sendable, Equatable {
    var since: Date?
    var minLevel: LogLevel
    var components: Set<LogComponent>
    /// Project root path; entries without a project are kept only when this is nil.
    var project: String?
    var search: String?
    var action: String?
    var limit: Int

    init(since: Date? = nil, minLevel: LogLevel = .debug, components: Set<LogComponent> = [], project: String? = nil, search: String? = nil, action: String? = nil, limit: Int = 200) {
        self.since = since
        self.minLevel = minLevel
        self.components = components
        self.project = project
        self.search = search
        self.action = action
        self.limit = limit
    }

    func matches(_ entry: LogEntry) -> Bool {
        if let action, entry.action != action { return false }
        if let since, entry.ts < since { return false }
        if entry.level < minLevel { return false }
        if !components.isEmpty, !components.contains(entry.component) { return false }
        if let project, entry.project != project { return false }
        if let needle = search?.trimmingCharacters(in: .whitespaces), !needle.isEmpty {
            let haystack = ([entry.event, entry.message] + entry.context.values).joined(separator: " ")
            if haystack.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) == nil { return false }
        }
        return true
    }

    /// `30m`, `24h`, `7d` (or a bare number of hours) before `now`.
    static func parseSince(_ text: String, now: Date = .now) throws -> Date {
        let t = text.trimmingCharacters(in: .whitespaces).lowercased()
        let unit = t.last.flatMap { $0.isLetter ? $0 : nil }
        guard let n = Double(unit == nil ? t : String(t.dropLast())), n >= 0 else { throw VibeDeckError.invalidLogFilter(text) }
        let seconds: Double
        switch unit {
        case "m": seconds = n * 60
        case "h", nil: seconds = n * 3600
        case "d": seconds = n * 86400
        default: throw VibeDeckError.invalidLogFilter(text)
        }
        return now.addingTimeInterval(-seconds)
    }

    static func parseLevel(_ text: String) throws -> LogLevel {
        guard let level = LogLevel(rawValue: text.lowercased()) else { throw VibeDeckError.invalidLogFilter(text) }
        return level
    }

    static func parseComponents(_ values: [String]) throws -> Set<LogComponent> {
        Set(try values.map { value in
            guard let c = LogComponent(rawValue: value.lowercased()) else { throw VibeDeckError.invalidLogFilter(value) }
            return c
        })
    }
}

// MARK: - Store

/// Logs of every VibeDeck process (app, CLI, MCP), one JSON Lines file per day (UTC), kept outside
/// projects in Application Support. Unlike project data, lines are appended with O_APPEND instead
/// of AtomicFile: each line goes out in a single write, so concurrent processes never interleave.
struct LogStore: Sendable {
    static let maxAgeDays = 14
    let dir: URL
    /// Past this size a day only accepts warnings, errors and crashes.
    let maxDailyBytes: Int

    init(dir: URL, maxDailyBytes: Int = 5_000_000) {
        self.dir = dir
        self.maxDailyBytes = maxDailyBytes
    }

    /// `~/Library/Application Support/VibeDeck/logs/`.
    static var `default`: LogStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: ".local/share")
        return LogStore(dir: base.appending(path: "VibeDeck/logs", directoryHint: .isDirectory))
    }

    var runningDir: URL { dir.appending(path: "running", directoryHint: .isDirectory) }

    static func day(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle().year().month().day())
    }

    func fileURL(for date: Date) -> URL { dir.appending(path: "\(Self.day(date)).jsonl") }

    /// Day files, newest first.
    func files() -> [URL] {
        let all = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return all.filter { $0.pathExtension == "jsonl" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    func append(_ entry: LogEntry) throws {
        var data = try VDJSON.compactEncoder.encode(entry)
        data.append(0x0A)
        let url = fileURL(for: entry.ts)
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        if size >= maxDailyBytes, entry.level < .warning { return }
        do { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) } catch {
            throw VibeDeckError.logUnavailable(error.localizedDescription)
        }
        let fd = open(url.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        guard fd >= 0 else { throw VibeDeckError.logUnavailable(String(cString: strerror(errno))) }
        defer { close(fd) }
        let written = data.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        guard written == data.count else { throw VibeDeckError.logUnavailable(String(cString: strerror(errno))) }
    }

    /// Matching entries, newest first. Unreadable lines are skipped.
    func entries(_ filter: LogFilter = LogFilter()) -> [LogEntry] {
        let firstDay = filter.since.map(Self.day)
        var out: [LogEntry] = []
        for file in files() {
            if let firstDay, file.deletingPathExtension().lastPathComponent < firstDay { break }
            guard let data = try? Data(contentsOf: file) else { continue }
            let lines = data.split(separator: 0x0A, omittingEmptySubsequences: true)
            let decoded = lines.compactMap { try? VDJSON.decoder.decode(LogEntry.self, from: Data($0)) }
            // A day may hold lines from several processes slightly out of order.
            for entry in decoded.sorted(by: { $0.ts > $1.ts }) where filter.matches(entry) {
                out.append(entry)
                if out.count >= filter.limit { return out }
            }
        }
        return out
    }

    /// Removes day files older than `maxAgeDays`. Returns how many were removed.
    @discardableResult
    func prune(now: Date = .now) -> Int {
        let cutoff = Self.day(now.addingTimeInterval(-Double(Self.maxAgeDays) * 86400))
        var removed = 0
        for file in files() where file.deletingPathExtension().lastPathComponent < cutoff {
            if (try? FileManager.default.removeItem(at: file)) != nil { removed += 1 }
        }
        return removed
    }

    /// Plain-text report (oldest first) to paste in an issue.
    func report(_ filter: LogFilter = LogFilter(minLevel: .warning), header: String? = nil) -> String {
        let entries = entries(filter)
        var lines = [header ?? "Relatório de diagnóstico do VibeDeck", "Gerado em \(Date.now.formatted(Date.ISO8601FormatStyle()))",
                     "Entradas: \(entries.count)", ""]
        lines += entries.reversed().map(\.line)
        return lines.joined(separator: "\n") + "\n"
    }
}

// MARK: - Facade

/// Process-wide logger. Unconfigured processes (tests, libraries) only mirror to os.Logger and
/// never touch the user's log directory. Writing never throws: failures fall back to stderr.
enum VDLog {
    /// Task-local values follow child Tasks, without mixing actions from different windows.
    @TaskLocal static var actionID: String?
    @TaskLocal static var actionLabel: String?
    @TaskLocal static var projectRoot: URL?
    @TaskLocal static var undoName: String?
    @TaskLocal static var testStore: LogStore?

    @discardableResult
    static func withAction<T>(control: String, label: String, project: URL? = nil,
                                     id: String = UUID().uuidString, _ body: () throws -> T) rethrows -> T {
        try $actionID.withValue(id) {
            try $actionLabel.withValue(label) {
                try $projectRoot.withValue(project ?? projectRoot) {
                    info("ui.activated", "Ação do usuário", component: .app,
                         context: ["control": control, "label": label])
                    return try body()
                }
            }
        }
    }

    /// Detached work keeps actor independence while explicitly inheriting correlation metadata.
    @discardableResult
    static func detached<T: Sendable>(priority: TaskPriority? = nil,
        operation: @escaping @Sendable () async throws -> T) -> Task<T, Error> {
        let action = actionID, label = actionLabel, root = projectRoot, undo = undoName, logs = testStore
        return Task.detached(priority: priority) {
            try await $actionID.withValue(action) {
                try await $actionLabel.withValue(label) {
                    try await $projectRoot.withValue(root) {
                        try await $undoName.withValue(undo) {
                            try await $testStore.withValue(logs) { try await operation() }
                        }
                    }
                }
            }
        }
    }

    @discardableResult
    static func detached<T: Sendable>(priority: TaskPriority? = nil,
        operation: @escaping @Sendable () async -> T) -> Task<T, Never> {
        let action = actionID, label = actionLabel, root = projectRoot, undo = undoName, logs = testStore
        return Task.detached(priority: priority) {
            await $actionID.withValue(action) {
                await $actionLabel.withValue(label) {
                    await $projectRoot.withValue(root) {
                        await $undoName.withValue(undo) {
                            await $testStore.withValue(logs) { await operation() }
                        }
                    }
                }
            }
        }
    }

    /// Explicitly carries correlation across native threads and callback queues as well as Tasks.
    struct Context: Sendable {
        fileprivate let action: String?, label: String?, root: URL?, undo: String?
        fileprivate let logs: LogStore?
        func perform<T>(_ body: () throws -> T) rethrows -> T {
            try VDLog.$actionID.withValue(action) {
                try VDLog.$actionLabel.withValue(label) {
                    try VDLog.$projectRoot.withValue(root) {
                        try VDLog.$undoName.withValue(undo) {
                            try VDLog.$testStore.withValue(logs, operation: body)
                        }
                    }
                }
            }
        }
    }
    static func captureContext() -> Context {
        Context(action: actionID, label: actionLabel, root: projectRoot, undo: undoName, logs: testStore)
    }

    /// Shared by ProjectModel's direct writes and the ProjectStore operations it invokes.
    static func fileWritten(_ url: URL, bytes: Int) {
        let config = state.withLock { $0 }
        guard config.component == .app || testStore != nil,
              let root = projectRoot ?? config.project.map({ URL(fileURLWithPath: $0) }) else { return }
        let prefix = root.standardizedFileURL.path + "/"
        guard url.standardizedFileURL.path.hasPrefix(prefix) else { return }
        info("store.file_written", "Arquivo gravado", project: root, component: .app,
             context: ["file": String(url.standardizedFileURL.path.dropFirst(prefix.count)),
                       "undo": undoName ?? actionLabel ?? "Salvar", "bytes": String(bytes)])
    }

    struct Config: Sendable {
        var inheritedAction = ProcessInfo.processInfo.environment["VIBEDECK_ACTION"]
        var component: LogComponent = .core
        var store: LogStore?
        var version: String?
        var project: String?
        var session = UUID().uuidString
    }

    private static let state = Mutex(Config())
    private static let queue = DispatchQueue(label: "vibedeck.log")

    static func configure(component: LogComponent, version: String?, store: LogStore? = .default, project: URL? = nil) {
        state.withLock {
            $0.component = component
            $0.store = store
            $0.version = version
            $0.project = project.map(path)
        }
    }

    /// Default project for entries that don't name one (the CLI/MCP root).
    static func setProject(_ root: URL?) {
        state.withLock { $0.project = root.map(path) }
    }

    static var store: LogStore? { state.withLock { $0.store } }
    static var session: String { state.withLock { $0.session } }

    static func path(_ url: URL) -> String { url.standardizedFileURL.path }

    /// `sync` writes before returning (crash handlers, process exit).
    static func log(
        _ level: LogLevel, _ event: String, _ message: String, project: URL? = nil,
        component: LogComponent? = nil, context: [String: String] = [:], sync: Bool = false
    ) {
        let config = state.withLock { $0 }
        var context = context
        if let action = actionID ?? config.inheritedAction { context["action"] = action }
        let entry = LogEntry(level: level, component: component ?? config.component, event: event, message: message,
                             project: (project ?? projectRoot).map(path) ?? config.project, session: config.session,
                             pid: ProcessInfo.processInfo.processIdentifier, version: config.version, context: context)
        mirror(entry)
        guard let store = testStore ?? config.store else { return }
        let work: @Sendable () -> Void = {
            do { try store.append(entry) } catch {
                FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            }
        }
        if sync { queue.sync(execute: work) } else { queue.async(execute: work) }
    }

    static func debug(_ event: String, _ message: String, project: URL? = nil, component: LogComponent? = nil, context: [String: String] = [:]) {
        log(.debug, event, message, project: project, component: component, context: context)
    }

    static func info(_ event: String, _ message: String, project: URL? = nil, component: LogComponent? = nil, context: [String: String] = [:]) {
        log(.info, event, message, project: project, component: component, context: context)
    }

    static func warning(_ event: String, _ message: String, project: URL? = nil, component: LogComponent? = nil, context: [String: String] = [:]) {
        log(.warning, event, message, project: project, component: component, context: context)
    }

    static func error(_ event: String, _ message: String, project: URL? = nil, component: LogComponent? = nil, context: [String: String] = [:]) {
        log(.error, event, message, project: project, component: component, context: context)
    }

    /// Logs a thrown error with its description and type.
    static func error(_ error: Error, event: String, project: URL? = nil, component: LogComponent? = nil, context: [String: String] = [:]) {
        let message = "Falha na operação"
        log(.error, event, message, project: project, component: component,
            context: context.merging(["errorType": String(describing: type(of: error))]) { a, _ in a })
    }

    /// Waits for pending writes (tests, before exiting).
    static func flush() { queue.sync {} }

    private static func mirror(_ entry: LogEntry) {
        #if canImport(os)
        let logger = Logger(subsystem: "app.vibedeck", category: entry.component.rawValue)
        let text = "\(entry.event): \(entry.message)"
        switch entry.level {
        case .debug: logger.debug("\(text, privacy: .public)")
        case .info: logger.info("\(text, privacy: .public)")
        case .warning: logger.warning("\(text, privacy: .public)")
        case .error: logger.error("\(text, privacy: .public)")
        case .crash: logger.fault("\(text, privacy: .public)")
        }
        #endif
    }
}

// MARK: - Crash detection

/// What a previous run left behind when it didn't exit cleanly.
struct CrashInfo: Codable, Equatable, Sendable {
    var pid: Int32
    var startedAt: Date
    var version: String?
    /// macOS crash report (`.ips`) matched to the run, if any.
    var report: String?
    var summary: String?
}

/// A running process leaves `running/<pid>.json`; a clean exit removes it. On the next launch,
/// files of dead pids are unclean exits, matched to the crash report macOS wrote, if any.
/// No signal handlers: they must be async-signal-safe, and macOS already writes the full report.
enum CrashSentinel {
    struct Marker: Codable {
        var pid: Int32
        var startedAt: Date
        var version: String?
        var component: LogComponent

        init(pid: Int32, startedAt: Date, version: String?, component: LogComponent) {
            self.pid = pid; self.startedAt = startedAt; self.version = version; self.component = component
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            pid = try c.decodeIfPresent(Int32.self, forKey: .pid) ?? 0
            startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt) ?? .distantPast
            version = try c.decodeIfPresent(String.self, forKey: .version)
            component = (try? c.decodeIfPresent(LogComponent.self, forKey: .component)).flatMap { $0 } ?? .app
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(pid, forKey: .pid)
            try c.encode(startedAt, forKey: .startedAt)
            try c.encodeIfPresent(version, forKey: .version)
            try c.encode(component, forKey: .component)
        }

        private enum CodingKeys: String, CodingKey { case pid, startedAt, version, component }
    }

    static var diagnosticReportsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/DiagnosticReports", directoryHint: .isDirectory)
    }

    static func begin(store: LogStore, version: String?, component: LogComponent = .app, pid: Int32 = ProcessInfo.processInfo.processIdentifier, now: Date = .now) throws {
        let marker = Marker(pid: pid, startedAt: now, version: version, component: component)
        try AtomicFile.write(VDJSON.encode(marker), to: store.runningDir.appending(path: "\(pid).json"))
    }

    static func end(store: LogStore, pid: Int32 = ProcessInfo.processInfo.processIdentifier) {
        try? FileManager.default.removeItem(at: store.runningDir.appending(path: "\(pid).json"))
    }

    /// Unclean exits since the last call; their markers are removed.
    static func detectUnclean(
        store: LogStore, reportsDir: URL = diagnosticReportsDir, isAlive: (Int32) -> Bool = { kill($0, 0) == 0 }
    ) -> [CrashInfo] {
        let fm = FileManager.default
        let markers = (try? fm.contentsOfDirectory(at: store.runningDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        var found: [CrashInfo] = []
        for url in markers where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url), let marker = try? VDJSON.decoder.decode(Marker.self, from: data) else {
                try? fm.removeItem(at: url)
                continue
            }
            if marker.pid == ProcessInfo.processInfo.processIdentifier || isAlive(marker.pid) { continue }
            let report = crashReport(after: marker.startedAt, in: reportsDir)
            found.append(CrashInfo(pid: marker.pid, startedAt: marker.startedAt, version: marker.version,
                                   report: report?.path, summary: report.flatMap(summary)))
            try? fm.removeItem(at: url)
        }
        return found.sorted { $0.startedAt < $1.startedAt }
    }

    /// Oldest VibeDeck `.ips` written after `start`.
    static func crashReport(after start: Date, in dir: URL) -> URL? {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
        return files
            .filter { $0.pathExtension == "ips" && $0.lastPathComponent.lowercased().hasPrefix("vibedeck") }
            .compactMap { url -> (URL, Date)? in
                guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, date >= start else { return nil }
                return (url, date)
            }
            .min { $0.1 < $1.1 }?.0
    }

    /// "EXC_BREAKPOINT (SIGTRAP)" from an `.ips`: a JSON header line followed by a JSON body.
    static func summary(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url), let newline = data.firstIndex(of: 0x0A),
              let body = try? JSONSerialization.jsonObject(with: data[data.index(after: newline)...]) as? [String: Any],
              let exception = body["exception"] as? [String: Any] else { return nil }
        let type = exception["type"] as? String
        let signal = exception["signal"] as? String
        return [type, signal.map { "(\($0))" }].compactMap { $0 }.joined(separator: " ").nonEmpty
    }
}
