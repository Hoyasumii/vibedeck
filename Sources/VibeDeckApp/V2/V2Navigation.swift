import SwiftUI

/// Medidas fixas da janela V2 (prancha 18: trilho de 76 pt; prancha 19: barra de status de 32 pt).
/// Largura de colunas de conteúdo e de inspector NÃO ficam aqui: usam navigationSplitViewColumnWidth / inspectorColumnWidth.
extension DesignTokens {
    enum V2Layout {
        static let railWidth: CGFloat = 76
        static let railItemWidth: CGFloat = 60
        static let railItemHeight: CGFloat = 56
        static let statusBarHeight: CGFloat = 32
    }
}

/// Os quatro espaços do trilho (prancha 18).
enum V2Space: String, CaseIterable, Identifiable, Hashable {
    case plan, automation, quality, project

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plan: return "Planejar"
        case .automation: return "Automação"
        case .quality: return "Qualidade"
        case .project: return "Projeto"
        }
    }

    var icon: VDIconName {
        switch self {
        case .plan: return .idea
        case .automation: return .workflow
        case .quality: return .rule
        case .project: return .stack
        }
    }

    /// Conceitos do espaço, na ordem em que aparecem na coluna de conteúdo.
    var concepts: [V2Concept] {
        switch self {
        case .plan: return [.ideas, .docs, .references]
        case .automation: return [.agents, .commands, .skills, .workflows]
        case .quality: return [.rules, .reviews]
        case .project: return [.project]
        }
    }
}

/// Um conceito do produto. Cada um tem lista filtrável na coluna de conteúdo do seu espaço.
/// Conceitos com `section` usam as listas de seção existentes; `references` e `project` são listas de páginas.
enum V2Concept: String, CaseIterable, Identifiable, Hashable {
    case ideas, docs, references
    case agents, commands, skills, workflows
    case rules, reviews
    case project

    var id: String { rawValue }

    var space: V2Space {
        switch self {
        case .ideas, .docs, .references: return .plan
        case .agents, .commands, .skills, .workflows: return .automation
        case .rules, .reviews: return .quality
        case .project: return .project
        }
    }

    var title: String {
        switch self {
        case .ideas: return "Ideias"
        case .docs: return "Docs"
        case .references: return "Referências"
        case .agents: return "Agentes"
        case .commands: return "Comandos"
        case .skills: return "Skills"
        case .workflows: return "Workflows"
        case .rules: return "Regras"
        case .reviews: return "Revisões"
        case .project: return "Projeto"
        }
    }

    /// Seção V1 que fornece as linhas (nil para listas de páginas).
    var section: SidebarSection? {
        switch self {
        case .ideas: return .ideas
        case .docs: return .docs
        case .agents: return .agents
        case .commands: return .commands
        case .skills: return .skills
        case .workflows: return .workflows
        case .rules: return .topics
        case .reviews: return .groups
        case .references, .project: return nil
        }
    }

    /// Páginas listadas quando o conceito não é uma seção.
    var pages: [V2Page] {
        switch self {
        case .references: return [.links, .claudeItems]
        case .project: return [.overview, .stack, .patterns, .graph]
        default: return []
        }
    }

    /// Item aberto ao entrar no conceito (nil: mostra a tabela da seção ou a visão geral).
    var defaultSelection: SidebarItem? {
        switch self {
        case .references: return .links
        default: return nil
        }
    }

    static func forSection(_ section: SidebarSection) -> V2Concept {
        switch section {
        case .docs: return .docs
        case .groups: return .reviews
        case .topics: return .rules
        case .ideas: return .ideas
        case .agents: return .agents
        case .commands: return .commands
        case .skills: return .skills
        case .workflows: return .workflows
        }
    }

    /// Conceito dono de um item (nil para o chat e terminais, que não pertencem a um espaço).
    static func of(_ item: SidebarItem) -> V2Concept? {
        switch item {
        case .stack, .patterns, .graph: return .project
        case .links, .claudeItems: return .references
        case .claude, .terminal: return nil
        case .section(let section): return forSection(section)
        case .doc: return .docs
        case .group: return .reviews
        case .topic: return .rules
        case .idea: return .ideas
        case .agent: return .agents
        case .command: return .commands
        case .skill: return .skills
        case .workflow: return .workflows
        }
    }
}

/// Página única listada em Referências e Projeto.
enum V2Page: Hashable, Identifiable {
    case overview, stack, patterns, links, claudeItems, graph

    var id: V2Page { self }

    init?(item: SidebarItem) {
        switch item {
        case .stack: self = .stack
        case .patterns: self = .patterns
        case .links: self = .links
        case .claudeItems: self = .claudeItems
        case .graph: self = .graph
        default: return nil
        }
    }

    /// Item de detalhe correspondente (nil: Visão geral, que é a página inicial do Projeto).
    var item: SidebarItem? {
        switch self {
        case .overview: return nil
        case .stack: return .stack
        case .patterns: return .patterns
        case .links: return .links
        case .claudeItems: return .claudeItems
        case .graph: return .graph
        }
    }

    var title: String {
        switch self {
        case .overview: return "Visão geral"
        case .stack: return "Stack"
        case .patterns: return "Padrões"
        case .links: return "Links"
        case .claudeItems: return "Coleção do Claude"
        case .graph: return "Grafo"
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .stack: return "square.stack.3d.up"
        case .patterns: return "building.columns"
        case .links: return "link"
        case .claudeItems: return "square.stack"
        case .graph: return "point.3.connected.trianglepath.dotted"
        }
    }
}
