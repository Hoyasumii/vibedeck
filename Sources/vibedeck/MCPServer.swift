import ArgumentParser
import Foundation
import MCP
import VibeDeckCore

struct MCPCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp",
        abstract: "Servidor MCP (stdio) expondo o projeto para agentes de IA.",
        discussion: "Registre no Claude Code com: vibedeck mcp install",
        subcommands: [MCPServe.self, MCPInstall.self, MCPUninstall.self],
        defaultSubcommand: MCPServe.self
    )
}

enum MCPScope: String, ExpressibleByArgument, CaseIterable {
    case local, project, user
}

/// Roda `claude <arguments>` no diretório dado, repassando stdout/stderr. Retorna o código de saída.
@discardableResult
func runClaude(_ arguments: [String], in directory: URL) throws -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["claude"] + arguments
    process.currentDirectoryURL = directory
    do {
        try process.run()
    } catch {
        FileHandle.standardError.write(Data("Não foi possível executar `claude`: \(error.localizedDescription)\n".utf8))
        throw ExitCode.failure
    }
    process.waitUntilExit()
    return process.terminationStatus
}

/// Caminho do executável `vibedeck` a registrar: o encontrado no PATH (symlink estável entre builds)
/// ou, na falta dele, o binário atual.
func vibedeckExecutablePath() -> String {
    let arg0 = CommandLine.arguments[0]
    if arg0.contains("/") {
        return URL(fileURLWithPath: arg0).standardizedFileURL.path
    }
    for dir in (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":") {
        let candidate = URL(fileURLWithPath: String(dir)).appendingPathComponent(arg0).path
        if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
    }
    return Bundle.main.executablePath ?? arg0
}

struct MCPInstall: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: "Registra o servidor MCP no Claude Code (claude mcp add).",
        discussion: """
        Escopos: local (só você, neste projeto), project (grava .mcp.json para o time) ou
        user (todos os seus projetos; o servidor falha em pastas sem vibedeck.json).
        """
    )

    @OptionGroup var options: RootOptions
    @Option(name: [.short, .long], help: "Escopo: local, project ou user.") var scope: MCPScope?
    @Option(help: "Provedor: claude ou codex.") var provider: AIProvider = .claude
    @Option(help: "Nome do servidor.") var name = "vibedeck"
    @Flag(help: "Substitui um registro existente com o mesmo nome.") var force = false

    func run() throws {
        let root = try options.store().root
        let scope = scope ?? (provider == .codex ? .project : .local)
        if provider == .codex {
            guard scope != .local else { throw ValidationError("Codex suporta os escopos project ou user.") }
            try CodexMCP.install(root: root, cli: vibedeckExecutablePath(), name: name, user: scope == .user, force: force)
            print("MCP instalado no Codex (\(scope.rawValue)). Reinicie o cliente para carregar as tools.")
            return
        }
        // .mcp.json é versionado: usa o comando do PATH em vez de um caminho absoluto desta máquina.
        let executable = scope == .project ? "vibedeck" : vibedeckExecutablePath()

        if force {
            try runClaude(["mcp", "remove", name, "-s", scope.rawValue], in: root)
        }
        let status = try runClaude(["mcp", "add", name, "-s", scope.rawValue, "--", executable, "mcp"], in: root)
        if status != 0 {
            FileHandle.standardError.write(Data("`claude mcp add` falhou. Se já existe um servidor \"\(name)\", use --force.\n".utf8))
            throw ExitCode(status)
        }
        print("Reinicie o Claude Code (ou use /mcp) para carregar as tools do VibeDeck.")
    }
}

struct MCPUninstall: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uninstall",
        abstract: "Remove o servidor MCP do Claude Code (claude mcp remove)."
    )

    @OptionGroup var options: RootOptions
    @Option(name: [.short, .long], help: "Escopo: local, project ou user.") var scope: MCPScope?
    @Option(help: "Provedor: claude ou codex.") var provider: AIProvider = .claude
    @Option(help: "Nome do servidor.") var name = "vibedeck"

    func run() throws {
        let root = try options.store().root
        let scope = scope ?? (provider == .codex ? .project : .local)
        if provider == .codex {
            guard scope != .local else { throw ValidationError("Codex suporta project ou user.") }
            try CodexMCP.uninstall(root: root, name: name, user: scope == .user)
            return
        }
        let status = try runClaude(["mcp", "remove", name, "-s", scope.rawValue], in: root)
        if status != 0 { throw ExitCode(status) }
    }
}

struct MCPServe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "serve",
        abstract: "Inicia o servidor MCP (stdio). É o padrão de `vibedeck mcp`."
    )

    @OptionGroup var options: RootOptions

    func run() async throws {
        let store = try options.store()
        try? store.refreshAgentsGuideIfNeeded()
        let server = Server(
            name: "vibedeck",
            version: VibeDeckCLI.configuration.version,
            instructions: MCPHandler.instructions(root: store.root.path),
            capabilities: .init(resources: .init(subscribe: false, listChanged: false), tools: .init(listChanged: false))
        )
        let handler = MCPHandler(store: store)

        await server.withMethodHandler(ListTools.self) { _ in .init(tools: MCPHandler.tools) }
        await server.withMethodHandler(CallTool.self) { params in
            do {
                return .init(content: [.text(text: try await handler.call(params.name, params.arguments ?? [:]), annotations: nil, _meta: nil)], isError: false)
            } catch {
                return .init(content: [.text(text: error.localizedDescription, annotations: nil, _meta: nil)], isError: true)
            }
        }
        await server.withMethodHandler(ListResources.self) { _ in .init(resources: try handler.resources(), nextCursor: nil) }
        await server.withMethodHandler(ReadResource.self) { params in .init(contents: [try handler.read(params.uri)]) }

        try await server.start(transport: StdioTransport())
        await server.waitUntilCompleted()
    }
}

struct MCPHandler: Sendable {
    let store: ProjectStore
    var stackService: StackService { StackService(store: store) }

    static func instructions(root: String) -> String {
        """
        Projeto VibeDeck em \(root).

        REGRA OBRIGATÓRIA: nenhuma tarefa neste projeto está concluída sem passar pelas regras.
        Antes de dizer que terminou qualquer alteração:
        1. chame rules_for com os arquivos que você alterou (e review_item, se houver);
        2. chame submit_rule_check (results=[]): ele roda os scripts das regras sozinho; as manuais ficam pending;
        3. se passed=false, corrija e envie outro check. Só conclua com passed=true, avisando os warnings
           ("should") e quantas manuais ficaram sem verificar;
        4. manuais só quando o usuário pedir: rules_for include_manual=true e submit_rule_check
           verify_manual=true respondendo pass/fail/na para TODAS, com evidência.
        Antes de implementar: itens de revisão abertos da área, list_stack e list_patterns. Registros criados por você são author=ai.
        Ideias que surgirem: add_idea (não são regras ativas).
        Referências aceitam slug, id (ou prefixo >= 4) ou título.
        Guia: .vibedeck/AGENTS.md (leia antes). Detalhes: ai_guide.
        """
    }

    // MARK: Tool definitions
    // Every tool schema is a fixed per-session token cost: keep descriptions to what the name doesn't say.
    // Usage rules live in AGENTS.md/ai_guide; `scripts/mcp-contract.py` guards the contract and the budget.

    /// `type` "array" means an array of strings; `custom` adds hand-written property schemas.
    /// An empty description is omitted (the parameter name says it all).
    private static func schema(
        _ props: [String: (String, String)], required: [String] = [], enums: [String: [String]] = [:], custom: [String: Value] = [:]
    ) -> Value {
        var properties: [String: Value] = custom
        for (name, (type, description)) in props {
            var p: [String: Value] = ["type": .string(type)]
            if !description.isEmpty { p["description"] = .string(description) }
            if type == "array" { p["items"] = ["type": "string"] }
            if let values = enums[name] { p["enum"] = .array(values.map { .string($0) }) }
            properties[name] = .object(p)
        }
        var object: [String: Value] = ["type": "object", "properties": .object(properties)]
        if !required.isEmpty { object["required"] = .array(required.map { .string($0) }) }
        return .object(object)
    }

    private static let statuses = ReviewStatus.allCases.map(\.rawValue)
    private static let priorities = ReviewPriority.allCases.map(\.rawValue)
    private static let severities = RuleSeverity.allCases.map(\.rawValue)
    private static let ideaStatuses = IdeaStatus.allCases.map(\.rawValue)
    private static let stepKinds = ["agent", "command", "skill"]
    private static let providerSettings = ("object", "{codex|claude:{model,effort}}")
    private static let provider = ("string", "claude (padrão) ou codex")
    private static let run = ("string", "<workflow>/<execução> ou id")

    private static let resultsSchema: Value = [
        "type": "array",
        "description": "Só com verify_manual=true: uma resposta por regra manual.",
        "items": [
            "type": "object",
            "properties": [
                "ruleId": ["type": "string", "description": "Id ou prefixo >= 4"],
                "verdict": ["type": "string", "enum": .array(RuleVerdict.allCases.map { .string($0.rawValue) })],
                "note": ["type": "string", "description": "Evidência"],
            ],
            "required": ["ruleId", "verdict"],
        ],
    ]

    private static let questionsSchema: Value = [
        "type": "array",
        "description": "2 a 4 opções cada, recomendada primeiro.",
        "items": [
            "type": "object",
            "properties": [
                "question": ["type": "string"],
                "context": ["type": "string"],
                "options": [
                    "type": "array",
                    "items": ["type": "object", "properties": ["label": ["type": "string"], "description": ["type": "string"]], "required": ["label"]],
                ],
                "multiple": ["type": "boolean"],
            ],
            "required": ["question"],
        ],
    ]

