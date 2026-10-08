import Foundation

/// Uso dos limites do plano do Claude Code (sessão de 5 horas e semana), como o Claude Code
/// informa ao comando da statusline. Fica fora do projeto: é da máquina, não do repositório.
public struct ClaudeUsage: Codable, Equatable, Sendable {
    public struct Window: Codable, Equatable, Sendable {
        /// 0–100.
        public var usedPercentage: Double
        public var resetsAt: Date?

        public init(usedPercentage: Double, resetsAt: Date? = nil) {
            self.usedPercentage = usedPercentage
            self.resetsAt = resetsAt
        }

        /// Percentual valendo em `now`: depois do reset a janela recomeça do zero.
        public func percentage(at now: Date = .now) -> Double {
            if let resetsAt, resetsAt <= now { return 0 }
            return min(max(usedPercentage, 0), 100)
        }

        enum CodingKeys: String, CodingKey { case usedPercentage, resetsAt }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            usedPercentage = try c.decode(Double.self, forKey: .usedPercentage)
            resetsAt = try c.decodeIfPresent(Date.self, forKey: .resetsAt)
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(usedPercentage, forKey: .usedPercentage)
            try c.encodeIfPresent(resetsAt, forKey: .resetsAt)
        }
    }

    /// Limite da sessão (janela de 5 horas).
    public var session: Window?
    /// Limite semanal (7 dias).
    public var weekly: Window?
    public var model: String?
    public var updatedAt: Date

    public init(session: Window? = nil, weekly: Window? = nil, model: String? = nil, updatedAt: Date = .now) {
        self.session = session
        self.weekly = weekly
        self.model = model
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey { case session, weekly, model, updatedAt }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        session = try c.decodeIfPresent(Window.self, forKey: .session)
        weekly = try c.decodeIfPresent(Window.self, forKey: .weekly)
        model = try c.decodeIfPresent(String.self, forKey: .model)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(session, forKey: .session)
        try c.encodeIfPresent(weekly, forKey: .weekly)
        try c.encodeIfPresent(model, forKey: .model)
        try c.encode(updatedAt, forKey: .updatedAt)
    }

    public var hasLimits: Bool { session != nil || weekly != nil }

    /// Lê o JSON que o Claude Code manda para a statusline (`rate_limits.five_hour` / `seven_day`, com
    /// `used_percentage` e `resets_at` em segundos Unix). Sem `rate_limits` (chave de API, Bedrock…) as janelas ficam nil.
    public static func fromStatusLine(_ data: Data, now: Date = .now) throws -> ClaudeUsage {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw VibeDeckError.invalidStatusLine
        }
        let limits = root["rate_limits"] as? [String: Any]
        let model = (root["model"] as? [String: Any])?["display_name"] as? String
        return ClaudeUsage(
            session: window(limits?["five_hour"]),
            weekly: window(limits?["seven_day"]),
            model: model,
            updatedAt: now
        )
    }

    private static func window(_ value: Any?) -> Window? {
        guard let dict = value as? [String: Any], let used = (dict["used_percentage"] as? NSNumber)?.doubleValue else { return nil }
        let reset: Date? = switch dict["resets_at"] {
        case let n as NSNumber: Date(timeIntervalSince1970: n.doubleValue)
        case let s as String: try? Date(s, strategy: .iso8601)
        default: nil
        }
        return Window(usedPercentage: used, resetsAt: reset)
    }

    /// Linha curta para a statusline do Claude Code, ex.: "sessão 42% (reinicia 14:30) · semana 18%".
    public func summary(at now: Date = .now) -> String {
        var parts: [String] = []
        if let model { parts.append(model) }
        if let session {
            var text = "sessão \(Int(session.percentage(at: now).rounded()))%"
            if let reset = session.resetsAt, reset > now {
                text += " (reinicia \(reset.formatted(date: .omitted, time: .shortened)))"
            }
            parts.append(text)
        }
        if let weekly { parts.append("semana \(Int(weekly.percentage(at: now).rounded()))%") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Claude Code na máquina

/// Ligação da statusline do Claude Code ao VibeDeck (a detecção fica em ClaudeCode.swift).
extension ClaudeCode {
    public static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    public static var configDir: URL { home.appending(path: ".claude", directoryHint: .isDirectory) }
    public static var settingsURL: URL { configDir.appending(path: "settings.json") }

    /// Onde `vibedeck usage record` grava o último uso informado pelo Claude Code.
    public static var usageURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "VibeDeck/claude-usage.json")
    }

    // MARK: Uso

    @discardableResult
    public static func recordUsage(statusLine data: Data, to url: URL = usageURL, now: Date = .now) throws -> ClaudeUsage {
        let usage = try ClaudeUsage.fromStatusLine(data, now: now)
        // Sem limites (sessão ainda sem resposta da API, ou conta sem plano) não apaga o último valor conhecido.
        if usage.hasLimits { try AtomicFile.write(VDJSON.encode(usage), to: url) }
        return usage
    }

    public static func loadUsage(from url: URL = usageURL) -> ClaudeUsage? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? VDJSON.decoder.decode(ClaudeUsage.self, from: data)
    }

    // MARK: Statusline

    public enum StatusLineState: Equatable, Sendable {
        /// Nenhuma statusline configurada.
        case none
        /// A statusline é o `vibedeck usage record` (com `previous` = comando encadeado, se houver).
        case vibedeck(previous: String?)
        /// Outra statusline, que será encadeada ao instalar.
        case other(String)
    }

    static let recordMarker = "usage record"

    public static func statusLineState(settings url: URL = settingsURL) throws -> StatusLineState {
        let settings = try readSettings(url)
        guard let command = (settings["statusLine"] as? [String: Any])?["command"] as? String, !command.isEmpty else { return .none }
        guard command.contains(recordMarker) else { return .other(command) }
        return .vibedeck(previous: previousCommand(in: command))
    }

    /// Faz a statusline do Claude Code passar pelo `vibedeck usage record`. Uma statusline existente
    /// continua aparecendo: vira `--then` e recebe o mesmo JSON.
    public static func installStatusLine(executable: String, settings url: URL = settingsURL) throws {
        var settings = try readSettings(url)
        var command = "\(shellQuote(executable)) usage record"
        switch try statusLineState(settings: url) {
        case .none: break
        case .vibedeck(let previous): if let previous { command += " --then \(shellQuote(previous))" }
        case .other(let previous): command += " --then \(shellQuote(previous))"
        }
        var statusLine = settings["statusLine"] as? [String: Any] ?? [:]
        statusLine["type"] = "command"
        statusLine["command"] = command
        settings["statusLine"] = statusLine
        try writeSettings(settings, to: url)
    }

    /// Desfaz `installStatusLine`, devolvendo a statusline encadeada (se havia uma).
    public static func uninstallStatusLine(settings url: URL = settingsURL) throws {
        guard case .vibedeck(let previous) = try statusLineState(settings: url) else { return }
        var settings = try readSettings(url)
        if let previous {
            var statusLine = settings["statusLine"] as? [String: Any] ?? [:]
            statusLine["command"] = previous
            settings["statusLine"] = statusLine
        } else {
            settings["statusLine"] = nil
        }
        try writeSettings(settings, to: url)
    }

    private static func readSettings(_ url: URL) throws -> [String: Any] {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return [:] }
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw VibeDeckError.invalidClaudeSettings(url.path)
        }
        return dict
    }

    private static func writeSettings(_ settings: [String: Any], to url: URL) throws {
        var data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        data.append(0x0A)
        try AtomicFile.write(data, to: url)
    }

    /// Extrai o argumento de `--then '<comando>'` gravado por `installStatusLine`.
    static func previousCommand(in command: String) -> String? {
        guard let range = command.range(of: " --then ") else { return nil }
        let quoted = String(command[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        guard quoted.count >= 2, quoted.hasPrefix("'"), quoted.hasSuffix("'") else { return quoted.isEmpty ? nil : quoted }
        return String(quoted.dropFirst().dropLast()).replacingOccurrences(of: "'\\''", with: "'")
    }

    static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
