import Foundation

/// Compact discovery is opt-in; existing list APIs retain their wire format.
public struct AICatalogPage: Codable, Sendable {
    public struct Item: Codable, Sendable {
        public let ref: String
        public let title: String
        public let summary: String?
        public let paths: [String]?
    }
    public let items: [Item]
    public let nextOffset: Int?
    public let total: Int
}

