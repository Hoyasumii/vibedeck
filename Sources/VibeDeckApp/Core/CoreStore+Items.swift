import Foundation

// Referências a agentes, comandos, skills e workflows para os prompts de IA (leitura via recursos do Core).
extension CoreStore {
    /// Referências para o prompt de workflows e a validação das etapas.
    func itemRefs() async throws -> (refs: ItemDiscover.Refs, listing: [String: [ItemDiscover.Existing]]) {
        let agents = try await listAgents(), commands = try await listCommands(), skills = try await listSkills()
        let refs = ItemDiscover.Refs(agents: agents.map(\.slug), commands: commands.map(\.slug), skills: skills.map(\.slug))
        let listing: [String: [ItemDiscover.Existing]] = [
            "Agentes": agents.map { ItemDiscover.Existing(slug: $0.slug, title: $0.value.title, summary: $0.value.summary) },
            "Comandos": commands.map { ItemDiscover.Existing(slug: $0.slug, title: $0.value.title, summary: $0.value.summary) },
            "Skills": skills.map { ItemDiscover.Existing(slug: $0.slug, title: $0.value.title, summary: $0.value.summary) },
        ]
        return (refs, listing)
    }

    /// Itens já existentes do tipo, para a IA não duplicar.
    func existingItems(_ kind: ItemDiscover.Kind) async throws -> [ItemDiscover.Existing] {
        switch kind {
        case .agent:
            return try await listAgents().map { ItemDiscover.Existing(slug: $0.slug, title: $0.value.title, summary: $0.value.summary) }
        case .command:
            return try await listCommands().map { ItemDiscover.Existing(slug: $0.slug, title: $0.value.title, summary: $0.value.summary) }
        case .skill:
            return try await listSkills().map { ItemDiscover.Existing(slug: $0.slug, title: $0.value.title, summary: $0.value.summary) }
        case .workflow:
            return try await listWorkflows().map { ItemDiscover.Existing(slug: $0.slug, title: $0.value.title, summary: $0.value.summary) }
        }
    }
}

extension CoreStore {
    /// O gate único para implementar uma ideia (padrão ou workflow, app ou chat): relê as ideias no Core e lança
    /// todos os motivos pelos quais ela não pode ser implementada agora. `ref` é slug, UUID ou título.
    func implementableIdea(_ ref: String) async throws -> (slug: String, idea: Idea) {
        let fresh = try await listIdeas()
        let needle = ref.lowercased()
        let found = fresh.first { $0.slug == ref || $0.value.id.uuidString.lowercased() == needle }
            ?? fresh.first { $0.value.title.caseInsensitiveCompare(ref) == .orderedSame }
        guard let match = found else { throw VibeDeckError.ideaNotFound(ref) }
        var reasons: [String] = []
        if !IdeaImplementation.isEligible(match.value) {
            reasons.append("a ideia precisa estar aprovada e ter uma avaliação viável atual. Verifique novamente.")
        }
        let pairs = fresh.map { (slug: $0.slug, idea: $0.value) }
        reasons += IdeaImplementation.dependencyBlockers(of: match.value, in: pairs).map(\.message)
        guard reasons.isEmpty else { throw VibeDeckError.ideaNotImplementable(reasons) }
        return (match.slug, match.value)
    }
}