    static let tools: [Tool] = [
        Tool(name: "codex_usage", description: "Limites de uso atuais do Codex.", inputSchema: schema([:]), annotations: .init(readOnlyHint: true)),
        Tool(name: "claude_usage", description: "Último uso dos limites do Claude Code (5h e semana, %, reset), via statusline.",
             inputSchema: schema([:]), annotations: .init(readOnlyHint: true)),
        Tool(name: "cloud_check", description: "Compara a branch padrão local com a do origin; blocked=true impede sessões na nuvem.",
             inputSchema: schema([:]), annotations: .init(readOnlyHint: true)),
        Tool(name: "start_cloud_session", description: "Cria sessão na nuvem (repo do GitHub) e devolve o link; recusa branch divergente ou árvore suja sem allow_dirty. Só a pedido do usuário.",
             inputSchema: schema(["provider": provider,
                 "environment": ("string", "Ambiente do Codex Cloud"),
                 "description": ("string", "Tarefa"),
                 "allow_dirty": ("boolean", ""),
             ], required: ["description"])),
        Tool(name: "export_graph", description: "Exporta graph.html offline, sem IA.", inputSchema: schema([:])),
        Tool(name: "get_project", description: "vibedeck.json e resumo dos docs e grupos de revisão.", inputSchema: schema([:]),
             annotations: .init(readOnlyHint: true)),
        Tool(name: "list_docs", description: "Docs markdown (slug e título).", inputSchema: schema([:]),
             annotations: .init(readOnlyHint: true)),
        Tool(name: "read_doc", description: "Lê um doc.", inputSchema: schema(["slug": ("string", "")], required: ["slug"]),
             annotations: .init(readOnlyHint: true)),
        Tool(name: "write_doc", description: "generated: novo doc author=ai; senão cria/sobrescreve.",
             inputSchema: schema([
                 "slug": ("string", ""),
                 "title": ("string", ""),
                 "content": ("string", ""),
                 "generated": ("boolean", ""),
             ], required: ["content"])),
        Tool(name: "list_review_groups", description: "Grupos de revisão com itens abertos.", inputSchema: schema([:]),
             annotations: .init(readOnlyHint: true)),
        Tool(name: "list_review_items", description: "Itens de revisão, com filtros.",
             inputSchema: schema([
                 "group": ("string", ""),
                 "status": ("string", ""),
                 "kind": ("string", "Ver reviewKinds"),
             ], enums: ["status": statuses]),
             annotations: .init(readOnlyHint: true)),
        Tool(name: "add_review_item", description: "Adiciona um item de revisão (cria o grupo se preciso). author=ai.",
             inputSchema: schema([
                 "group": ("string", ""),
                 "kind": ("string", "Ver reviewKinds"),
                 "title": ("string", ""),
                 "details": ("string", ""),
                 "priority": ("string", ""),
                 "file": ("string", ""),
                 "route": ("string", ""),
                 "component": ("string", ""),
                 "selector": ("string", ""),
                 "rules": ("array", "Tópicos de regras do item"),
             ], required: ["group", "kind", "title"], enums: ["priority": priorities])),
        Tool(name: "update_review_item", description: "Atualiza um item. status=done exige check aprovado com review_item quando o item tem regras.",
             inputSchema: schema([
                 "id": ("string", ""),
                 "status": ("string", ""),
                 "priority": ("string", ""),
                 "title": ("string", ""),
                 "details": ("string", ""),
                 "kind": ("string", ""),
                 "rules": ("array", "Substitui os tópicos"),
             ], required: ["id"], enums: ["status": statuses, "priority": priorities])),
        Tool(name: "add_link", description: "Adiciona um link ao projeto.",
             inputSchema: schema([
                 "url": ("string", ""),
                 "title": ("string", ""),
                 "tags": ("string", "Separadas por vírgula"),
             ], required: ["url"])),

        // Stack
        Tool(name: "list_stack", description: "Stack do projeto, com notas de uso. Consulte antes de implementar.",
             inputSchema: schema([:]), annotations: .init(readOnlyHint: true)),
        Tool(name: "search_stack_icons", description: "Procura ids no catálogo do Skill Icons para add_stack.",
             inputSchema: schema([
                 "query": ("string", "Vazio = tudo"),
                 "category": ("string", ""),
                 "limit": ("integer", "Padrão 50"),
             ], enums: ["category": SkillIcons.categories]),
             annotations: .init(readOnlyHint: true)),
        Tool(name: "add_stack", description: "Adiciona tecnologias à stack (desconhecidas recusam tudo) e atualiza o badge do README.",
             inputSchema: schema([
                 "icons": ("array", "Ids, nomes ou aliases, na ordem"),
                 "note": ("string", "Nota de uso para todas"),
             ], required: ["icons"])),
        Tool(name: "remove_stack", description: "Retira tecnologias da stack e atualiza o badge.",
             inputSchema: schema(["icons": ("array", "")], required: ["icons"])),
        Tool(name: "update_stack", description: "Altera nota ou posição de uma tecnologia.",
             inputSchema: schema([
                 "icon": ("string", ""),
                 "note": ("string", "Vazia apaga"),
                 "position": ("integer", "A partir de 0"),
             ], required: ["icon"])),

        // Patterns
        Tool(name: "list_patterns", description: "Padrões de projeto que o código novo segue, com nota, paths e regras.",
             inputSchema: schema([:]), annotations: .init(readOnlyHint: true)),
        Tool(name: "pattern_catalog", description: "Catálogo embutido de padrões, para add_pattern.",
             inputSchema: schema(["query": ("string", "Vazio = tudo")]), annotations: .init(readOnlyHint: true)),
        Tool(name: "add_pattern", description: "Adiciona padrões do catálogo (`patterns`) ou um personalizado (`name` + `rules`). Cada um vira um tópico de regras.",
             inputSchema: schema([
                 "patterns": ("array", "Ids do catálogo"),
                 "name": ("string", ""),
                 "summary": ("string", ""),
                 "rules": ("array", "Regras do personalizado"),
                 "note": ("string", "Como o projeto aplica"),
                 "paths": ("array", "Globs; vazio = projeto inteiro"),
             ])),
        Tool(name: "remove_pattern", description: "Retira padrões e apaga seus tópicos de regras.",
             inputSchema: schema(["patterns": ("array", "")], required: ["patterns"])),
        Tool(name: "update_pattern", description: "Altera nota, paths ou posição de um padrão.",
             inputSchema: schema([
                 "pattern": ("string", ""),
                 "note": ("string", "Vazia apaga"),
                 "paths": ("array", "[] = projeto inteiro"),
                 "position": ("integer", "A partir de 0"),
             ], required: ["pattern"])),

        Tool(name: "ai_guide", description: "Índice ou uma seção do guia.",
             inputSchema: schema(["section": ("integer", "Omita para o índice")]), annotations: .init(readOnlyHint: true)),
        Tool(name: "ai_catalog", description: "Índice paginado sem prompts; depois leia só o registro necessário (get_*).",
             inputSchema: schema(["kind": ("string", "agents, commands, skills, workflows ou rules"), "offset": ("integer", ""), "limit": ("integer", "1 a 100, padrão 20")], required: ["kind"]), annotations: .init(readOnlyHint: true)),
        Tool(name: "ai_context", description: "Página de uma referência de contexto; nextOffset indica continuação.",
             inputSchema: schema(["id": ("string", ""), "offset": ("integer", ""), "limit": ("integer", "1 a 16000, padrão 4000")], required: ["id"]), annotations: .init(readOnlyHint: true)),
        Tool(name: "ai_usage", description: "Consumo local por tarefa; campos ausentes não são zero. clear só a pedido do usuário.",
             inputSchema: schema(["clear": ("boolean", "")])),

        // Rules
        Tool(name: "rules_for", description: "OBRIGATÓRIO antes de concluir uma tarefa: regras aplicáveis aos arquivos (forma compacta). Manuais só como contagem, até include_manual=true.",
             inputSchema: schema([
                 "files": ("array", "Arquivos alterados"),
                 "topics": ("array", "Tópicos extras"),
                 "review_item": ("string", ""),
                 "include_manual": ("boolean", "Lista as manuais com detalhes"),
                 "verbose": ("boolean", "Forma completa"),
             ]),
             annotations: .init(readOnlyHint: true)),
        Tool(name: "submit_rule_check", description: "Grava o check rodando os scripts das regras; manuais ficam pending. Com verify_manual=true, responda TODAS as manuais em results. passed=false: corrija e reenvie. Devolve resumo; check completo em disco.",
             inputSchema: schema([
                 "task": ("string", "Resumo do que foi feito"),
                 "files": ("array", ""),
                 "topics": ("array", "Os mesmos do rules_for"),
                 "review_item": ("string", ""),
                 "verify_manual": ("boolean", ""),
                 "verbose": ("boolean", "Anexa o JSON completo"),
             ], required: ["task"], custom: ["results": resultsSchema])),
        Tool(name: "run_rule_tests", description: "Roda os scripts das regras (0 cumpre, 77 n/a, outro viola) sem gravar check. Sem files/review_item, só os topics.",
             inputSchema: schema([
                 "files": ("array", ""),
                 "topics": ("array", ""),
                 "review_item": ("string", ""),
             ]),
             annotations: .init(readOnlyHint: true)),
        Tool(name: "set_rule_test", description: "Define a verificação de uma regra: script (roda na raiz, recebe $VIBEDECK_FILES, exit 0/77/outro) ou manual. Mudar a regra desatualiza o teste.",
             inputSchema: schema([
                 "rule_id": ("string", ""),
                 "mode": ("string", ""),
                 "command": ("string", "Obrigatório em script"),
                 "reason": ("string", ""),
             ], required: ["rule_id", "mode"], enums: ["mode": RuleTestMode.allCases.map(\.rawValue)])),
        Tool(name: "list_rule_topics", description: "Tópicos de regras (paths e contagem).", inputSchema: schema([:]),
             annotations: .init(readOnlyHint: true)),
        Tool(name: "get_rule_topic", description: "Tópico de regras completo.", inputSchema: schema(["topic": ("string", "")], required: ["topic"]),
             annotations: .init(readOnlyHint: true)),
        Tool(name: "add_rule_topic", description: "Cria um tópico de regras; sem paths vale para toda tarefa.",
             inputSchema: schema([
                 "title": ("string", ""),
                 "description": ("string", "Quando se aplica"),
                 "paths": ("array", "Globs"),
                 "tags": ("array", ""),
             ], required: ["title"])),
        Tool(name: "add_rule", description: "Adiciona uma regra a um tópico (cria o tópico se preciso). author=ai.",
             inputSchema: schema([
                 "topic": ("string", ""),
                 "text": ("string", "Curta e verificável"),
                 "details": ("string", "Como verificar"),
                 "severity": ("string", "must bloqueia; should avisa"),
             ], required: ["topic", "text"], enums: ["severity": severities])),

        // Ideas
        Tool(name: "list_ideas", description: "Ideias do projeto (não são regras ativas).",
             inputSchema: schema(["status": ("string", "")], enums: ["status": ideaStatuses]),
             annotations: .init(readOnlyHint: true)),
        Tool(name: "get_idea", description: "Ideia completa, com regras rascunho.", inputSchema: schema(["idea": ("string", "")], required: ["idea"]),
             annotations: .init(readOnlyHint: true)),
        Tool(name: "add_idea", description: "Registra uma ideia futura. author=ai.",
             inputSchema: schema([
                 "title": ("string", ""),
                 "body": ("string", ""),
                 "tags": ("array", ""),
             ], required: ["title"])),
        Tool(name: "update_idea", description: "Atualiza uma ideia.",
             inputSchema: schema([
                 "idea": ("string", ""),
                 "title": ("string", ""),
                 "body": ("string", ""),
                 "status": ("string", ""),
                 "tags": ("array", ""),
             ], required: ["idea"], enums: ["status": ideaStatuses])),
        Tool(name: "add_idea_rule", description: "Adiciona uma regra rascunho a uma ideia (vale após promote_idea).",
             inputSchema: schema([
                 "idea": ("string", ""),
                 "text": ("string", ""),
                 "details": ("string", ""),
                 "severity": ("string", ""),
             ], required: ["idea", "text"], enums: ["severity": severities])),
        // Agents
        Tool(name: "list_agents", description: "Agentes do VibeDeck (não os do provedor).",
             inputSchema: schema([:]), annotations: .init(readOnlyHint: true)),
        Tool(name: "get_agent", description: "Agente completo.", inputSchema: schema(["agent": ("string", "")], required: ["agent"]),
             annotations: .init(readOnlyHint: true)),
        Tool(name: "add_agent", description: "Cria um agente do VibeDeck.",
             inputSchema: schema(["provider_settings": providerSettings,
                 "title": ("string", ""),
                 "summary": ("string", "Quando usar"),
                 "model": ("string", ""),
                 "tools": ("array", ""),
                 "prompt": ("string", ""),
                 "tags": ("array", ""),
             ], required: ["title"])),
        Tool(name: "update_agent", description: "Atualiza um agente (fluxo: add_agent_next_step).",
             inputSchema: schema(["provider_settings": providerSettings,
                 "agent": ("string", ""),
                 "title": ("string", ""),
                 "summary": ("string", ""),
                 "model": ("string", ""),
                 "tools": ("array", ""),
                 "prompt": ("string", ""),
                 "tags": ("array", ""),
             ], required: ["agent"])),
        Tool(name: "add_agent_next_step", description: "Encadeia ao agente um agente, comando ou skill que atua sobre o resultado.",
             inputSchema: schema([
                 "agent": ("string", ""),
                 "target": ("string", ""),
                 "kind": ("string", ""),
                 "note": ("string", ""),
             ], required: ["agent", "target"], enums: ["kind": stepKinds])),
        Tool(name: "agent_flow", description: "JSON do fluxo do agente para orquestrar.",
             inputSchema: schema(["agent": ("string", "")], required: ["agent"]), annotations: .init(readOnlyHint: true)),
        Tool(name: "import_agents", description: "Importa agentes do provedor (.claude/agents) como agentes do VibeDeck.",
             inputSchema: schema(["provider": provider, "overwrite": ("boolean", "")])),
        // Commands
        Tool(name: "list_commands", description: "Comandos do VibeDeck (não os do provedor).",
             inputSchema: schema([:]), annotations: .init(readOnlyHint: true)),
        Tool(name: "get_command", description: "Comando completo.", inputSchema: schema(["command": ("string", "")], required: ["command"]),
             annotations: .init(readOnlyHint: true)),
        Tool(name: "add_command", description: "Cria um comando do VibeDeck (prompt de slash command, com $ARGUMENTS).",
             inputSchema: schema(["provider_settings": providerSettings,
                 "title": ("string", ""),
                 "summary": ("string", ""),
                 "argument_hint": ("string", "O que vai em $ARGUMENTS"),
                 "model": ("string", ""),
                 "tools": ("array", ""),
                 "prompt": ("string", ""),
                 "tags": ("array", ""),
             ], required: ["title"])),
        Tool(name: "update_command", description: "Atualiza um comando (fluxo: add_command_next_step).",
             inputSchema: schema(["provider_settings": providerSettings,
                 "command": ("string", ""),
                 "title": ("string", ""),
                 "summary": ("string", ""),
                 "argument_hint": ("string", ""),
                 "model": ("string", ""),
                 "tools": ("array", ""),
                 "prompt": ("string", ""),
                 "tags": ("array", ""),
             ], required: ["command"])),
        Tool(name: "add_command_next_step", description: "Encadeia ao comando um agente, comando ou skill que atua sobre o resultado.",
             inputSchema: schema([
                 "command": ("string", ""),
                 "target": ("string", ""),
                 "kind": ("string", ""),
                 "note": ("string", ""),
             ], required: ["command", "target"], enums: ["kind": stepKinds])),
        Tool(name: "command_flow", description: "JSON do fluxo do comando para orquestrar.",
             inputSchema: schema(["command": ("string", "")], required: ["command"]), annotations: .init(readOnlyHint: true)),
        Tool(name: "import_commands", description: "Importa comandos do provedor (.claude/commands) como comandos do VibeDeck.",
             inputSchema: schema(["provider": provider, "overwrite": ("boolean", "")])),
        // Skills
        Tool(name: "list_skills", description: "Skills do VibeDeck (não as do provedor).",
             inputSchema: schema([:]), annotations: .init(readOnlyHint: true)),
        Tool(name: "get_skill", description: "Skill completa.", inputSchema: schema(["skill": ("string", "")], required: ["skill"]),
             annotations: .init(readOnlyHint: true)),
        Tool(name: "add_skill", description: "Cria uma skill do VibeDeck (formato SKILL.md; summary diz quando dispará-la).",
             inputSchema: schema(["provider_settings": providerSettings,
                 "title": ("string", ""),
                 "summary": ("string", "Quando usar"),
                 "model": ("string", ""),
                 "tools": ("array", ""),
                 "prompt": ("string", ""),
                 "tags": ("array", ""),
             ], required: ["title"])),
        Tool(name: "update_skill", description: "Atualiza uma skill (fluxo: add_skill_next_step).",
             inputSchema: schema(["provider_settings": providerSettings,
                 "skill": ("string", ""),
                 "title": ("string", ""),
                 "summary": ("string", ""),
                 "model": ("string", ""),
                 "tools": ("array", ""),
                 "prompt": ("string", ""),
                 "tags": ("array", ""),
             ], required: ["skill"])),
        Tool(name: "add_skill_next_step", description: "Encadeia à skill um agente, comando ou skill que atua sobre o resultado.",
             inputSchema: schema([
                 "skill": ("string", ""),
                 "target": ("string", ""),
                 "kind": ("string", ""),
                 "note": ("string", ""),
             ], required: ["skill", "target"], enums: ["kind": stepKinds])),
        Tool(name: "skill_flow", description: "JSON do fluxo da skill para orquestrar.",
             inputSchema: schema(["skill": ("string", "")], required: ["skill"]), annotations: .init(readOnlyHint: true)),
        Tool(name: "import_skills", description: "Importa skills do provedor (.claude/skills) como skills do VibeDeck.",
             inputSchema: schema(["provider": provider, "overwrite": ("boolean", "")])),
        // Workflows
        Tool(name: "list_workflows", description: "Workflows: etapas (agentes, comandos, skills) com transições condicionais.",
             inputSchema: schema([:]), annotations: .init(readOnlyHint: true)),
        Tool(name: "get_workflow", description: "Workflow completo.", inputSchema: schema(["workflow": ("string", "")], required: ["workflow"]),
             annotations: .init(readOnlyHint: true)),
        Tool(name: "add_workflow", description: "Cria um workflow vazio (depois add_workflow_step/add_workflow_transition).",
             inputSchema: schema([
                 "title": ("string", ""),
                 "summary": ("string", ""),
                 "input": ("string", "O que pedir ao iniciar"),
                 "max_steps": ("integer", "Etapas por execução (padrão \(Workflow.defaultMaxSteps))"),
                 "tags": ("array", ""),
             ], required: ["title"])),
        Tool(name: "update_workflow", description: "Atualiza um workflow.",
             inputSchema: schema([
                 "workflow": ("string", ""),
                 "title": ("string", ""),
                 "summary": ("string", ""),
                 "input": ("string", ""),
                 "max_steps": ("integer", "0 = padrão"),
                 "tags": ("array", ""),
             ], required: ["workflow"])),
        Tool(name: "add_workflow_step", description: "Adiciona uma etapa (a primeira é o início) e devolve o id.",
             inputSchema: schema([
                 "workflow": ("string", ""),
                 "target": ("string", ""),
                 "kind": ("string", ""),
                 "note": ("string", "Instrução extra ($ARGUMENTS em comandos)"),
                 "max_visits": ("integer", "Por ciclo"),
             ], required: ["workflow", "target"], enums: ["kind": stepKinds])),
        Tool(name: "set_workflow_step_max_visits", description: "Limite de execuções da etapa por ciclo; estourar para a execução.",
             inputSchema: schema([
                 "workflow": ("string", ""),
                 "step": ("string", "Id ou posição"),
                 "max_visits": ("integer", "0 = sem limite"),
             ], required: ["workflow", "step", "max_visits"])),
        Tool(name: "remove_workflow_step", description: "Remove uma etapa e as transições para ela.",
             inputSchema: schema([
                 "workflow": ("string", ""),
                 "step": ("string", "Id ou posição"),
             ], required: ["workflow", "step"])),
        Tool(name: "move_workflow_step", description: "Move uma etapa (1 = início).",
             inputSchema: schema([
                 "workflow": ("string", ""),
                 "step": ("string", "Id ou posição"),
                 "position": ("integer", ""),
             ], required: ["workflow", "step", "position"])),
        Tool(name: "add_workflow_transition", description: "Depois de `from`, vá para `to` quando o veredito for `verdict` ou `when` valer; sem ambos é o senão (um por etapa). Ordem: vereditos, condições, senão; nenhuma = fim.",
             inputSchema: schema([
                 "workflow": ("string", ""),
                 "from": ("string", "Id ou posição"),
                 "to": ("string", "Id ou posição"),
                 "verdict": ("string", "Ex.: APROVADO; ignora caixa e acentos"),
                 "when": ("string", "Condição em linguagem natural"),
             ], required: ["workflow", "from", "to"])),
        Tool(name: "remove_workflow_transition", description: "Remove a transição `index` (1, 2, …) de uma etapa.",
             inputSchema: schema([
                 "workflow": ("string", ""),
                 "from": ("string", "Id ou posição"),
                 "index": ("integer", ""),
             ], required: ["workflow", "from", "index"])),
        Tool(name: "workflow_flow", description: "JSON do workflow para orquestrar; siga as `rules` dele.",
             inputSchema: schema([
                 "workflow": ("string", ""),
                 "input": ("string", "Sem ela, pergunte ao usuário"),
             ], required: ["workflow"]), annotations: .init(readOnlyHint: true)),
        Tool(name: "workflow_run_start", description: "Inicia ou retoma uma execução e devolve {ref, action, prompt}: siga o `prompt` (etapas em subagentes). `from` libera mais uma volta numa execução parada.",
             inputSchema: schema(["provider": provider,
                 "workflow": ("string", ""),
                 "input": ("string", "Nomeia a execução"),
                 "from": ("string", "Etapa inicial"),
             ], required: ["workflow"])),
        Tool(name: "workflow_run_next", description: "Próxima ação: run-step, ask, decide, done ou stop.",
             inputSchema: schema(["run": run], required: ["run"]),
             annotations: .init(readOnlyHint: true)),
        Tool(name: "workflow_run_step", description: "Prompt da etapa atual, para o subagente que a executa.",
             inputSchema: schema(["run": run], required: ["run"]),
             annotations: .init(readOnlyHint: true)),
        Tool(name: "workflow_run_record", description: "Registra o veredito da etapa e devolve a próxima ação. Em `decide`, avalie os `candidates` e chame de novo com `to` ou `none_holds`.",
             inputSchema: schema([
                 "run": run,
                 "verdict": ("string", "Última linha do resultado"),
                 "summary": ("string", "1 a 3 linhas"),
                 "to": ("string", ""),
                 "none_holds": ("boolean", ""),
             ], required: ["run"])),
        Tool(name: "workflow_run_ask", description: "Grava perguntas da etapa para o usuário; termine a etapa com a última linha PERGUNTA.",
             inputSchema: schema(["run": run], required: ["run", "questions"], custom: ["questions": questionsSchema])),
        Tool(name: "workflow_run_questions", description: "Perguntas de uma execução.",
             inputSchema: schema([
                 "run": run,
                 "open": ("boolean", "Só as abertas"),
             ], required: ["run"]), annotations: .init(readOnlyHint: true)),
        Tool(name: "workflow_run_answer", description: "Grava a resposta do usuário (opções separadas por \"; \" ou texto) e devolve a próxima ação.",
             inputSchema: schema([
                 "run": run,
                 "number": ("integer", ""),
                 "answer": ("string", ""),
             ], required: ["run", "number", "answer"])),
        Tool(name: "workflow_run_list", description: "Execuções, mais recentes primeiro.",
             inputSchema: schema([
                 "workflow": ("string", ""),
                 "status": ("string", ""),
             ], enums: ["status": WorkflowRunStatus.allCases.map(\.rawValue)]), annotations: .init(readOnlyHint: true)),
        Tool(name: "workflow_run_show", description: "Execução completa: status, histórico e perguntas.",
             inputSchema: schema(["run": run], required: ["run"]),
             annotations: .init(readOnlyHint: true)),
        Tool(name: "workflow_run_stop", description: "Para uma execução. Só a pedido do usuário.",
             inputSchema: schema([
                 "run": run,
                 "reason": ("string", ""),
             ], required: ["run"])),
        Tool(name: "set_tags", description: "Substitui as tags de um registro (lista vazia remove).",
             inputSchema: schema([
                 "kind": ("string", ""),
                 "ref": ("string", ""),
                 "tags": ("array", ""),
             ], required: ["kind", "ref", "tags"], enums: ["kind": ["doc", "review_group", "rule_topic", "idea", "agent", "command", "skill", "workflow", "stack", "pattern"]])),
        Tool(name: "promote_idea", description: "Transforma as regras da ideia num tópico ativo. Só faça isso quando o usuário pedir.",
             inputSchema: schema(["idea": ("string", "")], required: ["idea"])),
        Tool(name: "unpromote_idea", description: "Desfaz promote_idea (apaga o tópico; regras voltam a rascunho). Só faça isso quando o usuário pedir.",
             inputSchema: schema(["idea": ("string", "")], required: ["idea"])),
    ]

