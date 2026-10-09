import Foundation

// MARK: - Patterns

/// A code pattern the project follows (TDD, hexagonal architecture, CQRS…), kept in `vibedeck.json` under `patterns`.
/// Its rules live in a real rule topic (`topic`, with `sourcePattern` pointing back), so `rules_for` enforces them.
public struct ProjectPattern: Codable, Equatable, Hashable, Identifiable, Sendable {
    /// Catalog id (`tdd`, `hexagonal`) or the slug of a custom pattern's name.
    public var id: String
    public var name: String
    public var category: String?
    public var summary: String?
    /// How the project applies it ("hexagonal só no Core; a UI fala com casos de uso"); goes into the topic description.
    public var note: String?
    /// Slug of the rule topic that enforces the pattern.
    public var topic: String?
    public var author: Author

    public init(id: String, name: String, category: String? = nil, summary: String? = nil, note: String? = nil, topic: String? = nil, author: Author = .human) {
        self.id = id
        self.name = name
        self.category = category
        self.summary = summary
        self.note = note
        self.topic = topic
        self.author = author
    }

    enum CodingKeys: String, CodingKey { case id, name, category, summary, note, topic, author }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? id
        category = try c.decodeIfPresent(String.self, forKey: .category)
        summary = try c.decodeIfPresent(String.self, forKey: .summary)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        topic = try c.decodeIfPresent(String.self, forKey: .topic)
        author = try c.decodeIfPresent(Author.self, forKey: .author) ?? .human
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(category, forKey: .category)
        if let summary, !summary.isEmpty { try c.encode(summary, forKey: .summary) }
        if let note, !note.isEmpty { try c.encode(note, forKey: .note) }
        try c.encodeIfPresent(topic, forKey: .topic)
        try c.encode(author, forKey: .author)
    }

    /// Description of the pattern's rule topic: what the pattern is, plus the project's note.
    public var topicDescription: String {
        let parts = [summary?.trimmed.nonEmpty, note?.trimmed.nonEmpty.map { "No projeto: \($0)" }].compactMap { $0 }
        return (parts.isEmpty ? ["Padrão de projeto \(name)."] : parts).joined(separator: "\n\n")
    }
}

public enum PatternCategory {
    public static let all = ["practices", "architecture", "domain", "custom"]

    public static func label(_ id: String?) -> String {
        switch id {
        case "practices": "Práticas"
        case "architecture": "Arquitetura"
        case "domain": "Domínio"
        case "custom": "Personalizados"
        case let other?: other.capitalized
        case nil: "Outros"
        }
    }
}

/// A rule a catalog pattern brings to its topic.
public struct PatternRule: Codable, Equatable, Hashable, Sendable {
    public var text: String
    public var details: String?
    public var severity: RuleSeverity

    public init(_ text: String, _ details: String? = nil, severity: RuleSeverity = .must) {
        self.text = text
        self.details = details
        self.severity = severity
    }
}

/// A pattern from the built-in catalog, with ready-made rules.
public struct PatternTemplate: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var category: String
    public var summary: String
    public var aliases: [String]
    public var rules: [PatternRule]

    public init(id: String, name: String, category: String, summary: String, aliases: [String] = [], rules: [PatternRule]) {
        self.id = id
        self.name = name
        self.category = category
        self.summary = summary
        self.aliases = aliases
        self.rules = rules
    }

    /// Exact match on id, name or alias, ignoring case, accents and punctuation ("Ports & Adapters" = "ports-adapters").
    public func matches(exactly ref: String) -> Bool {
        let key = Slug.make(ref)
        return !key.isEmpty && ([id, name] + aliases).contains { Slug.make($0) == key }
    }

    public func matches(containing ref: String) -> Bool {
        let key = Slug.make(ref)
        return !key.isEmpty && ([id, name, summary] + aliases).contains { Slug.make($0).contains(key) }
    }
}

