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
}
