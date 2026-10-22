import Foundation
enum ReorganizeError: LocalizedError {
    case invalidJSON, stale, invalidAction, incompatible, occupied, busy
    var errorDescription: String? {
        switch self {
        case .invalidJSON: "A IA retornou uma proposta de reorganização inválida. Nenhum arquivo foi alterado."
        case .stale: "O projeto mudou. Analise novamente antes de aceitar a reorganização."
        case .invalidAction: "A ação ou a escolha de conflito não é válida. Nenhum arquivo foi alterado."
        case .incompatible: "Os itens têm campos incompatíveis ou protegidos e não podem ser reorganizados desta forma."
        case .occupied: "O destino já está ocupado. Nenhum item será sobrescrito."
        case .busy: "Já existe uma análise de reorganização em andamento neste projeto."
        }
    }
}

/// Tipos da proposta de reorganização. Prompt, validação e aplicação ficam no Core Rust (`reorganize_*`).
enum ReorganizeDiscover {
    enum Concept: String, Codable, CaseIterable, Sendable { case rules, docs, ideas, reviews }
    enum Kind: String, Codable, CaseIterable, Sendable { case conflict, merge, move, create, flow }
    struct Reference: Codable, Hashable, Sendable {
        var concept: Concept
        var slug: String
        var itemID: String?
        init(_ concept: Concept, _ slug: String, itemID: String? = nil) {
            self.concept = concept; self.slug = slug; self.itemID = itemID
        }
        var key: String { concept.rawValue + "/" + slug + (itemID.map { "#" + $0 } ?? "") }
    }
    struct Action: Codable, Equatable, Identifiable, Sendable {
        var id: String
        var kind: Kind
        var item: Reference
        var involved: [Reference]
        var reason: String
        var destination: String?
        var title: String?
        var content: String?
        init(id: String = UUID().uuidString, kind: Kind, item: Reference, involved: [Reference] = [],
                    reason: String, destination: String? = nil, title: String? = nil, content: String? = nil) {
            self.id = id; self.kind = kind; self.item = item; self.involved = involved; self.reason = reason
            self.destination = destination; self.title = title; self.content = content
        }
        var references: [Reference] { [item] + involved.filter { $0 != item } }
        var label: String {
            switch kind { case .conflict: "Conflito"; case .merge: "Mesclar repetidos"; case .move: "Mover";
            case .create: "Criar tópico/subpasta"; case .flow: "Melhoria de fluxo" }
        }
    }
    struct Answer: Codable, Sendable {
        var actions: [Action]
        init(actions: [Action]) { self.actions = actions }
    }
    struct Proposal: Codable, Equatable, Sendable {
        var fingerprint: String
        var actions: [Action]
        var discarded: Int
        init(fingerprint: String, actions: [Action], discarded: Int = 0) {
            self.fingerprint = fingerprint; self.actions = actions; self.discarded = discarded
        }
    }
    struct Acceptance: Codable, Sendable {
        var selected: [String]
        /// Action ID -> explicitly chosen existing reference key.
        var conflicts: [String: String]
        init(selected: [String], conflicts: [String: String] = [:]) {
            self.selected = selected; self.conflicts = conflicts
        }
    }
    static func decodeProposal(_ data: Data) throws -> Proposal {
        guard let value = try? VDJSON.decoder.decode(Proposal.self, from: data) else { throw ReorganizeError.invalidJSON }
        return value
    }
    static func decodeAcceptance(_ data: Data) throws -> Acceptance {
        guard let value = try? VDJSON.decoder.decode(Acceptance.self, from: data) else { throw ReorganizeError.invalidJSON }
        return value
    }
}

struct ReorganizeCatalogItem: Codable, Sendable {
    var reference: ReorganizeDiscover.Reference
    var title: String
}
struct ReorganizeReceipt: Codable, Sendable {
    var before: [String: Data]
    var after: [String: Data]
    var createdDirectories: [String]
    var pathMoves: [String: String]
}

