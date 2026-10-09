import AppKit
import SwiftUI
import VibeDeckCore

/// Skill Icons catalog and rendered icons, shared by every window. Both come from the Skill Icons MCP server
/// (the image URL from `skill_icons_badge`, never written by hand) and are kept in `~/Library/Caches` so the
/// picker opens offline after the first load.
@MainActor
@Observable
final class SkillIconCache {
    static let shared = SkillIconCache()

    private(set) var catalog: [SkillIcon] = []
    private(set) var catalogError: String?
    private(set) var loadingCatalog = false
    private var images: [String: NSImage] = [:]
    @ObservationIgnored private var inFlight: Set<String> = []
    @ObservationIgnored private let api: any SkillIconsAPI = SkillIcons()

    private let cacheDir: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appending(path: "VibeDeck/skill-icons", directoryHint: .isDirectory)
    }()
    private var catalogURL: URL { cacheDir.appending(path: "catalog.json") }

    private init() {
        if let data = try? Data(contentsOf: catalogURL), let icons = try? JSONDecoder().decode([SkillIcon].self, from: data) {
            catalog = icons
        }
    }

    func icon(_ id: String) -> SkillIcon? { catalog.first { $0.id == id } }

    /// Loads the catalog from the server (once per launch unless `force`); the disk copy is used meanwhile.
    func loadCatalog(force: Bool = false) async {
        guard !loadingCatalog, force || catalogError != nil || !fetchedCatalog else { return }
        loadingCatalog = true
        defer { loadingCatalog = false }
        do {
            let icons = try await api.catalog()
            catalog = icons
            catalogError = nil
            fetchedCatalog = true
            try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            try? JSONEncoder().encode(icons).write(to: catalogURL, options: .atomic)
        } catch {
            catalogError = error.localizedDescription
        }
    }
    @ObservationIgnored private var fetchedCatalog = false

    /// The rendered icon, or nil while it loads (the call starts the download).
    func image(_ id: String, theme: SkillIconTheme) -> NSImage? {
        let key = "\(id)-\(theme.rawValue)"
        if let image = images[key] { return image }
        guard !inFlight.contains(key) else { return nil }
        inFlight.insert(key)
        let file = cacheDir.appending(path: "\(key).svg")
        Task {
            defer { inFlight.remove(key) }
            if let data = try? Data(contentsOf: file), let image = NSImage(data: data) {
                images[key] = image
                return
            }
            do {
                let badge = try await api.badge(icons: [id], theme: theme, perLine: nil)
                let data = try await api.image(url: badge.url)
                guard let image = NSImage(data: data) else { return }
                images[key] = image
                try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
                try? data.write(to: file, options: .atomic)
            } catch {
                // Leaves the placeholder; the next appearance retries.
            }
        }
        return nil
    }
}

/// A Skill Icons icon, in the variant that matches the current appearance.
struct SkillIconImage: View {
    let id: String
    var size: CGFloat = 40
    @Environment(\.colorScheme) private var colorScheme
    private var cache: SkillIconCache { .shared }

    var body: some View {
        // Icons without variants come out the same in both themes.
        let theme: SkillIconTheme = colorScheme == .dark ? .dark : .light
        Group {
            if let image = cache.image(id, theme: theme) {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: size * 0.22).fill(.quaternary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(cache.icon(id)?.name ?? id)
    }
}
