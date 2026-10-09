import ArgumentParser
import Foundation
import VibeDeckCore

@main
struct VibeDeckCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "vibedeck",
        abstract: "Gerencia projetos VibeDeck (links, docs, revisões, regras e ideias) a partir do terminal.",
        version: "0.2.0",
        subcommands: [AI.self, Init.self, Status.self, Stack.self, Patterns.self, Links.self, Docs.self, Review.self, Rules.self, Ideas.self, Agents.self, Commands.self, Skills.self, Workflows.self, Runs.self, Tag.self, Hook.self, Usage.self, Cloud.self, MCPCommand.self]
    )
}

struct RootOptions: ParsableArguments {
    @Option(name: [.customShort("C"), .long], help: "Diretório do projeto (padrão: procura vibedeck.json a partir do diretório atual).")
    var root: String?

    var startURL: URL {
        URL(fileURLWithPath: root.map { NSString(string: $0).expandingTildeInPath } ?? FileManager.default.currentDirectoryPath)
    }

    func store() throws -> ProjectStore {
        let store = try ProjectStore.locate(from: startURL)
        try? store.refreshAgentsGuideIfNeeded()
        return store
    }
}

func hashtags(_ tags: [String]) -> String {
    tags.isEmpty ? "" : "  #" + tags.joined(separator: " #")
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
        let ruleTopics: [String]
        let ideas: [String]
        let agents: [String]
        let commands: [String]
        let skills: [String]
        let workflows: [String]
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
        let topics = try store.listTopics()
        let ideas = try store.listIdeas()
        let agents = try store.listAgents()
        let commands = try store.listCommands()
        let skills = try store.listSkills()
        let workflows = try store.listWorkflows()
        if json {
            try printJSON(Summary(
                root: store.root.path, project: project, docs: docs.map(\.slug),
                groups: groups.map { GroupSummary(slug: $0.slug, title: $0.group.title, open: $0.group.openCount, total: $0.group.items.count) },
                ruleTopics: topics.map(\.slug), ideas: ideas.map(\.slug), agents: agents.map(\.slug),
                commands: commands.map(\.slug), skills: skills.map(\.slug), workflows: workflows.map(\.slug)
            ))
            return
        }
        print("\(project.name) — \(store.root.path)")
        if let d = project.description { print(d) }
        if !project.stack.isEmpty { print("Stack: " + project.stack.map(\.name).joined(separator: ", ")) }
        if !project.patterns.isEmpty { print("Padrões: " + project.patterns.map(\.name).joined(separator: ", ")) }
        print("\nLinks: \(project.links.count)  Docs: \(docs.count)  Grupos de revisão: \(groups.count)")
        for (slug, group) in groups {
            print("  • \(group.title) [\(slug)] — \(group.openCount) aberto(s) de \(group.items.count)")
        }
        let ruleCount = topics.reduce(0) { $0 + $1.topic.rules.count }
        print("Tópicos de regras: \(topics.count) (\(ruleCount) regra(s))  Ideias: \(ideas.count) (\(ideas.filter { !$0.idea.status.isClosed }.count) abertas)  Agentes: \(agents.count)  Comandos: \(commands.count)  Skills: \(skills.count)  Workflows: \(workflows.count)")
    }
}

// MARK: - stack

struct Stack: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Stack do projeto: as tecnologias de destaque (ícones do Skill Icons).",
        discussion: "Ao adicionar ou retirar, o badge da stack no README.md é atualizado.",
        subcommands: [List.self, Add.self, Remove.self, Note.self, Move.self, Search.self, Badge.self],
        defaultSubcommand: List.self
    )

    static func report(_ change: StackService.Change, json: Bool) throws {
        if json { return try printJSON(change) }
        for item in change.items { print(line(item)) }
        if let warning = change.readmeWarning { FileHandle.standardError.write(Data((warning + "\n").utf8)) }
    }

    static func line(_ item: StackItem) -> String {
        "\(item.icon)  \(item.name)" + (item.category.map { "  [\($0)]" } ?? "") + (item.note.map { "  — \($0)" } ?? "")
    }

    struct List: ParsableCommand {
        @OptionGroup var options: RootOptions
        @Flag(help: "Saída JSON.") var json = false

        func run() throws {
            let stack = try options.store().loadProject().stack
            if json { return try printJSON(stack) }
            if stack.isEmpty { print("Stack vazia. Adicione com `vibedeck stack add <tecnologias…>`.") }
            for item in stack { print(Stack.line(item)) }
        }
    }

    struct Add: AsyncParsableCommand {
        @OptionGroup var options: RootOptions
        @Argument(help: "Ids, nomes ou aliases do Skill Icons (ex.: swift k8s \"Next.js\").") var icons: [String]
        @Option(help: "Nota de uso para essas tecnologias.") var note: String?
        @Flag(help: "Marca as tecnologias como adicionadas por IA.") var ai = false
        @Flag(help: "Saída JSON.") var json = false

        func run() async throws {
            let change = try await StackService(store: options.store()).add(icons, note: note, author: ai ? .ai : .human)
            try Stack.report(change, json: json)
        }
    }

    struct Remove: AsyncParsableCommand {
        @OptionGroup var options: RootOptions
        @Argument(help: "Id, nome ou prefixo do id.") var icons: [String]
        @Flag(help: "Saída JSON.") var json = false

        func run() async throws {
            try Stack.report(await StackService(store: options.store()).remove(icons), json: json)
        }
    }

    struct Note: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Define a nota de uso de uma tecnologia (vazia apaga).")
        @OptionGroup var options: RootOptions
        @Argument(help: "Id, nome ou prefixo do id.") var icon: String
        @Argument(help: "Nota.") var note: String = ""
        @Flag(help: "Saída JSON.") var json = false

        func run() async throws {
            try Stack.report(await StackService(store: options.store()).setNote(icon, note), json: json)
        }
    }

    struct Move: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Move uma tecnologia para outra posição (a partir de 0).")
        @OptionGroup var options: RootOptions
        @Argument(help: "Id, nome ou prefixo do id.") var icon: String
        @Argument(help: "Nova posição.") var position: Int
        @Flag(help: "Saída JSON.") var json = false

        func run() async throws {
            try Stack.report(await StackService(store: options.store()).move(icon, to: position), json: json)
        }
    }

    struct Search: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Procura tecnologias no catálogo do Skill Icons.")
        @OptionGroup var options: RootOptions
        @Argument(help: "Texto a procurar (vazio = tudo).") var query: String?
        @Option(help: "Categoria: \(SkillIcons.categories.joined(separator: ", ")).") var category: String?
        @Option(help: "Máximo de resultados.") var limit: Int = 50
        @Flag(help: "Saída JSON.") var json = false

        func run() async throws {
            let icons = try await SkillIcons().search(query: query, category: category, limit: limit)
            if json { return try printJSON(icons) }
            let current = Set((try? options.store().loadProject().stack.map(\.icon)) ?? [])
            for icon in icons {
                print((current.contains(icon.id) ? "✓ " : "  ") + "\(icon.id)  \(icon.name)" + (icon.category.map { "  [\($0)]" } ?? ""))
            }
        }
    }

    struct Badge: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Mostra o badge da stack (Markdown) e, com --sync, regrava o bloco no README.md.")
        @OptionGroup var options: RootOptions
        @Option(help: "Tema: dark ou light.") var theme: String?
        @Flag(help: "Regrava o bloco da stack no README.md.") var sync = false
        @Flag(help: "Saída JSON.") var json = false

        func run() async throws {
            let service = StackService(store: try options.store())
            if sync, let warning = await service.syncReadme() { throw ValidationError(warning) }
            guard let badge = try await service.badge(theme: theme.flatMap(SkillIconTheme.init(rawValue:))) else {
                if json { return print("null") }
                return print("Stack vazia.")
            }
            if json { return try printJSON(badge) }
            print(badge.markdown)
        }
    }
}

// MARK: - patterns