public enum PatternCatalog {
    public static func find(_ ref: String) -> PatternTemplate? {
        all.first { $0.matches(exactly: ref) }
    }

    public static func search(_ query: String?) -> [PatternTemplate] {
        guard let q = query?.trimmed.nonEmpty else { return all }
        return all.filter { $0.matches(containing: q) }
    }

    /// Resolves every ref or throws (resolving nothing) with suggestions for the unknown ones.
    public static func resolve(_ refs: [String]) throws -> [PatternTemplate] {
        var found: [PatternTemplate] = []
        var unknown: [String: [String]] = [:]
        for ref in refs {
            if let t = find(ref) {
                if !found.contains(where: { $0.id == t.id }) { found.append(t) }
            } else {
                unknown[ref] = Array(search(ref).prefix(5).map(\.id))
            }
        }
        if !unknown.isEmpty { throw VibeDeckError.unknownPatterns(unknown) }
        return found
    }

    public static let all: [PatternTemplate] = [
        // Práticas
        PatternTemplate(
            id: "tdd", name: "TDD", category: "practices",
            summary: "Test-Driven Development: o teste vem antes do código; cada comportamento novo nasce de um teste que falha.",
            aliases: ["test-driven development", "testes primeiro", "test first"],
            rules: [
                PatternRule("Todo comportamento novo ou corrigido tem um teste automatizado",
                            "Escreva primeiro o teste que falha (vermelho), depois o mínimo de código para passar (verde), depois refatore.\nVerificar: a alteração vem acompanhada de testes que a exercitam; um bug corrigido ganha um teste de regressão."),
                PatternRule("A suíte de testes passa antes de concluir",
                            "Verificar: rode os testes do projeto e confirme que todos passam; não desative nem apague testes para fazer passar."),
                PatternRule("O código é testável sem infraestrutura real",
                            "Dependências externas (rede, disco, relógio, banco) entram por parâmetro ou protocolo e são trocadas por dublês nos testes.\nVerificar: os testes novos não dependem de serviços externos nem de estado global."),
            ]),
        PatternTemplate(
            id: "solid", name: "SOLID", category: "practices",
            summary: "Responsabilidade única, aberto/fechado, substituição de Liskov, segregação de interfaces e inversão de dependência.",
            aliases: ["solid principles", "principios solid"],
            rules: [
                PatternRule("Cada tipo tem uma única responsabilidade",
                            "Verificar: classes/structs/módulos novos ou alterados têm um motivo só para mudar; nada de \"Manager\" que faz tudo."),
                PatternRule("Módulos de alto nível dependem de abstrações, não de implementações concretas",
                            "Verificar: regras de negócio recebem protocolos/interfaces; implementações concretas são injetadas de fora."),
                PatternRule("Interfaces são pequenas e específicas",
                            "Verificar: nenhum protocolo novo obriga quem o implementa a métodos que não usa.", severity: .should),
                PatternRule("Comportamento novo entra por extensão, não alterando código estável",
                            "Verificar: prefira novos tipos/estratégias a encher de `if`/`switch` um fluxo existente.", severity: .should),
            ]),
        PatternTemplate(
            id: "dependency-injection", name: "Injeção de dependência", category: "practices",
            summary: "Os objetos recebem suas dependências de fora (construtor/parâmetro) em vez de criá-las ou buscá-las em singletons.",
            aliases: ["di", "dependency injection", "inversao de controle", "ioc"],
            rules: [
                PatternRule("Dependências entram pelo construtor ou por parâmetro",
                            "Verificar: código novo não instancia serviços concretos internamente nem acessa singletons/estado global para obtê-los."),
                PatternRule("A montagem das dependências fica num ponto de composição",
                            "Verificar: a criação dos objetos concretos fica no ponto de entrada (main, app, container), não espalhada pelo domínio."),
            ]),
        PatternTemplate(
            id: "functional-core", name: "Núcleo funcional", category: "practices",
            summary: "Functional core, imperative shell: lógica em funções puras e dados imutáveis; efeitos colaterais só na borda.",
            aliases: ["functional core imperative shell", "imutabilidade", "funcoes puras", "fp"],
            rules: [
                PatternRule("A lógica de negócio fica em funções puras",
                            "Mesma entrada, mesma saída, sem I/O, relógio ou aleatoriedade escondidos.\nVerificar: regras novas podem ser testadas sem mocks, só com valores."),
                PatternRule("Dados são imutáveis por padrão",
                            "Verificar: prefira `let`/valores/cópias com alteração a estado mutável compartilhado."),
                PatternRule("Efeitos colaterais ficam na casca, fora do núcleo",
                            "Verificar: I/O, persistência e chamadas externas ficam nas bordas, que chamam o núcleo puro."),
            ]),
        PatternTemplate(
            id: "clean-code", name: "Clean Code", category: "practices",
            summary: "Código legível: nomes que revelam intenção, funções pequenas, sem duplicação nem código morto.",
            aliases: ["codigo limpo", "clean"],
            rules: [
                PatternRule("Funções são pequenas e fazem uma coisa",
                            "Verificar: funções novas cabem na tela e têm um nível de abstração; extraia passos com nomes claros.", severity: .should),
                PatternRule("Nomes revelam intenção",
                            "Verificar: variáveis, funções e tipos dizem o que são/fazem, sem abreviações obscuras."),
                PatternRule("Sem duplicação nem código morto",
                            "Verificar: reaproveite o que já existe em vez de copiar; remova código comentado e não usado."),
            ]),
        // Arquitetura
        PatternTemplate(
            id: "hexagonal", name: "Arquitetura hexagonal", category: "architecture",
            summary: "Ports & Adapters: o domínio no centro define portas (interfaces); adaptadores (UI, banco, HTTP) as implementam por fora.",
            aliases: ["ports and adapters", "ports & adapters", "portas e adaptadores", "hexagonal architecture"],
            rules: [
                PatternRule("O domínio não depende de frameworks nem de infraestrutura",
                            "Verificar: o núcleo não importa UI, banco, HTTP ou SDKs; só a linguagem e o próprio domínio."),
                PatternRule("O domínio fala com o mundo por portas (interfaces) que ele mesmo define",
                            "Portas de entrada (casos de uso) e de saída (repositórios, gateways) ficam no núcleo.\nVerificar: toda dependência externa nova tem uma porta no domínio."),
                PatternRule("Adaptadores implementam as portas e ficam fora do núcleo",
                            "Verificar: código de UI, persistência e integrações está em adaptadores que dependem do domínio, nunca o contrário."),
                PatternRule("Os casos de uso são testáveis com adaptadores falsos",
                            "Verificar: há testes do núcleo usando implementações em memória das portas.", severity: .should),
            ]),
        PatternTemplate(
            id: "clean-architecture", name: "Clean Architecture", category: "architecture",
            summary: "Camadas concêntricas (entidades, casos de uso, adaptadores, frameworks) com dependências apontando só para dentro.",
            aliases: ["arquitetura limpa", "clean arch", "onion", "onion architecture"],
            rules: [
                PatternRule("Dependências apontam só para dentro",
                            "Entidades ← casos de uso ← adaptadores ← frameworks.\nVerificar: nenhuma camada interna importa ou conhece uma externa."),
                PatternRule("Cada caso de uso é uma unidade explícita",
                            "Verificar: regras de aplicação novas ficam em casos de uso (interactors) com entrada e saída definidas, não em controllers/views."),
                PatternRule("Dados atravessam fronteiras como estruturas simples",
                            "Verificar: entidades e modelos de framework (ORM, DTO de rede) não vazam entre camadas; há mapeamento na fronteira.", severity: .should),
            ]),
        PatternTemplate(
            id: "layered", name: "Arquitetura em camadas", category: "architecture",
            summary: "Apresentação, aplicação, domínio e infraestrutura separados; cada camada só fala com a de baixo.",
            aliases: ["camadas", "layers", "n-tier", "layered architecture"],
            rules: [
                PatternRule("Cada camada só depende da camada abaixo",
                            "Verificar: a apresentação não acessa a infraestrutura direto; o domínio não conhece a apresentação."),
                PatternRule("Regra de negócio não fica na camada de apresentação",
                            "Verificar: views/controllers só orquestram e formatam; decisões de negócio estão no domínio/aplicação."),
            ]),
        PatternTemplate(
            id: "mvvm", name: "MVVM", category: "architecture",
            summary: "Model-View-ViewModel: a View só desenha e repassa eventos; o ViewModel expõe estado e ações; o Model guarda dados e regras.",
            aliases: ["model view viewmodel", "model-view-viewmodel"],
            rules: [
                PatternRule("Views não contêm lógica de negócio",
                            "Verificar: views novas só leem estado do ViewModel e chamam suas ações."),
                PatternRule("ViewModels não dependem da camada de UI",
                            "Verificar: o ViewModel não importa tipos de view e pode ser testado sem UI."),
                PatternRule("ViewModels têm testes do estado e das ações", nil, severity: .should),
            ]),
        PatternTemplate(
            id: "mvc", name: "MVC", category: "architecture",
            summary: "Model-View-Controller: Model com dados e regras, View só exibe, Controller recebe a entrada e coordena.",
            aliases: ["model view controller", "model-view-controller"],
            rules: [
                PatternRule("Regras de negócio ficam no Model",
                            "Verificar: controllers não acumulam lógica de domínio; eles coordenam Model e View."),
                PatternRule("Views não acessam dados direto",
                            "Verificar: views recebem o que exibem; não consultam banco nem serviços."),
            ]),
        // Domínio
        PatternTemplate(
            id: "ddd", name: "DDD", category: "domain",
            summary: "Domain-Driven Design: o código usa a linguagem do negócio, com entidades, objetos de valor, agregados e contextos delimitados.",
            aliases: ["domain-driven design", "domain driven design", "design orientado a dominio"],
            rules: [
                PatternRule("O código usa a linguagem ubíqua do domínio",
                            "Verificar: tipos, métodos e eventos têm os nomes que o negócio usa, não nomes técnicos genéricos."),
                PatternRule("Regras de negócio vivem nas entidades e objetos de valor, não em serviços anêmicos",
                            "Verificar: invariantes são garantidas dentro do próprio modelo; nada de entidade só com getters/setters."),
                PatternRule("Agregados protegem suas invariantes e são alterados só pela raiz",
                            "Verificar: código externo não altera entidades internas de um agregado diretamente; referências entre agregados são por id."),
                PatternRule("Contextos delimitados não se misturam",
                            "Verificar: conceitos de um contexto não são importados direto em outro; há tradução (anticorrupção) na fronteira.", severity: .should),
            ]),
        PatternTemplate(
            id: "cqrs", name: "CQRS", category: "domain",
            summary: "Command Query Responsibility Segregation: comandos alteram estado e não retornam dados; consultas leem e não alteram nada.",
            aliases: ["command query responsibility segregation", "command query separation", "cqs"],
            rules: [
                PatternRule("Comandos e consultas são separados",
                            "Verificar: uma operação nova ou altera estado (comando) ou retorna dados (consulta), nunca os dois."),
                PatternRule("Cada comando tem um handler explícito que valida e aplica a mudança",
                            "Verificar: comandos novos são tipos próprios com seu handler, não métodos soltos em serviços genéricos."),
                PatternRule("Consultas não têm efeitos colaterais",
                            "Verificar: o caminho de leitura não grava, não dispara eventos e pode usar modelos de leitura próprios."),
            ]),
        PatternTemplate(
            id: "event-sourcing", name: "Event Sourcing", category: "domain",
            summary: "O estado é derivado de uma sequência imutável de eventos de domínio, em vez de ser sobrescrito.",
            aliases: ["eventos", "event sourced", "event store"],
            rules: [
                PatternRule("Mudanças de estado são registradas como eventos imutáveis",
                            "Verificar: alterações novas geram eventos com nome no passado (PedidoCriado), sem editar ou apagar eventos antigos."),
                PatternRule("O estado é reconstruído aplicando os eventos",
                            "Verificar: o agregado tem funções de aplicar evento determinísticas e sem efeitos colaterais."),
                PatternRule("Eventos são versionados quando o formato muda", nil, severity: .should),
            ]),
        PatternTemplate(
            id: "repository", name: "Repository", category: "domain",
            summary: "O domínio acessa a persistência por repositórios com interface de coleção, sem conhecer o banco.",
            aliases: ["repositorio", "repository pattern"],
            rules: [
                PatternRule("Acesso a dados passa por repositórios",
                            "Verificar: código de domínio/aplicação não faz SQL, chamadas de ORM ou de arquivo direto."),
                PatternRule("A interface do repositório é do domínio; a implementação é da infraestrutura",
                            "Verificar: o protocolo fica junto do domínio e fala em entidades; a implementação concreta fica fora e pode ser trocada em testes."),
            ]),
    ]
}

