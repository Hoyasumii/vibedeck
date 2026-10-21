import Foundation

// MARK: - Running

/// What a rule's script said: exit 0 = pass, 77 = n/a (doesn't apply to the touched files), anything else = fail.
public struct RuleTestOutcome: Equatable, Sendable {
    public var verdict: RuleVerdict
    public var exitCode: Int32
    public var output: String

    public init(verdict: RuleVerdict, exitCode: Int32, output: String) {
        self.verdict = verdict
        self.exitCode = exitCode
        self.output = output
    }

    public static let notApplicableExit: Int32 = 77

    public init(exitCode: Int32, output: String) {
        let verdict: RuleVerdict = switch exitCode {
        case 0: .pass
        case Self.notApplicableExit: .na
        default: .fail
        }
        self.init(verdict: verdict, exitCode: exitCode, output: output)
    }
}

/// One script run, as reported by `runRuleTests`.
public struct RuleTestRun: Sendable {
    public var topic: String
    public var rule: Rule
    public var command: String
    public var outcome: RuleTestOutcome
}

/// Runs a rule's script. Injectable so tests don't spawn processes.
public struct RuleTestRunner: Sendable {
    public var run: @Sendable (_ command: String, _ context: Context) -> RuleTestOutcome

    public struct Context: Sendable {
        public var root: URL
        public var files: [String]
        public var ruleId: UUID
        /// Fired when the execution is cancelled: a running script must stop and return.
        public var cancellation: ShellCancellation? = nil
    }

    public init(run: @escaping @Sendable (_ command: String, _ context: Context) -> RuleTestOutcome) {
        self.run = run
    }

    public static let live = RuleTestRunner { command, context in
        let result = ShellRunner.run(command, in: context.root, environment: [
            "VIBEDECK_ROOT": RemoteExecution.path(for: context.root),
            "VIBEDECK_FILES": context.files.joined(separator: "\n"),
            "VIBEDECK_RULE_ID": context.ruleId.uuidString,
        ], timeout: 120, outputLimit: 4_000, cancellation: context.cancellation)
        return RuleTestOutcome(exitCode: result.status, output: result.output)
    }
}

/// Cancels shell runs from outside: running processes are terminated and later runs never start.
public final class ShellCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var handlers: [UUID: @Sendable () -> Void] = [:]

    public init() {}

    public var isCancelled: Bool { lock.withLock { cancelled } }

    public func cancel() {
        let pending: [@Sendable () -> Void] = lock.withLock {
            guard !cancelled else { return [] }
            cancelled = true
            defer { handlers = [:] }
            return Array(handlers.values)
        }
        pending.forEach { $0() }
    }

    /// Runs `handler` on cancellation (right away if already cancelled). Returns a token for `remove`.
    @discardableResult
    public func onCancel(_ handler: @escaping @Sendable () -> Void) -> UUID {
        let id = UUID()
        let now: Bool = lock.withLock {
            if cancelled { return true }
            handlers[id] = handler
            return false
        }
        if now { handler() }
        return id
    }

    public func remove(_ id: UUID) { lock.withLock { _ = handlers.removeValue(forKey: id) } }
}

