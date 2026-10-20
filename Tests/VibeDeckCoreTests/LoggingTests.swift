import Foundation
import Testing
@testable import VibeDeckCore

@Suite struct LoggingTests {
    private func tempDir(_ name: String = "logs") -> URL {
        FileManager.default.temporaryDirectory.appending(path: "vibedeck-\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private func entry(_ level: LogLevel, _ event: String, at ts: Date = .now, component: LogComponent = .cli, project: String? = nil) -> LogEntry {
        LogEntry(ts: ts, level: level, component: component, event: event, message: "mensagem \(event)", project: project)
    }

    @Test func appendsAndFiltersNewestFirst() throws {
        let logs = LogStore(dir: tempDir())
        defer { try? FileManager.default.removeItem(at: logs.dir) }
        let now = Date.now
        try logs.append(entry(.info, "a", at: now.addingTimeInterval(-30), project: "/p1"))
        try logs.append(entry(.error, "b", at: now.addingTimeInterval(-20), component: .mcp, project: "/p1"))
        try logs.append(entry(.warning, "c", at: now.addingTimeInterval(-10), project: "/p2"))

        #expect(logs.entries().map(\.event) == ["c", "b", "a"])
        #expect(logs.entries(LogFilter(minLevel: .warning)).map(\.event) == ["c", "b"])
        #expect(logs.entries(LogFilter(components: [.mcp])).map(\.event) == ["b"])
        #expect(logs.entries(LogFilter(project: "/p1")).map(\.event) == ["b", "a"])
        #expect(logs.entries(LogFilter(search: "MENSAGEM C")).map(\.event) == ["c"])
        #expect(logs.entries(LogFilter(since: now.addingTimeInterval(-15))).map(\.event) == ["c"])
        #expect(logs.entries(LogFilter(limit: 1)).map(\.event) == ["c"])
    }

    @Test func skipsCorruptLinesAndKeepsFractionalSeconds() throws {
        let logs = LogStore(dir: tempDir())
        defer { try? FileManager.default.removeItem(at: logs.dir) }
        let ts = Date(timeIntervalSince1970: 1_800_000_000.5)
        try logs.append(entry(.error, "ok", at: ts))
        let handle = try FileHandle(forWritingTo: logs.fileURL(for: ts))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("não é json\n{\"level\":\"desconhecido\"}\n".utf8))
        try handle.close()

        let text = try String(contentsOf: logs.fileURL(for: ts), encoding: .utf8)
        #expect(text.contains(".500Z"))
        let read = logs.entries(LogFilter(limit: 10))
        // The hand-written line decodes leniently (unknown level -> info); the garbage line is skipped.
        #expect(read.count == 2)
        let ok = try #require(read.first { $0.event == "ok" })
        #expect(abs(ok.ts.timeIntervalSince(ts)) < 0.001)
        #expect(read.contains { $0.event.isEmpty && $0.level == .info })
    }

    @Test func sanitizesLongFieldsAndContext() {
        let long = String(repeating: "x", count: 2000)
        var context: [String: String] = [:]
        for i in 0..<30 { context[String(format: "k%02d", i)] = long }
        let e = LogEntry(level: .error, component: .core, event: "e", message: long, context: context)
        #expect(e.message.count == LogEntry.maxField + 1)
        #expect(e.context.count == LogEntry.maxContext)
        #expect(e.context.values.allSatisfy { $0.count == LogEntry.maxField + 1 })
        #expect(e.context["k00"] != nil && e.context["k29"] == nil)
    }

    @Test func keepsLongCrashStacks() {
        let stack = String(repeating: "y", count: 5000)
        let e = LogEntry(level: .crash, component: .app, event: "e", message: "m", context: ["stack": stack, "name": stack])
        #expect(e.context["stack"] == stack)
        #expect(e.context["name"]?.count == LogEntry.maxField + 1)
    }