    // MARK: Tool calls

    func call(_ name: String, _ args: [String: Value]) async throws -> String {
        func str(_ key: String) -> String? { args[key]?.stringValue.flatMap { $0.isEmpty ? nil : $0 } }
        func req(_ key: String) throws -> String {
            guard let v = str(key) else { throw MCPError.invalidParams("Parâmetro obrigatório: \(key)") }
            return v
        }
        /// String arrays may arrive as a JSON array, a JSON-encoded string, or comma-separated text.
        func list(_ key: String) -> [String]? {
            guard let value = args[key] else { return nil }
            if let array = value.arrayValue { return array.compactMap(\.stringValue).filter { !$0.isEmpty } }
            guard let text = value.stringValue else { return nil }
            if let data = text.data(using: .utf8), let parsed = try? JSONDecoder().decode([String].self, from: data) { return parsed }
            return text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        /// Integers may arrive as JSON numbers or as text.
        func int(_ key: String) -> Int? {
            args[key]?.intValue ?? args[key]?.doubleValue.map { Int($0) } ?? str(key).flatMap { Int($0) }
        }
        func severity() throws -> RuleSeverity {
            guard let s = str("severity") else { return .must }
            guard let v = RuleSeverity(rawValue: s) else { throw MCPError.invalidParams("Severidade inválida: \(s)") }
            return v
        }

        func selectedProvider() throws -> AIProvider {
            guard let value = str("provider") else { return .claude }
            guard let provider = AIProvider(rawValue: value) else { throw MCPError.invalidParams("Provedor inválido: \(value)") }
            return provider
        }
        func providerSettings() throws -> [String: AIProviderSettings]? {
            guard let value = args["provider_settings"] else { return nil }
            let parsed = try JSONDecoder().decode([String: AIProviderSettings].self, from: JSONEncoder().encode(value))
            guard parsed.keys.allSatisfy({ AIProvider(rawValue: $0) != nil }) else { throw MCPError.invalidParams("Provedor inválido em provider_settings") }
            return parsed
        }
        switch name {
        case "codex_usage": return try json(await CodexQueries.limits(root: store.root))
        case "ai_guide":
            if let n = args["section"]?.intValue {
                guard let section = AgentsGuide.section(n) else { throw MCPError.invalidParams("Seção inexistente.") }
                return section
            }
            return AgentsGuide.index
        case "ai_catalog":
            return try json(store.aiCatalog(kind: req("kind"), offset: args["offset"]?.intValue ?? 0, limit: args["limit"]?.intValue ?? 20))
        case "ai_context":
            return try json(AIContextStore(root: store.root).page(id: req("id"), offset: args["offset"]?.intValue ?? 0, limit: args["limit"]?.intValue ?? 4000))
        case "ai_usage":
            let usage = AIUsageStore(root: store.root)
            if args["clear"]?.boolValue == true { try usage.clear(); return "Métricas locais apagadas." }
            return try json(usage.list())

        case "export_graph":
            let graph = try ProjectGraph.load(root: store.root)
            try GraphHTML.write(graph, root: store.root, output: store.root.appending(path: "graphify-out/graph.html"))
            return "Visualização offline exportada em graphify-out/graph.html"

        case "get_project":
            let groups = try store.listGroups().map { ["slug": $0.slug, "title": $0.group.title, "open": "\($0.group.openCount)", "total": "\($0.group.items.count)"] }
            return try json(ProjectSummary(root: store.root.path, project: store.loadProject(), docs: store.listDocs().map(\.slug), groups: groups))

        case "list_docs":
            return try json(store.listDocs().map { DocRow(slug: $0.slug, title: $0.title, tags: $0.tags) })

        case "read_doc":
            return try store.readDoc(req("slug"))

        case "write_doc":
            let content = try req("content")
            if args["generated"]?.boolValue == true {
                let slug = try store.createGeneratedDoc(title: req("title"), body: content)
                return "Criado: \(slug)"
            }
            if let slug = str("slug") {
                try store.writeDoc(slug, content)
                return "Salvo: \(slug)"
            }
            let slug = try store.createDoc(title: req("title"))
            try store.writeDoc(slug, content)
            return "Criado: \(slug)"

        case "list_review_groups":
            return try json(store.listGroups().map {
                GroupRow(slug: $0.slug, title: $0.group.title, description: $0.group.description, tags: $0.group.tags, open: $0.group.openCount, total: $0.group.items.count)
            })

        case "list_review_items":
            var groups = try store.listGroups()
            if let g = str("group") { let slug = try store.resolveGroupSlug(g); groups = groups.filter { $0.slug == slug } }
            let status = str("status").flatMap(ReviewStatus.init(rawValue:))
            let kind = str("kind")
            let rows = groups.flatMap { g in
                g.group.items
                    .filter { status == nil || $0.status == status }
                    .filter { kind == nil || $0.kind == kind }
                    .map { ItemRow(group: g.slug, item: $0) }
            }
            return try json(rows)

        case "add_review_item":
            let kind = try req("kind")
            let kinds = try store.loadProject().reviewKinds.map(\.id)
            guard kinds.contains(kind) else { throw MCPError.invalidParams("Kind desconhecido '\(kind)'. Disponíveis: \(kinds.joined(separator: ", "))") }
            let item = ReviewItem(
                kind: kind, title: try req("title"), details: str("details"),
                priority: str("priority").flatMap(ReviewPriority.init(rawValue:)) ?? .normal,
                target: ReviewTarget(file: str("file"), route: str("route"), component: str("component"), selector: str("selector")),
                rules: try (list("rules") ?? []).map { try store.resolveTopicSlug($0) },
                author: .ai
            )
            let (slug, saved) = try store.addItem(item, toGroup: req("group"))
            return try json(ItemRow(group: slug, item: saved))

        case "update_review_item":
            let id = try req("id")
            let rules = try list("rules")?.map { try store.resolveTopicSlug($0) }
            if let rules { try store.updateItem(id) { $0.rules = rules } }
            if str("status") == ReviewStatus.done.rawValue { try store.ensureVerified(id) }
            if let k = str("kind") {
                let kinds = try store.loadProject().reviewKinds.map(\.id)
                guard kinds.contains(k) else { throw MCPError.invalidParams("Kind desconhecido '\(k)'. Disponíveis: \(kinds.joined(separator: ", "))") }
            }
            let item = try store.updateItem(id) { item in
                if let s = str("status") {
                    guard let status = ReviewStatus(rawValue: s) else { throw MCPError.invalidParams("Status inválido: \(s)") }
                    item.status = status
                }
                if let p = str("priority").flatMap(ReviewPriority.init(rawValue:)) { item.priority = p }
                if let t = str("title") { item.title = t }
                if let d = str("details") { item.details = d }
                if let k = str("kind") { item.kind = k }
            }
            return try json(item)

        case "add_link":
            let url = try req("url")
            let tags = list("tags") ?? []
            let link = Link(title: str("title") ?? url, url: url, tags: tags)
            try store.updateProject { $0.links.append(link) }
            return try json(link)

        case "list_stack":
            let stack = try store.loadProject().stack
            let badge = stack.isEmpty ? nil : try? await stackService.badge()
            return try json(StackListing(stack: stack, badge: badge?.url))

        case "search_stack_icons":
            let icons = try await SkillIcons().search(query: str("query"), category: str("category"), limit: int("limit"))
            let current = Set(try store.loadProject().stack.map(\.icon))
            return try json(icons.map { IconRow(icon: $0, inStack: current.contains($0.id)) })

        case "add_stack":
            guard let icons = list("icons"), !icons.isEmpty else { throw MCPError.invalidParams("Parâmetro obrigatório: icons") }
            return try json(await stackService.add(icons, note: args["note"]?.stringValue, author: .ai))

        case "remove_stack":
            guard let icons = list("icons"), !icons.isEmpty else { throw MCPError.invalidParams("Parâmetro obrigatório: icons") }
            return try json(await stackService.remove(icons))

        case "update_stack":
            let icon = try req("icon")
            var change: StackService.Change?
            if let note = args["note"]?.stringValue { change = try await stackService.setNote(icon, note) }
            if let position = int("position") { change = try await stackService.move(icon, to: position) }
            guard let change else { throw MCPError.invalidParams("Informe note ou position.") }
            return try json(change)

        case "list_patterns":
            return try json(PatternListing(store: store))

        case "pattern_catalog":
            let current = Set(try store.loadProject().patterns.map(\.id))
            return try json(PatternCatalog.search(str("query")).map { CatalogRow(template: $0, inProject: current.contains($0.id)) })

        case "add_pattern":
            let paths = list("paths")
            if let name = str("name") {
                guard let rules = list("rules"), !rules.isEmpty else { throw MCPError.invalidParams("Padrão personalizado precisa de rules.") }
                try store.addCustomPattern(name: name, summary: str("summary"), rules: rules, note: str("note"), paths: paths, author: .ai)
            } else {
                guard let refs = list("patterns"), !refs.isEmpty else { throw MCPError.invalidParams("Informe patterns (catálogo) ou name + rules.") }
                try store.addPatterns(refs, note: str("note"), paths: paths, author: .ai)
            }
            return try json(PatternListing(store: store))

        case "remove_pattern":
            guard let refs = list("patterns"), !refs.isEmpty else { throw MCPError.invalidParams("Parâmetro obrigatório: patterns") }
            try store.removePatterns(refs)
            return try json(PatternListing(store: store))

        case "update_pattern":
            let ref = try req("pattern")
            guard args["note"] != nil || args["paths"] != nil || int("position") != nil else {
                throw MCPError.invalidParams("Informe note, paths ou position.")
            }
            if let note = args["note"]?.stringValue { try store.setPatternNote(ref, note) }
            if args["paths"] != nil { try store.setPatternPaths(ref, list("paths") ?? []) }
            if let position = int("position") { try store.movePattern(ref, to: position) }
            return try json(PatternListing(store: store))

        case "rules_for":
            var files = list("files") ?? []
            var topics = list("topics") ?? []
            if let ref = str("review_item") {
                let (_, group, index) = try store.findItem(ref)
                topics += group.items[index].rules
                if let file = group.items[index].target?.file { files.append(file) }
            }
            let applicable = try store.applicableTopics(files: files, explicit: topics)
            if applicable.allSatisfy({ $0.topic.rules.isEmpty }) {
                return "Nenhuma regra aplicável a esses arquivos. Mesmo assim, chame submit_rule_check com results=[] para registrar a tarefa."
            }
            let includeManual = args["include_manual"]?.boolValue ?? false
            if args["verbose"]?.boolValue == true {
                return try json(applicable.map { TopicChecklist(slug: $0.slug, topic: $0.topic, includeManual: includeManual) })
            }
            return try TopicChecklist.compactJSON(TopicChecklist.compact(applicable, includeManual: includeManual))

        case "submit_rule_check":
            var answers: [RuleAnswer] = []
            if let raw = args["results"] {
                do {
                    let data = try raw.stringValue.map { Data($0.utf8) } ?? JSONEncoder().encode(raw)
                    answers = try JSONDecoder().decode([RuleAnswer].self, from: data)
                } catch {
                    throw MCPError.invalidParams("results deve ser uma lista de {ruleId, verdict: pass|fail|na, note}.")
                }
            }
            let check = try store.submitCheck(
                task: req("task"), files: list("files") ?? [], topics: list("topics") ?? [],
                reviewItem: str("review_item"), answers: answers, verifyManual: args["verify_manual"]?.boolValue ?? false, author: .ai
            )
            return try check.agentSummary(verbose: args["verbose"]?.boolValue ?? false)

        case "run_rule_tests":
            let files = list("files") ?? []
            let item = str("review_item")
            let runs = try store.runRuleTests(files: files, topics: list("topics") ?? [], reviewItem: item, onlyTopics: files.isEmpty && item == nil)
            if runs.isEmpty { return "Nenhuma regra aplicável tem script." }
            return try json(runs.map(RuleTestRunRow.init))

        case "set_rule_test":
            guard let mode = RuleTestMode(rawValue: try req("mode")) else { throw MCPError.invalidParams("mode deve ser script ou manual.") }
            let rule = try store.setRuleTest(req("rule_id"), mode: mode, command: str("command"), reason: str("reason"))
            return "Regra \(rule.id.uuidString.prefix(8)): \(rule.testState.label)."

        case "list_rule_topics":
            return try json(store.listTopics().map {
                TopicRow(slug: $0.slug, title: $0.topic.title, description: $0.topic.description, tags: $0.topic.tags, paths: $0.topic.paths, rules: $0.topic.rules.count)
            })

        case "get_rule_topic":
            let slug = try store.resolveTopicSlug(req("topic"))
            return try json(TopicChecklist(slug: slug, topic: store.loadTopic(slug)))

        case "add_rule_topic":
            let (slug, topic) = try store.createTopic(title: req("title"), description: str("description"), tags: list("tags") ?? [], paths: list("paths") ?? [])
            return try json(TopicChecklist(slug: slug, topic: topic))

        case "set_tags":
            let tags = list("tags") ?? []
            let ref = try req("ref")
            switch try req("kind") {
            case "doc": try store.setDocTags(ref, tags)
            case "review_group": try store.updateGroup(ref) { $0.tags = tags }
            case "rule_topic": try store.updateTopic(ref) { $0.tags = tags }
            case "idea": try store.updateIdea(ref) { $0.tags = tags }
            case "agent": try store.updateAgent(ref) { $0.tags = tags }
            case "command": try store.updateCommand(ref) { $0.tags = tags }
            case "skill": try store.updateSkill(ref) { $0.tags = tags }
            case "workflow": try store.updateWorkflow(ref) { $0.tags = tags }
            case "stack": try store.setStackTags(ref, tags)
            case "pattern": try store.setPatternTags(ref, tags)
            case let other: throw MCPError.invalidParams("Tipo inválido: \(other)")
            }
            return tags.isEmpty ? "Tags removidas." : "Tags: " + tags.joined(separator: ", ")

        case "add_rule":
            let rule = Rule(text: try req("text"), details: str("details"), severity: try severity(), author: .ai)
            let (slug, saved) = try store.addRule(rule, toTopic: req("topic"))
            return try json(["topic": slug, "ruleId": saved.id.uuidString, "text": saved.text])

        case "list_ideas":
            let status = str("status").flatMap(IdeaStatus.init(rawValue:))
            return try json(store.listIdeas().filter { status == nil || $0.idea.status == status }.map {
                IdeaRow(slug: $0.slug, title: $0.idea.title, status: $0.idea.status, tags: $0.idea.tags, rules: $0.idea.rules.count, promotedTopic: $0.idea.promotedTopic)
            })

        case "get_idea":
            let slug = try store.resolveIdeaSlug(req("idea"))
            return try json(SlugAnd(slug: slug, value: store.loadIdea(slug)))

        case "add_idea":
            let (slug, idea) = try store.createIdea(title: req("title"), body: str("body"), tags: list("tags") ?? [], author: .ai)
            return try json(SlugAnd(slug: slug, value: idea))

        case "update_idea":
            let status = try str("status").map { s in
                guard let v = IdeaStatus(rawValue: s) else { throw MCPError.invalidParams("Status inválido: \(s)") }
                return v
            }
            let tags = list("tags")
            let (slug, idea) = try store.updateIdea(req("idea")) { idea in
                if let t = str("title") { idea.title = t }
                if let b = str("body") { idea.body = b }
                if let status { idea.status = status }
                if let tags { idea.tags = tags }
            }
            return try json(SlugAnd(slug: slug, value: idea))

        case "add_idea_rule":
            let rule = Rule(text: try req("text"), details: str("details"), severity: try severity(), author: .ai)
            let (slug, saved) = try store.addRule(rule, toIdea: req("idea"))
            return try json(["idea": slug, "ruleId": saved.id.uuidString, "text": saved.text])

        case "claude_usage":
            guard let usage = ClaudeCode.loadUsage() else {
                return "Nenhum uso registrado. O usuário precisa ligar a statusline com `vibedeck usage install`."
            }
            return try json(usage)

        case "cloud_check":
            return try json(CloudSession.check(root: store.root))

        case "start_cloud_session":
            let result = try CloudSession.launch(root: store.root, description: try req("description"), allowDirty: args["allow_dirty"]?.boolValue ?? false, provider: try selectedProvider(), environment: str("environment"))
            return try json(CloudStart(sync: result.sync, url: result.url?.absoluteString, output: result.output))

        case "list_agents":
            return try json(store.listAgents().map {
                AgentRow(slug: $0.slug, title: $0.agent.title, model: $0.agent.model, tags: $0.agent.tags, nextSteps: $0.agent.nextSteps)
            })

        case "get_agent":
            let slug = try store.resolveAgentSlug(req("agent"))
            return try json(SlugAnd(slug: slug, value: store.loadAgent(slug)))

        case "add_agent":
            let (slug, agent) = try store.createAgent(
                title: req("title"), summary: str("summary"), model: str("model"), tools: list("tools") ?? [],
                prompt: str("prompt") ?? "", tags: list("tags") ?? [], author: .ai)
            if let settings = try providerSettings() {
                _ = try store.updateAgent(slug) { $0.providerSettings = settings }
                return try json(SlugAnd(slug: slug, value: store.loadAgent(slug)))
            }
            return try json(SlugAnd(slug: slug, value: agent))

        case "update_agent":
            let overrides = try providerSettings()
            let tags = list("tags"), tools = list("tools")
            let (slug, agent) = try store.updateAgent(req("agent")) { a in
                if let overrides { a.providerSettings = overrides }
                if let t = str("title") { a.title = t }
                if let v = str("summary") { a.summary = v }
                if let v = str("model") { a.model = v }
                if let v = str("prompt") { a.prompt = v }
                if let tools { a.tools = tools }
                if let tags { a.tags = tags }
            }
            return try json(SlugAnd(slug: slug, value: agent))

        case "add_agent_next_step":
            let kind = try str("kind").map { k in
                guard let v = NextStepKind(rawValue: k) else { throw MCPError.invalidParams("Tipo inválido: \(k)") }
                return v
            } ?? .agent
            let (slug, agent) = try store.addNextStep(to: req("agent"), kind: kind, target: req("target"), note: str("note"))
            return try json(SlugAnd(slug: slug, value: agent))

        case "agent_flow":
            let slug = try store.resolveAgentSlug(req("agent"))
            return try AgentFlow.json(from: slug, agents: store.listAgents(), commands: store.listCommands(), skills: store.listSkills()) ?? ""

        case "import_agents":
            let result = try store.importAgents(provider: try selectedProvider(), overwrite: args["overwrite"]?.boolValue ?? false, author: .ai)
            return try selectedProvider() == .claude ? json(result.slugs) : json(ImportReport(slugs: result.slugs, warnings: result.warnings))

        case "list_commands":
            return try json(store.listCommands().map {
                CommandRow(slug: $0.slug, title: $0.command.title, argumentHint: $0.command.argumentHint, model: $0.command.model,
                           tags: $0.command.tags, nextSteps: $0.command.nextSteps)
            })

        case "get_command":
            let slug = try store.resolveCommandSlug(req("command"))
            return try json(SlugAnd(slug: slug, value: store.loadCommand(slug)))

        case "add_command":
            let (slug, command) = try store.createCommand(
                title: req("title"), summary: str("summary"), argumentHint: str("argument_hint"), model: str("model"),
                tools: list("tools") ?? [], prompt: str("prompt") ?? "", tags: list("tags") ?? [], author: .ai)
            if let settings = try providerSettings() {
                _ = try store.updateCommand(slug) { $0.providerSettings = settings }
                return try json(SlugAnd(slug: slug, value: store.loadCommand(slug)))
            }
            return try json(SlugAnd(slug: slug, value: command))

        case "update_command":
            let overrides = try providerSettings()
            let tags = list("tags"), tools = list("tools")
            let (slug, command) = try store.updateCommand(req("command")) { c in
                if let overrides { c.providerSettings = overrides }
                if let t = str("title") { c.title = t }
                if let v = str("summary") { c.summary = v }
                if let v = str("argument_hint") { c.argumentHint = v }
                if let v = str("model") { c.model = v }
                if let v = str("prompt") { c.prompt = v }
                if let tools { c.tools = tools }
                if let tags { c.tags = tags }
            }
            return try json(SlugAnd(slug: slug, value: command))

        case "add_command_next_step":
            let kind = try str("kind").map { k in
                guard let v = NextStepKind(rawValue: k) else { throw MCPError.invalidParams("Tipo inválido: \(k)") }
                return v
            } ?? .agent
            let (slug, command) = try store.addCommandNextStep(to: req("command"), kind: kind, target: req("target"), note: str("note"))
            return try json(SlugAnd(slug: slug, value: command))

        case "command_flow":
            let slug = try store.resolveCommandSlug(req("command"))
            return try AgentFlow.json(kind: .command, from: slug, agents: store.listAgents(), commands: store.listCommands(), skills: store.listSkills()) ?? ""

        case "import_commands":
            let result = try store.importCommands(provider: try selectedProvider(), overwrite: args["overwrite"]?.boolValue ?? false, author: .ai)
            return try selectedProvider() == .claude ? json(result.slugs) : json(ImportReport(slugs: result.slugs, warnings: result.warnings))

        case "list_skills":
            return try json(store.listSkills().map {
                SkillRow(slug: $0.slug, title: $0.skill.title, summary: $0.skill.summary, model: $0.skill.model, tags: $0.skill.tags, nextSteps: $0.skill.nextSteps)
            })

        case "get_skill":
            let slug = try store.resolveSkillSlug(req("skill"))
            return try json(SlugAnd(slug: slug, value: store.loadSkill(slug)))

        case "add_skill":
            let (slug, skill) = try store.createSkill(
                title: req("title"), summary: str("summary"), model: str("model"), tools: list("tools") ?? [],
                prompt: str("prompt") ?? "", tags: list("tags") ?? [], author: .ai)
            if let settings = try providerSettings() {
                _ = try store.updateSkill(slug) { $0.providerSettings = settings }
                return try json(SlugAnd(slug: slug, value: store.loadSkill(slug)))
            }
            return try json(SlugAnd(slug: slug, value: skill))

        case "update_skill":
            let overrides = try providerSettings()
            let tags = list("tags"), tools = list("tools")
            let (slug, skill) = try store.updateSkill(req("skill")) { s in
                if let overrides { s.providerSettings = overrides }
                if let t = str("title") { s.title = t }
                if let v = str("summary") { s.summary = v }
                if let v = str("model") { s.model = v }
                if let v = str("prompt") { s.prompt = v }
                if let tools { s.tools = tools }
                if let tags { s.tags = tags }
            }
            return try json(SlugAnd(slug: slug, value: skill))

        case "add_skill_next_step":
            let kind = try str("kind").map { k in
                guard let v = NextStepKind(rawValue: k) else { throw MCPError.invalidParams("Tipo inválido: \(k)") }
                return v
            } ?? .agent
            let (slug, skill) = try store.addSkillNextStep(to: req("skill"), kind: kind, target: req("target"), note: str("note"))
            return try json(SlugAnd(slug: slug, value: skill))

        case "skill_flow":
            let slug = try store.resolveSkillSlug(req("skill"))
            return try AgentFlow.json(kind: .skill, from: slug, agents: store.listAgents(), commands: store.listCommands(), skills: store.listSkills()) ?? ""

        case "import_skills":
            let result = try await store.importSkills(provider: try selectedProvider(), overwrite: args["overwrite"]?.boolValue ?? false, author: .ai)
            return try selectedProvider() == .claude ? json(result.slugs) : json(ImportReport(slugs: result.slugs, warnings: result.warnings))

        case "list_workflows":
            return try json(store.listWorkflows().map {
                WorkflowRow(slug: $0.slug, title: $0.workflow.title, summary: $0.workflow.summary, input: $0.workflow.input,
                            tags: $0.workflow.tags, steps: $0.workflow.steps.map(\.id))
            })

        case "get_workflow":
            let slug = try store.resolveWorkflowSlug(req("workflow"))
            return try json(SlugAnd(slug: slug, value: store.loadWorkflow(slug)))

        case "add_workflow":
            let (slug, workflow) = try store.createWorkflow(
                title: req("title"), summary: str("summary"), input: str("input"), maxSteps: int("max_steps").flatMap { $0 > 0 ? $0 : nil },
                tags: list("tags") ?? [], author: .ai)
            return try json(SlugAnd(slug: slug, value: workflow))

        case "update_workflow":
            let tags = list("tags"), maxSteps = int("max_steps")
            let (slug, workflow) = try store.updateWorkflow(req("workflow")) { w in
                if let t = str("title") { w.title = t }
                if let v = str("summary") { w.summary = v }
                if let v = str("input") { w.input = v }
                if let maxSteps { w.maxSteps = maxSteps > 0 ? maxSteps : nil }
                if let tags { w.tags = tags }
            }
            return try json(SlugAnd(slug: slug, value: workflow))

        case "add_workflow_step":
            let kind = try str("kind").map { k in
                guard let v = NextStepKind(rawValue: k) else { throw MCPError.invalidParams("Tipo inválido: \(k)") }
                return v
            } ?? .agent
            var (slug, workflow, step) = try store.addWorkflowStep(to: req("workflow"), kind: kind, target: req("target"), note: str("note"))
            if let visits = int("max_visits") { (slug, workflow) = try store.setWorkflowStepMaxVisits(slug, step: step, maxVisits: visits) }
            return try json(WorkflowStepAdded(slug: slug, step: step, workflow: workflow))

        case "set_workflow_step_max_visits":
            guard let visits = int("max_visits") else { throw MCPError.invalidParams("Parâmetro obrigatório: max_visits") }
            let (slug, workflow) = try store.setWorkflowStepMaxVisits(req("workflow"), step: req("step"), maxVisits: visits)
            return try json(SlugAnd(slug: slug, value: workflow))

        case "remove_workflow_step":
            let (slug, workflow) = try store.removeWorkflowStep(req("workflow"), step: req("step"))
            return try json(SlugAnd(slug: slug, value: workflow))

        case "move_workflow_step":
            guard let position = int("position") else { throw MCPError.invalidParams("Parâmetro obrigatório: position") }
            let (slug, workflow) = try store.moveWorkflowStep(req("workflow"), step: req("step"), to: position)
            return try json(SlugAnd(slug: slug, value: workflow))

        case "add_workflow_transition":
            let (slug, workflow) = try store.addWorkflowTransition(req("workflow"), from: req("from"), to: req("to"), when: str("when"), verdict: str("verdict"))
            return try json(SlugAnd(slug: slug, value: workflow))

        case "remove_workflow_transition":
            guard let index = int("index") else { throw MCPError.invalidParams("Parâmetro obrigatório: index") }
            let (slug, workflow) = try store.removeWorkflowTransition(req("workflow"), from: req("from"), index: index)
            return try json(SlugAnd(slug: slug, value: workflow))

        case "workflow_flow":
            return try store.workflowPlan(req("workflow"), input: str("input")).json()

        case "workflow_run_start":
            let (ref, run, action) = try store.startRun(req("workflow"), input: str("input"), from: str("from"), provider: str("provider") == nil ? nil : try selectedProvider())
            let title = (try? store.loadWorkflow(run.workflow).title) ?? run.workflow
            return try json(RunStarted(ref: ref, action: action, prompt: WorkflowOrchestration.orchestratorPrompt(ref: ref, title: title, input: run.input, provider: run.provider)))

        case "workflow_run_next":
            return try json(store.nextRunAction(req("run")))

        case "workflow_run_step":
            return try store.runStepPrompt(req("run"))

        case "workflow_run_record":
            return try json(store.recordRun(
                req("run"), verdict: str("verdict"), summary: str("summary"), to: str("to"), noneHolds: args["none_holds"]?.boolValue ?? false
            ))

        case "workflow_run_ask":
            guard let raw = args["questions"] else { throw MCPError.invalidParams("Parâmetro obrigatório: questions") }
            let drafts: [WorkflowQuestionDraft]
            do {
                let data = try raw.stringValue.map { Data($0.utf8) } ?? JSONEncoder().encode(raw)
                drafts = try JSONDecoder().decode([WorkflowQuestionDraft].self, from: data)
            } catch {
                throw MCPError.invalidParams("questions deve ser uma lista de {question, context, options: [{label, description}], multiple}.")
            }
            let added = try store.askRun(req("run"), questions: drafts)
            return "Pergunta(s) gravada(s): \(added.map { String($0.number) }.joined(separator: ", ")). Termine a etapa com a última linha: PERGUNTA"

        case "workflow_run_questions":
            let run = try store.loadRun(store.resolveRunRef(req("run")))
            return try json((args["open"]?.boolValue ?? false) ? run.openQuestions : run.questions)

        case "workflow_run_answer":
            guard let number = int("number") else { throw MCPError.invalidParams("Parâmetro obrigatório: number") }
            return try json(store.answerRun(req("run"), number: number, answer: req("answer")))

        case "workflow_run_list":
            let status = str("status").flatMap(WorkflowRunStatus.init(rawValue:))
            return try json(store.listRuns(workflow: str("workflow")).filter { status == nil || $0.run.status == status }.map {
                RunRow(ref: $0.ref, workflow: $0.run.workflow, input: $0.run.input, status: $0.run.status, current: $0.run.current,
                       steps: $0.run.history.count, openQuestions: $0.run.openQuestions.count, updatedAt: $0.run.updatedAt)
            })

        case "workflow_run_show":
            return try json(store.loadRun(store.resolveRunRef(req("run"))))

        case "workflow_run_stop":
            return try json(store.stopRun(req("run"), reason: str("reason")))

        case "promote_idea":
            let stale = try store.unmatchedIdeaPaths(req("idea"))
            let topic = try store.promoteIdea(req("idea"))
            return "Ideia promovida para o tópico de regras: \(topic)"
                + (stale.isEmpty ? "" : "\nAviso: globs da ideia que não casam nenhum arquivo foram copiados: \(stale.joined(separator: ", "))")

        case "unpromote_idea":
            let ref = try req("idea")
            guard try store.loadIdea(store.resolveIdeaSlug(ref)).promotedTopic != nil else { return "A ideia não estava promovida." }
            let topic = try store.unpromoteIdea(ref)
            return topic.map { "Ideia despromovida; tópico removido: \($0)" } ?? "Ideia despromovida (o tópico já não existia)."

        default:
            throw MCPError.methodNotFound("Tool desconhecida: \(name)")
        }
    }

    // MARK: Resources

    func resources() throws -> [Resource] {
        var list = [Resource(name: "vibedeck.json", uri: "vibedeck://project", description: "Manifesto do projeto", mimeType: "application/json")]
        list.append(Resource(name: "Stack", uri: "vibedeck://stack", description: "Tecnologias de destaque do projeto", mimeType: "application/json"))
        list.append(Resource(name: "Padrões", uri: "vibedeck://patterns", description: "Padrões de projeto que o código deve seguir", mimeType: "application/json"))
        list += try store.listDocs().map { Resource(name: $0.title, uri: "vibedeck://docs/\($0.slug)", mimeType: "text/markdown") }
        list += try store.listGroups().map {
            Resource(name: "Revisão: \($0.group.title)", uri: "vibedeck://reviews/\($0.slug)", description: "\($0.group.openCount) aberto(s)", mimeType: "application/json")
        }
        list += try store.listTopics().map {
            Resource(name: "Regras: \($0.topic.title)", uri: "vibedeck://rules/\($0.slug)", description: "\($0.topic.rules.count) regra(s)", mimeType: "application/json")
        }
        list += try store.listIdeas().map {
            Resource(name: "Ideia: \($0.idea.title)", uri: "vibedeck://ideas/\($0.slug)", description: $0.idea.status.label, mimeType: "application/json")
        }
        list += try store.listAgents().map {
            Resource(name: "Agente: \($0.agent.title)", uri: "vibedeck://agents/\($0.slug)", description: $0.agent.model, mimeType: "application/json")
        }
        list += try store.listCommands().map {
            Resource(name: "Comando: \($0.command.title)", uri: "vibedeck://commands/\($0.slug)", description: $0.command.summary, mimeType: "application/json")
        }
        list += try store.listSkills().map {
            Resource(name: "Skill: \($0.skill.title)", uri: "vibedeck://skills/\($0.slug)", description: $0.skill.summary, mimeType: "application/json")
        }
        list += try store.listWorkflows().map {
            Resource(name: "Workflow: \($0.workflow.title)", uri: "vibedeck://workflows/\($0.slug)", description: $0.workflow.summary, mimeType: "application/json")
        }
        return list
    }

    func read(_ uri: String) throws -> Resource.Content {
        if uri == "vibedeck://project" {
            return .text(try String(contentsOf: store.manifestURL, encoding: .utf8), uri: uri, mimeType: "application/json")
        }
        if uri == "vibedeck://patterns" {
            return .text(try json(PatternListing(store: store)), uri: uri, mimeType: "application/json")
        }
        if uri == "vibedeck://stack" {
            return .text(try json(store.loadProject().stack), uri: uri, mimeType: "application/json")
        }
        if let slug = uri.stripping("vibedeck://docs/") {
            return .text(try store.readDoc(slug), uri: uri, mimeType: "text/markdown")
        }
        if let slug = uri.stripping("vibedeck://reviews/") {
            return .text(try String(contentsOf: store.groupURL(slug), encoding: .utf8), uri: uri, mimeType: "application/json")
        }
        if let slug = uri.stripping("vibedeck://rules/") {
            return .text(try String(contentsOf: store.topicURL(slug), encoding: .utf8), uri: uri, mimeType: "application/json")
        }
        if let slug = uri.stripping("vibedeck://ideas/") {
            return .text(try String(contentsOf: store.ideaURL(slug), encoding: .utf8), uri: uri, mimeType: "application/json")
        }
        if let slug = uri.stripping("vibedeck://agents/") {
            return .text(try String(contentsOf: store.agentURL(slug), encoding: .utf8), uri: uri, mimeType: "application/json")
        }
        if let slug = uri.stripping("vibedeck://commands/") {
            return .text(try String(contentsOf: store.commandURL(slug), encoding: .utf8), uri: uri, mimeType: "application/json")
        }
        if let slug = uri.stripping("vibedeck://skills/") {
            return .text(try String(contentsOf: store.skillURL(slug), encoding: .utf8), uri: uri, mimeType: "application/json")
        }
        if let slug = uri.stripping("vibedeck://workflows/") {
            return .text(try String(contentsOf: store.workflowURL(slug), encoding: .utf8), uri: uri, mimeType: "application/json")
        }
        throw MCPError.invalidParams("URI desconhecida: \(uri)")
    }

    private func json<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try VDJSON.encoder.encode(value), as: UTF8.self)
    }
}

