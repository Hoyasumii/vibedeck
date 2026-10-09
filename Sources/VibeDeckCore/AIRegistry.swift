import Foundation

public struct AIImportResult: Sendable {
    public var slugs: [String] = []
    public var warnings: [String] = []
    public init() {}
}

/// Reads the string fields used by Codex agent TOML, including multiline basic/literal strings.
/// Other settings remain in the original file and are never interpreted as VibeDeck permissions.
public enum CodexAgentFile {
    public struct Parsed: Equatable, Sendable {
        public var name: String
        public var description: String?
        public var model: String?
        public var effort: String?
        public var prompt: String
    }
    public static func parse(_ text: String, fallbackName: String) throws -> Parsed {
        let wanted: Set<String> = ["name", "description", "model", "model_reasoning_effort", "developer_instructions"]
        let chars = Array(text); var i = 0, fields: [String: String] = [:]
        func skipLine() { while i < chars.count, chars[i] != "\n" { i += 1 } }
        func invalid() -> CodexRPCError { .server("TOML inválido no agente \(fallbackName)") }
        while i < chars.count {
            while i < chars.count, chars[i].isWhitespace { i += 1 }
            guard i < chars.count else { break }
            if chars[i] == "#" { skipLine(); continue }
            // Only root fields describe an agent; nested tables describe optional runtime settings.
            if chars[i] == "[" { break }
            let begin = i
            while i < chars.count, chars[i] != "=", chars[i] != "\n" { i += 1 }
            guard i < chars.count, chars[i] == "=" else { throw invalid() }
            let key = String(chars[begin..<i]).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            i += 1
            while i < chars.count, chars[i] == " " || chars[i] == "\t" { i += 1 }
            guard i < chars.count else { throw invalid() }
            if chars[i] != "\"", chars[i] != "'" {
                if wanted.contains(key) { throw invalid() }
                skipLine(); continue
            }
            let quote = chars[i], triple = i + 2 < chars.count && chars[i + 1] == quote && chars[i + 2] == quote
            i += triple ? 3 : 1
            if triple, i < chars.count, chars[i] == "\n" { i += 1 }
            var value = "", closed = false
            while i < chars.count {
                if chars[i] == quote, !triple || (i + 2 < chars.count && chars[i + 1] == quote && chars[i + 2] == quote) {
                    i += triple ? 3 : 1; closed = true; break
                }
                if !triple, chars[i] == "\n" { throw invalid() }
                if chars[i] == "\\", quote == "\"" {
                    i += 1; guard i < chars.count else { throw invalid() }
                    let c = chars[i]; i += 1
                    switch c {
                    case "n": value += "\n"
                    case "r": value += "\r"
                    case "t": value += "\t"
                    case "b": value += "\u{08}"
                    case "f": value += "\u{0c}"
                    case "\"": value += "\""
                    case "\\": value += "\\"
                    case "u", "U":
                        let count = c == "u" ? 4 : 8
                        guard i + count <= chars.count, let hex = UInt32(String(chars[i..<i+count]), radix: 16), let scalar = UnicodeScalar(hex) else { throw invalid() }
                        value.unicodeScalars.append(scalar); i += count
                    case "\n", "\r", " ", "\t":
                        guard triple else { throw invalid() }
                        while i < chars.count, chars[i].isWhitespace { i += 1 }
                    default: throw invalid()
                    }
                } else { value.append(chars[i]); i += 1 }
            }
            guard closed else { throw invalid() }
            if wanted.contains(key) {
                guard fields[key] == nil else { throw invalid() }
                fields[key] = value
            }
            while i < chars.count, chars[i] == " " || chars[i] == "\t" || chars[i] == "\r" { i += 1 }
            if i < chars.count, chars[i] == "#" { skipLine() }
            if i < chars.count, chars[i] != "\n" { throw invalid() }
        }
        guard let prompt = fields["developer_instructions"], !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CodexRPCError.server("Agente \(fallbackName) sem developer_instructions.")
        }
        return Parsed(name: fields["name"] ?? fallbackName, description: fields["description"], model: fields["model"], effort: fields["model_reasoning_effort"], prompt: prompt)
    }
}

