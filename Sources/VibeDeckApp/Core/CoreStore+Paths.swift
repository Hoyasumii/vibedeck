import Foundation

// Funções puras de caminho que o Core Swift tinha em `ProjectStore` (sem tocar o projeto).
extension CoreStore {
    /// Valida e normaliza um caminho de grupo (`a/b`); vazio só é aceito com `allowRoot`.
    func normalizedGroupPath(_ path: String, allowRoot: Bool = false) throws -> String {
        if path.isEmpty, allowRoot { return "" }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"),
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.hasPrefix(".") }) else {
            throw VibeDeckError.invalidGroupPath(path)
        }
        return parts.map { Slug.make(String($0)) }.joined(separator: "/")
    }

    /// Caminho relativo à raiz do projeto (aceita absoluto, `./x` e relativo).
    func relativePath(_ file: String) -> String {
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        var path = file.hasPrefix("/") ? URL(fileURLWithPath: file).standardizedFileURL.path : file
        if path.hasPrefix(rootPath) { path.removeFirst(rootPath.count) }
        if path.hasPrefix("./") { path.removeFirst(2) }
        return path
    }

    /// Resolve links simbólicos do ancestral existente mais longo e acrescenta o que falta.
    static func canonicalURL(_ url: URL) -> URL {
        let fm = FileManager.default
        var ancestor = url.standardizedFileURL
        var missing: [String] = []
        while !fm.fileExists(atPath: ancestor.path), ancestor.path != "/" {
            missing.append(ancestor.lastPathComponent)
            ancestor = ancestor.deletingLastPathComponent()
        }
        var resolved = ancestor.resolvingSymlinksInPath()
        for component in missing.reversed() { resolved = resolved.appending(path: component) }
        return resolved.standardizedFileURL
    }

    /// Nome do arquivo de um check em `.vibedeck/checks/`.
    static func checkFileName(_ check: RuleCheck) -> String {
        var style = Date.VerbatimFormatStyle(
            format: "\(year: .defaultDigits)\(month: .twoDigits)\(day: .twoDigits)-\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased))\(minute: .twoDigits)\(second: .twoDigits)",
            timeZone: .gmt, calendar: Calendar(identifier: .gregorian)
        )
        style.locale = Locale(identifier: "en_US_POSIX")
        return "\(check.createdAt.formatted(style))-\(check.id.uuidString.prefix(8).lowercased()).json"
    }

    /// Reescreve o grupo de regras `from` para `to` nas regras dadas (valida colisões).
    func ruleGroupRenamed(_ rules: [Rule], from: String, to: String) throws -> [Rule] {
        _ = try normalizedGroupPath(from)
        let source = from
        let target = try normalizedGroupPath(to)
        guard target != source, !target.hasPrefix(source + "/") else { throw VibeDeckError.invalidGroupPath(to) }
        guard !rules.contains(where: { ($0.group ?? "") == target || ($0.group ?? "").hasPrefix(target + "/") }) else { throw VibeDeckError.groupConflict(target) }
        return rules.map { rule in
            var moved = rule
            if let group = rule.group, group == source || group.hasPrefix(source + "/") { moved.group = target + String(group.dropFirst(source.count)) }
            return moved
        }
    }

    /// Caminho de um anexo relativo à profundidade do dono (`../attachments/nome`).
    static func attachmentPath(name: String, owner: String) -> String {
        String(repeating: "../", count: owner.split(separator: "/").count) + "attachments/" + name
    }

    /// Scripts de regras rodando ao mesmo tempo no app.
    static var defaultScriptConcurrency: Int { ProcessInfo.processInfo.activeProcessorCount }

    static func scriptConcurrency(_ requested: Int?) -> Int {
        min(max(requested ?? defaultScriptConcurrency, 1), defaultScriptConcurrency)
    }
}
