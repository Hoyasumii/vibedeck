import ArgumentParser
import Foundation
import VibeDeckCore

@main
struct VibeDeckCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "vibedeck",
        abstract: "Gerencia projetos VibeDeck (links, docs e itens de revisão) a partir do terminal.",
        version: "0.1.0",
        subcommands: [Init.self, Status.self, Links.self, Docs.self, Review.self, MCPServe.self]
    )
}

struct RootOptions: ParsableArguments {
    @Option(name: [.customShort("C"), .long], help: "Diretório do projeto (padrão: procura vibedeck.json a partir do diretório atual).")
    var root: String?

    var startURL: URL {
        URL(fileURLWithPath: root.map { NSString(string: $0).expandingTildeInPath } ?? FileManager.default.currentDirectoryPath)
    }

    func store() throws -> ProjectStore { try ProjectStore.locate(from: startURL) }
}

func printJSON<T: Encodable>(_ value: T) throws {
    print(String(decoding: try VDJSON.encoder.encode(value), as: UTF8.self))
}

// MARK: - init / status

struct Init: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Cria vibedeck.json e .vibedeck/ no diretório.")

    @Argument(help: "Diretório (padrão: atual).") var directory: String?
    @Option(help: "Nome do projeto (padrão: nome da pasta).") var name: String?
    @Option(help: "Descrição.") var description: String?

    func run() throws {
        let dir = URL(fileURLWithPath: NSString(string: directory ?? FileManager.default.currentDirectoryPath).expandingTildeInPath)
        let store = try ProjectStore.initialize(at: dir, name: name, description: description)
        print("Projeto criado em \(store.root.path)")
    }
}

struct Status: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Resumo do projeto.")
    @OptionGroup var options: RootOptions
    @Flag(help: "Saída JSON.") var json = false

    struct Summary: Encodable {
        let root: String
        let project: Project
        let docs: [String]
        let groups: [GroupSummary]
    }

    struct GroupSummary: Encodable {
        let slug: String
        let title: String
        let open: Int
        let total: Int
    }

    func run() throws {
        let store = try options.store()
        let project = try store.loadProject()
        let docs = try store.listDocs()
        let groups = try store.listGroups()
        if json {
            try printJSON(Summary(
                root: store.root.path, project: project, docs: docs.map(\.slug),
                groups: groups.map { GroupSummary(slug: $0.slug, title: $0.group.title, open: $0.group.openCount, total: $0.group.items.count) }
            ))
            return
        }
        print("\(project.name) — \(store.root.path)")
        if let d = project.description { print(d) }
        print("\nLinks: \(project.links.count)  Docs: \(docs.count)  Grupos de revisão: \(groups.count)")
        for (slug, group) in groups {
            print("  • \(group.title) [\(slug)] — \(group.openCount) aberto(s) de \(group.items.count)")
        }
    }
}

// MARK: - links

struct Links: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Links do projeto.", subcommands: [List.self, Add.self, Remove.self], defaultSubcommand: List.self)

    struct List: ParsableCommand {
        @OptionGroup var options: RootOptions
        @Flag(help: "Saída JSON.") var json = false

        func run() throws {
            let links = try options.store().loadProject().links
            if json { return try printJSON(links) }
            for l in links {
                let tags = l.tags.isEmpty ? "" : "  #" + l.tags.joined(separator: " #")
                print("\(l.id.uuidString.prefix(8))  \(l.title)  \(l.url)\(tags)")
            }
        }
    }

    struct Add: ParsableCommand {
        @OptionGroup var options: RootOptions
        @Argument var url: String
        @Option var title: String?
        @Option(parsing: .upToNextOption) var tags: [String] = []

        func run() throws {
            let link = Link(title: title ?? url, url: url, tags: tags)
            try options.store().updateProject { $0.links.append(link) }
            print(link.id.uuidString)
        }
    }

    struct Remove: ParsableCommand {
        @OptionGroup var options: RootOptions
        @Argument(help: "Id ou prefixo do id.") var id: String

        func run() throws {
            try options.store().updateProject { project in
                let before = project.links.count
                project.links.removeAll { $0.id.uuidString.lowercased().hasPrefix(id.lowercased()) }
                if project.links.count == before { throw ValidationError("Link não encontrado: \(id)") }
            }
        }
    }
}

// MARK: - docs