struct Patterns: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Padrões de projeto que o código deve seguir (TDD, hexagonal, DDD, CQRS…).",
        discussion: "Cada padrão cria um tópico de regras em .vibedeck/rules/, cobrado pelo `rules for` / `rules check`.",
        subcommands: [List.self, Catalog.self, Add.self, Remove.self, Note.self, Paths.self, Move.self],
        defaultSubcommand: List.self
    )

    static func line(_ pattern: ProjectPattern, store: ProjectStore) -> String {
        let topic = store.patternTopic(pattern)
        let scope = topic.map { $0.topic.paths.isEmpty ? "projeto inteiro" : $0.topic.paths.joined(separator: ", ") } ?? "sem tópico"
        let rules = topic.map { "\($0.topic.rules.count) regra(s) em \($0.slug)" } ?? ""
        return "\(pattern.id)  \(pattern.name)  [\(PatternCategory.label(pattern.category))]  (\(scope); \(rules))"
            + (pattern.note.map { "\n    — \($0)" } ?? "")
    }

    static func report(_ store: ProjectStore, json: Bool) throws {
        let patterns = try store.loadProject().patterns
        if json { return try printJSON(patterns) }
        if patterns.isEmpty { print("Nenhum padrão. Veja `vibedeck patterns catalog` e adicione com `vibedeck patterns add <ids…>`.") }
        for pattern in patterns { print(line(pattern, store: store)) }
    }

    struct List: ParsableCommand {
        @OptionGroup var options: RootOptions
        @Flag(help: "Saída JSON.") var json = false

        func run() throws { try Patterns.report(options.store(), json: json) }
    }

    struct Catalog: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Lista o catálogo embutido de padrões.")
        @OptionGroup var options: RootOptions
        @Argument(help: "Texto a procurar (vazio = tudo).") var query: String?
        @Flag(help: "Saída JSON.") var json = false

        func run() throws {
            let templates = PatternCatalog.search(query)
            if json { return try printJSON(templates) }
            let current = Set((try? options.store().loadProject().patterns.map(\.id)) ?? [])
            for t in templates {
                print((current.contains(t.id) ? "✓ " : "  ") + "\(t.id)  \(t.name)  [\(PatternCategory.label(t.category))]  — \(t.summary)")
            }
        }
    }

    struct Add: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Adiciona padrões do catálogo, ou um personalizado com --custom.",
            discussion: "Ex.: vibedeck patterns add tdd hexagonal --path 'Sources/Core/**'\n     vibedeck patterns add --custom \"Feature folders\" --rule \"Uma pasta por feature\""
        )
        @OptionGroup var options: RootOptions
        @Argument(help: "Ids, nomes ou aliases do catálogo.") var patterns: [String] = []
        @Option(help: "Nome de um padrão personalizado.") var custom: String?
        @Option(help: "Resumo do padrão personalizado.") var summary: String?
        @Option(help: "Regra obrigatória do padrão personalizado (repita).") var rule: [String] = []
        @Option(help: "Como o projeto aplica o padrão.") var note: String?
        @Option(help: "Glob de escopo (repita; sem = projeto inteiro).") var path: [String] = []
        @Flag(help: "Marca como adicionado por IA.") var ai = false
        @Flag(help: "Saída JSON.") var json = false

        func run() throws {
            let store = try options.store()
            let author: Author = ai ? .ai : .human
            let paths = path.isEmpty ? nil : path
            if let custom {
                guard !rule.isEmpty else { throw ValidationError("Padrão personalizado precisa de ao menos uma --rule.") }
                try store.addCustomPattern(name: custom, summary: summary, rules: rule, note: note, paths: paths, author: author)
            } else {
                guard !patterns.isEmpty else { throw ValidationError("Informe ids do catálogo ou --custom <nome>.") }
                try store.addPatterns(patterns, note: note, paths: paths, author: author)
            }
            try Patterns.report(store, json: json)
        }
    }

    struct Remove: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Retira padrões e apaga o tópico de regras deles.")
        @OptionGroup var options: RootOptions
        @Argument(help: "Id, nome ou prefixo do id.") var patterns: [String]
        @Flag(help: "Saída JSON.") var json = false

        func run() throws {
            let store = try options.store()
            try store.removePatterns(patterns)
            try Patterns.report(store, json: json)
        }
    }

    struct Note: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Define como o projeto aplica um padrão (vazia apaga).")
        @OptionGroup var options: RootOptions
        @Argument(help: "Id, nome ou prefixo do id.") var pattern: String
        @Argument(help: "Nota.") var note: String = ""
        @Flag(help: "Saída JSON.") var json = false

        func run() throws {
            let store = try options.store()
            try store.setPatternNote(pattern, note)
            try Patterns.report(store, json: json)
        }
    }

    struct Paths: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Define os globs de escopo de um padrão (sem globs = projeto inteiro).")
        @OptionGroup var options: RootOptions
        @Argument(help: "Id, nome ou prefixo do id.") var pattern: String
        @Argument(help: "Globs (ex.: 'Sources/Core/**').") var globs: [String] = []
        @Flag(help: "Saída JSON.") var json = false

        func run() throws {
            let store = try options.store()
            try store.setPatternPaths(pattern, globs)
            try Patterns.report(store, json: json)
        }
    }

    struct Move: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Move um padrão para outra posição (a partir de 0).")
        @OptionGroup var options: RootOptions
        @Argument(help: "Id, nome ou prefixo do id.") var pattern: String
        @Argument(help: "Nova posição.") var position: Int
        @Flag(help: "Saída JSON.") var json = false

        func run() throws {
            let store = try options.store()
            try store.movePattern(pattern, to: position)
            try Patterns.report(store, json: json)
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
            for doc in try options.store().listDocs() { print("\(doc.slug)\t\(doc.title)\(hashtags(doc.tags))") }
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
            for (slug, g) in try options.store().listGroups() { print("\(slug)\t\(g.title)\t\(g.openCount)/\(g.items.count)\(hashtags(g.tags))") }
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
        @Option(parsing: .upToNextOption, help: "Tópicos de regras que o item precisa cumprir.") var rules: [String] = []
        @Flag(help: "Marca o item como criado por IA.") var ai = false

        func run() throws {
            let store = try options.store()
            let kinds = try store.loadProject().reviewKinds.map(\.id)
            guard kinds.contains(kind) else { throw ValidationError("Kind desconhecido '\(kind)'. Disponíveis: \(kinds.joined(separator: ", "))") }
            let item = ReviewItem(
                kind: kind, title: title, details: details, priority: priority,
                target: ReviewTarget(file: file, route: route, component: component, selector: selector),
                rules: try rules.map { try store.resolveTopicSlug($0) },
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
        @Option(parsing: .upToNextOption, help: "Substitui os tópicos de regras do item.") var rules: [String] = []
        @Flag(help: "Conclui sem check de regras aprovado (só humanos).") var force = false

        func run() throws {
            let store = try options.store()
            if !rules.isEmpty {
                let slugs = try rules.map { try store.resolveTopicSlug($0) }
                try store.updateItem(id) { $0.rules = slugs }
            }
            if status == .done, !force { try store.ensureVerified(id) }
            if let kind {
                let kinds = try store.loadProject().reviewKinds.map(\.id)
                guard kinds.contains(kind) else { throw ValidationError("Kind desconhecido '\(kind)'. Disponíveis: \(kinds.joined(separator: ", "))") }
            }
            let item = try store.updateItem(id) { item in
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

// MARK: - rules

extension RuleSeverity: ExpressibleByArgument {}
extension IdeaStatus: ExpressibleByArgument {}
extension NextStepKind: ExpressibleByArgument {}

private func printRules(_ rules: [Rule], indent: String = "  ") {
    for r in rules {
        let mark = r.severity == .must ? "●" : "○"
        let test = switch r.testState {
        case .none: ""
        case .script: "  ⚙ \(r.test?.command ?? "")"
        case .manual: "  ✋ manual"
        case .stale: "  ⚠ teste desatualizado"
        }
        print("\(indent)\(r.id.uuidString.prefix(8))  \(mark) \(r.text)\(r.author == .ai ? "  ✨" : "")\(test)")
    }
}

struct Rules: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Tópicos de regras que toda tarefa precisa cumprir antes de ser concluída.",
        subcommands: [List.self, Show.self, New.self, Add.self, Remove.self, For.self, Test.self, SetTest.self, Check.self, Checks.self],
        defaultSubcommand: List.self
    )

    struct List: ParsableCommand {
        @OptionGroup var options: RootOptions
        @Flag(help: "Saída JSON.") var json = false

        func run() throws {
            let topics = try options.store().listTopics()
            if json { return try printJSON(topics.map { TopicChecklist(slug: $0.slug, topic: $0.topic) }) }
            for (slug, t) in topics {
                let scope = t.isGlobal ? "global" : t.paths.joined(separator: ", ")
                print("\(slug)\t\(t.title)\t\(t.rules.count) regra(s)\t[\(scope)]\(hashtags(t.tags))")
            }
        }
    }

    struct Show: ParsableCommand {
        @OptionGroup var options: RootOptions
        @Argument(help: "Tópico (slug, id ou título).") var topic: String
        @Flag(help: "Saída JSON.") var json = false

        func run() throws {
            let store = try options.store()
            let slug = try store.resolveTopicSlug(topic)
            let t = try store.loadTopic(slug)
            if json { return try printJSON(TopicChecklist(slug: slug, topic: t)) }
            print("\(t.title) [\(slug)] — \(t.isGlobal ? "global" : t.paths.joined(separator: ", "))")
            if let d = t.description { print(d) }
            printRules(t.rules)
        }
    }

    struct New: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Cria um tópico. Sem --path, vale para toda tarefa.")
        @OptionGroup var options: RootOptions
        @Argument var title: String
        @Option var description: String?
        @Option(name: .customLong("path"), help: "Glob de escopo (repetível), ex.: 'Sources/App/**'.") var paths: [String] = []
        @Option(parsing: .upToNextOption) var tags: [String] = []

        func run() throws { print(try options.store().createTopic(title: title, description: description, tags: tags, paths: paths).slug) }
    }

    struct Add: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Adiciona uma regra a um tópico (cria o tópico se não existir).")
        @OptionGroup var options: RootOptions
        @Argument var topic: String
        @Argument var text: String
        @Option var details: String?
        @Flag(help: "Regra recomendada (não bloqueia).") var should = false
        @Flag(help: "Marca a regra como criada por IA.") var ai = false

        func run() throws {
            let rule = Rule(text: text, details: details, severity: should ? .should : .must, author: ai ? .ai : .human)
            let (slug, _) = try options.store().addRule(rule, toTopic: topic)
            print("\(rule.id.uuidString)\t\(slug)")
        }
    }

    struct Remove: ParsableCommand {
        @OptionGroup var options: RootOptions
        @Argument(help: "Id ou prefixo da regra.") var id: String
        func run() throws { try options.store().deleteRule(id) }
    }

    struct For: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Regras aplicáveis a um conjunto de arquivos.")
        @OptionGroup var options: RootOptions
        @Argument(help: "Arquivos alterados.") var files: [String] = []
        @Option(parsing: .upToNextOption, help: "Tópicos extras.") var topics: [String] = []
        @Option(help: "Id do item de revisão relacionado.") var item: String?
        @Flag(help: "Lista também as regras manuais (por padrão só as de script, as outras viram contagem).") var manual = false
        @Flag(help: "Saída JSON.") var json = false

        func run() throws {
            let store = try options.store()
            var files = files, topics = topics
            if let item {
                let (_, group, index) = try store.findItem(item)
                topics += group.items[index].rules
                if let file = group.items[index].target?.file { files.append(file) }
            }
            let applicable = try store.applicableTopics(files: files, explicit: topics)
            if json { return try printJSON(applicable.map { TopicChecklist(slug: $0.slug, topic: $0.topic, includeManual: manual) }) }
            if applicable.isEmpty { return print("Nenhuma regra aplicável.") }
            for (slug, t) in applicable {
                print("## \(t.title) [\(slug)]")
                printRules(t.rules)
            }
        }
    }

    struct Test: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Roda os scripts das regras aplicáveis (não grava check).",
            discussion: "Exit do script: 0 = cumpre, 77 = não se aplica, outro = viola. Sem arquivos nem tópicos, roda todos os tópicos."
        )
        @OptionGroup var options: RootOptions
        @Argument(help: "Arquivos alterados.") var files: [String] = []
        @Option(parsing: .upToNextOption, help: "Tópicos (só eles, quando não há arquivos).") var topics: [String] = []
        @Option(help: "Id do item de revisão relacionado.") var item: String?
        @Flag(help: "Saída JSON.") var json = false

        func run() throws {
            let store = try options.store()
            let all = files.isEmpty && topics.isEmpty && item == nil
            let runs = try store.runRuleTests(
                files: files, topics: all ? try store.listTopics().map(\.slug) : topics, reviewItem: item,
                onlyTopics: files.isEmpty && item == nil
            )
            if json { return try printJSON(runs.map(RuleTestRunRow.init)) }
            if runs.isEmpty { return print("Nenhuma regra aplicável tem script. Gere com o botão \"Gerar testes\" no app.") }
            for r in runs {
                let icon = switch r.outcome.verdict { case .pass: "✅"; case .fail: "❌"; case .na: "–" }
                print("\(icon) [\(r.topic)] \(r.rule.id.uuidString.prefix(8)) \(r.rule.text)  (exit \(r.outcome.exitCode))")
                if r.outcome.verdict == .fail {
                    print(r.outcome.output.split(separator: "\n", omittingEmptySubsequences: false).map { "    \($0)" }.joined(separator: "\n"))
                }
            }
            if runs.contains(where: { $0.outcome.verdict == .fail && $0.rule.severity == .must }) { throw ExitCode.failure }
        }
    }

    struct SetTest: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "set-test",
            abstract: "Define como uma regra é verificada: por script (--command) ou manual (--manual)."
        )
        @OptionGroup var options: RootOptions
        @Argument(help: "Id ou prefixo da regra.") var id: String
        @Option(help: "Comando do script, rodado na raiz do projeto (ex.: .vibedeck/tests/geral/ab12cd34.sh).") var command: String?
        @Flag(help: "A regra não é testável por script: continua com o agente.") var manual = false
        @Option(help: "O que o script verifica ou por que a regra é manual.") var reason: String?
        @Flag(help: "Remove o teste da regra (e o script em .vibedeck/tests).") var clear = false

        func validate() throws {
            let modes = [command != nil, manual, clear].filter { $0 }.count
            guard modes == 1 else { throw ValidationError("Use exatamente um de --command, --manual ou --clear.") }
        }

        func run() throws {
            let store = try options.store()
            let rule = clear
                ? try store.clearRuleTest(id)
                : try store.setRuleTest(id, mode: manual ? .manual : .script, command: command, reason: reason)
            print("\(rule.id.uuidString.prefix(8))\t\(rule.testState.label)")
        }
    }

    struct Check: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Registra a verificação das regras aplicáveis.",
            discussion: """
            Por padrão só roda os scripts das regras (⚙ em `rules for`); as manuais ficam pendentes.
            Com --manual, lê de stdin (ou --results) um JSON e exige a resposta de todas as manuais:
            [{"ruleId": "ab12", "verdict": "pass|fail|na", "note": "..."}]
            """
        )
        @OptionGroup var options: RootOptions
        @Option(help: "Resumo do que foi feito.") var task: String
        @Option(name: .customLong("file"), help: "Arquivo alterado (repetível).") var files: [String] = []
        @Option(parsing: .upToNextOption, help: "Tópicos extras.") var topics: [String] = []
        @Option(help: "Id do item de revisão relacionado.") var item: String?
        @Option(help: "JSON dos resultados (padrão: stdin).") var results: String?
        @Flag(help: "Marca o check como feito por IA.") var ai = false
        @Flag(help: "Exige a resposta de todas as regras manuais (a parte feita pela IA).") var manual = false
        @Flag(help: "Saída JSON.") var json = false

        func run() throws {
            let raw = results.map { Data($0.utf8) } ?? (manual ? FileHandle.standardInput.readDataToEndOfFile() : Data())
            let answers = try JSONDecoder().decode([RuleAnswer].self, from: raw.isEmpty ? Data("[]".utf8) : raw)
            let check = try options.store().submitCheck(
                task: task, files: files, topics: topics, reviewItem: item, answers: answers, verifyManual: manual, author: ai ? .ai : .human
            )
            if json { return try printJSON(check) }
            let scripted = check.results.filter { $0.source == .script }.count
            print(check.passed ? "✅ Aprovado (\(check.results.count) regra(s), \(scripted) por script)" : "❌ Reprovado")
            for f in check.failures { print("  ✗ \(f)") }
            for w in check.warnings { print("  ⚠ \(w)") }
            if !check.pending.isEmpty { print("  ⏭ \(check.pending.count) regra(s) manual(is) não verificada(s) (use --manual)") }
            if !check.passed { throw ExitCode.failure }
        }
    }

    struct Checks: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Histórico de verificações.")
        @OptionGroup var options: RootOptions
        @Option(help: "Filtra por tópico.") var topic: String?
        @Option var limit = 20
        @Flag(help: "Saída JSON.") var json = false

        func run() throws {
            let store = try options.store()
            let slug = try topic.map { try store.resolveTopicSlug($0) }
            let checks = try store.listChecks().filter { slug == nil || $0.topics.contains(slug!) }.prefix(limit)
            if json { return try printJSON(Array(checks)) }
            for c in checks {
                let item = c.reviewItem.map { "  item \($0.uuidString.prefix(8))" } ?? ""
                print("\(c.createdAt.formatted(date: .numeric, time: .shortened))  \(c.passed ? "✅" : "❌")  \(c.task)\(item)")
            }
        }
    }
}