    @Test func omitsEmptyOptionalFields() throws {
        let data = try VDJSON.compactEncoder.encode(LogEntry(level: .info, component: .app, event: "e", message: "m"))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ["ts", "level", "component", "event", "message"])
    }

    @Test func prunesOldDaysAndCapsDailySize() throws {
        let logs = LogStore(dir: tempDir(), maxDailyBytes: 400)
        defer { try? FileManager.default.removeItem(at: logs.dir) }
        let now = Date.now
        try logs.append(entry(.error, "velho", at: now.addingTimeInterval(-20 * 86400)))
        for i in 0..<10 { try logs.append(entry(.info, "info\(i)", at: now)) }
        try logs.append(entry(.error, "erro", at: now))

        let today = logs.entries(LogFilter(since: now.addingTimeInterval(-60), limit: 100))
        #expect(today.count < 11)
        #expect(today.contains { $0.event == "erro" })

        #expect(logs.prune(now: now) == 1)
        #expect(!logs.entries(LogFilter(limit: 100)).contains { $0.event == "velho" })
    }

    @Test func concurrentAppendsKeepWholeLines() async throws {
        let logs = LogStore(dir: tempDir())
        defer { try? FileManager.default.removeItem(at: logs.dir) }
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<200 {
                group.addTask { try? logs.append(LogEntry(level: .error, component: .mcp, event: "e\(i)", message: String(repeating: "m", count: 300))) }
            }
        }
        #expect(logs.entries(LogFilter(limit: 1000)).count == 200)
    }

    @Test func parsesFilters() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(try LogFilter.parseSince("30m", now: now) == now.addingTimeInterval(-1800))
        #expect(try LogFilter.parseSince("24h", now: now) == now.addingTimeInterval(-86400))
        #expect(try LogFilter.parseSince("2", now: now) == now.addingTimeInterval(-7200))
        #expect(try LogFilter.parseSince("7d", now: now) == now.addingTimeInterval(-7 * 86400))
        #expect(throws: VibeDeckError.invalidLogFilter("1w")) { try LogFilter.parseSince("1w") }
        #expect(throws: VibeDeckError.invalidLogFilter("fatal")) { try LogFilter.parseLevel("fatal") }
        #expect(try LogFilter.parseComponents(["MCP", "app"]) == [.mcp, .app])
    }

    @Test func reportIsChronological() throws {
        let logs = LogStore(dir: tempDir())
        defer { try? FileManager.default.removeItem(at: logs.dir) }
        let now = Date.now
        try logs.append(entry(.error, "primeiro", at: now.addingTimeInterval(-2)))
        try logs.append(entry(.warning, "segundo", at: now.addingTimeInterval(-1)))
        try logs.append(entry(.info, "ignorado", at: now))
        let report = logs.report(header: "Teste")
        #expect(report.hasPrefix("Teste\n"))
        #expect(report.contains("Entradas: 2"))
        let first = try #require(report.range(of: "primeiro")), second = try #require(report.range(of: "segundo"))
        #expect(first.lowerBound < second.lowerBound)
        #expect(!report.contains("ignorado"))
    }

    @Test func crashSentinelDetectsDeadRunsAndMatchesReport() throws {
        let logs = LogStore(dir: tempDir())
        let reports = tempDir("reports")
        defer {
            try? FileManager.default.removeItem(at: logs.dir)
            try? FileManager.default.removeItem(at: reports)
        }
        let start = Date.now.addingTimeInterval(-60)
        try CrashSentinel.begin(store: logs, version: "1.0", pid: 99_001, now: start)
        try CrashSentinel.begin(store: logs, version: "1.0", pid: 99_002, now: start)
        try CrashSentinel.begin(store: logs, version: "1.0", pid: 99_003, now: start)
        CrashSentinel.end(store: logs, pid: 99_003)

        let ips = #"{"app_name":"VibeDeck"}"# + "\n" + #"{"exception":{"type":"EXC_BREAKPOINT","signal":"SIGTRAP"}}"#
        try AtomicFile.write(Data(ips.utf8), to: reports.appending(path: "VibeDeck-2026-10-11-120000.ips"))
        try AtomicFile.write(Data(ips.utf8), to: reports.appending(path: "Outro-2026-10-11-120000.ips"))

        // 99_002 is still running; 99_001 died.
        let crashes = CrashSentinel.detectUnclean(store: logs, reportsDir: reports) { $0 == 99_002 }
        #expect(crashes.map(\.pid) == [99_001])
        #expect(crashes.first?.version == "1.0")
        #expect(crashes.first?.report?.hasSuffix("VibeDeck-2026-10-11-120000.ips") == true)
        #expect(crashes.first?.summary == "EXC_BREAKPOINT (SIGTRAP)")
        // Reported once: the marker is gone, the live one stays.
        #expect(CrashSentinel.detectUnclean(store: logs, reportsDir: reports) { $0 == 99_002 }.isEmpty)
        #expect(CrashSentinel.detectUnclean(store: logs, reportsDir: reports) { _ in false }.map(\.pid) == [99_002])
    }

    @Test func unconfiguredLoggerWritesNothing() {
        // Tests and libraries never configure VDLog, so they can't touch the user's log directory.
        #expect(VDLog.store == nil)
        VDLog.error("teste", "não deve ser gravado")
        VDLog.flush()
    }
    @Test func actionMetadataRoundTripsAndDecodesOlderEntries() throws {
        let entry = LogEntry(level: .info, component: .app, event: "ui.activated", message: "Ação do usuário",
                             context: ["action": "a1", "control": "docs.generate", "label": "Gerar documentos"])
        let decoded = try VDJSON.decoder.decode(LogEntry.self, from: VDJSON.compactEncoder.encode(entry))
        #expect(decoded.action == "a1")
        #expect(decoded.control == "docs.generate")
        #expect(decoded.label == "Gerar documentos")
        let old = try VDJSON.decoder.decode(LogEntry.self, from: Data(#"{"event":"legacy","context":null}"#.utf8))
        #expect(old.action == nil && old.control == nil && old.label == nil)
        let unknown = try VDJSON.decoder.decode(LogEntry.self, from: Data(#"{"level":"future","context":{"action":42}}"#.utf8))
        #expect(unknown.level == .info && unknown.context.isEmpty)
    }

    @Test func actionFilterIncludesOnlyItsReactions() throws {
        let logs = LogStore(dir: tempDir())
        defer { try? FileManager.default.removeItem(at: logs.dir) }
        for (action, event) in [("a1", "ui.activated"), ("a1", "store.file_written"), ("a2", "ui.activated")] {
            try logs.append(LogEntry(level: .info, component: .app, event: event, message: "Operação", context: ["action": action]))
        }
        let entries = logs.entries(LogFilter(action: "a1"))
        #expect(entries.count == 2)
        #expect(Set(entries.map(\.event)) == ["ui.activated", "store.file_written"])
        #expect(logs.entries(LogFilter(action: "missing")).isEmpty)
    }

    @Test func editingLogsMetadataWithoutDocumentContent() async throws {
        let logs = LogStore(dir: tempDir())
        let root = tempDir("project")
        defer { try? FileManager.default.removeItem(at: logs.dir); try? FileManager.default.removeItem(at: root) }
        let secret = "CONTEUDO_PRIVADO_DE_DOCUMENTO_123456"
        let task = try VDLog.$testStore.withValue(logs) {
            try VDLog.withAction(control: "docs.title", label: "Título", project: root, id: "edit-1") {
                try VDLog.$undoName.withValue("Editar documento") {
                    try AtomicFile.write(Data(secret.utf8), to: root.appending(path: ".vibedeck/docs/exemplo.md"))
                }
                return VDLog.detached {
                    VDLog.info("ai.request_finished", "Chamada encerrada", component: .ai)
                }
            }
        }
        await task.value
        VDLog.flush()
        let entries = logs.entries(LogFilter(action: "edit-1"))
        #expect(entries.count == 3)
        let written = try #require(entries.first { $0.event == "store.file_written" })
        #expect(written.context["file"] == ".vibedeck/docs/exemplo.md")
        #expect(written.context["undo"] == "Editar documento")
        #expect(entries.allSatisfy { $0.project == root.path && $0.action == "edit-1" })
        let text = try String(contentsOf: logs.fileURL(for: .now), encoding: .utf8)
        #expect(!text.contains(secret))
        #expect(text.contains("docs.title"))
    }

    @Test func parallelActionsKeepIndependentCorrelation() async {
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<20 {
                group.addTask {
                    let task = VDLog.withAction(control: "test.action", label: "Teste", id: String(index)) {
                        VDLog.detached { VDLog.actionID }
                    }
                    #expect(await task.value == String(index))
                    #expect(VDLog.actionID == nil)
                }
            }
        }
    }

    @Test func ruleWorkersKeepActionAcrossNativeThreads() throws {
        let logs = LogStore(dir: tempDir())
        let root = tempDir("rule-project")
        defer { try? FileManager.default.removeItem(at: logs.dir); try? FileManager.default.removeItem(at: root) }
        let store = try ProjectStore.initialize(at: root)
        let added = try store.addRule(Rule(text: "Teste de correlação"), toTopic: "Logs")
        _ = try store.setRuleTest(added.1.id.uuidString, mode: .script, command: "true")
        let snapshot = [(slug: added.0, topic: try store.loadTopic(added.0))]
        VDLog.$testStore.withValue(logs) {
            VDLog.withAction(control: "rules.execute", label: "Executar", project: root, id: "rule-action") {
                _ = store.runRuleScripts(snapshot: snapshot, runner: RuleTestRunner { _, _ in
                    VDLog.info("rules.script_finished", "Script encerrado", component: .rules)
                    return .init(exitCode: 0, output: "")
                })
            }
        }
        VDLog.flush()
        let entries = logs.entries(LogFilter(action: "rule-action"))
        #expect(entries.count == 2)
        #expect(entries.contains { $0.component == .rules && $0.project == root.path })
    }

}
