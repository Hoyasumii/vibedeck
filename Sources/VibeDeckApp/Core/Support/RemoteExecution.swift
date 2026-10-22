import Foundation

public enum RemoteExecution {
    public static func path(for root: URL) -> String { RemoteWorkspace.existing(at: root)?.destination.directory ?? root.path }
    /// Replaces a local launch with SSH. Never falls back to the Mac's executable.
    public static func configure(_ process: Process, root: URL, program: String? = nil, command: String? = nil, environment: [String: String] = [:]) throws {
        guard let workspace = RemoteWorkspace.existing(at: root) else { return }
        try workspace.requireSynchronized()
        let connection = SSHConnection(workspace.destination)
        let name = program ?? process.executableURL?.lastPathComponent ?? ""
        var body: String
        body = command ?? launcher(name, arguments: process.arguments ?? [])
        let exports = environment.filter { $0.key.range(of: "^[A-Za-z_][A-Za-z_0-9]*$", options: .regularExpression) != nil }
            .map { "export " + $0.key + "=" + SSHConnection.quote($0.value) + "; " }.joined()
        body = connection.inDirectory(exports + body)
        let login = "exec \"${SHELL:-/bin/sh}\" -lc " + SSHConnection.quote(body)
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = connection.commandArguments(login)
        process.currentDirectoryURL = nil
    }
    /// Usual per-user install dirs. A login shell that is not interactive skips ~/.bashrc
    /// (where nvm, npm and the Claude installer put PATH), so the tool must be found here.
    static let searchDirectories = ["$HOME/.local/bin", "$HOME/.claude/local", "$HOME/.npm-global/bin", "$HOME/.bun/bin",
                                    "$HOME/.volta/bin", "$HOME/.cargo/bin", "/usr/local/bin", "/opt/homebrew/bin",
                                    "$HOME/.nvm/versions/node/*/bin", "$HOME/.local/share/fnm/node-versions/*/installation/bin"]
    /// Shell body that finds `name` on the server (PATH, install dirs, then an interactive shell) and execs it.
    static func launcher(_ name: String, arguments: [String]) -> String {
        let tool = SSHConnection.quote(name), found = "command -v " + tool + " >/dev/null 2>&1"
        // Plain sh does the globbing: zsh aborts on unmatched patterns.
        let scan = "for d in " + searchDirectories.map { "\"" + $0.replacingOccurrences(of: "/*/", with: "\"/*/\"") + "\"" }.joined(separator: " ")
            + "; do [ -x \"$d/$1\" ] && { printf %s \"$d\"; exit 0; }; done; exit 1"
        let interactive = "\"${SHELL:-/bin/sh}\" -ic " + SSHConnection.quote("command -v " + tool) + " </dev/null 2>/dev/null | tail -n 1"
        return found + " || { d=$(/bin/sh -c " + SSHConnection.quote(scan) + " sh " + tool + ") && PATH=\"$d:$PATH\"; }; "
            + found + " || { p=$(" + interactive + "); case \"$p\" in /*) [ -x \"$p\" ] && PATH=\"${p%/*}:$PATH\";; esac; }; "
            + "export PATH; " + found + " || { printf '%s\\n' " + SSHConnection.quote("Ferramenta remota ausente: \(name). Instale no servidor ou selecione outro provedor manualmente.")
            + " >&2; exit 127; }; exec " + ([name] + arguments).map(SSHConnection.quote).joined(separator: " ")
    }
    /// Sem espelho local (o Core roda no servidor), não há o que sincronizar antes de chamar o provedor.
    public static func synchronize(root: URL) async throws {}
    public static func contextDirectory(_ workspace: RemoteWorkspace) -> String { "/tmp/vibedeck-context-" + workspace.destination.id }
    /// Transfer only full context references actually used by this prompt, off the UI thread.
    public static func prepareContext(_ text: String, root: URL) async throws -> String {
        guard let workspace = RemoteWorkspace.existing(at: root) else { return text }
        return try await VDLog.detached {
            let local = AIContextStore(root: root).directory
            let files = (try? FileManager.default.contentsOfDirectory(at: local, includingPropertiesForKeys: nil)) ?? []
            var result = text
            let connection = SSHConnection(workspace.destination), directory = contextDirectory(workspace)
            for file in files where result.contains(file.path) {
                let target = directory + "/" + file.lastPathComponent
                let command = "umask 077; test ! -L " + SSHConnection.quote(directory) + " && mkdir -p " + SSHConnection.quote(directory) + " && chmod 700 " + SSHConnection.quote(directory) + " && test ! -L " + SSHConnection.quote(target) + " && cat > " + SSHConnection.quote(target)
                _ = try connection.run(command, input: Data(contentsOf: file))
                result = result.replacingOccurrences(of: file.path, with: target)
            }
            return result
        }.value
    }
    public static func executable(_ provider: AIProvider, root: URL) -> URL? {
        RemoteWorkspace.existing(at: root) == nil ? provider.executable : URL(fileURLWithPath: "/" + provider.rawValue)
    }
    public static func available(_ provider: AIProvider, root: URL) -> Bool { RemoteWorkspace.existing(at: root) != nil || provider.isInstalled }
    public static func providers(root: URL) -> [AIProvider] { RemoteWorkspace.existing(at: root) == nil ? AIProvider.installed : AIProvider.allCases }
}