// MARK: - Store

extension ProjectStore {
    /// Index of the pattern `ref` names: exact id, then name (case-insensitive), then a unique id prefix.
    public func patternIndex(_ ref: String, in patterns: [ProjectPattern]) throws -> Int {
        let key = ref.trimmed
        if let i = patterns.firstIndex(where: { $0.id == key }) { return i }
        if let i = patterns.firstIndex(where: { $0.name.caseInsensitiveCompare(key) == .orderedSame }) { return i }
        if let t = PatternCatalog.find(key), let i = patterns.firstIndex(where: { $0.id == t.id }) { return i }
        let prefixed = patterns.indices.filter { patterns[$0].id.lowercased().hasPrefix(key.lowercased()) }
        if prefixed.count == 1, !key.isEmpty { return prefixed[0] }
        throw VibeDeckError.patternNotFound(ref)
    }

    /// The rule topic that enforces the pattern, if it still exists.
    public func patternTopic(_ pattern: ProjectPattern) -> (slug: String, topic: RuleTopic)? {
        guard let ref = pattern.topic, let slug = try? resolveTopicSlug(ref), let topic = try? loadTopic(slug) else { return nil }
        return (slug, topic)
    }

    /// Adds catalog patterns (ids, names or aliases; any unknown ref refuses all). Each new one gets its own rule
    /// topic, scoped by `paths` (empty = whole project). Existing ones keep their place; a given note/paths replaces theirs.
    @discardableResult
    public func addPatterns(_ refs: [String], note: String? = nil, paths: [String]? = nil, author: Author) throws -> [ProjectPattern] {
        let templates = try PatternCatalog.resolve(refs)
        return try templates.map { t in
            try addPattern(
                ProjectPattern(id: t.id, name: t.name, category: t.category, summary: t.summary, author: author),
                rules: t.rules.map { Rule(text: $0.text, details: $0.details, severity: $0.severity, author: author) },
                note: note, paths: paths)
        }
    }