/// The project's patterns with the scope and rules of their topics.
private struct PatternListing: Encodable {
    struct Row: Encodable {
        let pattern: ProjectPattern
        let topic: String?
        let paths: [String]
        let rules: [Rule]

        enum CodingKeys: String, CodingKey { case id, name, category, summary, note, topic, paths, rules, author }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(pattern.id, forKey: .id)
            try c.encode(pattern.name, forKey: .name)
            try c.encodeIfPresent(pattern.category, forKey: .category)
            try c.encodeIfPresent(pattern.summary, forKey: .summary)
            try c.encodeIfPresent(pattern.note, forKey: .note)
            try c.encodeIfPresent(topic, forKey: .topic)
            try c.encode(paths, forKey: .paths)
            try c.encode(rules, forKey: .rules)
            try c.encode(pattern.author, forKey: .author)
        }
    }

    let patterns: [Row]

    init(store: ProjectStore) throws {
        patterns = try store.loadProject().patterns.map { pattern in
            let topic = store.patternTopic(pattern)
            return Row(pattern: pattern, topic: topic?.slug, paths: topic?.topic.paths ?? [], rules: topic?.topic.rules ?? [])
        }
    }
}

private struct CatalogRow: Encodable {
    let template: PatternTemplate
    let inProject: Bool

