import Foundation

/// File exploration for isolated Codex calls. These tools never spawn commands or write files.
enum CodexReadTools {
    private static let byteLimit = 2_000_000
    private static let outputLimit = 16_000

    static let specs: JSONValue = .array([
        spec("Read", "Leia um arquivo UTF-8 do projeto, com linhas numeradas. Use offset/limit para trechos.",
             properties: ["path": string, "offset": integer, "limit": integer], required: ["path"]),
        spec("Glob", "Liste arquivos do projeto por glob. Use offset/limit para paginar.",
             properties: ["pattern": string, "offset": integer, "limit": integer], required: ["pattern"]),
        spec("Grep", "Busque texto literal nos arquivos do projeto. Restrinja glob para buscas grandes; saída com arquivo:linha.",
             properties: ["pattern": string, "glob": string], required: ["pattern"])
    ])
    private static let string: JSONValue = .object(["type": .string("string")])
    private static let integer: JSONValue = .object(["type": .string("integer"), "minimum": .number(1)])
    private static func spec(_ name: String, _ description: String, properties: [String: JSONValue], required: [String]) -> JSONValue {
        .object(["type": .string("function"), "name": .string(name), "description": .string(description),
                 "inputSchema": .object(["type": .string("object"), "properties": .object(properties),
                                          "required": .array(required.map(JSONValue.string)), "additionalProperties": .bool(false)])])
    }

    static func response(root: URL, tool: String, arguments: JSONValue) -> JSONValue {
        do { return result(try execute(root: root, tool: tool, arguments: arguments), success: true) }
        catch { return result(error.localizedDescription, success: false) }
    }
    private static func result(_ text: String, success: Bool) -> JSONValue {
        .object(["success": .bool(success), "contentItems": .array([
            .object(["type": .string("inputText"), "text": .string(String(text.prefix(outputLimit)))])
        ])])
    }
    private static func invalid(_ message: String) -> VibeDeckError { .discoverFailed(message) }
    private static func positive(_ arguments: JSONValue, _ key: String, default fallback: Int, maximum: Int) throws -> Int {
        guard let value = arguments[key] else { return fallback }
        guard let number = value.number, number.isFinite, number >= 1, number.rounded() == number, number <= Double(maximum) else {
            throw invalid("\(key) deve ser um inteiro entre 1 e \(maximum).")
        }
        return Int(number)
    }
    private static func file(_ path: String, root: URL) throws -> URL {
        let base = root.resolvingSymlinksInPath().standardizedFileURL
        let url = (path.hasPrefix("/") ? URL(fileURLWithPath: path) : base.appendingPathComponent(path))
            .resolvingSymlinksInPath().standardizedFileURL
        let prefix = base.path + "/"
        guard url.path.hasPrefix(prefix) else {
            throw invalid("Arquivo fora do projeto ou indisponível: \(path)")
        }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, (values.fileSize ?? Int.max) <= byteLimit else {
            throw invalid("Leia um arquivo de texto regular de até 2 MB: \(path)")
        }
        return url
    }
    private static func read(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        guard data.count <= byteLimit, !data.contains(0), let text = String(data: data, encoding: .utf8) else {
            throw invalid("Arquivo não é texto UTF-8 de até 2 MB: \(url.lastPathComponent)")
        }
        return text
    }
    static func execute(root: URL, tool: String, arguments: JSONValue) throws -> String {
        guard ["Read", "Glob", "Grep"].contains(tool) else { throw invalid("Ferramenta não permitida: \(tool)") }
        let metadata = RuleDiscover.projectFiles(root: root.appending(path: ".vibedeck"))
            .map { ".vibedeck/" + $0 }
        let files = Array(Set(RuleDiscover.projectFiles(root: root) + metadata)).sorted()
        switch tool {
        case "Read":
            guard let path = arguments["path"]?.string else { throw invalid("Informe path para ler um arquivo.") }
            let text = try read(file(path, root: root))
            let offset = try positive(arguments, "offset", default: 1, maximum: byteLimit)
            let limit = try positive(arguments, "limit", default: 200, maximum: 500)
            let lines = text.components(separatedBy: "\n")
            let start = min(offset - 1, lines.count)
            return lines[start..<min(start + limit, lines.count)].enumerated()
                .map { "\(path):\(start + $0.offset + 1):\($0.element)" }.joined(separator: "\n")
        case "Glob":
            guard let pattern = arguments["pattern"]?.string else { throw invalid("Informe pattern para listar arquivos.") }
            let offset = try positive(arguments, "offset", default: 1, maximum: byteLimit)
            let limit = try positive(arguments, "limit", default: 200, maximum: 1000)
            let matches = files.filter { Glob.matches(pattern, path: $0) }
            let start = min(offset - 1, matches.count)
            let end = min(start + limit, matches.count)
            return matches[start..<end].joined(separator: "\n") + "\n\(matches.count) arquivo(s); próximo offset: \(end + 1)."
        default:
            guard let pattern = arguments["pattern"]?.string, !pattern.isEmpty, pattern.count <= 1000 else {
                throw invalid("Informe pattern com 1 a 1000 caracteres para busca literal.")
            }
            let glob = arguments["glob"]?.string ?? "**"
            var matches: [String] = [], bytes = 0, count = 0
            let deadline = Date().addingTimeInterval(2)
            for path in files where Glob.matches(glob, path: path) {
                try Task.checkCancellation()
                if Date() > deadline || bytes >= 10_000_000 || count >= 1000 || matches.count >= 100 {
                    matches.append("Busca limitada; refine glob ou pattern."); break
                }
                count += 1
                guard let url = try? file(path, root: root), let text = try? read(url) else { continue }
                bytes += text.utf8.count
                for (index, line) in text.components(separatedBy: "\n").enumerated() where line.contains(pattern) {
                    matches.append("\(path):\(index + 1):\(String(line.prefix(1000)))")
                    if matches.count >= 100 { break }
                }
            }
            return matches.isEmpty ? "Nenhuma ocorrência." : matches.joined(separator: "\n")
        }
    }
}
