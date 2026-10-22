import Foundation

public struct InstalledKitItem: Codable, Equatable, Sendable {
    public let catalogID: String
    public let kind: KitItemKind
    public let slug: String
}

