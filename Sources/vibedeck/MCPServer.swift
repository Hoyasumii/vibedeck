import ArgumentParser
import Foundation
import MCP
import VibeDeckCore

struct MCPServe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp",
        abstract: "Servidor MCP (stdio) expondo o projeto para agentes de IA.",
        discussion: "Registre com: claude mcp add vibedeck -- vibedeck mcp"
    )

    @OptionGroup var options: RootOptions

    func run() async throws {
        let store = try options.store()
        let server = Server(
            name: "vibedeck",
            version: VibeDeckCLI.configuration.version,
            instructions: "Projeto VibeDeck em \(store.root.path). Leia os itens de revisão abertos antes de mexer numa área; ao concluir um item, marque status=done. Itens criados por você são marcados author=ai.",
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

    // MARK: Tool definitions

    private static func schema(_ props: [String: (String, String)], required: [String] = [], enums: [String: [String]] = [:]) -> Value {
        var properties: [String: Value] = [:]
        for (name, (type, description)) in props {
            var p: [String: Value] = ["type": .string(type), "description": .string(description)]
            if let values = enums[name] { p["enum"] = .array(values.map { .string($0) }) }
            properties[name] = .object(p)
        }
        return .object(["type": "object", "properties": .object(properties), "required": .array(required.map { .string($0) })])
    }

    private static let statuses = ReviewStatus.allCases.map(\.rawValue)
    private static let priorities = ReviewPriority.allCases.map(\.rawValue)

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
             ], required: ["group", "kind", "title"], enums: ["priority": priorities])),
        Tool(name: "update_review_item", description: "Atualiza um item de revisão pelo id (ou prefixo >= 4 chars).",
             inputSchema: schema([
                 "id": ("string", "Id do item"),
                 "status": ("string", "Novo status"),
                 "priority": ("string", "Nova prioridade"),
                 "title": ("string", "Novo título"),
                 "details": ("string", "Novos detalhes"),
                 "kind": ("string", "Novo kind"),
             ], required: ["id"], enums: ["status": statuses, "priority": priorities])),
        Tool(name: "add_link", description: "Adiciona um link ao projeto.",
             inputSchema: schema([
                 "url": ("string", "URL"),
                 "title": ("string", "Título"),
                 "tags": ("string", "Tags separadas por vírgula"),
             ], required: ["url"])),
    ]

    // MARK: Tool calls

    func call(_ name: String, _ args: [String: Value]) throws -> String {
        func str(_ key: String) -> String? { args[key]?.stringValue.flatMap { $0.isEmpty ? nil : $0 } }
        func req(_ key: String) throws -> String {
            guard let v = str(key) else { throw MCPError.invalidParams("Parâmetro obrigatório: \(key)") }
            return v
        }

        switch name {
        case "get_project":
            let groups = try store.listGroups().map { ["slug": $0.slug, "title": $0.group.title, "open": "\($0.group.openCount)", "total": "\($0.group.items.count)"] }
            return try json(ProjectSummary(root: store.root.path, project: store.loadProject(), docs: store.listDocs().map(\.slug), groups: groups))

        case "list_docs":
            return try json(store.listDocs().map { ["slug": $0.slug, "title": $0.title] })

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
            return try json(store.listGroups().map { ["slug": $0.slug, "title": $0.group.title, "description": $0.group.description ?? "", "open": "\($0.group.openCount)", "total": "\($0.group.items.count)"] })

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
                author: .ai
            )
            let (slug, saved) = try store.addItem(item, toGroup: req("group"))
            return try json(ItemRow(group: slug, item: saved))

        case "update_review_item":
            let item = try store.updateItem(req("id")) { item in
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

private struct ItemRow: Encodable {
    let group: String
    let item: ReviewItem
}

private extension String {
    func stripping(_ prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}
