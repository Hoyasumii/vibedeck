import Foundation

/// Projeto remoto: o Core Rust roda no servidor (`ssh host vibedeck mcp -C <dir>`) e o app só fala MCP com ele.
/// Não há espelho local nem sincronização. A raiz é uma URL `ssh://[usuário@]host[:porta]/diretório[?alias=nome]`,
/// que serve de identidade da janela e sobrevive à restauração de janelas.
struct RemoteWorkspace {
    let root: URL
    let destination: SSHDestination

    /// `nil` para pastas locais.
    static func existing(at root: URL) -> RemoteWorkspace? {
        guard root.scheme == "ssh", let components = URLComponents(url: root, resolvingAgainstBaseURL: false),
              let host = components.host, !host.isEmpty else { return nil }
        let user = components.user ?? NSUserName()
        let alias = components.queryItems?.first { $0.name == "alias" }?.value
        let directory = components.path.isEmpty ? "/" : components.path
        guard let destination = try? SSHDestination(host: host, port: components.port ?? 22, user: user, directory: directory, alias: alias) else { return nil }
        return RemoteWorkspace(root: root, destination: destination)
    }

    static func rootURL(for destination: SSHDestination) -> URL {
        var components = URLComponents()
        components.scheme = "ssh"
        components.user = destination.user
        components.host = destination.host
        components.port = destination.port == 22 ? nil : destination.port
        components.path = destination.directory
        if let alias = destination.alias { components.queryItems = [URLQueryItem(name: "alias", value: alias)] }
        return components.url ?? URL(fileURLWithPath: destination.directory)
    }
}