/// Build tools whose scripts share build directories or lock files (`.build`, `node_modules`, `target`…):
/// two scripts with the same key never run at the same time. One table for every ecosystem.
public enum BuildToolLock {
    /// (serialization key, pattern of an invocation of the tool).
    static let table: [(key: String, pattern: String)] = [
        ("swift", #"\bswift\s+(build|test|run|package)\b|\bxcodebuild\b|\bswiftc\b|\bswift["']\s*,\s*["'](build|test|run|package)\b"#),
        ("node", #"\b(npm|npx|yarn|pnpm)\s+\S"#),
        ("cargo", #"\bcargo\s+\S"#),
        ("go", #"\bgo\s+(build|test|run|vet|install|generate|mod)\b"#),
        ("gradle", #"(\bgradle|/gradlew)\b"#),
        ("maven", #"(\bmvn|/mvnw)\b"#),
        ("dotnet", #"\bdotnet\s+\S"#),
        ("composer", #"\bcomposer\s+\S|vendor/bin/"#),
        ("make", #"\bmake\b(\s|$)"#),
    ]

    /// Keys of the build tools invoked by `text`. Comment lines are ignored.
    public static func keys(in text: String) -> [String] {
        let code = text.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
            .joined(separator: "\n")
        return table.filter { code.range(of: $0.pattern, options: .regularExpression) != nil }.map(\.key)
    }

    /// Reads referenced shell and Python files too: rule wrappers and sourced helpers can invoke a build indirectly.
    /// Only local readable paths are followed; shell expressions are never evaluated.
    public static func keys(command: String, root: URL) -> [String] {
        var text = command
        let base = root.resolvingSymlinksInPath().standardizedFileURL
        var visited = Set<URL>()
        func readReferences(_ source: String, directory: URL) {
            let code = source.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }.joined(separator: "\n")
            for match in code.matches(of: /[A-Za-z0-9_.\/-]+\.(sh|py)\b/) {
                let path = String(match.0)
                let direct = path.hasPrefix("/") ? URL(fileURLWithPath: path) : base.appending(path: path)
                let candidates = [direct, directory.appending(path: path),
                                  directory.appending(path: URL(fileURLWithPath: path).lastPathComponent)]
                for candidate in candidates {
                    let url = candidate.resolvingSymlinksInPath().standardizedFileURL
                    guard url.path.hasPrefix(base.path + "/"),
                          let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
                    if visited.insert(url).inserted {
                        text += "\n" + content
                        readReferences(content, directory: url.deletingLastPathComponent())
                    }
                    break
                }
            }
        }
        readReferences(command, directory: base)
        return keys(in: text)
    }
}

/// `command` in the user's login shell, stdout+stderr merged, killed after `timeout` seconds.
public enum ShellRunner {
    public static let timedOutStatus: Int32 = 124
    public static let cancelledStatus: Int32 = 130
    private static let timeoutQueue = DispatchQueue(label: "vibedeck.shell-runner-timeout")

    public static func run(
        _ command: String, in root: URL, environment: [String: String] = [:], timeout: TimeInterval = 120, outputLimit: Int = 20_000,
        cancellation: ShellCancellation? = nil
    ) -> (output: String, status: Int32) {
        if cancellation?.isCancelled == true { return ("Cancelado.", cancelledStatus) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SHELL"] ?? ClaudeCode.defaultShell)
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = root
        var environment = environment
        if let action = VDLog.actionID { environment["VIBEDECK_ACTION"] = action }
        if !environment.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
        }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        let timedOut = Flag()
        let timer = DispatchWorkItem {
            guard process.isRunning else { return }
            timedOut.set()
            terminateTree(process)
        }
        // Only the program name is logged: the rest of the command may carry user content.
        let candidate = command.split(separator: " ").first.map { String($0.split(separator: "/").last ?? $0) } ?? ""
        let program = candidate.range(of: "^[a-zA-Z0-9_.+-]+$", options: .regularExpression) != nil ? candidate : "shell"
        do { try RemoteExecution.configure(process, root: root, command: command, environment: environment); try process.run() } catch {
            VDLog.error(error, event: "shell.launch_failed", project: root, context: ["program": program])
            return ("Não foi possível executar: \(error.localizedDescription)", 127)
        }
        // The timeout counts from this script's own start, never from time spent waiting in a queue.
        let started = Date.now
        timeoutQueue.asyncAfter(deadline: .now() + timeout, execute: timer)
        let cancelled = Flag()
        let token = cancellation?.onCancel {
            guard process.isRunning else { return }
            cancelled.set()
            terminateTree(process)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timer.cancel()
        if let token { cancellation?.remove(token) }
        var text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        // Keep the end: that's where test runners print the failure summary.
        if text.count > outputLimit { text = "… (saída cortada)\n" + String(text.suffix(outputLimit)) }
        if cancelled.isSet {
            VDLog.info("rules.script_cancelled", "Script cancelado", project: root, component: .rules, context: ["program": program])
            return ((text.isEmpty ? "" : text + "\n") + "Cancelado.", cancelledStatus)
        }
        if timedOut.isSet {
            VDLog.warning("shell.timeout", "Comando interrompido após \(Int(timeout)) s", project: root,
                          context: ["program": program, "ms": String(Int(Date.now.timeIntervalSince(started) * 1000))])
            return ((text.isEmpty ? "" : text + "\n") + "Tempo esgotado (\(Int(timeout)) s).", timedOutStatus)
        }
        VDLog.info("rules.script_finished", "Script encerrado", project: root, component: .rules,
                   context: ["program": program, "exit": String(process.terminationStatus), "ms": String(Int(Date.now.timeIntervalSince(started) * 1000))])
        return (text.isEmpty ? "(sem saída)" : text, process.terminationStatus)
    }

    /// Terminates the shell and the processes it started: a child left alive (`sleep` after `echo`) would keep
    /// the output pipe open and the run would only return when it ended.
    private static func terminateTree(_ process: Process) {
        func children(_ pid: Int32) -> [Int32] {
            let pgrep = Process()
            pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
            pgrep.arguments = ["-P", String(pid)]
            let out = Pipe()
            pgrep.standardOutput = out
            pgrep.standardError = FileHandle.nullDevice
            guard (try? pgrep.run()) != nil else { return [] }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            pgrep.waitUntilExit()
            return String(decoding: data, as: UTF8.self).split(separator: "\n").compactMap { Int32($0) }
        }
        func descendants(_ pid: Int32) -> [Int32] { children(pid).flatMap { [$0] + descendants($0) } }
        let tree = descendants(process.processIdentifier)
        process.terminate()
        for pid in tree { kill(pid, SIGTERM) }
    }

    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        func set() { lock.withLock { value = true } }
        var isSet: Bool { lock.withLock { value } }
    }
}

/// Shared state of `runScripts`; every access holds the condition's lock.
/// Wraps `NSCondition` instead of subclassing it.
final class ScriptSchedule: @unchecked Sendable {
    private let condition = NSCondition()
    var pending: [Int]
    var running = 0
    var busy = Set<String>()
    var stopped = false
    var results: [RuleTestRun?]

    init(count: Int) {
        pending = Array(0..<count)
        results = Array(repeating: nil, count: count)
    }

    func lock() { condition.lock() }
    func unlock() { condition.unlock() }
    func wait() { condition.wait() }
    func broadcast() { condition.broadcast() }
}

// MARK: - Generating

public enum RuleTestPrompt {
    /// Where the generated script of a rule goes, relative to the project root.
    public static func scriptPath(topic slug: String, rule: Rule) -> String {
        "\(ProjectStore.dataDirName)/tests/\(slug)/\(rule.id.uuidString.prefix(8).lowercased()).sh"
    }

    /// Which rules of a topic a generation covers.
    public enum Selection: String, CaseIterable, Sendable {
        /// No test registered yet.
        case missing
        /// The rule changed since its test was registered.
        case stale
        /// `missing` + `stale`.
        case pending
        /// Every rule, current tests included.
        case all
    }

    /// The rules of `topic` that `selection` covers.
    public static func rules(_ topic: RuleTopic, _ selection: Selection) -> [Rule] {
        switch selection {
        case .missing: topic.rules.filter { $0.testState == .none }
        case .stale: topic.rules.filter { $0.testState == .stale }
        case .pending: topic.rules.filter { $0.testState == .none || $0.testState == .stale }
        case .all: topic.rules
        }
    }

    /// Rules that still need a test written (none yet, or the rule changed since).
    public static func pending(_ topic: RuleTopic) -> [Rule] {
        rules(topic, .pending)
    }

    /// The chat prompt behind the "Gerar/Atualizar testes" button. `onlyPending` skips rules whose test is current.
    public static func generate(slug: String, topic: RuleTopic, onlyPending: Bool) -> String {
        generate(slug: slug, topic: topic, selection: onlyPending ? .pending : .all)
    }

    /// Prompt for generating the tests of `selection`. `headless` (with the `cli` path) is for a background
    /// `claude -p` run: nobody answers questions and project MCP servers may not be approved, so it registers
    /// through the CLI and ends with a short summary.
    public static func generate(slug: String, topic: RuleTopic, selection: Selection, headless cli: String? = nil) -> String {
        let rules = rules(topic, selection)
        let list = rules.map { rule in
            var line = "- `\(rule.id.uuidString.prefix(8))` [\(rule.severity.rawValue)] \(rule.text)"
            if let details = rule.details?.trimmed.nonEmpty {
                line += "\n" + details.split(separator: "\n", omittingEmptySubsequences: false).map { "  > \($0)" }.joined(separator: "\n")
            }
            switch rule.testState {
            case .stale: line += "\n  (a regra mudou desde o teste atual: `\(rule.test?.command ?? "manual")` — reescreva)"
            case .script: line += "\n  (teste atual: `\(rule.test?.command ?? "")`)"
            case .manual: line += "\n  (hoje manual: \(rule.test?.reason ?? "sem motivo"))"
            case .none: break
            }
            line += "\n  script: `\(scriptPath(topic: slug, rule: rule))`"
            return line
        }.joined(separator: "\n")

        let register = cli.map { "Registre com `\($0) rules set-test <id> --command \"<caminho do script>\"`" }
            ?? "Registre com `set_rule_test` (MCP) ou `vibedeck rules set-test <id> --command \"<caminho do script>\"`"
        let manual = cli.map { "registre como manual: `\($0) rules set-test <id> --manual --reason \"<motivo>\"`" }
            ?? "registre como manual: `set_rule_test` com `mode=manual` e `reason` explicando por quê"
        let violation = cli == nil ? "verifique se é violação real (avise-me) ou bug do script (corrija)"
            : "verifique se é violação real (anote no resumo final) ou bug do script (corrija)"
        let ending = cli == nil ? "No fim, me mostre uma tabela: regra, script ou manual, resultado da primeira execução."
            : "Você roda em segundo plano, sem ninguém para responder perguntas: não pergunte, decida. No fim, escreva um resumo curto: regra, script ou manual, resultado da primeira execução."

        return """
        \(selection == .all ? "Gere" : "Atualize") os testes das regras do tópico "\(topic.title)" (`\(slug)`). \
        O objetivo é que a verificação dessas regras rode um script, sem precisar de você a cada check.
        \(topic.isGlobal ? "O tópico vale para toda tarefa." : "Escopo do tópico: \(topic.paths.joined(separator: ", ")).")

        Regras:
        \(list)

        Para cada regra:
        1. Leia o código relevante e decida se a regra é verificável de forma objetiva por um script.
        2. Se for, escreva o script no caminho indicado (`#!/usr/bin/env bash`, `set -euo pipefail`, executável com `chmod +x`). Ele roda na raiz do projeto com:
           - `$VIBEDECK_FILES`: arquivos alterados na tarefa, um por linha (pode vir vazio — aí verifique o projeto todo);
           - `$VIBEDECK_ROOT` e `$VIBEDECK_RULE_ID`.
           Saída: `exit 0` = cumpre, `exit 77` = não se aplica a esses arquivos, qualquer outro código = viola. \
        Em caso de falha, imprima o arquivo/linha e o motivo. Seja rápido (limite de 120 s) e determinístico; sem rede.
        3. Rode o script e confira o resultado contra o código atual. Se ele falhar, \(violation). \
        Nunca afrouxe a regra só para o script passar.
        4. \(register).
        5. Se a regra for subjetiva ou depender de julgamento (ex.: "README atualizado quando muda algo documentado"), \
        \(manual) — ela permanece pendente até a verificação manual solicitada; nunca marque como aprovada sem evidência.

        \(ending)
        """
    }
}
