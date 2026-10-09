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
    }

    public init(run: @escaping @Sendable (_ command: String, _ context: Context) -> RuleTestOutcome) {
        self.run = run
    }

    public static let live = RuleTestRunner { command, context in
        let result = ShellRunner.run(command, in: context.root, environment: [
            "VIBEDECK_ROOT": context.root.path,
            "VIBEDECK_FILES": context.files.joined(separator: "\n"),
            "VIBEDECK_RULE_ID": context.ruleId.uuidString,
        ], timeout: 120, outputLimit: 4_000)
        return RuleTestOutcome(exitCode: result.status, output: result.output)
    }
}

/// `command` in the user's login shell, stdout+stderr merged, killed after `timeout` seconds.
public enum ShellRunner {
    public static let timedOutStatus: Int32 = 124
    private static let timeoutQueue = DispatchQueue(label: "vibedeck.shell-runner-timeout")

    public static func run(
        _ command: String, in root: URL, environment: [String: String] = [:], timeout: TimeInterval = 120, outputLimit: Int = 20_000
    ) -> (output: String, status: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SHELL"] ?? ClaudeCode.defaultShell)
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = root
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
            process.terminate()
        }
        do { try process.run() } catch { return ("Não foi possível executar: \(error.localizedDescription)", 127) }
        timeoutQueue.asyncAfter(deadline: .now() + timeout, execute: timer)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timer.cancel()
        var text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        // Keep the end: that's where test runners print the failure summary.
        if text.count > outputLimit { text = "… (saída cortada)\n" + String(text.suffix(outputLimit)) }
        if timedOut.isSet {
            return ((text.isEmpty ? "" : text + "\n") + "Tempo esgotado (\(Int(timeout)) s).", timedOutStatus)
        }
        return (text.isEmpty ? "(sem saída)" : text, process.terminationStatus)
    }

    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        func set() { lock.withLock { value = true } }
        var isSet: Bool { lock.withLock { value } }
    }
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
        \(manual) — ela continua sendo verificada pelo agente no check.

        \(ending)
        """
    }
}
