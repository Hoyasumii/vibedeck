import Foundation

/// Built-in starting points. Installed items use the ordinary project models and editors.
enum KitItemKind: String, Codable, CaseIterable, Sendable {
    case agent, command, skill, workflow

    var title: String {
        switch self {
        case .agent: "Agente"
        case .command: "Comando"
        case .skill: "Skill"
        case .workflow: "Workflow"
        }
    }
}

struct KitCatalogItem: Codable, Identifiable, Sendable {
    let id: String
    let kind: KitItemKind
    let title: String
    let summary: String
    let prompt: String
    let nextSteps: [NextStep]
    let steps: [WorkflowStep]

    var dependencies: [String] {
        Array(Set(nextSteps.map(\.ref) + steps.map(\.ref))).sorted()
    }
}

struct CatalogKit: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let summary: String
    let items: [KitCatalogItem]
}

enum KitCatalog {
    /// Kit ids explicitly select all their items; item ids select only that item.
    static func selection(_ refs: [String]) throws -> [KitCatalogItem] {
        let all = kits.flatMap(\.items)
        var ids = Set<String>()
        for ref in refs {
            if let kit = kits.first(where: { $0.id == ref }) { ids.formUnion(kit.items.map(\.id)) }
            else if all.contains(where: { $0.id == ref }) { ids.insert(ref) }
            else { throw VibeDeckError.invalidKitSelection(ref) }
        }
        return all.filter { ids.contains($0.id) }
    }

    static func missingDependencies(_ refs: [String]) throws -> [String] {
        let items = try selection(refs)
        let ids = Set(items.map(\.id))
        return Array(Set(items.flatMap(\.dependencies)).subtracting(ids)).sorted()
    }

    private static let guidance = """
    Trabalhe por objetivo, restrições, evidências e critério de conclusão. Consulte a stack, os padrões,
    os tópicos de regras e os itens de revisão abertos da área no VibeDeck antes de implementar.
    Preserve decisões do usuário e pergunte quando faltar uma decisão de produto.
    Use responsabilidades claras, mudanças coesas e os padrões do projeto para evitar código espaguete.
    Valide com testes pertinentes. Ao concluir, consulte rules_for com os arquivos alterados e o item
    de revisão, quando houver, e envie submit_rule_check; corrija até passed=true. Verificações manuais
    seguem as regras do projeto. Só marque a revisão como done após a verificação exigida.
    Respeite o provedor, o modelo, as permissões e os limites escolhidos; não os troque automaticamente.
    """

    static let kits: [CatalogKit] = [
        makeKit(id: "manutencao", title: "Manutenção de sistema",
                summary: "Diagnosticar, corrigir, evoluir e revisar código existente.",
                agent: "Revisor de manutenção", command: "Corrigir sistema", skill: "Diagnóstico de sistema",
                workflow: "Manutenção com revisão",
                agentPrompt: "Revise a mudança e seus testes. Procure regressões, complexidade desnecessária e violações dos padrões. Informe evidências e problemas acionáveis. Termine com APROVADO ou AJUSTAR.",
                commandPrompt: "Corrija ou evolua o sistema conforme $ARGUMENTS. Reproduza o problema, investigue sua causa e implemente a menor mudança coesa. Termine com IMPLEMENTADO após testes e check aprovados.",
                skillPrompt: "Use ao investigar defeitos ou evolução de código existente. Reproduza o comportamento, siga o fluxo de dados, registre a causa e proponha uma correção com teste de regressão. Termine com DIAGNOSTICADO."),
        makeKit(id: "novas-ferramentas", title: "Desenvolvimento de novas ferramentas",
                summary: "Planejar, desenvolver e validar uma ferramenta seguindo os padrões do projeto.",
                agent: "Revisor de ferramentas", command: "Desenvolver ferramenta", skill: "Planejamento de ferramenta",
                workflow: "Ferramenta com revisão",
                agentPrompt: "Revise a ferramenta contra o objetivo e os critérios de aceite. Verifique limites entre módulos, clareza das interfaces e cobertura dos cenários essenciais. Termine com APROVADO ou AJUSTAR.",
                commandPrompt: "Implemente a ferramenta descrita em $ARGUMENTS a partir do plano aprovado. Organize responsabilidades e integre com os padrões existentes. Termine com IMPLEMENTADO após testes e check aprovados.",
                skillPrompt: "Use ao iniciar uma ferramenta. Defina usuários, entradas, saídas, restrições e critérios de aceite. Examine a arquitetura existente, proponha módulos coesos e esclareça decisões não especificadas com o usuário. Termine com PLANEJADO.")
    ]

    private static func makeKit(id: String, title: String, summary: String,
                                agent: String, command: String, skill: String, workflow: String,
                                agentPrompt: String, commandPrompt: String, skillPrompt: String) -> CatalogKit {
        func key(_ kind: KitItemKind) -> String { id + ":" + kind.rawValue }
        func item(_ kind: KitItemKind, _ title: String, _ summary: String, _ prompt: String,
                  steps: [WorkflowStep] = []) -> KitCatalogItem {
            KitCatalogItem(id: key(kind), kind: kind, title: title, summary: summary,
                           prompt: prompt + "\n\n" + guidance + "\n\n" + AIPromptPolicy.instructions, nextSteps: [], steps: steps)
        }
        let steps = [
            WorkflowStep(id: "planejar", kind: .skill, ref: key(.skill),
                         transitions: [WorkflowTransition(to: "implementar")]),
            WorkflowStep(id: "implementar", kind: .command, ref: key(.command),
                         note: "Use o objetivo da execução e o plano da etapa anterior.", maxVisits: 3,
                         transitions: [WorkflowTransition(verdict: "IMPLEMENTADO", to: "revisar")]),
            WorkflowStep(id: "revisar", kind: .agent, ref: key(.agent), maxVisits: 3,
                         transitions: [WorkflowTransition(verdict: "AJUSTAR", to: "implementar")])
        ]
        return CatalogKit(id: id, title: title, summary: summary, items: [
            item(.agent, agent, "Revisar mudanças, testes e aderência aos padrões.", agentPrompt),
            item(.command, command, "Implementar uma mudança com validação e check.", commandPrompt),
            item(.skill, skill, "Investigar o contexto e preparar um plano verificável.", skillPrompt),
            item(.workflow, workflow, "Planejar → implementar → revisar, com até três rodadas de ajustes.", "", steps: steps)
        ])
    }
}