    /// Adds a pattern of the project's own, with one `must` rule per entry of `rules`.
    @discardableResult
    public func addCustomPattern(
        name: String, summary: String? = nil, rules: [String], note: String? = nil, paths: [String]? = nil, author: Author
    ) throws -> ProjectPattern {
        guard let name = name.trimmed.nonEmpty, !Slug.make(name).isEmpty else { throw VibeDeckError.invalidName }
        let taken = Set(try loadProject().patterns.map(\.id))
        let base = Slug.make(name)
        var id = base
        var n = 2
        while taken.contains(id) || PatternCatalog.all.contains(where: { $0.id == id }) { id = "\(base)-\(n)"; n += 1 }
        return try addPattern(
            ProjectPattern(id: id, name: name, category: "custom", summary: summary?.trimmed.nonEmpty, author: author),
            rules: rules.compactMap(\.trimmed.nonEmpty).map { Rule(text: $0, author: author) },
            note: note, paths: paths)
    }

    private func addPattern(_ new: ProjectPattern, rules: [Rule], note: String?, paths: [String]?) throws -> ProjectPattern {
        let note = note?.trimmed
        let paths = paths?.compactMap(\.trimmed.nonEmpty)
        if let i = try loadProject().patterns.firstIndex(where: { $0.id == new.id }) {
            var existing = try loadProject().patterns[i]
            if let note { existing = try setPatternNote(existing.id, note) }
            if let paths { existing = try setPatternPaths(existing.id, paths) }
            return existing
        }
        var pattern = new
        pattern.note = note?.nonEmpty
        let topic = try createTopic(
            title: "Padrão: \(pattern.name)", description: pattern.topicDescription, tags: ["padrao"],
            paths: paths ?? [], rules: rules, sourcePattern: pattern.id
        )
        pattern.topic = topic.slug
        try updateProject { $0.patterns.append(pattern) }
        return pattern
    }