    enum CodingKeys: String, CodingKey { case id, name, category, summary, aliases, rules, inProject }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(template.id, forKey: .id)
        try c.encode(template.name, forKey: .name)
        try c.encode(template.category, forKey: .category)
        try c.encode(template.summary, forKey: .summary)
        if !template.aliases.isEmpty { try c.encode(template.aliases, forKey: .aliases) }
        try c.encode(template.rules.map(\.text), forKey: .rules)
        try c.encode(inProject, forKey: .inProject)
    }
}

private struct StackListing: Encodable {
    let stack: [StackItem]
    let badge: String?
}

private struct IconRow: Encodable {
    let icon: SkillIcon
    let inStack: Bool

    enum CodingKeys: String, CodingKey { case id, name, category, themed, aliases, inStack }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(icon.id, forKey: .id)
        try c.encode(icon.name, forKey: .name)
        try c.encodeIfPresent(icon.category, forKey: .category)
        try c.encode(icon.themed, forKey: .themed)
        if !icon.aliases.isEmpty { try c.encode(icon.aliases, forKey: .aliases) }
        try c.encode(inStack, forKey: .inStack)
    }
}

private struct ProjectSummary: Encodable {
    let root: String
    let project: Project
    let docs: [String]
    let groups: [[String: String]]
}

