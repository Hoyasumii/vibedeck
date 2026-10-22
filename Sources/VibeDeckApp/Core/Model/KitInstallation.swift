import Foundation

struct InstalledKitItem: Codable, Equatable, Sendable {
    let catalogID: String
    let kind: KitItemKind
    let slug: String
}