// MARK: - ideas

struct Ideas: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Ideias futuras do projeto (brainstorm), com regras rascunho.",
        subcommands: [List.self, Show.self, New.self, Set.self, AddRule.self, Promote.self, Unpromote.self],
        defaultSubcommand: List.self
    )

    struct List: ParsableCommand {
        @OptionGroup var options: RootOptions
        @Option(help: "Filtra por status.") var status: IdeaStatus?
        @Flag(help: "Saída JSON.") var json = false

        func run() throws {
            let ideas = try options.store().listIdeas().filter { status == nil || $0.idea.status == status }
            if json { return try printJSON(ideas.map(\.idea)) }
            for (slug, idea) in ideas {
                let tags = idea.tags.isEmpty ? "" : "  #" + idea.tags.joined(separator: " #")
                print("\(slug)\t[\(idea.status.rawValue)] \(idea.title)  (\(idea.rules.count) regra(s))\(tags)")
            }
        }
    }

    struct Show: ParsableCommand {
        @OptionGroup var options: RootOptions
        @Argument var idea: String
        @Flag(help: "Saída JSON.") var json = false

        func run() throws {
            let store = try options.store()
            let idea = try store.loadIdea(store.resolveIdeaSlug(self.idea))
            if json { return try printJSON(idea) }
            print("\(idea.title) — \(idea.status.label)")
            if let body = idea.body, !body.isEmpty { print("\n\(body)\n") }
            if !idea.rules.isEmpty { print("Regras rascunho:"); printRules(idea.rules) }
            if let t = idea.promotedTopic { print("Promovida para o tópico: \(t)") }
        }
    }

    struct New: ParsableCommand {
        @OptionGroup var options: RootOptions
        @Argument var title: String
        @Option var body: String?
        @Option(parsing: .upToNextOption) var tags: [String] = []
        @Flag(help: "Marca a ideia como criada por IA.") var ai = false

        func run() throws {
            print(try options.store().createIdea(title: title, body: body, tags: tags, author: ai ? .ai : .human).slug)
        }
    }

    struct Set: ParsableCommand {
        @OptionGroup var options: RootOptions
        @Argument var idea: String
        @Option var status: IdeaStatus?
        @Option var title: String?
        @Option var body: String?

        func run() throws {
            let (slug, idea) = try options.store().updateIdea(self.idea) { idea in
                if let status { idea.status = status }
                if let title { idea.title = title }
                if let body { idea.body = body }
            }
            print("\(slug)\t[\(idea.status.rawValue)] \(idea.title)")
        }
    }

    struct AddRule: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "add-rule", abstract: "Adiciona uma regra rascunho à ideia.")
        @OptionGroup var options: RootOptions
        @Argument var idea: String
        @Argument var text: String
        @Flag(help: "Regra recomendada (não bloqueia).") var should = false
        @Flag(help: "Marca a regra como criada por IA.") var ai = false

        func run() throws {
            let rule = Rule(text: text, severity: should ? .should : .must, author: ai ? .ai : .human)
            try options.store().addRule(rule, toIdea: idea)
            print(rule.id.uuidString)
        }
    }

    struct Promote: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Transforma as regras da ideia em um tópico de regras ativo.")
        @OptionGroup var options: RootOptions
        @Argument var idea: String
        func run() throws {
            let store = try options.store()
            let stale = try store.unmatchedIdeaPaths(idea)
            print(try store.promoteIdea(idea))
            if !stale.isEmpty {
                FileHandle.standardError.write(Data("Aviso: globs da ideia que não casam nenhum arquivo foram copiados: \(stale.joined(separator: ", "))\n".utf8))
            }
        }
    }

    struct Unpromote: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Desfaz a promoção: apaga o tópico de regras da ideia e remove o vínculo.")
        @OptionGroup var options: RootOptions
        @Argument var idea: String
        func run() throws {
            let store = try options.store()
            let slug = try store.resolveIdeaSlug(idea)
            guard try store.loadIdea(slug).promotedTopic != nil else { return print("A ideia não estava promovida.") }
            let topic = try store.unpromoteIdea(slug)
            print(topic.map { "Tópico removido: \($0)" } ?? "Vínculo removido (o tópico já não existia).")
        }
    }
}

