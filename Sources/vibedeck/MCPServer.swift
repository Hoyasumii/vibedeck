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
    @Option(name: [.short, .long], help: "Escopo: local, project ou user.") var scope: MCPScope = .local
    @Option(help: "Nome do servidor no Claude Code.") var name = "vibedeck"
    @Flag(help: "Substitui um registro existente com o mesmo nome.") var force = false

    func run() throws {
        let root = try options.store().root
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
    @Option(name: [.short, .long], help: "Escopo: local, project ou user.") var scope: MCPScope = .local
    @Option(help: "Nome do servidor no Claude Code.") var name = "vibedeck"

    func run() throws {
        let status = try runClaude(["mcp", "remove", name, "-s", scope.rawValue], in: try options.store().root)
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
                return .init(content: [.text(text: try handler.call(params.name, params.arguments ?? [:]), annotations: nil, _meta: nil)], isError: false)
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

    static func instructions(root: String) -> String {
        """
        Projeto VibeDeck em \(root).

        REGRA OBRIGATÓRIA: nenhuma tarefa neste projeto está concluída sem passar pelas regras.
        Antes de dizer que terminou qualquer implementação ou alteração:
        1. chame rules_for com os arquivos que você alterou (e review_item, se a tarefa veio de um item de revisão);
        2. verifique cada regra de verdade contra o código;
        3. chame submit_rule_check respondendo pass/fail/na para TODAS as regras, com nota de evidência;
        4. se passed=false, corrija e envie outro check. Só declare concluído quando passed=true
           (avise o usuário sobre warnings de regras "should").

        Leia os itens de revisão abertos antes de mexer numa área; ao concluir um item, marque status=done
        (bloqueado sem check aprovado quando o item tem regras). Itens, regras e ideias criados por você são author=ai.
        Ideias (list_ideas) são planos futuros, não regras ativas; registre ideias novas com add_idea.
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

    static let tools: [Tool] = [
        Tool(name: "get_project", description: "Retorna vibedeck.json (nome, links, reviewKinds) e um resumo dos docs e grupos de revisão.", inputSchema: schema([:]),
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

        // Rules
        Tool(name: "rules_for", description: "OBRIGATÓRIO antes de concluir uma tarefa: retorna as regras aplicáveis (tópicos globais + os que casam os arquivos + os explícitos/do item), com ids para submit_rule_check.",
             inputSchema: schema([
                 "files": ("array", "Arquivos alterados (relativos à raiz ou absolutos)"),
                 "topics": ("array", "Tópicos extras a incluir (slug, id ou título)"),
                 "review_item": ("string", "Id do item de revisão relacionado"),
             ]),
             annotations: .init(readOnlyHint: true)),
        Tool(name: "submit_rule_check", description: "Registra a verificação das regras aplicáveis. Responda TODAS as regras de rules_for. Retorna passed=false se alguma regra 'must' falhou: corrija e envie de novo.",
             inputSchema: schema([
                 "task": ("string", "Resumo do que foi feito"),
                 "files": ("array", "Arquivos alterados"),
                 "topics": ("array", "Tópicos extras (os mesmos passados a rules_for)"),
                 "review_item": ("string", "Id do item de revisão relacionado"),
             ], required: ["task", "results"], custom: ["results": resultsSchema])),
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
        Tool(name: "set_tags", description: "Substitui as tags de um doc, grupo de revisão, tópico de regras ou ideia (lista vazia remove).",
             inputSchema: schema([
                 "kind": ("string", "Tipo do item"),
                 "ref": ("string", "Slug, id ou título"),
                 "tags": ("array", "Novas tags"),
             ], required: ["kind", "ref", "tags"], enums: ["kind": ["doc", "review_group", "rule_topic", "idea"]])),
        Tool(name: "promote_idea", description: "Transforma as regras de uma ideia em um tópico de regras ativo. Só faça isso quando o usuário pedir.",
             inputSchema: schema(["idea": ("string", "Slug, id ou título")], required: ["idea"])),
    ]

    // MARK: Tool calls

    func call(_ name: String, _ args: [String: Value]) throws -> String {
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
        func severity() throws -> RuleSeverity {
            guard let s = str("severity") else { return .must }
            guard let v = RuleSeverity(rawValue: s) else { throw MCPError.invalidParams("Severidade inválida: \(s)") }
            return v
        }

        switch name {
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
            let tags = str("tags")?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? []
            let link = Link(title: str("title") ?? url, url: url, tags: tags)
            try store.updateProject { $0.links.append(link) }
            return try json(link)

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
            return summary + "\n" + (try json(check))

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

        case "promote_idea":
            let topic = try store.promoteIdea(req("idea"))
            return "Ideia promovida para o tópico de regras: \(topic)"

        default:
            throw MCPError.methodNotFound("Tool desconhecida: \(name)")
        }
    }

    // MARK: Resources

    func resources() throws -> [Resource] {
        var list = [Resource(name: "vibedeck.json", uri: "vibedeck://project", description: "Manifesto do projeto", mimeType: "application/json")]
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
        return list
    }

    func read(_ uri: String) throws -> Resource.Content {
        if uri == "vibedeck://project" {
            return .text(try String(contentsOf: store.manifestURL, encoding: .utf8), uri: uri, mimeType: "application/json")
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
        throw MCPError.invalidParams("URI desconhecida: \(uri)")
    }

    private func json<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try VDJSON.encoder.encode(value), as: UTF8.self)
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
    }

    init(slug: String, topic: RuleTopic) {
        self.slug = slug
        title = topic.title
        description = topic.description
        paths = topic.paths
        rules = topic.rules.map { RuleRow(ruleId: $0.id.uuidString, text: $0.text, details: $0.details, severity: $0.severity) }
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