/// A topic as a checklist: what agents need to answer in submit_rule_check.
/// One script run, for `run_rule_tests` / `vibedeck rules test --json`.
struct RuleTestRunRow: Encodable {
    let topic: String
    let ruleId: String
    let text: String
    let severity: RuleSeverity
    let command: String
    let verdict: RuleVerdict
    let exitCode: Int32
    let output: String

    init(_ run: RuleTestRun) {
        topic = run.topic
        ruleId = run.rule.id.uuidString
        text = run.rule.text
        severity = run.rule.severity
        command = run.command
        verdict = run.outcome.verdict
        exitCode = run.outcome.exitCode
        output = run.outcome.output
    }
}

private struct DocRow: Encodable {
    let slug: String
    let title: String
    let tags: [String]
}

private struct GroupRow: Encodable {
    let slug: String
    let title: String
    let description: String?
    let tags: [String]
    let open: Int
    let total: Int
}

private struct TopicRow: Encodable {
    let slug: String
    let title: String
    let description: String?
    let tags: [String]
    let paths: [String]
    let rules: Int
}

private struct IdeaRow: Encodable {
    let slug: String
    let title: String
    let status: IdeaStatus
    let tags: [String]
    let rules: Int
    let promotedTopic: String?
}

private struct CloudStart: Encodable {
    let sync: CloudSync
    let url: String?
    let output: String
}