// MARK: - agents

struct Agents: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Agentes do VibeDeck (nome, modelo, prompt) e os próximos passos que formam um fluxo.",
        subcommands: [List.self, Show.self, New.self, Set.self, Next.self, Unnext.self, Flow.self, Import.self],
        defaultSubcommand: List.self
    )

    struct List: ParsableCommand {
        @OptionGroup var options: RootOptions
        @Flag(help: "Saída JSON.") var json = false

        func run() throws {
            let agents = try options.store().listAgents()
            if json { return try printJSON(agents.map(\.agent)) }
            for (slug, a) in agents {
                let tags = a.tags.isEmpty ? "" : "  #" + a.tags.joined(separator: " #")
                print("\(slug)\t\(a.title)  [\(a.model ?? "herdado")]  → \(a.nextSteps.count) passo(s)\(tags)")
            }
        }
    }

    struct Show: ParsableCommand {
        @OptionGroup var options: RootOptions
        @Argument var agent: String
        @Flag(help: "Saída JSON.") var json = false

        func run() throws {
            let store = try options.store()
            let a = try store.loadAgent(store.resolveAgentSlug(agent))
            if json { return try printJSON(a) }
            print("\(a.title) — modelo: \(a.model ?? "herdado")")
            if let s = a.summary { print(s) }
            if !a.tools.isEmpty { print("Ferramentas: " + a.tools.joined(separator: ", ")) }
            print("\n\(a.prompt)\n")
            for step in a.nextSteps { print("→ [\(step.kind.rawValue)] \(step.ref)\(step.note.map { " — \($0)" } ?? "")") }
        }
    }

    struct New: ParsableCommand {
        @OptionGroup var options: RootOptions
        @Argument var title: String
        @Option var model: String?
        @Option var summary: String?
        @Option var prompt: String = ""
        @Option(parsing: .upToNextOption) var tools: [String] = []
        @Option(parsing: .upToNextOption) var tags: [String] = []
        @Flag(help: "Marca o agente como criado por IA.") var ai = false

        func run() throws {
            print(try options.store().createAgent(
                title: title, summary: summary, model: model, tools: tools, prompt: prompt, tags: tags, author: ai ? .ai : .human
            ).slug)
        }
    }

    struct Set: ParsableCommand {
        @OptionGroup var options: RootOptions
        @Argument var agent: String
        @Option var title: String?
        @Option var model: String?
        @Option var provider: AIProvider?
        @Option var effort: String?
        @Option var summary: String?
        @Option var prompt: String?

        func run() throws {
            let (slug, a) = try options.store().updateAgent(agent) { a in
                if let title { a.title = title }
                if let provider {
                    var all = a.providerSettings ?? [:]
                    var settings = all[provider.rawValue] ?? AIProviderSettings()
                    if let model { settings.model = model.nonEmptyOrNil }
                    if let effort { settings.effort = effort.nonEmptyOrNil }
                    all[provider.rawValue] = settings; a.providerSettings = all
                } else if let model { a.model = model.nonEmptyOrNil }
                if let summary { a.summary = summary.nonEmptyOrNil }
                if let prompt { a.prompt = prompt }
            }
            print("\(slug)\t\(a.title)")
        }
    }

    struct Next: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Adiciona um próximo passo (agente, comando ou skill do VibeDeck) ao agente.")
        @OptionGroup var options: RootOptions
        @Argument var agent: String
        @Argument(help: "Agente (slug, id ou título), comando ou skill do VibeDeck.") var target: String
        @Option var kind: NextStepKind = .agent
        @Option var note: String?

        func run() throws {
            let (slug, a) = try options.store().addNextStep(to: agent, kind: kind, target: target, note: note)
            print("\(slug)\t\(a.nextSteps.count) passo(s)")
        }
    }

    struct Unnext: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "unnext", abstract: "Remove um próximo passo do agente.")
        @OptionGroup var options: RootOptions
        @Argument var agent: String
        @Argument var ref: String

        func run() throws {
            let store = try options.store()
            let targets = Swift.Set([ref, try? store.resolveAgentSlug(ref), try? store.resolveCommandSlug(ref), try? store.resolveSkillSlug(ref)].compactMap { $0 })
            try store.updateAgent(agent) { $0.nextSteps.removeAll { targets.contains($0.ref) } }
        }
    }

    struct Flow: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Imprime o JSON do fluxo (agente + próximos passos) para orquestrar a IA em um prompt.")
        @OptionGroup var options: RootOptions
        @Argument var agent: String

        func run() throws {
            let store = try options.store()
            let slug = try store.resolveAgentSlug(agent)
            print(try AgentFlow.json(from: slug, agents: store.listAgents(), commands: store.listCommands(), skills: store.listSkills()) ?? "")
        }
    }

    struct Import: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Importa agentes do Claude Code (.claude/agents do projeto e do usuário).")
        @OptionGroup var options: RootOptions
        @Option(help: "Provedor: claude ou codex.") var provider: AIProvider = .claude
        @Flag(help: "Sobrescreve agentes já existentes.") var overwrite = false
        @Option(help: "Diretório extra com arquivos .md de agentes.") var dir: String?
        @Flag(help: "Marca os agentes como criados por IA.") var ai = false

        func run() async throws {
            let store = try options.store()
            let dirs = dir.map { [URL(fileURLWithPath: $0)] }
            let result = try store.importAgents(provider: provider, from: dirs, overwrite: overwrite, author: ai ? .ai : .human)
            result.warnings.forEach { FileHandle.standardError.write(Data(($0 + "\n").utf8)) }
            let slugs = result.slugs
            slugs.forEach { print($0) }
            if slugs.isEmpty { print("Nada para importar.") }
        }
    }
}

// MARK: - commands

struct Commands: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Comandos do VibeDeck (prompt no formato de slash command) e os próximos passos que formam um fluxo.",
        subcommands: [List.self, Show.self, New.self, Set.self, Next.self, Unnext.self, Flow.self, Import.self],
        defaultSubcommand: List.self
    )

    struct List: ParsableCommand {
        @OptionGroup var options: RootOptions
        @Flag(help: "Saída JSON.") var json = false

        func run() throws {
            let commands = try options.store().listCommands()
            if json { return try printJSON(commands.map(\.command)) }
            for (slug, c) in commands {
                let tags = c.tags.isEmpty ? "" : "  #" + c.tags.joined(separator: " #")
                let hint = c.argumentHint.map { " \($0)" } ?? ""
                print("\(slug)\t\(c.title)\(hint)  [\(c.model ?? "herdado")]  → \(c.nextSteps.count) passo(s)\(tags)")
            }
        }
    }

    struct Show: ParsableCommand {
        @OptionGroup var options: RootOptions
        @Argument var command: String
        @Flag(help: "Saída JSON.") var json = false

        func run() throws {
            let store = try options.store()
            let c = try store.loadCommand(store.resolveCommandSlug(command))
            if json { return try printJSON(c) }
            print("\(c.title) — modelo: \(c.model ?? "herdado")")
            if let s = c.summary { print(s) }
            if let h = c.argumentHint { print("Argumentos: \(h)") }
            if !c.tools.isEmpty { print("Ferramentas: " + c.tools.joined(separator: ", ")) }
            print("\n\(c.prompt)\n")
            for step in c.nextSteps { print("→ [\(step.kind.rawValue)] \(step.ref)\(step.note.map { " — \($0)" } ?? "")") }
        }
    }

    struct New: ParsableCommand {
        @OptionGroup var options: RootOptions
        @Argument var title: String
        @Option var model: String?
        @Option var summary: String?
        @Option(help: "O que vai em $ARGUMENTS (ex.: \"<mensagem>\").") var argumentHint: String?
        @Option var prompt: String = ""
        @Option(parsing: .upToNextOption) var tools: [String] = []
        @Option(parsing: .upToNextOption) var tags: [String] = []
        @Flag(help: "Marca o comando como criado por IA.") var ai = false

        func run() throws {
            print(try options.store().createCommand(
                title: title, summary: summary, argumentHint: argumentHint, model: model, tools: tools, prompt: prompt,
                tags: tags, author: ai ? .ai : .human
            ).slug)
        }
    }

    struct Set: ParsableCommand {
        @OptionGroup var options: RootOptions
        @Argument var command: String
        @Option var title: String?
        @Option var model: String?
        @Option var provider: AIProvider?
        @Option var effort: String?
        @Option var summary: String?
        @Option var argumentHint: String?
        @Option var prompt: String?

        func run() throws {
            let (slug, c) = try options.store().updateCommand(command) { c in
                if let title { c.title = title }
                if let provider {
                    var all = c.providerSettings ?? [:]
                    var settings = all[provider.rawValue] ?? AIProviderSettings()
                    if let model { settings.model = model.nonEmptyOrNil }
                    if let effort { settings.effort = effort.nonEmptyOrNil }
                    all[provider.rawValue] = settings; c.providerSettings = all
                } else if let model { c.model = model.nonEmptyOrNil }
                if let summary { c.summary = summary.nonEmptyOrNil }
                if let argumentHint { c.argumentHint = argumentHint.nonEmptyOrNil }
                if let prompt { c.prompt = prompt }
            }
            print("\(slug)\t\(c.title)")
        }
    }

    struct Next: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Adiciona um próximo passo (agente, comando ou skill do VibeDeck) ao comando.")
        @OptionGroup var options: RootOptions
        @Argument var command: String
        @Argument(help: "Agente, comando ou skill do VibeDeck (slug, id ou título).") var target: String
        @Option var kind: NextStepKind = .agent
        @Option var note: String?

        func run() throws {
            let (slug, c) = try options.store().addCommandNextStep(to: command, kind: kind, target: target, note: note)
            print("\(slug)\t\(c.nextSteps.count) passo(s)")
        }
    }

    struct Unnext: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "unnext", abstract: "Remove um próximo passo do comando.")
        @OptionGroup var options: RootOptions
        @Argument var command: String
        @Argument var ref: String

        func run() throws {
            let store = try options.store()
            let targets = Swift.Set([ref, try? store.resolveAgentSlug(ref), try? store.resolveCommandSlug(ref), try? store.resolveSkillSlug(ref)].compactMap { $0 })
            try store.updateCommand(command) { $0.nextSteps.removeAll { targets.contains($0.ref) } }
        }
    }

    struct Flow: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Imprime o JSON do fluxo (comando + próximos passos) para orquestrar a IA em um prompt.")
        @OptionGroup var options: RootOptions
        @Argument var command: String

        func run() throws {
            let store = try options.store()
            let slug = try store.resolveCommandSlug(command)
            print(try AgentFlow.json(kind: .command, from: slug, agents: store.listAgents(), commands: store.listCommands(), skills: store.listSkills()) ?? "")
        }
    }

    struct Import: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Importa comandos do Claude Code (.claude/commands do projeto e do usuário).")
        @OptionGroup var options: RootOptions
        @Option(help: "Provedor: claude ou codex.") var provider: AIProvider = .claude
        @Flag(help: "Sobrescreve comandos já existentes.") var overwrite = false
        @Option(help: "Diretório extra com arquivos .md de comandos.") var dir: String?
        @Flag(help: "Marca os comandos como criados por IA.") var ai = false

        func run() async throws {
            let store = try options.store()
            let dirs = dir.map { [URL(fileURLWithPath: $0)] }
            let result = try store.importCommands(provider: provider, from: dirs, overwrite: overwrite, author: ai ? .ai : .human)
            result.warnings.forEach { FileHandle.standardError.write(Data(($0 + "\n").utf8)) }
            let slugs = result.slugs
            slugs.forEach { print($0) }
            if slugs.isEmpty { print("Nada para importar.") }
        }
    }
}