    /// Removes the patterns `refs` name and deletes their rule topics. Throws (removing nothing) if any is unknown.
    @discardableResult
    public func removePatterns(_ refs: [String]) throws -> [ProjectPattern] {
        var removed: [ProjectPattern] = []
        try updateProject { project in
            let indices = Set(try refs.map { try patternIndex($0, in: project.patterns) })
            removed = indices.sorted().map { project.patterns[$0] }
            project.patterns = project.patterns.enumerated().filter { !indices.contains($0.offset) }.map(\.element)
        }
        for pattern in removed {
            if let (slug, _) = patternTopic(pattern) { try FileManager.default.removeItem(at: topicURL(slug)) }
        }
        return removed
    }

    /// Sets (or, with nil/empty, clears) a pattern's note, and refreshes its topic description.
    @discardableResult
    public func setPatternNote(_ ref: String, _ note: String?) throws -> ProjectPattern {
        var pattern: ProjectPattern!
        try updateProject { project in
            let i = try patternIndex(ref, in: project.patterns)
            project.patterns[i].note = note?.trimmed.nonEmpty
            pattern = project.patterns[i]
        }
        if let (slug, _) = patternTopic(pattern) { try updateTopic(slug) { $0.description = pattern.topicDescription } }
        return pattern
    }