private struct AgentRow: Encodable {
    let slug: String
    let title: String
    let model: String?
    let tags: [String]
    let nextSteps: [NextStep]
}

private struct CommandRow: Encodable {
    let slug: String
    let title: String
    let argumentHint: String?
    let model: String?
    let tags: [String]
    let nextSteps: [NextStep]
}

private struct SkillRow: Encodable {
    let slug: String
    let title: String
    let summary: String?
    let model: String?
    let tags: [String]
    let nextSteps: [NextStep]
}

private struct WorkflowRow: Encodable {
    let slug: String
    let title: String
    let summary: String?
    let input: String?
    let tags: [String]
    let steps: [String]
}

private struct WorkflowStepAdded: Encodable {
    let slug: String
    let step: String
    let workflow: Workflow
}

private struct RunStarted: Encodable {
    let ref: String
    let action: WorkflowRunAction
    /// Script of the orchestrator: follow it.
    let prompt: String
}

private struct RunRow: Encodable {
    let ref: String
    let workflow: String
    let input: String?
    let status: WorkflowRunStatus
    let current: String?
    let steps: Int
    let openQuestions: Int
    let updatedAt: Date
}

private struct SlugAnd<T: Encodable>: Encodable {
    let slug: String
    let value: T

    func encode(to encoder: Encoder) throws {
        try value.encode(to: encoder)
        var c = encoder.container(keyedBy: Key.self)
        try c.encode(slug, forKey: .slug)
    }

    enum Key: String, CodingKey { case slug }
}

private struct ItemRow: Encodable {
    let group: String
    let item: ReviewItem
}

private extension String {
    func stripping(_ prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}

private struct ImportReport: Encodable { var slugs: [String]; var warnings: [String] }
