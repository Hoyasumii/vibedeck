import Foundation

enum VibeDeckError: LocalizedError, Equatable {
    case notAProject(String)
    case alreadyAProject(String)
    case docNotFound(String)
    case groupNotFound(String)
    case itemNotFound(String)
    case ambiguousItem(String)
    case topicNotFound(String)
    case ideaNotFound(String)
    case invalidIdeaDependency(String)
    case ideaNotImplementable([String])
    case agentNotFound(String)
    case commandNotFound(String)
    case skillNotFound(String)
    case workflowNotFound(String)
    case runNotFound(String)
    case invalidWorkflow(String)
    case invalidNextStep(String)
    case ruleNotFound(String)
    case ambiguousRule(String)
    case incompleteCheck([String])
    case invalidRuleTest(String)
    case rulesNotVerified([String])
    case invalidName
    case invalidGroupPath(String)
    case ambiguousReference(String, [String])
    case groupConflict(String)
    case groupConfirmationRequired(String)
    case invalidKitSelection(String)
    case missingKitDependencies([String])
    case kitRestoreConflict(String)
    case invalidClaudeURL
    case claudeItemNotFound(String)
    case ambiguousClaudeItem(String)
    case invalidStatusLine
    case invalidClaudeSettings(String)
    case discoverFailed(String)
    case discoverInvalidAnswer
    case docGenerationInvalidAnswer
    case discoverTimedOut
    case skillIconsUnavailable(String)
    case unknownStackIcons([String: [String]])
    case stackItemNotFound(String)
    case unknownPatterns([String: [String]])
    case patternNotFound(String)
    case ssh(String)
    case graph(String)
    case invalidLogFilter(String)
    case logUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .notAProject(let p): "Nenhum vibedeck.json encontrado em \(p) ou diretórios acima. Rode `vibedeck init`."
        case .alreadyAProject(let p): "\(p) já contém um vibedeck.json."
        case .docNotFound(let s): "Doc não encontrado: \(s)"
        case .groupNotFound(let s): "Grupo de revisão não encontrado: \(s)"
        case .itemNotFound(let s): "Item de revisão não encontrado: \(s)"
        case .ambiguousItem(let s): "Prefixo de id ambíguo: \(s)"
        case .topicNotFound(let s): "Tópico de regras não encontrado: \(s)"
        case .ideaNotFound(let s): "Ideia não encontrada: \(s)"
        case .invalidIdeaDependency(let s): "Dependência inválida: \(s) Nada foi alterado."
        case .ideaNotImplementable(let reasons):
            "A ideia não pode ser implementada:\n" + reasons.map { "- \($0)" }.joined(separator: "\n")
        case .agentNotFound(let s): "Agente não encontrado: \(s)"
        case .commandNotFound(let s): "Comando não encontrado: \(s)"
        case .skillNotFound(let s): "Skill não encontrada: \(s)"
        case .workflowNotFound(let s): "Workflow não encontrado: \(s)"
        case .runNotFound(let s): "Execução de workflow não encontrada: \(s)"
        case .invalidWorkflow(let s): "Workflow inválido: \(s)"
        case .invalidNextStep(let s): "Próximo passo inválido: \(s)"
        case .ruleNotFound(let s): "Regra não encontrada entre as aplicáveis: \(s)"
        case .ambiguousRule(let s): "Prefixo de id de regra ambíguo: \(s)"
        case .incompleteCheck(let missing):
            "Check incompleto: responda todas as regras aplicáveis que não são decididas por script (pass, fail ou na). Faltando:\n" + missing.map { "- \($0)" }.joined(separator: "\n")
        case .invalidRuleTest(let s): "Teste de regra inválido: \(s)"
        case .rulesNotVerified(let problems):
            "O item não pode ser concluído sem passar pelas regras:\n" + problems.map { "- \($0)" }.joined(separator: "\n")
                + "\nUse rules_for / submit_rule_check (ou `vibedeck rules check`) com o id do item."
        case .invalidClaudeURL: "Informe uma URL http ou https do claude.ai."
        case .claudeItemNotFound(let s): "Item do Claude não encontrado: \(s)"
        case .ambiguousClaudeItem(let s): "Referência do Claude ambígua: \(s)"
        case .invalidGroupPath(let path): "Caminho de grupo inválido ou fora da pasta do conceito: \(path)"
        case .ambiguousReference(let ref, let paths): "Referência ambígua: \(ref). Use um dos caminhos: " + paths.sorted().joined(separator: ", ")
        case .groupConflict(let path): "O destino já existe: \(path). Nada foi sobrescrito."
        case .groupConfirmationRequired(let path): "O grupo \(path) contém itens. Confirme explicitamente a exclusão."
        case .invalidName: "Nome inválido."
        case .invalidKitSelection(let ref): "Seleção de kit inválida: \(ref). Consulte o catálogo e selecione pelo menos um item."
        case .missingKitDependencies(let ids): "Selecione também as dependências: " + ids.joined(separator: ", ")
        case .kitRestoreConflict(let file): "Não foi possível refazer a adição: \(file) já existe. Preserve ou mova esse arquivo antes de tentar novamente."
        case .invalidStatusLine: "Entrada da statusline do Claude Code não é um objeto JSON."
        case .invalidClaudeSettings(let p): "\(p) não é um objeto JSON válido; corrija antes de ligar a statusline."
        case .discoverFailed(let output):
            "O Claude Code não conseguiu descobrir; nada foi alterado." + (output.isEmpty ? "" : "\n\(output)")
        case .docGenerationInvalidAnswer: "A IA retornou uma proposta de documentos inválida. Nenhum documento foi criado. Tente gerar novamente."
        case .discoverInvalidAnswer: "O Claude Code respondeu num formato inesperado; nada foi alterado. Tente de novo."
        case .discoverTimedOut: "O Descubra demorou demais e foi interrompido; nada foi alterado. Tente de novo."
        case .skillIconsUnavailable(let s): "Skill Icons indisponível: \(s)"
        case .unknownStackIcons(let unknown):
            "Ícone(s) desconhecido(s) no Skill Icons; nada foi alterado:\n" + unknown.keys.sorted().map { name in
                let suggestions = unknown[name] ?? []
                return "- \(name)" + (suggestions.isEmpty ? "" : " (sugestões: \(suggestions.joined(separator: ", ")))")
            }.joined(separator: "\n")
        case .stackItemNotFound(let s): "Tecnologia não encontrada na stack: \(s)"
        case .unknownPatterns(let unknown):
            "Padrão(ões) desconhecido(s) no catálogo; nada foi alterado:\n" + unknown.keys.sorted().map { name in
                let suggestions = unknown[name] ?? []
                return "- \(name)" + (suggestions.isEmpty ? "" : " (sugestões: \(suggestions.joined(separator: ", ")))")
            }.joined(separator: "\n") + "\nVeja `pattern_catalog` / `vibedeck patterns catalog`, ou crie um padrão personalizado."
        case .ssh(let s): "SSH: \(s)"
        case .graph(let s): "Grafo: \(s)"
        case .patternNotFound(let s): "Padrão não encontrado no projeto: \(s)"
        case .invalidLogFilter(let s): "Filtro de log inválido: \(s). Use, por exemplo, 30m, 24h ou 7d."
        case .logUnavailable(let s): "Não foi possível gravar o log: \(s)"
        }
    }
}

