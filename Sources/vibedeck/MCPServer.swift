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
        Antes de dizer que terminou qualquer implementação ou alteração:
        1. chame rules_for com os arquivos que você alterou (e review_item, se a tarefa veio de um item de revisão);
        2. verifique de verdade contra o código cada regra com check="manual" (as de check="script" são decididas
           rodando o script delas — run_rule_tests mostra o resultado antes do check);
        3. chame submit_rule_check respondendo pass/fail/na para TODAS as regras manuais, com nota de evidência
           (o submit roda os scripts sozinho e ignora respostas para regras de script);
        4. se passed=false, corrija e envie outro check. Só declare concluído quando passed=true
           (avise o usuário sobre warnings de regras "should").

        Leia os itens de revisão abertos antes de mexer numa área; ao concluir um item, marque status=done
        (bloqueado sem check aprovado quando o item tem regras). Itens, regras, ideias, agentes, comandos, skills e workflows criados por você são author=ai.
        Ideias (list_ideas) são planos futuros, não regras ativas; registre ideias novas com add_idea.
        Antes de implementar, consulte list_stack: são as tecnologias de destaque do projeto; prefira-as e siga as notas delas.
        Consulte também list_patterns: são os padrões de projeto (TDD, hexagonal, DDD…) que o código novo deve seguir;
        as regras de cada padrão entram no rules_for.
        Para executar um workflow, use workflow_run_start e siga o `prompt` devolvido: você orquestra, cada etapa roda
        num subagente (que lê workflow_run_step), o veredito vai para workflow_run_record e as perguntas das etapas
        chegam por workflow_run_questions para você fazer ao usuário.
        Guia completo: .vibedeck/AGENTS.md.
        """
    }

    // MARK: Tool definitions

    /// `type` "array" means an array of strings; `custom` adds hand-written property schemas.
    private static func schema(
        _ props: [String: (String, String)], required: [String] = [], enums: [String: [String]] = [:], custom: [String: Value] = [:]
    ) -> Value {
        var properties: [String: Value] = custom
        for (name, (type, description)) in props {
            var p: [String: Value] = ["type": .string(type), "description": .string(description)]
            if type == "array" { p["items"] = ["type": "string"] }
            if let values = enums[name] { p["enum"] = .array(values.map { .string($0) }) }
            properties[name] = .object(p)
        }
        return .object(["type": "object", "properties": .object(properties), "required": .array(required.map { .string($0) })])
    }

    private static let statuses = ReviewStatus.allCases.map(\.rawValue)
    private static let priorities = ReviewPriority.allCases.map(\.rawValue)
    private static let severities = RuleSeverity.allCases.map(\.rawValue)
    private static let ideaStatuses = IdeaStatus.allCases.map(\.rawValue)

    private static let resultsSchema: Value = [
        "type": "array",
        "description": "Uma resposta para CADA regra retornada por rules_for.",
        "items": [
            "type": "object",
            "properties": [
                "ruleId": ["type": "string", "description": "Id da regra (completo ou prefixo >= 4 chars)"],
                "verdict": ["type": "string", "enum": .array(RuleVerdict.allCases.map { .string($0.rawValue) }), "description": "pass | fail | na (não se aplica)"],
                "note": ["type": "string", "description": "Evidência curta: o que você verificou"],
            ],
            "required": ["ruleId", "verdict"],
        ],
    ]

    private static let questionsSchema: Value = [
        "type": "array",
        "description": "Perguntas para o usuário, de 2 a 4 opções cada (a recomendada primeiro).",
        "items": [
            "type": "object",
            "properties": [
                "question": ["type": "string", "description": "Pergunta direta, em pt-BR"],
                "context": ["type": "string", "description": "O que gerou a dúvida"],
                "options": [
                    "type": "array",
                    "items": ["type": "object", "properties": ["label": ["type": "string"], "description": ["type": "string"]], "required": ["label"]],
                ],
                "multiple": ["type": "boolean", "description": "Múltipla escolha"],
            ],
            "required": ["question"],
        ],
    ]

    static let tools: [Tool] = [
        Tool(name: "codex_usage", description: "Limites de uso atuais do Codex, consultados no App Server local.", inputSchema: schema([:]), annotations: .init(readOnlyHint: true)),
        Tool(name: "claude_usage", description: "Último uso dos limites do Claude Code (sessão de 5h e semana, em %, com horário de reset), registrado pela statusline (`vibedeck usage install`).",
             inputSchema: schema([:]), annotations: .init(readOnlyHint: true)),
        Tool(name: "cloud_check", description: "Compara a branch padrão local com a do GitHub (origin). Uma sessão do Claude Code na nuvem só vê o GitHub: se as branches forem diferentes (blocked=true), não dá para usar a nuvem até sincronizar.",
             inputSchema: schema([:]), annotations: .init(readOnlyHint: true)),
        Tool(name: "start_cloud_session", description: "Cria uma sessão do Claude Code na nuvem (claude.ai/code) com a tarefa dada, sobre o repositório no GitHub, e devolve o link. Recusa se a branch local for diferente da do GitHub, ou se houver alterações não commitadas sem allow_dirty. Só faça isso quando o usuário pedir.",
             inputSchema: schema(["provider": ("string", "claude ou codex; padrão claude"),
                 "environment": ("string", "ID do ambiente Codex Cloud"),
                 "description": ("string", "O que a sessão deve fazer"),
                 "allow_dirty": ("boolean", "Cria mesmo com alterações não commitadas, que a nuvem não vê (padrão: não)"),
             ], required: ["description"])),
        Tool(name: "get_project", description: "Retorna vibedeck.json (nome, links, stack, padrões, reviewKinds) e um resumo dos docs e grupos de revisão.", inputSchema: schema([:]),
             annotations: .init(readOnlyHint: true)),
        Tool(name: "list_docs", description: "Lista os documentos markdown do projeto (slug e título).", inputSchema: schema([:]),
             annotations: .init(readOnlyHint: true)),
        Tool(name: "read_doc", description: "Lê um documento markdown pelo slug.", inputSchema: schema(["slug": ("string", "Slug do doc")], required: ["slug"]),
             annotations: .init(readOnlyHint: true)),
        Tool(name: "write_doc", description: "Cria ou sobrescreve um documento markdown. Sem slug, cria um novo a partir do título.",
             inputSchema: schema([
                 "slug": ("string", "Slug existente (omita para criar)"),
                 "title": ("string", "Título para um doc novo"),
                 "content": ("string", "Conteúdo markdown completo"),
             ], required: ["content"])),
        Tool(name: "list_review_groups", description: "Lista os grupos (temas) de revisão com contagem de itens abertos.", inputSchema: schema([:]),
             annotations: .init(readOnlyHint: true)),
        Tool(name: "list_review_items", description: "Lista itens de revisão, com filtros opcionais.",
             inputSchema: schema([
                 "group": ("string", "Slug, id ou título do grupo"),
                 "status": ("string", "Status"),
                 "kind": ("string", "Kind (ver reviewKinds)"),
             ], enums: ["status": statuses]),
             annotations: .init(readOnlyHint: true)),
        Tool(name: "add_review_item", description: "Adiciona um item de revisão a um grupo (o grupo é criado se não existir). Marcado como author=ai.",
             inputSchema: schema([
                 "group": ("string", "Slug, id ou título do grupo/tema"),
                 "kind": ("string", "Kind (ver reviewKinds do projeto)"),
                 "title": ("string", "Título curto"),
                 "details": ("string", "Detalhes"),
                 "priority": ("string", "Prioridade"),
                 "file": ("string", "Arquivo relacionado"),
                 "route": ("string", "Rota/tela relacionada"),
                 "component": ("string", "Componente relacionado"),
                 "selector": ("string", "Seletor CSS/acessibilidade"),
                 "rules": ("array", "Slugs de tópicos de regras que o item precisa cumprir"),
             ], required: ["group", "kind", "title"], enums: ["priority": priorities])),
        Tool(name: "update_review_item", description: "Atualiza um item de revisão pelo id (ou prefixo >= 4 chars). status=done exige um check aprovado (submit_rule_check com review_item) quando o item tem regras.",
             inputSchema: schema([
                 "id": ("string", "Id do item"),
                 "status": ("string", "Novo status"),
                 "priority": ("string", "Nova prioridade"),
                 "title": ("string", "Novo título"),
                 "details": ("string", "Novos detalhes"),
                 "kind": ("string", "Novo kind"),
                 "rules": ("array", "Substitui os tópicos de regras do item"),
             ], required: ["id"], enums: ["status": statuses, "priority": priorities])),
        Tool(name: "add_link", description: "Adiciona um link ao projeto.",
             inputSchema: schema([
                 "url": ("string", "URL"),
                 "title": ("string", "Título"),
                 "tags": ("string", "Tags separadas por vírgula"),
             ], required: ["url"])),

        // Stack
        Tool(name: "list_stack", description: "Lista a stack do projeto: as tecnologias de destaque (ids do Skill Icons), na ordem, com nota de uso e o badge. Consulte antes de implementar: prefira essas tecnologias e siga as notas.",
             inputSchema: schema([:]), annotations: .init(readOnlyHint: true)),
        Tool(name: "search_stack_icons", description: "Procura tecnologias no catálogo do Skill Icons (por id, nome ou alias, como \"postgres\", \"Next.js\", \"k8s\"), para achar o id a usar em add_stack.",
             inputSchema: schema([
                 "query": ("string", "Texto a procurar (vazio = tudo)"),
                 "category": ("string", "Só ícones desta categoria"),
                 "limit": ("integer", "Máximo de resultados (padrão 50)"),
             ], enums: ["category": SkillIcons.categories]),
             annotations: .init(readOnlyHint: true)),
        Tool(name: "add_stack", description: "Adiciona tecnologias à stack (ids, nomes ou aliases do Skill Icons; nomes desconhecidos recusam tudo, com sugestões). Já existentes mantêm o lugar; a nota, se dada, substitui a delas. Atualiza o badge no README.md. Marcado como author=ai.",
             inputSchema: schema([
                 "icons": ("array", "Tecnologias, na ordem (ex.: [\"swift\", \"swiftui\"])"),
                 "note": ("string", "Nota de uso para todas elas (ex.: \"Swift 6, strict concurrency\")"),
             ], required: ["icons"])),
        Tool(name: "remove_stack", description: "Retira tecnologias da stack (id, nome ou prefixo do id) e atualiza o badge no README.md.",
             inputSchema: schema(["icons": ("array", "Tecnologias a retirar")], required: ["icons"])),
        Tool(name: "update_stack", description: "Altera a nota de uso ou a posição de uma tecnologia da stack.",
             inputSchema: schema([
                 "icon": ("string", "Id, nome ou prefixo do id"),
                 "note": ("string", "Nova nota (string vazia apaga)"),
                 "position": ("integer", "Nova posição, a partir de 0"),
             ], required: ["icon"])),

        // Patterns
        Tool(name: "list_patterns", description: "Lista os padrões de projeto (TDD, hexagonal, DDD, CQRS…) que o código deve seguir, na ordem, com nota, escopo (paths) e as regras do tópico de cada um. Consulte antes de implementar: o código novo deve seguir esses padrões; as regras deles entram no rules_for.",
             inputSchema: schema([:]), annotations: .init(readOnlyHint: true)),
        Tool(name: "pattern_catalog", description: "Lista o catálogo embutido de padrões (id, nome, categoria, resumo, regras que traz), para achar o id a usar em add_pattern.",
             inputSchema: schema(["query": ("string", "Texto a procurar (vazio = tudo)")]), annotations: .init(readOnlyHint: true)),
        Tool(name: "add_pattern", description: "Adiciona padrões de projeto. Com `patterns`: ids/nomes/aliases do catálogo (desconhecidos recusam tudo, com sugestões). Com `name` + `rules`: um padrão personalizado. Cada padrão novo cria um tópico de regras (aplicado pelo rules_for); já existentes mantêm o lugar e recebem a nota/paths dados. Marcado como author=ai.",
             inputSchema: schema([
                 "patterns": ("array", "Ids do catálogo (ex.: [\"tdd\", \"hexagonal\"])"),
                 "name": ("string", "Nome de um padrão personalizado"),
                 "summary": ("string", "Resumo do padrão personalizado"),
                 "rules": ("array", "Regras (obrigatórias) do padrão personalizado, uma por item"),
                 "note": ("string", "Como o projeto aplica o padrão (ex.: \"só no Core\")"),
                 "paths": ("array", "Globs de escopo (vazio = projeto inteiro)"),
             ])),
        Tool(name: "remove_pattern", description: "Retira padrões do projeto (id, nome ou prefixo do id) e apaga o tópico de regras de cada um.",
             inputSchema: schema(["patterns": ("array", "Padrões a retirar")], required: ["patterns"])),
        Tool(name: "update_pattern", description: "Altera a nota, o escopo (paths) ou a posição de um padrão do projeto.",
             inputSchema: schema([
                 "pattern": ("string", "Id, nome ou prefixo do id"),
                 "note": ("string", "Nova nota (string vazia apaga)"),
                 "paths": ("array", "Novos globs de escopo ([] = projeto inteiro)"),
                 "position": ("integer", "Nova posição, a partir de 0"),
             ], required: ["pattern"])),

        // Rules
        Tool(name: "rules_for", description: "OBRIGATÓRIO antes de concluir uma tarefa: retorna as regras aplicáveis (tópicos globais + os que casam os arquivos + os explícitos/do item), com ids para submit_rule_check.",
             inputSchema: schema([
                 "files": ("array", "Arquivos alterados (relativos à raiz ou absolutos)"),
                 "topics": ("array", "Tópicos extras a incluir (slug, id ou título)"),
                 "review_item": ("string", "Id do item de revisão relacionado"),
             ]),
             annotations: .init(readOnlyHint: true)),
        Tool(name: "submit_rule_check", description: "Registra a verificação das regras aplicáveis. Responda TODAS as regras de rules_for com check=manual; as de check=script são decididas rodando o script (respostas para elas são ignoradas). Retorna passed=false se alguma regra 'must' falhou: corrija e envie de novo.",
             inputSchema: schema([
                 "task": ("string", "Resumo do que foi feito"),
                 "files": ("array", "Arquivos alterados"),
                 "topics": ("array", "Tópicos extras (os mesmos passados a rules_for)"),
                 "review_item": ("string", "Id do item de revisão relacionado"),
             ], required: ["task", "results"], custom: ["results": resultsSchema])),
        Tool(name: "run_rule_tests", description: "Roda os scripts das regras aplicáveis (exit 0 = cumpre, 77 = não se aplica, outro = viola) e devolve o resultado de cada um. Não grava check. Sem files/review_item, roda só os topics indicados.",
             inputSchema: schema([
                 "files": ("array", "Arquivos alterados"),
                 "topics": ("array", "Tópicos (slug, id ou título)"),
                 "review_item": ("string", "Id do item de revisão relacionado"),
             ]),
             annotations: .init(readOnlyHint: true)),
        Tool(name: "set_rule_test", description: "Define como uma regra é verificada: mode=script com o comando do script (rodado na raiz; recebe $VIBEDECK_FILES; exit 0/77/outro) ou mode=manual quando a regra não é testável objetivamente. Guarda o hash da regra: se ela mudar, o teste fica desatualizado.",
             inputSchema: schema([
                 "rule_id": ("string", "Id da regra (ou prefixo >= 4 chars)"),
                 "mode": ("string", "script | manual"),
                 "command": ("string", "Comando do script (obrigatório em mode=script), ex.: .vibedeck/tests/geral/ab12cd34.sh"),
                 "reason": ("string", "O que o script verifica ou por que a regra é manual"),
             ], required: ["rule_id", "mode"], enums: ["mode": RuleTestMode.allCases.map(\.rawValue)])),
        Tool(name: "list_rule_topics", description: "Lista os tópicos de regras (escopo por paths e quantidade de regras).", inputSchema: schema([:]),
             annotations: .init(readOnlyHint: true)),
        Tool(name: "get_rule_topic", description: "Retorna um tópico de regras completo.", inputSchema: schema(["topic": ("string", "Slug, id ou título")], required: ["topic"]),
             annotations: .init(readOnlyHint: true)),
        Tool(name: "add_rule_topic", description: "Cria um tópico de regras. Sem paths, vale para toda tarefa.",
             inputSchema: schema([
                 "title": ("string", "Título do tópico"),
                 "description": ("string", "Quando o tópico se aplica"),
                 "paths": ("array", "Globs de escopo (ex.: Sources/App/**, *.tsx)"),
                 "tags": ("array", "Tags"),
             ], required: ["title"])),
        Tool(name: "add_rule", description: "Adiciona uma regra (comportamento esperado) a um tópico; o tópico é criado se não existir. Marcada author=ai.",
             inputSchema: schema([
                 "topic": ("string", "Slug, id ou título do tópico"),
                 "text": ("string", "A regra, curta e verificável"),
                 "details": ("string", "Detalhes/como verificar"),
                 "severity": ("string", "must bloqueia; should só avisa"),
             ], required: ["topic", "text"], enums: ["severity": severities])),

        // Ideas
        Tool(name: "list_ideas", description: "Lista as ideias do projeto (brainstorm). Não são regras ativas.",
             inputSchema: schema(["status": ("string", "Filtra por status")], enums: ["status": ideaStatuses]),
             annotations: .init(readOnlyHint: true)),
        Tool(name: "get_idea", description: "Retorna uma ideia completa (texto e regras rascunho).", inputSchema: schema(["idea": ("string", "Slug, id ou título")], required: ["idea"]),
             annotations: .init(readOnlyHint: true)),
        Tool(name: "add_idea", description: "Registra uma ideia futura. Marcada author=ai.",
             inputSchema: schema([
                 "title": ("string", "Título"),
                 "body": ("string", "Descrição em markdown"),
                 "tags": ("array", "Tags"),
             ], required: ["title"])),
        Tool(name: "update_idea", description: "Atualiza uma ideia.",
             inputSchema: schema([
                 "idea": ("string", "Slug, id ou título"),
                 "title": ("string", "Novo título"),
                 "body": ("string", "Novo texto markdown"),
                 "status": ("string", "Novo status"),
                 "tags": ("array", "Substitui as tags"),
             ], required: ["idea"], enums: ["status": ideaStatuses])),
        Tool(name: "add_idea_rule", description: "Adiciona uma regra rascunho a uma ideia (só passa a valer após promote_idea).",
             inputSchema: schema([
                 "idea": ("string", "Slug, id ou título"),
                 "text": ("string", "A regra"),
                 "details": ("string", "Detalhes"),
                 "severity": ("string", "must ou should"),
             ], required: ["idea", "text"], enums: ["severity": severities])),
        // Agents
        Tool(name: "list_agents", description: "Lista os agentes do VibeDeck (nome, modelo e próximos passos). Não são os agentes do provedor de IA.",
             inputSchema: schema([:]), annotations: .init(readOnlyHint: true)),
        Tool(name: "get_agent", description: "Retorna um agente completo (prompt e próximos passos).", inputSchema: schema(["agent": ("string", "Slug, id ou título")], required: ["agent"]),
             annotations: .init(readOnlyHint: true)),
        Tool(name: "add_agent", description: "Cria um agente do VibeDeck. Marcado author=ai.",
             inputSchema: schema(["provider_settings": ("object", "Configurações por provedor: {codex:{model,effort},claude:{model,effort}}"),
                 "title": ("string", "Nome do agente"),
                 "summary": ("string", "Quando usar"),
                 "model": ("string", "Modelo (ex.: sonnet, opus)"),
                 "tools": ("array", "Ferramentas"),
                 "prompt": ("string", "Prompt do agente (markdown)"),
                 "tags": ("array", "Tags"),
             ], required: ["title"])),
        Tool(name: "update_agent", description: "Atualiza um agente (use add_agent_next_step para o fluxo).",
             inputSchema: schema(["provider_settings": ("object", "Configurações por provedor: {codex:{model,effort},claude:{model,effort}}"),
                 "agent": ("string", "Slug, id ou título"),
                 "title": ("string", "Novo nome"),
                 "summary": ("string", "Nova descrição"),
                 "model": ("string", "Novo modelo"),
                 "tools": ("array", "Substitui as ferramentas"),
                 "prompt": ("string", "Novo prompt"),
                 "tags": ("array", "Substitui as tags"),
             ], required: ["agent"])),
        Tool(name: "add_agent_next_step", description: "Adiciona um próximo passo ao agente: outro agente, comando ou skill do VibeDeck que atua sobre o resultado. Forma um fluxo.",
             inputSchema: schema([
                 "agent": ("string", "Agente de origem (slug, id ou título)"),
                 "target": ("string", "Agente, comando ou skill do VibeDeck (slug, id ou título)"),
                 "kind": ("string", "agent (padrão), command ou skill"),
                 "note": ("string", "Quando/como executar"),
             ], required: ["agent", "target"], enums: ["kind": ["agent", "command", "skill"]])),
        Tool(name: "agent_flow", description: "JSON do fluxo de um agente (prompt + próximos passos encadeados) para orquestrar a IA.",
             inputSchema: schema(["agent": ("string", "Slug, id ou título")], required: ["agent"]), annotations: .init(readOnlyHint: true)),
        Tool(name: "import_agents", description: "Importa agentes do Claude Code (.claude/agents do projeto e do usuário) como agentes do VibeDeck. Marcados como author=ai.",
             inputSchema: schema(["provider": ("string", "claude ou codex; padrão claude"), "overwrite": ("boolean", "Sobrescreve existentes (padrão: não)")])),
        // Commands
        Tool(name: "list_commands", description: "Lista os comandos do VibeDeck (nome, argumentos, modelo e próximos passos). Não são os comandos do provedor de IA.",
             inputSchema: schema([:]), annotations: .init(readOnlyHint: true)),
        Tool(name: "get_command", description: "Retorna um comando completo (prompt e próximos passos).", inputSchema: schema(["command": ("string", "Slug, id ou título")], required: ["command"]),
             annotations: .init(readOnlyHint: true)),
        Tool(name: "add_command", description: "Cria um comando do VibeDeck (prompt no formato de slash command, com $ARGUMENTS). Marcado author=ai.",
             inputSchema: schema(["provider_settings": ("object", "Configurações por provedor: {codex:{model,effort},claude:{model,effort}}"),
                 "title": ("string", "Nome do comando"),
                 "summary": ("string", "O que o comando faz"),
                 "argument_hint": ("string", "O que vai em $ARGUMENTS (ex.: <mensagem>)"),
                 "model": ("string", "Modelo (ex.: sonnet, opus)"),
                 "tools": ("array", "Ferramentas permitidas"),
                 "prompt": ("string", "Prompt do comando (markdown)"),
                 "tags": ("array", "Tags"),
             ], required: ["title"])),
        Tool(name: "update_command", description: "Atualiza um comando (use add_command_next_step para o fluxo).",
             inputSchema: schema(["provider_settings": ("object", "Configurações por provedor: {codex:{model,effort},claude:{model,effort}}"),
                 "command": ("string", "Slug, id ou título"),
                 "title": ("string", "Novo nome"),
                 "summary": ("string", "Nova descrição"),
                 "argument_hint": ("string", "Novos argumentos"),
                 "model": ("string", "Novo modelo"),
                 "tools": ("array", "Substitui as ferramentas"),
                 "prompt": ("string", "Novo prompt"),
                 "tags": ("array", "Substitui as tags"),
             ], required: ["command"])),
        Tool(name: "add_command_next_step", description: "Adiciona um próximo passo ao comando: um agente, outro comando ou uma skill do VibeDeck que atua sobre o resultado. Forma um fluxo.",
             inputSchema: schema([
                 "command": ("string", "Comando de origem (slug, id ou título)"),
                 "target": ("string", "Agente, comando ou skill do VibeDeck (slug, id ou título)"),
                 "kind": ("string", "agent (padrão), command ou skill"),
                 "note": ("string", "Quando/como executar"),
             ], required: ["command", "target"], enums: ["kind": ["agent", "command", "skill"]])),
        Tool(name: "command_flow", description: "JSON do fluxo de um comando (prompt + próximos passos encadeados) para orquestrar a IA.",
             inputSchema: schema(["command": ("string", "Slug, id ou título")], required: ["command"]), annotations: .init(readOnlyHint: true)),
        Tool(name: "import_commands", description: "Importa comandos do Claude Code (.claude/commands do projeto e do usuário) como comandos do VibeDeck. Marcados como author=ai.",
             inputSchema: schema(["provider": ("string", "claude ou codex; padrão claude"), "overwrite": ("boolean", "Sobrescreve existentes (padrão: não)")])),
        // Skills
        Tool(name: "list_skills", description: "Lista as skills do VibeDeck (nome, descrição, modelo e próximos passos). Não são as skills do provedor de IA.",
             inputSchema: schema([:]), annotations: .init(readOnlyHint: true)),
        Tool(name: "get_skill", description: "Retorna uma skill completa (instruções e próximos passos).", inputSchema: schema(["skill": ("string", "Slug, id ou título")], required: ["skill"]),
             annotations: .init(readOnlyHint: true)),
        Tool(name: "add_skill", description: "Cria uma skill do VibeDeck (instruções no formato do SKILL.md; a descrição diz quando usá-la). Marcada author=ai.",
             inputSchema: schema(["provider_settings": ("object", "Configurações por provedor: {codex:{model,effort},claude:{model,effort}}"),
                 "title": ("string", "Nome da skill"),
                 "summary": ("string", "Quando usar a skill (é o que a dispara)"),
                 "model": ("string", "Modelo (ex.: sonnet, opus)"),
                 "tools": ("array", "Ferramentas permitidas"),
                 "prompt": ("string", "Instruções da skill (markdown)"),
                 "tags": ("array", "Tags"),
             ], required: ["title"])),
        Tool(name: "update_skill", description: "Atualiza uma skill (use add_skill_next_step para o fluxo).",
             inputSchema: schema(["provider_settings": ("object", "Configurações por provedor: {codex:{model,effort},claude:{model,effort}}"),
                 "skill": ("string", "Slug, id ou título"),
                 "title": ("string", "Novo nome"),
                 "summary": ("string", "Nova descrição"),
                 "model": ("string", "Novo modelo"),
                 "tools": ("array", "Substitui as ferramentas"),
                 "prompt": ("string", "Novas instruções"),
                 "tags": ("array", "Substitui as tags"),
             ], required: ["skill"])),
        Tool(name: "add_skill_next_step", description: "Adiciona um próximo passo à skill: um agente, comando ou outra skill do VibeDeck que atua sobre o resultado. Forma um fluxo.",
             inputSchema: schema([
                 "skill": ("string", "Skill de origem (slug, id ou título)"),
                 "target": ("string", "Agente, comando ou skill do VibeDeck (slug, id ou título)"),
                 "kind": ("string", "agent (padrão), command ou skill"),
                 "note": ("string", "Quando/como executar"),
             ], required: ["skill", "target"], enums: ["kind": ["agent", "command", "skill"]])),
        Tool(name: "skill_flow", description: "JSON do fluxo de uma skill (instruções + próximos passos encadeados) para orquestrar a IA.",
             inputSchema: schema(["skill": ("string", "Slug, id ou título")], required: ["skill"]), annotations: .init(readOnlyHint: true)),
        Tool(name: "import_skills", description: "Importa skills do Claude Code (.claude/skills/<nome>/SKILL.md do projeto e do usuário) como skills do VibeDeck. Marcadas como author=ai.",
             inputSchema: schema(["provider": ("string", "claude ou codex; padrão claude"), "overwrite": ("boolean", "Sobrescreve existentes (padrão: não)")])),
        // Workflows
        Tool(name: "list_workflows", description: "Lista os workflows do VibeDeck: fluxos nomeados de etapas (agentes, comandos e skills do VibeDeck) com transições condicionais.",
             inputSchema: schema([:]), annotations: .init(readOnlyHint: true)),
        Tool(name: "get_workflow", description: "Retorna um workflow completo (etapas e transições).", inputSchema: schema(["workflow": ("string", "Slug, id ou título")], required: ["workflow"]),
             annotations: .init(readOnlyHint: true)),
        Tool(name: "add_workflow", description: "Cria um workflow do VibeDeck (sem etapas; use add_workflow_step e add_workflow_transition). Marcado author=ai.",
             inputSchema: schema([
                 "title": ("string", "Nome do workflow"),
                 "summary": ("string", "O que o workflow faz"),
                 "input": ("string", "O que pedir ao iniciar (ex.: <número do PR>)"),
                 "max_steps": ("integer", "Limite de etapas executadas por execução (padrão: \(Workflow.defaultMaxSteps))"),
                 "tags": ("array", "Tags"),
             ], required: ["title"])),
        Tool(name: "update_workflow", description: "Atualiza nome, descrição, entrada, limite ou tags de um workflow.",
             inputSchema: schema([
                 "workflow": ("string", "Slug, id ou título"),
                 "title": ("string", "Novo nome"),
                 "summary": ("string", "Nova descrição"),
                 "input": ("string", "Nova entrada"),
                 "max_steps": ("integer", "Novo limite de etapas (0 volta ao padrão)"),
                 "tags": ("array", "Substitui as tags"),
             ], required: ["workflow"])),
        Tool(name: "add_workflow_step", description: "Adiciona uma etapa ao workflow: um agente, comando ou skill do VibeDeck (pode repetir). A primeira etapa é o início. Retorna o id da etapa.",
             inputSchema: schema([
                 "workflow": ("string", "Slug, id ou título"),
                 "target": ("string", "Agente, comando ou skill do VibeDeck (slug, id ou título)"),
                 "kind": ("string", "agent (padrão), command ou skill"),
                 "note": ("string", "Instrução extra da etapa ($ARGUMENTS para comandos)"),
                 "max_visits": ("integer", "Máximo de vezes que a etapa roda por ciclo de uma execução"),
             ], required: ["workflow", "target"], enums: ["kind": ["agent", "command", "skill"]])),
        Tool(name: "set_workflow_step_max_visits", description: "Define quantas vezes uma etapa pode rodar por ciclo de uma execução (0 remove o limite). Estourou → a execução para.",
             inputSchema: schema([
                 "workflow": ("string", "Slug, id ou título"),
                 "step": ("string", "Id ou posição da etapa"),
                 "max_visits": ("integer", "Máximo (0 = sem limite)"),
             ], required: ["workflow", "step", "max_visits"])),
        Tool(name: "remove_workflow_step", description: "Remove uma etapa do workflow e as transições que apontam para ela.",
             inputSchema: schema([
                 "workflow": ("string", "Slug, id ou título"),
                 "step": ("string", "Id ou posição (1, 2, …) da etapa"),
             ], required: ["workflow", "step"])),
        Tool(name: "move_workflow_step", description: "Move uma etapa para outra posição (1 = início).",
             inputSchema: schema([
                 "workflow": ("string", "Slug, id ou título"),
                 "step": ("string", "Id ou posição da etapa"),
                 "position": ("integer", "Nova posição (1, 2, …)"),
             ], required: ["workflow", "step", "position"])),
        Tool(name: "add_workflow_transition", description: "Adiciona uma transição: depois da etapa `from`, vá para `to` (pode voltar a etapas anteriores) quando o veredito da etapa (última linha do resultado) for `verdict`, ou quando `when` valer para o resultado. Sem nenhum dos dois é o \"senão\" (um por etapa, sempre por último). Vereditos primeiro, depois condições, depois o senão; nenhuma = fim.",
             inputSchema: schema([
                 "workflow": ("string", "Slug, id ou título"),
                 "from": ("string", "Etapa de origem (id ou posição)"),
                 "to": ("string", "Etapa de destino (id ou posição)"),
                 "verdict": ("string", "Veredito que leva a esta transição (ex.: APROVADO); maiúsculas e acentos não importam"),
                 "when": ("string", "Condição em linguagem natural sobre o resultado da etapa"),
             ], required: ["workflow", "from", "to"])),
        Tool(name: "remove_workflow_transition", description: "Remove a transição na posição `index` (1, 2, …) de uma etapa.",
             inputSchema: schema([
                 "workflow": ("string", "Slug, id ou título"),
                 "from": ("string", "Etapa de origem (id ou posição)"),
                 "index": ("integer", "Posição da transição na etapa"),
             ], required: ["workflow", "from", "index"])),
        Tool(name: "workflow_flow", description: "JSON do workflow (etapas resolvidas, transições e regras de execução) para orquestrar a IA. Para executar, siga as `rules` do JSON.",
             inputSchema: schema([
                 "workflow": ("string", "Slug, id ou título"),
                 "input": ("string", "Entrada desta execução (sem ela, a IA pede a entrada ao usuário)"),
             ], required: ["workflow"]), annotations: .init(readOnlyHint: true)),
        Tool(name: "workflow_run_start", description: "Inicia (ou retoma, com a mesma entrada) uma execução de workflow com estado em disco e devolve {ref, action, prompt}: `prompt` é o roteiro do orquestrador — siga-o (cada etapa num subagente, veredito decide a transição, perguntas ao usuário). `from` libera mais uma volta numa execução parada a partir de uma etapa.",
             inputSchema: schema(["provider": ("string", "claude ou codex; padrão claude"),
                 "workflow": ("string", "Slug, id ou título"),
                 "input": ("string", "Entrada da execução (a execução recebe o nome dela)"),
                 "from": ("string", "Etapa por onde começar"),
             ], required: ["workflow"])),
        Tool(name: "workflow_run_next", description: "Próxima ação do orquestrador numa execução: run-step (lance um subagente para `step`), ask (faça as perguntas abertas), decide (avalie as condições), done ou stop.",
             inputSchema: schema(["run": ("string", "<workflow>/<execução>, nome da execução ou id")], required: ["run"]),
             annotations: .init(readOnlyHint: true)),
        Tool(name: "workflow_run_step", description: "Prompt da etapa atual da execução, para o subagente que a executa (instruções resolvidas, pasta da execução, respostas do usuário e protocolo de saída).",
             inputSchema: schema(["run": ("string", "<workflow>/<execução>, nome da execução ou id")], required: ["run"]),
             annotations: .init(readOnlyHint: true)),
        Tool(name: "workflow_run_record", description: "Registra o veredito (última linha) da etapa atual e devolve a próxima ação. Se vier `decide`, avalie os `candidates` e chame de novo com `to` (ou `none_holds`).",
             inputSchema: schema([
                 "run": ("string", "<workflow>/<execução>, nome da execução ou id"),
                 "verdict": ("string", "Última linha do resultado da etapa"),
                 "summary": ("string", "Resumo de 1 a 3 linhas do que a etapa fez"),
                 "to": ("string", "Etapa escolhida ao avaliar as condições"),
                 "none_holds": ("boolean", "Nenhuma condição vale: segue o senão ou termina"),
             ], required: ["run"])),
        Tool(name: "workflow_run_ask", description: "Grava perguntas da etapa atual para o usuário (a etapa não fala com ele); a execução espera as respostas. Depois termine a etapa com a última linha PERGUNTA.",
             inputSchema: schema(["run": ("string", "<workflow>/<execução>, nome da execução ou id")], required: ["run", "questions"], custom: ["questions": questionsSchema])),
        Tool(name: "workflow_run_questions", description: "Perguntas de uma execução (só as abertas com open=true).",
             inputSchema: schema([
                 "run": ("string", "<workflow>/<execução>, nome da execução ou id"),
                 "open": ("boolean", "Só as abertas"),
             ], required: ["run"]), annotations: .init(readOnlyHint: true)),
        Tool(name: "workflow_run_answer", description: "Grava a resposta do usuário a uma pergunta (opção escolhida, várias separadas por \"; \", ou texto livre) e devolve a próxima ação.",
             inputSchema: schema([
                 "run": ("string", "<workflow>/<execução>, nome da execução ou id"),
                 "number": ("integer", "Número da pergunta"),
                 "answer": ("string", "Resposta"),
             ], required: ["run", "number", "answer"])),
        Tool(name: "workflow_run_list", description: "Execuções de workflows (mais recentes primeiro), com status e etapa atual.",
             inputSchema: schema([
                 "workflow": ("string", "Só deste workflow"),
                 "status": ("string", "Filtra pelo status"),
             ], enums: ["status": WorkflowRunStatus.allCases.map(\.rawValue)]), annotations: .init(readOnlyHint: true)),
        Tool(name: "workflow_run_show", description: "Uma execução completa: status, etapa atual, histórico com vereditos e perguntas.",
             inputSchema: schema(["run": ("string", "<workflow>/<execução>, nome da execução ou id")], required: ["run"]),
             annotations: .init(readOnlyHint: true)),
        Tool(name: "workflow_run_stop", description: "Para uma execução. Só faça isso quando o usuário pedir.",
             inputSchema: schema([
                 "run": ("string", "<workflow>/<execução>, nome da execução ou id"),
                 "reason": ("string", "Motivo"),
             ], required: ["run"])),
        Tool(name: "set_tags", description: "Substitui as tags de um doc, grupo de revisão, tópico de regras, ideia, agente, comando, skill ou workflow (lista vazia remove).",
             inputSchema: schema([
                 "kind": ("string", "Tipo do item"),
                 "ref": ("string", "Slug, id ou título"),
                 "tags": ("array", "Novas tags"),
             ], required: ["kind", "ref", "tags"], enums: ["kind": ["doc", "review_group", "rule_topic", "idea", "agent", "command", "skill", "workflow"]])),
        Tool(name: "promote_idea", description: "Transforma as regras de uma ideia em um tópico de regras ativo. Só faça isso quando o usuário pedir.",
             inputSchema: schema(["idea": ("string", "Slug, id ou título")], required: ["idea"])),
        Tool(name: "unpromote_idea", description: "Desfaz promote_idea: apaga o tópico de regras criado pela ideia e remove o vínculo (as regras rascunho ficam na ideia; Aprovada volta para Explorando). Só faça isso quando o usuário pedir.",
             inputSchema: schema(["idea": ("string", "Slug, id ou título")], required: ["idea"])),
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
        case "get_project":
            let groups = try store.listGroups().map { ["slug": $0.slug, "title": $0.group.title, "open": "\($0.group.openCount)", "total": "\($0.group.items.count)"] }
            return try json(ProjectSummary(root: store.root.path, project: store.loadProject(), docs: store.listDocs().map(\.slug), groups: groups))

        case "list_docs":
            return try json(store.listDocs().map { DocRow(slug: $0.slug, title: $0.title, tags: $0.tags) })

        case "read_doc":
            return try store.readDoc(req("slug"))

        case "write_doc":
            let content = try req("content")
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
            return try json(applicable.map { TopicChecklist(slug: $0.slug, topic: $0.topic) })

        case "submit_rule_check":
            guard let raw = args["results"] else { throw MCPError.invalidParams("Parâmetro obrigatório: results") }
            let answers: [RuleAnswer]
            do {
                let data = try raw.stringValue.map { Data($0.utf8) } ?? JSONEncoder().encode(raw)
                answers = try JSONDecoder().decode([RuleAnswer].self, from: data)
            } catch {
                throw MCPError.invalidParams("results deve ser uma lista de {ruleId, verdict: pass|fail|na, note}.")
            }
            let check = try store.submitCheck(
                task: req("task"), files: list("files") ?? [], topics: list("topics") ?? [],
                reviewItem: str("review_item"), answers: answers, author: .ai
            )
            var summary = check.passed
                ? "✅ Check aprovado (\(check.results.count) regra(s))."
                : "❌ Check reprovado. Corrija e envie um novo check antes de concluir:\n" + check.failures.map { "- \($0)" }.joined(separator: "\n")
            if !check.warnings.isEmpty {
                summary += "\n⚠️ Recomendações não cumpridas (avise o usuário):\n" + check.warnings.map { "- \($0)" }.joined(separator: "\n")
            }
            let scripted = check.results.filter { $0.source == .script }
            if !scripted.isEmpty {
                summary += "\n⚙️ \(scripted.count) regra(s) decidida(s) por script."
                for r in scripted where r.verdict == .fail { summary += "\n--- script reprovado:\n\(r.note ?? "")" }
            }
            return summary + "\n" + (try json(check))

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
            let topic = try store.promoteIdea(req("idea"))
            return "Ideia promovida para o tópico de regras: \(topic)"

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
struct TopicChecklist: Encodable {
    let slug: String
    let title: String
    let description: String?
    let paths: [String]
    let rules: [RuleRow]

    struct RuleRow: Encodable {
        let ruleId: String
        let text: String
        let details: String?
        let severity: RuleSeverity
        /// "script": decided by running `test` in submit_rule_check; "manual": the agent answers it.
        let check: String
        let test: String?
        /// The rule changed since its test was written: answer it manually and regenerate the test.
        let staleTest: Bool?
    }

    init(slug: String, topic: RuleTopic) {
        self.slug = slug
        title = topic.title
        description = topic.description
        paths = topic.paths
        rules = topic.rules.map {
            RuleRow(ruleId: $0.id.uuidString, text: $0.text, details: $0.details, severity: $0.severity,
                    check: $0.testState == .script ? "script" : "manual", test: $0.scriptCommand,
                    staleTest: $0.testState == .stale ? true : nil)
        }
    }
}

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