// MARK: - skills

struct Skills: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Skills do VibeDeck (instruções no formato do SKILL.md) e os próximos passos que formam um fluxo.",
        subcommands: [List.self, Show.self, New.self, Set.self, Next.self, Unnext.self, Flow.self, Import.self],
        defaultSubcommand: List.self
    )

    struct List: ParsableCommand {
        @OptionGroup var options: RootOptions
        @Flag(help: "Saída JSON.") var json = false

        func run() throws {
            let skills = try options.store().listSkills()
            if json { return try printJSON(skills.map(\.skill)) }
            for (slug, s) in skills {
                let tags = s.tags.isEmpty ? "" : "  #" + s.tags.joined(separator: " #")
                print("\(slug)\t\(s.title)  [\(s.model ?? "herdado")]  → \(s.nextSteps.count) passo(s)\(tags)")
            }
        }
    }

    struct Show: ParsableCommand {
        @OptionGroup var options: RootOptions
        @Argument var skill: String
        @Flag(help: "Saída JSON.") var json = false

        func run() throws {
            let store = try options.store()
            let s = try store.loadSkill(store.resolveSkillSlug(skill))
            if json { return try printJSON(s) }
            print("\(s.title) — modelo: \(s.model ?? "herdado")")
            if let d = s.summary { print(d) }
            if !s.tools.isEmpty { print("Ferramentas: " + s.tools.joined(separator: ", ")) }
            print("\n\(s.prompt)\n")
            for step in s.nextSteps { print("→ [\(step.kind.rawValue)] \(step.ref)\(step.note.map { " — \($0)" } ?? "")") }
        }
    }

    struct New: ParsableCommand {
        @OptionGroup var options: RootOptions
        @Argument var title: String
        @Option var model: String?
        @Option(help: "Quando usar a skill (é o que a dispara).") var summary: String?
        @Option var prompt: String = ""
        @Option(parsing: .upToNextOption) var tools: [String] = []
        @Option(parsing: .upToNextOption) var tags: [String] = []
        @Flag(help: "Marca a skill como criada por IA.") var ai = false

        func run() throws {
            print(try options.store().createSkill(
                title: title, summary: summary, model: model, tools: tools, prompt: prompt, tags: tags, author: ai ? .ai : .human
            ).slug)
        }
    }

    struct Set: ParsableCommand {
        @OptionGroup var options: RootOptions
        @Argument var skill: String
        @Option var title: String?
        @Option var model: String?
        @Option var provider: AIProvider?
        @Option var effort: String?
        @Option var summary: String?
        @Option var prompt: String?

        func run() throws {
            let (slug, s) = try options.store().updateSkill(skill) { s in
                if let title { s.title = title }
                if let provider {
                    var all = s.providerSettings ?? [:]
                    var settings = all[provider.rawValue] ?? AIProviderSettings()
                    if let model { settings.model = model.nonEmptyOrNil }
                    if let effort { settings.effort = effort.nonEmptyOrNil }
                    all[provider.rawValue] = settings; s.providerSettings = all
                } else if let model { s.model = model.nonEmptyOrNil }
                if let summary { s.summary = summary.nonEmptyOrNil }
                if let prompt { s.prompt = prompt }
            }
            print("\(slug)\t\(s.title)")
        }
    }

    struct Next: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Adiciona um próximo passo (agente, comando ou skill do VibeDeck) à skill.")
        @OptionGroup var options: RootOptions
        @Argument var skill: String
        @Argument(help: "Agente, comando ou skill do VibeDeck (slug, id ou título).") var target: String
        @Option var kind: NextStepKind = .agent
        @Option var note: String?

        func run() throws {
            let (slug, s) = try options.store().addSkillNextStep(to: skill, kind: kind, target: target, note: note)
            print("\(slug)\t\(s.nextSteps.count) passo(s)")
        }
    }

    struct Unnext: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "unnext", abstract: "Remove um próximo passo da skill.")
        @OptionGroup var options: RootOptions
        @Argument var skill: String
        @Argument var ref: String

        func run() throws {
            let store = try options.store()
            let targets = Swift.Set([ref, try? store.resolveAgentSlug(ref), try? store.resolveCommandSlug(ref), try? store.resolveSkillSlug(ref)].compactMap { $0 })
            try store.updateSkill(skill) { $0.nextSteps.removeAll { targets.contains($0.ref) } }
        }
    }

    struct Flow: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Imprime o JSON do fluxo (skill + próximos passos) para orquestrar a IA em um prompt.")
        @OptionGroup var options: RootOptions
        @Argument var skill: String

        func run() throws {
            let store = try options.store()
            let slug = try store.resolveSkillSlug(skill)
            print(try AgentFlow.json(kind: .skill, from: slug, agents: store.listAgents(), commands: store.listCommands(), skills: store.listSkills()) ?? "")
        }
    }

    struct Import: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Importa skills do Claude Code (.claude/skills/<nome>/SKILL.md do projeto e do usuário).")
        @OptionGroup var options: RootOptions
        @Option(help: "Provedor: claude ou codex.") var provider: AIProvider = .claude
        @Flag(help: "Sobrescreve skills já existentes.") var overwrite = false
        @Option(help: "Diretório extra com pastas de skills (cada uma com SKILL.md).") var dir: String?
        @Flag(help: "Marca as skills como criadas por IA.") var ai = false

        func run() async throws {
            let store = try options.store()
            let dirs = dir.map { [URL(fileURLWithPath: $0)] }
            let result = try await store.importSkills(provider: provider, from: dirs, overwrite: overwrite, author: ai ? .ai : .human)
            result.warnings.forEach { FileHandle.standardError.write(Data(($0 + "\n").utf8)) }
            let slugs = result.slugs
            slugs.forEach { print($0) }
            if slugs.isEmpty { print("Nada para importar.") }
        }
    }
}

// MARK: - workflows

