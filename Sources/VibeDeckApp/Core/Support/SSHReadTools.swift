import Foundation

/// Remote counterparts of the isolated Codex tools. Only reads files inside the project;
/// commands are fixed by VibeDeck and tool arguments are quoted, never evaluated as shell code.
enum SSHReadTools {
    static func execute(_ workspace: RemoteWorkspace, tool: String, arguments: JSONValue) throws -> String {
        let connection = SSHConnection(workspace.destination)
        let root = workspace.destination.directory
        func read(_ path: String) throws -> String {
            let context = RemoteExecution.contextDirectory(workspace)
            if path.hasPrefix(context + "/") {
                let filename = String(path.dropFirst(context.count + 1))
                guard filename.hasSuffix(".txt"), filename.count == 68, filename.dropLast(4).allSatisfy({ "0123456789abcdef".contains($0) }) else { throw VibeDeckError.ssh("Referência de contexto inválida.") }
                let data = try connection.run("test ! -L " + SSHConnection.quote(context) + " && test ! -L " + SSHConnection.quote(path) + " && head -c 2000001 " + SSHConnection.quote(path))
                guard data.count <= 2_000_000, let value = String(data: data, encoding: .utf8) else { throw VibeDeckError.ssh("Leia o contexto por trechos de até 2 MB.") }
                return value
            }
            let relative: String
            if root == "/", path.hasPrefix("/") { relative = String(path.dropFirst()) }
            else if path.hasPrefix(root + "/") { relative = String(path.dropFirst(root.count + 1)) }
            else { relative = path }
            guard !relative.hasPrefix("/"), !relative.split(separator: "/").contains(".."), !relative.contains("\0") else { throw VibeDeckError.ssh("Arquivo fora do projeto.") }
            let parent = (relative as NSString).deletingLastPathComponent
            let file = (relative as NSString).lastPathComponent
            let script = "cd " + SSHConnection.quote(parent.isEmpty ? "." : parent) + " || exit; actual=$(pwd -P); case \"$actual/\" in " + SSHConnection.quote(root == "/" ? "/" : root + "/") + "*) ;; *) exit 45;; esac; test ! -L " + SSHConnection.quote(file) + " && test -f " + SSHConnection.quote(file) + " && head -c 2000001 " + SSHConnection.quote(file)
            let data = try connection.run(script)
            guard data.count <= 2_000_000, !data.contains(0), let text = String(data: data, encoding: .utf8) else { throw VibeDeckError.ssh("Leia um arquivo UTF-8 de até 2 MB.") }
            return text
        }
        func number(_ key: String, fallback: Int, max: Int) throws -> Int {
            guard let raw = arguments[key] else { return fallback }
            guard let value = raw.number, value.isFinite, value >= 1, value <= Double(max), value.rounded() == value else { throw VibeDeckError.ssh("Intervalo inválido: \(key).") }
            return Int(value)
        }
        if tool == "Read" {
            guard let path = arguments["path"]?.string else { throw VibeDeckError.ssh("Informe path.") }
            let text = try read(path), lines = text.components(separatedBy: "\n")
            let offset = try number("offset", fallback: 1, max: 2_000_000), limit = try number("limit", fallback: 200, max: 500)
            let start = min(offset - 1, lines.count)
            return lines[start..<min(start + limit, lines.count)].enumerated().map { "\(path):\(start + $0.offset + 1):\($0.element)" }.joined(separator: "\n")
        }
        guard ["Glob", "Grep"].contains(tool), let pattern = arguments["pattern"]?.string, !pattern.isEmpty, pattern.count <= 1000 else { throw VibeDeckError.ssh("Ferramenta ou padrão inválido.") }
        let bytes = try connection.run("find . -type d \\( -name .git -o -name node_modules -o -name .build \\) -prune -o -type f -print0")
        let files = bytes.split(separator: 0).map { String(decoding: $0, as: UTF8.self).replacingOccurrences(of: "./", with: "", options: .anchored) }.sorted()
        if tool == "Glob" {
            let matches = files.filter { Glob.matches(pattern, path: $0) }
            let offset = try number("offset", fallback: 1, max: 2_000_000), limit = try number("limit", fallback: 200, max: 1000)
            let start = min(offset - 1, matches.count), end = min(start + limit, matches.count)
            return matches[start..<end].joined(separator: "\n") + "\n\(matches.count) arquivo(s); próximo offset: \(end + 1)."
        }
        let glob = arguments["glob"]?.string ?? "**"
        var output = [String](), total = 0
        let deadline = Date().addingTimeInterval(20)
        for file in files.filter({ Glob.matches(glob, path: $0) }).prefix(1000) {
            try Task.checkCancellation()
            if Date() > deadline || total > 10_000_000 || output.count >= 100 { output.append("Busca limitada; refine glob ou pattern."); break }
            guard let text = try? read(file) else { continue }; total += text.utf8.count
            for (line, value) in text.components(separatedBy: "\n").enumerated() where value.contains(pattern) {
                output.append("\(file):\(line + 1):\(value)")
                if output.count >= 100 { break }
            }
        }
        return output.joined(separator: "\n")
    }
}
