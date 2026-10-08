import Foundation

/// Single detection of the local Claude Code install, reused by every AI feature: when it is missing,
/// those features are hidden instead of shown disabled.
public enum ClaudeCode {
    /// The `claude` executable, resolved once per process.
    public static let executable: URL? = locate()

    public static var isInstalled: Bool { executable != nil }

    /// Directories where installers put `claude`. GUI apps don't inherit the shell PATH, so these are
    /// checked explicitly before falling back to asking the login shell.
    static func candidateDirectories(home: URL, path: String?) -> [String] {
        var dirs = (path ?? "").split(separator: ":").map(String.init)
        dirs += [
            home.appending(path: ".local/bin").path,
            home.appending(path: ".claude/local").path,
            "/opt/homebrew/bin",
            "/usr/local/bin",
        ]
        var seen = Set<String>()
        return dirs.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    static func locate(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        path: String? = ProcessInfo.processInfo.environment["PATH"],
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
        loginShellLookup: () -> String? = { loginShell("command -v claude") }
    ) -> URL? {
        for dir in candidateDirectories(home: home, path: path) {
            let candidate = URL(fileURLWithPath: dir).appending(path: "claude").path
            if isExecutable(candidate) { return URL(fileURLWithPath: candidate) }
        }
        if let found = loginShellLookup()?.trimmingCharacters(in: .whitespacesAndNewlines),
           found.hasPrefix("/"), isExecutable(found) {
            return URL(fileURLWithPath: found)
        }
        return nil
    }

    /// PATH for child processes: the login shell's (so `git`, `node` and the `vibedeck` MCP server resolve
    /// as in the terminal), with the candidate directories appended as a fallback.
    public static func childPATH() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let base = loginShell(#"printf %s "$PATH""#) ?? ProcessInfo.processInfo.environment["PATH"]
        return candidateDirectories(home: home, path: base).joined(separator: ":")
    }

    /// Runs `command` in the user's login shell and returns its stdout, or nil on failure.
    static func loginShell(_ command: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh")
        process.arguments = ["-lc", command]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, let text = String(data: data, encoding: .utf8), !text.isEmpty else { return nil }
        return text
    }
}
