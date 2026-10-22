import Foundation

/// Compact discovery is opt-in; existing list APIs retain their wire format.
struct AICatalogPage: Codable, Sendable {
    struct Item: Codable, Sendable {
        let ref: String
        let title: String
        let summary: String?
        let paths: [String]?
    }
    let items: [Item]
    let nextOffset: Int?
    let total: Int
}