    /// Scopes the pattern's topic to `paths` (globs; empty = whole project). The topic is the source of truth for paths.
    @discardableResult
    public func setPatternPaths(_ ref: String, _ paths: [String]) throws -> ProjectPattern {
        let patterns = try loadProject().patterns
        let pattern = patterns[try patternIndex(ref, in: patterns)]
        guard let (slug, _) = patternTopic(pattern) else { throw VibeDeckError.topicNotFound(pattern.topic ?? pattern.id) }
        try updateTopic(slug) { $0.paths = paths.compactMap(\.trimmed.nonEmpty) }
        return pattern
    }

    /// Moves a pattern to `position` (0-based, clamped).
    public func movePattern(_ ref: String, to position: Int) throws {
        try updateProject { project in
            let item = project.patterns.remove(at: try patternIndex(ref, in: project.patterns))
            project.patterns.insert(item, at: max(0, min(position, project.patterns.count)))
        }
    }

    /// Drops patterns whose rule topic no longer exists (deleted by the app, the CLI or by hand): without rules
    /// nothing enforces them. Idempotent. Returns the ids removed.
    @discardableResult
    public func releaseOrphanedPatterns() throws -> [String] {
        guard let project = try? loadProject(), !project.patterns.isEmpty else { return [] }
        let orphaned = project.patterns.filter { patternTopic($0) == nil }.map(\.id)
        guard !orphaned.isEmpty else { return [] }
        try updateProject { $0.patterns.removeAll { orphaned.contains($0.id) } }
        return orphaned
    }
}
