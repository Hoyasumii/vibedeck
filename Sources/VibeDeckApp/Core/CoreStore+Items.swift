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