struct Workflows: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Workflows do VibeDeck: etapas (agentes, comandos e skills) e transições condicionais que orquestram um fluxo inteiro.",
        subcommands: [List.self, Show.self, New.self, Set.self, Step.self, Unstep.self, Move.self, Visits.self, Route.self, Unroute.self, Flow.self],
        defaultSubcommand: List.self
    )

    struct List: ParsableCommand {
        @OptionGroup var options: RootOptions
        @Flag(help: "Saída JSON.") var json = false

        func run() throws {
            let workflows = try options.store().listWorkflows()
            if json { return try printJSON(workflows.map(\.workflow)) }
            for (slug, w) in workflows {
                let tags = w.tags.isEmpty ? "" : "  #" + w.tags.joined(separator: " #")
                print("\(slug)\t\(w.title)  → \(w.steps.count) etapa(s)\(tags)")
            }
        }
    }

    struct Show: ParsableCommand {
        @OptionGroup var options: RootOptions
        @Argument var workflow: String
        @Flag(help: "Saída JSON.") var json = false

        func run() throws {
            let store = try options.store()
            let w = try store.loadWorkflow(store.resolveWorkflowSlug(workflow))
            if json { return try printJSON(w) }
            print("\(w.title) — até \(w.maxSteps ?? Workflow.defaultMaxSteps) etapa(s) por execução")
            if let d = w.summary { print(d) }
            if let i = w.input { print("Entrada: \(i)") }
            for (n, step) in w.steps.enumerated() {
                let visits = step.maxVisits.map { "  (até \($0)x)" } ?? ""
                print("\n\(n + 1). \(step.id) [\(step.kind.rawValue)] \(step.ref)\(n == 0 ? "  (início)" : "")\(visits)\(step.note.map { " — \($0)" } ?? "")")
                for (i, t) in step.transitions.enumerated() { print("   \(i + 1). \(t.label) → \(t.to)") }
                if step.transitions.isEmpty { print("   → fim") }
            }
        }
    }

    struct New: ParsableCommand {
        @OptionGroup var options: RootOptions
        @Argument var title: String
        @Option var summary: String?
        @Option(help: "O que pedir ao iniciar (ex.: <número do PR>).") var input: String?
        @Option(help: "Limite de etapas executadas (padrão: \(Workflow.defaultMaxSteps)).") var maxSteps: Int?
        @Option(parsing: .upToNextOption) var tags: [String] = []
        @Flag(help: "Marca o workflow como criado por IA.") var ai = false

        func run() throws {
            print(try options.store().createWorkflow(
                title: title, summary: summary, input: input, maxSteps: maxSteps, tags: tags, author: ai ? .ai : .human
            ).slug)
        }
    }

    struct Set: ParsableCommand {
        @OptionGroup var options: RootOptions
        @Argument var workflow: String
        @Option var title: String?
        @Option var summary: String?
        @Option var input: String?
        @Option(help: "Limite de etapas executadas (0 volta ao padrão).") var maxSteps: Int?

        func run() throws {
            let (slug, w) = try options.store().updateWorkflow(workflow) { w in
                if let title { w.title = title }
                if let summary { w.summary = summary.nonEmptyOrNil }
                if let input { w.input = input.nonEmptyOrNil }
                if let maxSteps { w.maxSteps = maxSteps > 0 ? maxSteps : nil }
            }
            print("\(slug)\t\(w.title)")
        }
    }

    struct Step: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Adiciona uma etapa (agente, comando ou skill do VibeDeck). A primeira etapa é o início.")
        @OptionGroup var options: RootOptions
        @Argument var workflow: String
        @Argument(help: "Agente, comando ou skill do VibeDeck (slug, id ou título).") var target: String
        @Option var kind: NextStepKind = .agent
        @Option(help: "Instrução extra da etapa ($ARGUMENTS para comandos).") var note: String?
        @Option(help: "Máximo de vezes que a etapa roda por ciclo de uma execução.") var maxVisits: Int?

        func run() throws {
            let store = try options.store()
            let (slug, _, step) = try store.addWorkflowStep(to: workflow, kind: kind, target: target, note: note)
            if let maxVisits { try store.setWorkflowStepMaxVisits(slug, step: step, maxVisits: maxVisits) }
            print("\(slug)\t\(step)")
        }
    }

    struct Visits: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Define quantas vezes uma etapa pode rodar por ciclo de uma execução (0 remove o limite).")
        @OptionGroup var options: RootOptions
        @Argument var workflow: String
        @Argument(help: "Id ou posição da etapa.") var step: String
        @Argument(help: "Máximo de vezes (0 = sem limite).") var max: Int

        func run() throws {
            let (slug, _) = try options.store().setWorkflowStepMaxVisits(workflow, step: step, maxVisits: max)
            print("\(slug)\t\(step): \(max > 0 ? "até \(max)x" : "sem limite")")
        }
    }

    struct Unstep: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Remove uma etapa (e as transições que apontam para ela).")
        @OptionGroup var options: RootOptions
        @Argument var workflow: String
        @Argument(help: "Id ou posição (1, 2, …) da etapa.") var step: String

        func run() throws {
            let (slug, w) = try options.store().removeWorkflowStep(workflow, step: step)
            print("\(slug)\t\(w.steps.count) etapa(s)")
        }
    }

    struct Move: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Move uma etapa para outra posição (1 = início).")
        @OptionGroup var options: RootOptions
        @Argument var workflow: String
        @Argument(help: "Id ou posição da etapa.") var step: String
        @Argument(help: "Nova posição (1, 2, …).") var position: Int

        func run() throws {
            let (slug, w) = try options.store().moveWorkflowStep(workflow, step: step, to: position)
            print("\(slug)\t" + w.steps.map(\.id).joined(separator: " → "))
        }
    }

    struct Route: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Adiciona uma transição entre etapas (pode voltar). --verdict casa a última linha do resultado; --when é uma condição; sem nenhum é o \"senão\"."
        )
        @OptionGroup var options: RootOptions
        @Argument var workflow: String
        @Argument(help: "Etapa de origem (id ou posição).") var from: String
        @Argument(help: "Etapa de destino (id ou posição).") var to: String
        @Option(help: "Veredito (última linha do resultado da etapa, ex.: APROVADO) que leva a esta transição.") var verdict: String?
        @Option(help: "Condição em linguagem natural sobre o resultado da etapa.") var when: String?

        func run() throws {
            let (slug, w) = try options.store().addWorkflowTransition(workflow, from: from, to: to, when: when, verdict: verdict)
            let step = w.steps[w.stepIndex(from) ?? 0]
            print("\(slug)\t\(step.id): \(step.transitions.count) transição(ões)")
        }
    }

    struct Unroute: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Remove uma transição de uma etapa (pela posição mostrada em `show`).")
        @OptionGroup var options: RootOptions
        @Argument var workflow: String
        @Argument(help: "Etapa de origem (id ou posição).") var from: String
        @Argument(help: "Posição da transição (1, 2, …).") var index: Int

        func run() throws {
            try options.store().removeWorkflowTransition(workflow, from: from, index: index)
        }
    }

    struct Flow: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Imprime o JSON do workflow (etapas, transições e regras de execução) para orquestrar a IA.")
        @OptionGroup var options: RootOptions
        @Argument var workflow: String
        @Option(help: "Entrada desta execução (sem ela, a IA pede a entrada ao usuário).") var input: String?
        @Flag(help: "Imprime o prompt completo (instrução + JSON) em vez de só o JSON.") var prompt = false

        func run() throws {
            let plan = try options.store().workflowPlan(workflow, input: input)
            print(prompt ? try plan.prompt() : try plan.json())
        }
    }
}

// MARK: - runs

/// How the subagents should call this CLI: the absolute path when it was run by path, else `vibedeck`.
func cliInvocation() -> String {
    let arg0 = CommandLine.arguments.first ?? "vibedeck"
    return arg0.contains("/") ? URL(fileURLWithPath: arg0).standardizedFileURL.path : "vibedeck"
}

func printRunAction(_ action: WorkflowRunAction, json: Bool) throws {
    if json { return try printJSON(action) }
    print("\(action.action.rawValue)\t\(action.step ?? "-")\t\(action.reason)")
    for c in action.candidates ?? [] { print("  \(c.label) → \(c.to)") }
    for q in action.questions ?? [] { print("  \(q.number). [\(q.step)] \(q.question)") }
}