struct Docs: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Documentos markdown.", subcommands: [List.self, Cat.self, New.self, Write.self], defaultSubcommand: List.self)

    struct List: ParsableCommand {
        @OptionGroup var options: RootOptions
        func run() throws {
            for doc in try options.store().listDocs() { print("\(doc.slug)\t\(doc.title)") }
        }
    }

    struct Cat: ParsableCommand {
        @OptionGroup var options: RootOptions
        @Argument var slug: String
        func run() throws { print(try options.store().readDoc(slug), terminator: "") }
    }

    struct New: ParsableCommand {
        @OptionGroup var options: RootOptions
        @Argument var title: String
        func run() throws { print(try options.store().createDoc(title: title)) }
    }

    struct Write: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Sobrescreve um doc com o conteúdo de --text ou stdin.")
        @OptionGroup var options: RootOptions
        @Argument var slug: String
        @Option var text: String?

        func run() throws {
            let content = text ?? String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
            try options.store().writeDoc(slug, content)
        }
    }
}

// MARK: - review

extension ReviewStatus: ExpressibleByArgument {}
extension ReviewPriority: ExpressibleByArgument {}

struct Review: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Itens de revisão agrupados por tema.",
        subcommands: [Groups.self, List.self, Add.self, Set.self, Remove.self], defaultSubcommand: List.self
    )

    struct Groups: ParsableCommand {
        @OptionGroup var options: RootOptions
        func run() throws {
            for (slug, g) in try options.store().listGroups() { print("\(slug)\t\(g.title)\t\(g.openCount)/\(g.items.count)") }
        }
    }

    struct List: ParsableCommand {
        @OptionGroup var options: RootOptions
        @Option(help: "Filtra por grupo (slug, id ou título).") var group: String?
        @Option(help: "Filtra por status.") var status: ReviewStatus?
        @Option(help: "Filtra por kind.") var kind: String?
        @Flag(help: "Saída JSON.") var json = false

        struct Row: Encodable {
            let group: String
            let item: ReviewItem
        }

        func run() throws {
            let store = try options.store()
            var groups = try store.listGroups()
            if let group { let slug = try store.resolveGroupSlug(group); groups = groups.filter { $0.slug == slug } }
            let rows = groups.flatMap { g in
                g.group.items
                    .filter { status == nil || $0.status == status }
                    .filter { kind == nil || $0.kind == kind }
                    .map { Row(group: g.slug, item: $0) }
            }
            if json { return try printJSON(rows) }
            var current = ""
            for row in rows {
                if row.group != current { current = row.group; print("\n## \(row.group)") }
                let i = row.item
                let where_ = [i.target?.file, i.target?.route, i.target?.component, i.target?.selector].compactMap { $0 }.joined(separator: " ")
                print("\(i.id.uuidString.prefix(8))  [\(i.status.rawValue)] (\(i.kind)) \(i.title)\(where_.isEmpty ? "" : "  → \(where_)")")
            }
        }
    }

    struct Add: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Adiciona um item (cria o grupo se não existir).")
        @OptionGroup var options: RootOptions
        @Argument(help: "Grupo/tema (slug, id ou título).") var group: String
        @Argument(help: "Título do item.") var title: String
        @Option(help: "Kind (ex.: disable, hide, fix, change, remove, note).") var kind = "note"
        @Option var details: String?
        @Option var priority: ReviewPriority = .normal
        @Option var file: String?
        @Option var route: String?
        @Option var component: String?
        @Option var selector: String?
        @Flag(help: "Marca o item como criado por IA.") var ai = false

        func run() throws {
            let store = try options.store()
            let kinds = try store.loadProject().reviewKinds.map(\.id)
            guard kinds.contains(kind) else { throw ValidationError("Kind desconhecido '\(kind)'. Disponíveis: \(kinds.joined(separator: ", "))") }
            let item = ReviewItem(
                kind: kind, title: title, details: details, priority: priority,
                target: ReviewTarget(file: file, route: route, component: component, selector: selector),
                author: ai ? .ai : .human
            )
            let (slug, _) = try store.addItem(item, toGroup: group)
            print("\(item.id.uuidString)\t\(slug)")
        }
    }

    struct Set: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Atualiza um item (id completo ou prefixo).")
        @OptionGroup var options: RootOptions
        @Argument var id: String
        @Option var status: ReviewStatus?
        @Option var priority: ReviewPriority?
        @Option var kind: String?
        @Option var title: String?
        @Option var details: String?

        func run() throws {
            let item = try options.store().updateItem(id) { item in
                if let status { item.status = status }
                if let priority { item.priority = priority }
                if let kind { item.kind = kind }
                if let title { item.title = title }
                if let details { item.details = details }
            }
            print("\(item.id.uuidString.prefix(8))  [\(item.status.rawValue)] \(item.title)")
        }
    }

    struct Remove: ParsableCommand {
        @OptionGroup var options: RootOptions
        @Argument var id: String
        func run() throws { try options.store().deleteItem(id) }
    }
}