extension ProjectStore {
    public func importAgents(provider: AIProvider, from dirs: [URL]? = nil, overwrite: Bool = false, author: Author = .human) throws -> AIImportResult {
        var result = AIImportResult()
        if provider == .claude { result.slugs = try importClaudeAgents(from: dirs, overwrite: overwrite, author: author); return result }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let sources = dirs ?? [root.appending(path: ".codex/agents"), home.appending(path: ".codex/agents")]
        var seen = Set<String>()
        for dir in sources {
            for file in ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []).sorted(by: { $0.path < $1.path }) where file.pathExtension == "toml" {
                do {
                    let parsed = try CodexAgentFile.parse(String(contentsOf: file, encoding: .utf8), fallbackName: file.deletingPathExtension().lastPathComponent)
                    let slug = Slug.make(parsed.name)
                    guard seen.insert(slug).inserted else { continue }
                    if FileManager.default.fileExists(atPath: agentURL(slug).path), !overwrite { continue }
                    var agent = (try? loadAgent(slug)) ?? Agent(title: parsed.name, author: author)
                    agent.summary = parsed.description; agent.prompt = parsed.prompt
                    agent.providerSettings = (agent.providerSettings ?? [:]).merging(["codex": AIProviderSettings(model: parsed.model, effort: parsed.effort)]) { _, new in new }
                    if !agent.tags.contains("codex") { agent.tags.append("codex") }
                    agent.updatedAt = .now
                    try saveAgent(agent, slug: slug); result.slugs.append(slug)
                } catch { result.warnings.append("\(file.path): \(error.localizedDescription)") }
            }
        }
        return result
    }

    public func importCommands(provider: AIProvider, from dirs: [URL]? = nil, overwrite: Bool = false, author: Author = .human) throws -> AIImportResult {
        var result = AIImportResult()
        if provider == .claude { result.slugs = try importClaudeCommands(from: dirs, overwrite: overwrite, author: author); return result }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let sources = dirs ?? [root.appending(path: ".codex/prompts"), home.appending(path: ".codex/prompts")]
        var seen = Set<String>()
        for dir in sources {
            for path in ((try? FileManager.default.subpathsOfDirectory(atPath: dir.path)) ?? []).sorted() where path.hasSuffix(".md") && !path.split(separator: "/").contains(where: { $0.hasPrefix(".") }) {
                do {
                    let parsed = ClaudeCommandFile.parse(try String(contentsOf: dir.appending(path: path), encoding: .utf8), fallbackName: String(path.dropLast(3)).replacingOccurrences(of: "/", with: ":"))
                    let slug = Slug.make(parsed.name)
                    guard seen.insert(slug).inserted else { continue }
                    if FileManager.default.fileExists(atPath: commandURL(slug).path), !overwrite { continue }
                    var command = (try? loadCommand(slug)) ?? Command(title: parsed.name, author: author)
                    command.summary = parsed.description; command.argumentHint = parsed.argumentHint; command.prompt = parsed.prompt
                    command.providerSettings = (command.providerSettings ?? [:]).merging(["codex": AIProviderSettings(model: parsed.model)]) { _, new in new }
                    if !command.tags.contains("codex") { command.tags.append("codex") }
                    command.updatedAt = .now
                    try saveCommand(command, slug: slug); result.slugs.append(slug)
                } catch { result.warnings.append("\(dir.path)/\(path): \(error.localizedDescription)") }
            }
        }
        return result
    }

    @MainActor public func importSkills(provider: AIProvider, from dirs: [URL]? = nil, overwrite: Bool = false, author: Author = .human) async throws -> AIImportResult {
        var result = AIImportResult()
        if provider == .claude { result.slugs = try importClaudeSkills(from: dirs, overwrite: overwrite, author: author); return result }
        var paths: [URL] = []
        if let dirs {
            paths = dirs.flatMap { dir in
                ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []).sorted(by: { $0.path < $1.path }).map { $0.appending(path: "SKILL.md") }
            }
        } else {
            let rpc = CodexRPC(); defer { rpc.stop() }
            try await rpc.start(root: root)
            let response = try await rpc.request("skills/list", params: ["cwds": .array([.string(root.path)]), "forceReload": .bool(true)])
            let entries = response["data"]?.array ?? []
            for entry in entries {
                for error in entry["errors"]?.array ?? [] { result.warnings.append("\(error["path"]?.string ?? "skill"): \(error["message"]?.string ?? "inválida")") }
                paths += (entry["skills"]?.array ?? []).filter { $0["enabled"]?.bool != false }.compactMap { $0["path"]?.string.map { URL(fileURLWithPath: $0) } }
            }
            // A project skill wins collisions even if app-server listed user/system skills first.
            paths.sort { a, b in
                let aProject = a.path.hasPrefix(root.path + "/"), bProject = b.path.hasPrefix(root.path + "/")
                return aProject == bProject ? a.path < b.path : aProject
            }
        }
        var seen = Set<String>()
        for file in paths {
            do {
                let parsed = ClaudeSkillFile.parse(try String(contentsOf: file, encoding: .utf8), fallbackName: file.deletingLastPathComponent().lastPathComponent)
                let slug = Slug.make(parsed.name)
                guard seen.insert(slug).inserted else { continue }
                if FileManager.default.fileExists(atPath: skillURL(slug).path), !overwrite { continue }
                var skill = (try? loadSkill(slug)) ?? Skill(title: parsed.name, author: author)
                skill.summary = parsed.description; skill.prompt = parsed.prompt
                skill.sourcePath = file.path
                skill.providerSettings = (skill.providerSettings ?? [:]).merging(["codex": AIProviderSettings(model: parsed.model)]) { _, new in new }
                if !skill.tags.contains("codex") { skill.tags.append("codex") }
                skill.updatedAt = .now
                try saveSkill(skill, slug: slug); result.slugs.append(slug)
            } catch { result.warnings.append("\(file.path): \(error.localizedDescription)") }
        }
        return result
    }

    public func runProviderSettings(_ ref: String, availableModels: [String], fallback: String?) throws -> (settings: AIProviderSettings, warning: String?) {
        let run = try loadRun(ref), workflow = try loadWorkflow(run.workflow)
        guard let current = run.current, let step = workflow.steps.first(where: { $0.id == current }) else { throw VibeDeckError.invalidWorkflow("Etapa inexistente") }
        let legacy: String?, overrides: [String: AIProviderSettings]?
        switch step.kind {
        case .agent: let record = try loadAgent(step.ref); legacy = record.model; overrides = record.providerSettings
        case .command: let record = try loadCommand(step.ref); legacy = record.model; overrides = record.providerSettings
        case .skill: let record = try loadSkill(step.ref); legacy = record.model; overrides = record.providerSettings
        }
        var settings = overrides?[run.provider.rawValue] ?? AIProviderSettings()
        let requested = settings.model ?? legacy
        if let requested, !availableModels.contains(requested) {
            settings.model = fallback
            return (settings, "Modelo \(requested) indisponível no \(run.provider.title); usando \(fallback ?? "padrão da sessão").")
        }
        settings.model = requested ?? fallback
        return (settings, nil)
    }

    /// Expand a registered command/agent/skill without pretending it is a native TUI slash command.
    public func expandAICommand(_ text: String) throws -> String {
        guard text.hasPrefix("/") else { return text }
        let words = text.split(maxSplits: 1, whereSeparator: \.isWhitespace)
        let name = String(words[0].dropFirst()), args = words.count > 1 ? String(words[1]) : ""
        if name.hasPrefix("agent:") {
            let slug = try resolveAgentSlug(String(name.dropFirst(6)))
            return try loadAgent(slug).prompt + "\n\nEntrada: " + args
        }
        if let slug = try? resolveCommandSlug(name) { return try loadCommand(slug).prompt.replacingOccurrences(of: "$ARGUMENTS", with: args) }
        if let slug = try? resolveSkillSlug(name) {
            let skill = try loadSkill(slug)
            return skill.prompt + (skill.sourcePath.map { "\n\nRecursos da skill: \(URL(fileURLWithPath: $0).deletingLastPathComponent().path)" } ?? "") + "\n\nEntrada: " + args
        }
        return text
    }
}