struct Runs: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Execuções de workflows: estado em disco, uma etapa por subagente, veredito decide a transição, perguntas sobem ao orquestrador.",
        subcommands: [List.self, Show.self, Start.self, Next.self, StepPrompt.self, Record.self, Ask.self, Questions.self, Answer.self, Stop.self, Delete.self, Orchestrate.self],
        defaultSubcommand: List.self
    )

    struct List: ParsableCommand {
        @OptionGroup var options: RootOptions
        @Option(help: "Só as execuções deste workflow.") var workflow: String?
        @Option(help: "running, waiting, done ou stopped.") var status: WorkflowRunStatus?
        @Flag(help: "Saída JSON.") var json = false

        struct Row: Encodable { let ref: String; let run: WorkflowRun }

        func run() throws {
            let runs = try options.store().listRuns(workflow: workflow).filter { status == nil || $0.run.status == status }
            if json { return try printJSON(runs.map { Row(ref: $0.ref, run: $0.run) }) }
            for (ref, r) in runs {
                print("\(ref)\t\(r.status.rawValue)\t\(r.current ?? "-")\t\(r.history.count) etapa(s)\(r.openQuestions.isEmpty ? "" : "  ❓\(r.openQuestions.count)")")
            }
        }
    }

    struct Show: ParsableCommand {
        @OptionGroup var options: RootOptions
        @Argument(help: "<workflow>/<execução>, nome da execução ou id.") var execution: String
        @Flag(help: "Saída JSON.") var json = false

        func run() throws {
            let store = try options.store()
            let ref = try store.resolveRunRef(execution)
            let r = try store.loadRun(ref)
            if json { return try printJSON(r) }
            print("\(ref) — \(r.status.rawValue)\(r.input.map { " — entrada: \($0)" } ?? "")")
            if let reason = r.reason { print(reason) }
            for (n, e) in r.history.enumerated() {
                print("\(n + 1). [c\(e.cycle)] \(e.step) → \(e.verdict ?? "—")\(e.next.map { " ⇒ \($0)" } ?? " ⇒ fim")\(e.summary.map { "  · \($0)" } ?? "")")
            }
            if let current = r.current, !r.isFinished { print("Próxima: \(current)") }
            for q in r.questions { print("❓ \(q.number). [\(q.step)] \(q.question)\(q.answer.map { " → \($0)" } ?? "  (aberta)")") }
        }
    }

    struct Start: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Inicia (ou retoma, com a mesma entrada) uma execução e imprime a próxima ação.")
        @OptionGroup var options: RootOptions
        @Option(help: "Provedor da nova execução: claude ou codex.") var provider: AIProvider?
        @Argument var workflow: String
        @Option(help: "Entrada da execução (a execução recebe o nome dela).") var input: String?
        @Option(help: "Etapa por onde começar (libera mais uma volta numa execução parada).") var from: String?
        @Flag(help: "Imprime o prompt do orquestrador em vez da ação.") var prompt = false
        @Flag(help: "Saída JSON.") var json = false

        func run() throws {
            let store = try options.store()
            let (ref, run, action) = try store.startRun(workflow, input: input, from: from, provider: provider)
            if prompt {
                let w = try store.loadWorkflow(store.resolveWorkflowSlug(workflow))
                return print(WorkflowOrchestration.orchestratorPrompt(ref: ref, title: w.title, input: input, cli: cliInvocation(), provider: run.provider))
            }
            try printRunAction(action, json: json)
        }
    }

    struct Next: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Próxima ação do orquestrador: run-step, ask, decide, done ou stop.")
        @OptionGroup var options: RootOptions
        @Argument(help: "<workflow>/<execução>, nome da execução ou id.") var execution: String
        @Flag(help: "Saída JSON.") var json = false

        func run() throws { try printRunAction(try options.store().nextRunAction(execution), json: json) }
    }

    struct StepPrompt: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "step", abstract: "Imprime o prompt da etapa atual (é o que o subagente da etapa segue).")
        @OptionGroup var options: RootOptions
        @Argument(help: "<workflow>/<execução>, nome da execução ou id.") var execution: String

        func run() throws { print(try options.store().runStepPrompt(execution, cli: cliInvocation())) }
    }

    struct Record: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Registra o veredito da etapa atual e imprime a próxima ação.")
        @OptionGroup var options: RootOptions
        @Argument(help: "<workflow>/<execução>, nome da execução ou id.") var execution: String
        @Option(help: "Última linha do resultado da etapa.") var verdict: String?
        @Option(help: "Resumo de 1 a 3 linhas do que a etapa fez.") var summary: String?
        @Option(help: "Etapa escolhida ao avaliar as condições (resposta a `decide`).") var to: String?
        @Flag(name: .customLong("nenhuma"), help: "Nenhuma condição vale (resposta a `decide`): segue o senão ou termina.") var noneHolds = false
        @Flag(help: "Saída JSON.") var json = false

        func run() throws {
            try printRunAction(try options.store().recordRun(execution, verdict: verdict, summary: summary, to: to, noneHolds: noneHolds), json: json)
        }
    }

    struct Ask: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Grava perguntas da etapa atual (JSON no stdin: [{question, context, options: [{label, description}], multiple}]); a execução espera as respostas."
        )
        @OptionGroup var options: RootOptions
        @Argument(help: "<workflow>/<execução>, nome da execução ou id.") var execution: String

        func run() throws {
            let data = FileHandle.standardInput.readDataToEndOfFile()
            let drafts: [WorkflowQuestionDraft]
            if let list = try? JSONDecoder().decode([WorkflowQuestionDraft].self, from: data) { drafts = list }
            else { drafts = [try JSONDecoder().decode(WorkflowQuestionDraft.self, from: data)] }
            let added = try options.store().askRun(execution, questions: drafts)
            print("Pergunta(s) gravada(s): \(added.map { String($0.number) }.joined(separator: ", ")). Termine com a última linha: PERGUNTA")
        }
    }

    struct Questions: ParsableCommand {
        @OptionGroup var options: RootOptions
        @Argument(help: "<workflow>/<execução>, nome da execução ou id.") var execution: String
        @Flag(help: "Só as abertas.") var open = false
        @Flag(help: "Saída JSON.") var json = false

        func run() throws {
            let store = try options.store()
            let r = try store.loadRun(store.resolveRunRef(execution))
            let list = open ? r.openQuestions : r.questions
            if json { return try printJSON(list) }
            for q in list {
                print("\(q.number). [\(q.step)] \(q.question)\(q.answer.map { " → \($0)" } ?? "")")
                for o in q.options { print("   - \(o.label)\(o.description.map { ": \($0)" } ?? "")") }
            }
        }
    }

    struct Answer: ParsableCommand {
        @OptionGroup var options: RootOptions
        @Argument(help: "<workflow>/<execução>, nome da execução ou id.") var execution: String
        @Argument(help: "Número da pergunta.") var number: Int
        @Argument(help: "Resposta (opção escolhida, várias separadas por \"; \", ou texto livre).") var answer: String
        @Flag(help: "Saída JSON.") var json = false

        func run() throws { try printRunAction(try options.store().answerRun(execution, number: number, answer: answer), json: json) }
    }

    struct Stop: ParsableCommand {
        @OptionGroup var options: RootOptions
        @Argument(help: "<workflow>/<execução>, nome da execução ou id.") var execution: String
        @Option(help: "Motivo.") var reason: String?

        func run() throws {
            let r = try options.store().stopRun(execution, reason: reason)
            print("\(execution)\t\(r.status.rawValue)")
        }
    }

    struct Delete: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Apaga a execução e a pasta dela (artefatos das etapas).")
        @OptionGroup var options: RootOptions
        @Argument(help: "<workflow>/<execução>, nome da execução ou id.") var execution: String

        func run() throws { try options.store().deleteRun(execution) }
    }

    struct Orchestrate: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Imprime o prompt do orquestrador de uma execução existente (para continuá-la num chat).")
        @OptionGroup var options: RootOptions
        @Argument(help: "<workflow>/<execução>, nome da execução ou id.") var execution: String

        func run() throws {
            let store = try options.store()
            let ref = try store.resolveRunRef(execution)
            let r = try store.loadRun(ref)
            let title = (try? store.loadWorkflow(r.workflow).title) ?? r.workflow
            print(WorkflowOrchestration.orchestratorPrompt(ref: ref, title: title, input: r.input, cli: cliInvocation(), provider: r.provider))
        }
    }
}

extension WorkflowRunStatus: ExpressibleByArgument {}

// MARK: - tag

struct Tag: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Define as tags de um doc, grupo de revisão, tópico de regras, ideia, agente, comando, skill, workflow, tecnologia da stack ou padrão (sem tags: remove todas).")

    enum Kind: String, ExpressibleByArgument, CaseIterable { case doc, review, rules, idea, agent, command, skill, workflow, stack, pattern }

    @OptionGroup var options: RootOptions
    @Argument(help: "doc, review, rules, idea, agent, command, skill, workflow, stack ou pattern.") var kind: Kind
    @Argument(help: "Slug, id ou título.") var ref: String
    @Argument(help: "Tags (substituem as atuais).") var tags: [String] = []

    func run() throws {
        let store = try options.store()
        switch kind {
        case .doc: try store.setDocTags(ref, tags)
        case .review: try store.updateGroup(ref) { $0.tags = tags }
        case .rules: try store.updateTopic(ref) { $0.tags = tags }
        case .idea: try store.updateIdea(ref) { $0.tags = tags }
        case .agent: try store.updateAgent(ref) { $0.tags = tags }
        case .command: try store.updateCommand(ref) { $0.tags = tags }
        case .skill: try store.updateSkill(ref) { $0.tags = tags }
        case .workflow: try store.updateWorkflow(ref) { $0.tags = tags }
        case .stack: try store.setStackTags(ref, tags)
        case .pattern: try store.setPatternTags(ref, tags)
        }
        print(tags.isEmpty ? "Tags removidas." : "Tags: " + tags.joined(separator: ", "))
    }
}

private extension String {
    var nonEmptyOrNil: String? { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self }
}

// MARK: - hook (portão de regras no Stop do Claude Code e do Codex)

extension HookAgent: ExpressibleByArgument {}
extension AIProvider: ExpressibleByArgument {}

enum HookScope: String, ExpressibleByArgument, CaseIterable {
    case local, project
}

/// Onde cada agente lê os hooks deste projeto. O Codex só tem o arquivo versionado (`.codex/hooks.json`).
func hookFileURL(agent: HookAgent, scope: HookScope, root: URL) -> URL? {
    switch (agent, scope) {
    case (.claude, .local): root.appending(path: ".claude/settings.local.json")
    case (.claude, .project): root.appending(path: ".claude/settings.json")
    case (.codex, .project): root.appending(path: ".codex/hooks.json")
    case (.codex, .local): nil
    }
}

/// Entrada comum dos hooks do Claude Code e do Codex (o Codex pode mandar `transcript_path: null`).
struct HookInput: Decodable {
    var sessionId: String?
    var transcriptPath: String?
    var cwd: String?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id", transcriptPath = "transcript_path", cwd
    }

    static func read() -> HookInput? {
        try? JSONDecoder().decode(HookInput.self, from: FileHandle.standardInput.readDataToEndOfFile())
    }

    /// Arquivo temporário da sessão (`start` marca o início; `count`, os bloqueios seguidos).
    func stateURL(_ kind: String) -> URL {
        FileManager.default.temporaryDirectory.appending(path: "vibedeck-\(kind)-\(sessionId ?? "sem-sessao")")
    }
}

