import Foundation

public enum CodexMCP {
    /// Embedded so installed app bundles and Linux CLI builds do not depend on a repository checkout.
    public static let adapter = #"""
"""Adapta capacidades experimentais do Codex para o SDK Swift MCP 0.12."""

import json
import subprocess
import sys


def adapt(line):
    try:
        message = json.loads(line)
        if message.get("method") != "initialize":
            return line
        capabilities = message.get("params", {}).get("capabilities", {})
        experimental = capabilities.get("experimental")
        if isinstance(experimental, dict):
            # The Swift SDK models these as strings. VibeDeck does not consume
            # experimental client capabilities; retain their JSON as text.
            capabilities["experimental"] = {
                key: value if isinstance(value, str) else json.dumps(value)
                for key, value in experimental.items()
            }
            return (json.dumps(message) + "\n").encode()
    except (ValueError, AttributeError, TypeError):
        pass
    return line


def main():
    process = subprocess.Popen(sys.argv[1:], stdin=subprocess.PIPE)
    try:
        for line in sys.stdin.buffer:
            process.stdin.write(adapt(line))
            process.stdin.flush()
        process.stdin.close()
        return process.wait()
    except BrokenPipeError:
        return process.wait()
    finally:
        if process.poll() is None:
            process.terminate()
            process.wait()


if __name__ == "__main__":
    sys.exit(main())
"""#

    public static func sessionConfig(root: URL, cli: String?) -> [String: JSONValue] {
        let args = ["-c", adapter, cli ?? "vibedeck", "mcp", "--root", root.path]
        return ["mcp_servers.vibedeck": .object(["command": .string("python3"), "args": .array(args.map(JSONValue.string)), "required": .bool(true)])]
    }

    public static func install(root: URL, cli: String, name: String = "vibedeck", user: Bool = false, force: Bool = false, home: URL = FileManager.default.homeDirectoryForCurrentUser) throws {
        guard !name.isEmpty, name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else { throw CodexRPCError.server("Nome MCP inválido") }
        let file = (user ? home : root).appending(path: ".codex/config.toml")
        var text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        let begin = "# BEGIN VibeDeck MCP \(name)\n", end = "# END VibeDeck MCP \(name)\n"
        if let range = managedRange(text, begin: begin, end: end) {
            guard force else { throw CodexRPCError.server("MCP \(name) já instalado; use --force.") }
            text.removeSubrange(range)
        }
        guard !text.contains("[mcp_servers.\(name)]"), !text.contains("[mcp_servers.\"\(name)\"]") else {
            throw CodexRPCError.server("Já existe uma configuração MCP manual para \(name). Remova ou renomeie esse registro antes de instalar.")
        }
        func literal(_ value: String) throws -> String {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.withoutEscapingSlashes]
            return String(decoding: try encoder.encode(value), as: UTF8.self)
        }
        let args = ["-c", adapter, cli, "mcp", "--root", root.path]
        text += "\n" + begin + "[mcp_servers.\(name)]\ncommand = \"python3\"\nargs = [" + (try args.map(literal)).joined(separator: ", ") + "]\n" + end
        try AtomicFile.write(Data(text.utf8), to: file)
    }
    public static func uninstall(root: URL, name: String = "vibedeck", user: Bool = false, home: URL = FileManager.default.homeDirectoryForCurrentUser) throws {
        let file = (user ? home : root).appending(path: ".codex/config.toml")
        guard var text = try? String(contentsOf: file, encoding: .utf8), let range = managedRange(text, begin: "# BEGIN VibeDeck MCP \(name)\n", end: "# END VibeDeck MCP \(name)\n") else { return }
        text.removeSubrange(range)
        try AtomicFile.write(Data(text.utf8), to: file)
    }
    private static func managedRange(_ text: String, begin: String, end: String) -> Range<String.Index>? {
        guard let start = text.range(of: begin), let stop = text.range(of: end, range: start.upperBound..<text.endIndex) else { return nil }
        return start.lowerBound..<stop.upperBound
    }
}