extension ProjectStore {
    public func commandProviderSettings(_ text: String, provider: AIProvider, availableModels: [String], fallback: String?) throws -> (settings: AIProviderSettings, warning: String?)? {
        guard text.hasPrefix("/"), let token = text.split(whereSeparator: \.isWhitespace).first else { return nil }
        let name = String(token.dropFirst())
        let legacy: String?, all: [String: AIProviderSettings]?
        if name.hasPrefix("agent:") {
            let record = try loadAgent(resolveAgentSlug(String(name.dropFirst(6))))
            legacy = record.model; all = record.providerSettings
        } else if let slug = try? resolveCommandSlug(name) {
            let record = try loadCommand(slug); legacy = record.model; all = record.providerSettings
        } else if let slug = try? resolveSkillSlug(name) {
            let record = try loadSkill(slug); legacy = record.model; all = record.providerSettings
        } else { return nil }
        var settings = all?[provider.rawValue] ?? AIProviderSettings()
        let chosen = settings.model ?? legacy
        if let chosen, !availableModels.contains(chosen) {
            settings.model = fallback
            return (settings, "Modelo \(chosen) indisponível no \(provider.title); usando \(fallback ?? "padrão da sessão").")
        }
        settings.model = chosen ?? fallback
        return (settings, nil)
    }
}