struct Hook: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Hook Stop do Claude Code ou do Codex: o agente não conclui a resposta com alterações sem check de regras aprovado.",
        subcommands: [Status.self, Stop.self, Start.self, Install.self, Uninstall.self],
        defaultSubcommand: Status.self
    )

    struct Status: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Mostra onde o hook está ligado e quais alterações ele bloquearia agora.")
        @OptionGroup var options: RootOptions
        @Flag(help: "Saída JSON.") var json = false

        struct Installed: Encodable {
            let agent: String
            let scope: String
            let file: String
            let on: Bool
        }

        struct Summary: Encodable {
            let hooks: [Installed]
            let unverified: [UnverifiedChange]
        }

        func run() throws {
            let store = try options.store()
            let hooks = try HookAgent.allCases.flatMap { agent in
                try HookScope.allCases.compactMap { scope -> Installed? in
                    guard let url = hookFileURL(agent: agent, scope: scope, root: store.root) else { return nil }
                    return Installed(agent: agent.rawValue, scope: scope.rawValue, file: url.path, on: try ClaudeCode.hasStopHook(settings: url))
                }
            }
            let unverified = try store.unverifiedChanges(store.workingTreeChanges(since: .distantPast))
            if json { return try printJSON(Summary(hooks: hooks, unverified: unverified)) }
            for h in hooks { print("\(h.agent) \(h.scope): \(h.on ? "ligado" : "desligado") (\(h.file))") }
            if unverified.isEmpty { return print("Nenhuma alteração pendente de check.") }
            print(ProjectStore.stopGateReason(unverified))
        }
    }

    struct Stop: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Comando do hook Stop: lê o JSON do agente no stdin e bloqueia o fim da resposta se faltar check.",
            discussion: """
            Considera os arquivos alterados (git) desde o início da sessão. Cada arquivo com regras aplicáveis precisa
            de um check aprovado, registrado depois da última alteração, cobrindo os tópicos dele.
            """
        )
        @OptionGroup var options: RootOptions
        @Option(help: "Bloqueios seguidos na sessão antes de liberar com aviso ao usuário (evita laço infinito).") var maxBlocks = 3

        func run() throws {
            let input = HookInput.read()
            let start = options.root == nil ? input?.cwd.map { URL(fileURLWithPath: $0) } ?? options.startURL : options.startURL
            // Fora de um projeto VibeDeck o hook não tem o que verificar.
            guard let store = try? ProjectStore.locate(from: start) else { return }
            // A sessão começa quando o transcript nasce (Claude Code) ou quando `hook start` rodou (Codex):
            // alterações anteriores (do usuário) não são cobradas.
            let created = { (path: String) in (try? FileManager.default.attributesOfItem(atPath: path))?[.creationDate] as? Date }
            let since = input?.transcriptPath.flatMap(created)
                ?? input.flatMap { created($0.stateURL("start").path) }
                ?? .distantPast
            let unverified = try store.unverifiedChanges(store.workingTreeChanges(since: since))

            let counter = input?.stateURL("count") ?? HookInput().stateURL("count")
            guard !unverified.isEmpty else {
                try? FileManager.default.removeItem(at: counter)
                return
            }
            let blocks = (try? String(contentsOf: counter, encoding: .utf8)).flatMap { Int($0) } ?? 0
            if blocks >= maxBlocks {
                try? FileManager.default.removeItem(at: counter)
                let files = unverified.map(\.file).joined(separator: ", ")
                return try printHookOutput(["systemMessage": "⚠️ VibeDeck: o agente parou sem check de regras aprovado para: \(files)"])
            }
            try? String(blocks + 1).write(to: counter, atomically: true, encoding: .utf8)
            try printHookOutput(["decision": "block", "reason": ProjectStore.stopGateReason(unverified)])
        }

        private func printHookOutput(_ output: [String: String]) throws {
            print(String(decoding: try JSONSerialization.data(withJSONObject: output, options: [.withoutEscapingSlashes]), as: UTF8.self))
        }
    }

    struct Start: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Comando do hook SessionStart: marca o início da sessão (para agentes que não informam o transcript, como o Codex)."
        )

        func run() throws {
            guard let input = HookInput.read(), input.sessionId != nil else { return }
            let marker = input.stateURL("start")
            // Retomar ou compactar a sessão não muda o início: só a primeira chamada cria a marca.
            if !FileManager.default.fileExists(atPath: marker.path) {
                FileManager.default.createFile(atPath: marker.path, contents: nil)
            }
        }
    }

    struct Install: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Liga o hook neste projeto, no Claude Code ou no Codex.",
            discussion: """
            Claude Code: .claude/settings.local.json (--scope local, padrão) ou .claude/settings.json (--scope project).
            Codex: .codex/hooks.json (só --scope project); depois aprove o hook com /hooks no Codex.
            """
        )
        @OptionGroup var options: RootOptions
        @Option(name: [.short, .long], help: "Agente: claude ou codex.") var agent: HookAgent = .claude
        @Option(name: [.short, .long], help: "Escopo: local (só você) ou project (versionado, para o time). Padrão: local no Claude Code, project no Codex.") var scope: HookScope?

        func run() throws {
            let scope = scope ?? (agent == .codex ? .project : .local)
            guard let url = hookFileURL(agent: agent, scope: scope, root: try options.store().root) else {
                throw ValidationError("O Codex não tem um arquivo de hooks só seu por projeto. Use --scope project (.codex/hooks.json).")
            }
            // Arquivos versionados usam o comando do PATH em vez de um caminho absoluto desta máquina.
            try ClaudeCode.installStopHook(
                executable: scope == .project ? "vibedeck" : vibedeckExecutablePath(), settings: url,
                sessionStart: agent.needsSessionStart
            )
            print("Hook ligado em \(url.path).")
            if agent == .codex { print("No Codex, aprove o hook com /hooks antes da próxima resposta (hooks novos só rodam depois de aprovados).") }
        }
    }

    struct Uninstall: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Desliga o hook do VibeDeck neste projeto.")
        @OptionGroup var options: RootOptions
        @Option(name: [.short, .long], help: "Agente: claude ou codex.") var agent: HookAgent = .claude
        @Option(name: [.short, .long], help: "Escopo: local ou project. Padrão: local no Claude Code, project no Codex.") var scope: HookScope?

        func run() throws {
            let scope = scope ?? (agent == .codex ? .project : .local)
            guard let url = hookFileURL(agent: agent, scope: scope, root: try options.store().root) else {
                throw ValidationError("O Codex só tem o escopo project (.codex/hooks.json).")
            }
            try ClaudeCode.uninstallStopHook(settings: url)
            print("Hook do VibeDeck removido de \(url.path).")
        }
    }
}

// MARK: - usage (limites do Claude Code)

struct Usage: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Limites de uso do Claude Code (sessão de 5h e semana), lidos da statusline dele.",
        subcommands: [Show.self, Record.self, Install.self, Uninstall.self],
        defaultSubcommand: Show.self
    )

    struct Show: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Mostra o último uso informado pelo Claude Code.")
        @Flag(help: "Saída JSON.") var json = false
        @Option var provider: AIProvider = .claude

        func run() async throws {
            if provider == .codex {
                let result = try await CodexQueries.limits(root: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
                if json { return try printJSON(result) }
                for limit in CodexRateLimit.list(result) { print("\(limit.id): \(Int(limit.usedPercent))% · \(Int(limit.minutes)) min") }
                return
            }
            guard let usage = ClaudeCode.loadUsage() else {
                throw ValidationError("Nenhum uso registrado ainda. Rode `vibedeck usage install` e use o Claude Code.")
            }
            if json { return try printJSON(usage) }
            print(usage.summary())
            print("Atualizado em \(usage.updatedAt.formatted(date: .abbreviated, time: .shortened))")
        }
    }

    struct Record: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Comando da statusline: lê o JSON do Claude Code no stdin, grava o uso e imprime a linha."
        )
        @Option(help: "Statusline anterior: recebe o mesmo JSON e a saída dela é a que aparece.") var then: String?

        func run() throws {
            let input = FileHandle.standardInput.readDataToEndOfFile()
            let usage = try? ClaudeCode.recordUsage(statusLine: input)
            if let then {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/sh")
                process.arguments = ["-c", then]
                let pipe = Pipe()
                process.standardInput = pipe
                try process.run()
                pipe.fileHandleForWriting.write(input)
                try pipe.fileHandleForWriting.close()
                process.waitUntilExit()
            } else if let usage {
                print(usage.summary())
            }
        }
    }

    struct Install: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Liga a statusline do Claude Code (~/.claude/settings.json) ao VibeDeck, mantendo a atual encadeada."
        )

        func run() throws {
            try ClaudeCode.installStatusLine(executable: vibedeckExecutablePath())
            print("Statusline ligada em \(ClaudeCode.settingsURL.path). O uso aparece depois da próxima resposta do Claude Code.")
        }
    }

    struct Uninstall: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Desliga a statusline do VibeDeck, devolvendo a anterior.")

        func run() throws {
            try ClaudeCode.uninstallStatusLine()
            print("Statusline do VibeDeck removida de \(ClaudeCode.settingsURL.path).")
        }
    }
}

// MARK: - cloud (sessões do Claude Code na nuvem)

struct Cloud: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Sessões do Claude Code na nuvem (claude.ai/code), sobre o repositório no GitHub.",
        discussion: "A branch padrão local precisa ser igual à do GitHub (origin); se não for, nada é criado.",
        subcommands: [Check.self, Start.self],
        defaultSubcommand: Check.self
    )

    struct Check: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Compara a branch padrão local com a do GitHub.")
        @OptionGroup var options: RootOptions
        @Flag(help: "Saída JSON.") var json = false

        func run() throws {
            let sync = CloudSession.check(root: try options.store().root)
            if json {
                try printJSON(sync)
            } else {
                print(sync.message)
                sync.dirty.prefix(10).forEach { print("  • \($0)") }
                if sync.dirty.count > 10 { print("  … e mais \(sync.dirty.count - 10)") }
            }
            if sync.blocked { throw ExitCode.failure }
        }
    }

    struct Start: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Cria uma sessão na nuvem com a tarefa dada, se a branch estiver sincronizada.")
        @OptionGroup var options: RootOptions
        @Option var provider: AIProvider = .claude
        @Option(name: .customLong("env"), help: "ID do ambiente Codex Cloud.") var environment: String?
        @Argument(help: "O que a sessão deve fazer.") var description: String
        @Flag(help: "Cria mesmo com alterações não commitadas (a nuvem não as vê).") var allowDirty = false
        @Flag(help: "Saída JSON.") var json = false

        struct Result: Encodable {
            let sync: CloudSync
            let url: String?
            let output: String
        }

        func run() throws {
            do {
                let result = try CloudSession.launch(root: try options.store().root, description: description, allowDirty: allowDirty, provider: provider, environment: environment)
                if json { return try printJSON(Result(sync: result.sync, url: result.url?.absoluteString, output: result.output)) }
                print(result.url.map { "Sessão criada: \($0.absoluteString)" } ?? result.output)
            } catch let error as VibeDeckError {
                FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
                throw ExitCode.failure
            }
        }
    }
}
