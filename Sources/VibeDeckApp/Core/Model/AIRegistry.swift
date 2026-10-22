import Foundation

struct AIImportResult: Sendable {
    var slugs: [String] = []
    var warnings: [String] = []
    init() {}
}

/// Reads the string fields used by Codex agent TOML, including multiline basic/literal strings.
/// Other settings remain in the original file and are never interpreted as VibeDeck permissions.
enum CodexAgentFile {
    struct Parsed: Equatable, Sendable {
        var name: String
        var description: String?
        var model: String?
        var effort: String?
        var prompt: String
    }
    static func parse(_ text: String, fallbackName: String) throws -> Parsed {
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


