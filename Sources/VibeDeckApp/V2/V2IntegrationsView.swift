import SwiftUI

/// Uma integração do VibeDeck com um agente: o MCP e o hook de regras (Stop), no Claude Code ou no Codex.
struct V2Integration: Identifiable, Equatable {
    enum Kind { case claudeMCP, codexMCP, claudeHook, codexHook }

    let kind: Kind
    let installed: Bool

    var id: Kind { kind }

    var title: String {
        switch kind {
        case .claudeMCP: return "MCP do VibeDeck no Claude Code"
        case .codexMCP: return "MCP do VibeDeck no Codex"
        case .claudeHook: return "Hook de regras no Claude Code"
        case .codexHook: return "Hook de regras no Codex"
        }
    }

    var detail: String {
        switch kind {
        case .claudeMCP, .codexMCP: return "O agente lê e grava os dados do projeto pelas tools do VibeDeck."
        case .claudeHook, .codexHook: return "O agente só conclui a resposta com as regras verificadas."
        }
    }

    /// Argumentos do CLI `vibedeck` que instalam a integração.
    var installArguments: [String] {
        switch kind {
        case .claudeMCP: return ["mcp", "install", "--provider", "claude"]
        case .codexMCP: return ["mcp", "install", "--provider", "codex"]
        case .claudeHook: return ["hook", "install", "--agent", "claude"]
        case .codexHook: return ["hook", "install", "--agent", "codex"]
        }
    }
}

/// Lê os arquivos de configuração do projeto (e do usuário) para saber o que já está instalado, e chama o CLI
/// empacotado para instalar. Só projetos locais.
enum V2IntegrationProbe {
    static func scan(root: URL) -> [V2Integration] {
        [
            V2Integration(kind: .claudeMCP, installed: claudeMCP(root: root)),
            V2Integration(kind: .codexMCP, installed: codexMCP(root: root)),
            V2Integration(kind: .claudeHook, installed: hook(root: root, files: [".claude/settings.local.json", ".claude/settings.json"])),
            V2Integration(kind: .codexHook, installed: hook(root: root, files: [".codex/hooks.json"])),
        ]
    }

    private static func text(_ url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    private static func claudeMCP(root: URL) -> Bool {
        if text(root.appending(path: ".mcp.json")).contains("\"vibedeck\"") { return true }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let user = text(home.appending(path: ".claude.json"))
        return user.contains(root.path) && user.contains("\"vibedeck\"")
    }

    private static func codexMCP(root: URL) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let project = text(root.appending(path: ".codex/config.toml"))
        let user = text(home.appending(path: ".codex/config.toml"))
        return project.contains("mcp_servers.vibedeck") || user.contains("mcp_servers.vibedeck")
    }

    private static func hook(root: URL, files: [String]) -> Bool {
        files.contains { file in
            let content = text(root.appending(path: file))
            return content.contains("vibedeck") && content.contains("hook stop")
        }
    }

    /// Roda `vibedeck -C <raiz> <argumentos>`. Devolve a mensagem de erro, ou nil quando deu certo.
    static func run(_ arguments: [String], root: URL) async -> String? {
        guard let binary = CoreLocator.binary() else { return "O executável vibedeck não foi encontrado." }
        return await Task.detached { () -> String? in
            let process = Process()
            process.executableURL = binary
            process.arguments = ["-C", root.path] + arguments
            let errors = Pipe()
            process.standardError = errors
            process.standardOutput = Pipe()
            do { try process.run() } catch { return error.localizedDescription }
            let data = errors.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            if process.terminationStatus == 0 { return nil }
            let message = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return message.isEmpty ? "A instalação falhou (código \(process.terminationStatus))." : message
        }.value
    }
}

/// Projeto › Integrações (prancha 17): o que já está instalado nos agentes e o que dá para instalar.
struct V2IntegrationsView: View {
    @Environment(ProjectModel.self) private var model
    @State private var items: [V2Integration] = []
    @State private var working: V2Integration.Kind?
    @State private var failure: String?

    private var isRemote: Bool { model.store.isRemote }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Space.s4) {
                Text("Integrações").font(DesignTokens.Typography.displayLG)
                Text("Como os agentes falam com o VibeDeck neste projeto.")
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(DesignTokens.Colors.inkMuted)
                if isRemote {
                    Text("Disponível só em projetos locais: as integrações ficam nas configurações da máquina do projeto.")
                        .font(DesignTokens.Typography.body)
                        .foregroundStyle(DesignTokens.Colors.inkMuted)
                } else {
                    ForEach(items) { item in row(item) }
                }
                if let failure {
                    Text(failure).font(DesignTokens.Typography.callout).foregroundStyle(DesignTokens.Colors.fix)
                }
            }
            .padding(DesignTokens.Space.s6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Integrações")
        .task { refresh() }
    }

    private func refresh() {
        items = isRemote ? [] : V2IntegrationProbe.scan(root: model.store.root)
    }

    private func row(_ item: V2Integration) -> some View {
        HStack(alignment: .top, spacing: DesignTokens.Space.s3) {
            VStack(alignment: .leading, spacing: DesignTokens.Space.s1) {
                Text(item.title).font(DesignTokens.Typography.headline)
                Text(item.detail)
                    .font(DesignTokens.Typography.callout)
                    .foregroundStyle(DesignTokens.Colors.inkMuted)
            }
            Spacer()
            if item.installed {
                VDBadge("instalado", icon: .check, tone: .done)
            } else {
                installButton(item)
            }
        }
        .padding(DesignTokens.Space.s4)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                .fill(DesignTokens.Colors.surface100)
        )
    }

    private func installButton(_ item: V2Integration) -> some View {
        LoggedButton(working == item.kind ? "Instalando…" : "Instalar") {
            install(item)
        }
        .loggedControl(control: "v2_integrations.install", label: "Instalar integração")
        .buttonStyle(VDButtonStyle(kind: .secondary, size: .md))
        .disabled(working != nil || model.isReadOnly)
    }

    private func install(_ item: V2Integration) {
        working = item.kind
        failure = nil
        let root = model.store.root
        Task {
            let error = await V2IntegrationProbe.run(item.installArguments, root: root)
            failure = error
            working = nil
            refresh()
        }
    }
}
