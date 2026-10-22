import Foundation
public enum ReorganizeError: LocalizedError {
    case invalidJSON, stale, invalidAction, incompatible, occupied, busy
    public var errorDescription: String? {
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
public enum ReorganizeDiscover {
    public enum Concept: String, Codable, CaseIterable, Sendable { case rules, docs, ideas, reviews }
    public enum Kind: String, Codable, CaseIterable, Sendable { case conflict, merge, move, create, flow }
    public struct Reference: Codable, Hashable, Sendable {
        public var concept: Concept
        public var slug: String
        public var itemID: String?
        public init(_ concept: Concept, _ slug: String, itemID: String? = nil) {
            self.concept = concept; self.slug = slug; self.itemID = itemID
        }
        public var key: String { concept.rawValue + "/" + slug + (itemID.map { "#" + $0 } ?? "") }
    }
    public struct Action: Codable, Equatable, Identifiable, Sendable {
        public var id: String
        public var kind: Kind
        public var item: Reference
        public var involved: [Reference]
        public var reason: String
        public var destination: String?
        public var title: String?
        public var content: String?
        public init(id: String = UUID().uuidString, kind: Kind, item: Reference, involved: [Reference] = [],
                    reason: String, destination: String? = nil, title: String? = nil, content: String? = nil) {
            self.id = id; self.kind = kind; self.item = item; self.involved = involved; self.reason = reason
            self.destination = destination; self.title = title; self.content = content
        }
        public var references: [Reference] { [item] + involved.filter { $0 != item } }
        public var label: String {
            switch kind { case .conflict: "Conflito"; case .merge: "Mesclar repetidos"; case .move: "Mover";
            case .create: "Criar tópico/subpasta"; case .flow: "Melhoria de fluxo" }
        }
    }
    public struct Answer: Codable, Sendable {
        public var actions: [Action]
        public init(actions: [Action]) { self.actions = actions }
    }
    public struct Proposal: Codable, Equatable, Sendable {
        public var fingerprint: String
        public var actions: [Action]
        public var discarded: Int
        public init(fingerprint: String, actions: [Action], discarded: Int = 0) {
            self.fingerprint = fingerprint; self.actions = actions; self.discarded = discarded
        }
    }
    public struct Acceptance: Codable, Sendable {
        public var selected: [String]
        /// Action ID -> explicitly chosen existing reference key.
        public var conflicts: [String: String]
        public init(selected: [String], conflicts: [String: String] = [:]) {
            self.selected = selected; self.conflicts = conflicts
        }
    }
    public static func decodeProposal(_ data: Data) throws -> Proposal {
        guard let value = try? VDJSON.decoder.decode(Proposal.self, from: data) else { throw ReorganizeError.invalidJSON }
        return value
    }
    public static func decodeAcceptance(_ data: Data) throws -> Acceptance {
        guard let value = try? VDJSON.decoder.decode(Acceptance.self, from: data) else { throw ReorganizeError.invalidJSON }
        return value
    }
}

public struct ReorganizeCatalogItem: Codable, Sendable {
    public var reference: ReorganizeDiscover.Reference
    public var title: String
}
public struct ReorganizeReceipt: Codable, Sendable {
    public var before: [String: Data]
    public var after: [String: Data]
    public var createdDirectories: [String]
    public var pathMoves: [String: String]
}

