import AppKit
import SwiftUI
import VibeDeckCore

@main
struct VibeDeckApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        WindowGroup("VibeDeck", for: URL.self) { $root in
            // No min-size frame here: on macOS 26+ it fights NavigationSplitView/inspector
            // column sizing and crashes AppKit's constraint pass. Columns set their own limits.
            RootView(root: $root)
        }
        .defaultSize(width: 1180, height: 760)
        .windowToolbarStyle(.unified)
        .commands { AppCommands() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare SwiftPM executable (outside a .app bundle).
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.post(name: .vibedeckFlushPendingSaves, object: nil)
    }
}

extension FocusedValues {
    /// The Claude session of the focused project window (nil when Claude Code isn't installed).
    @Entry var claudeSession: AISession?
    /// Closes the focused window's active tab (nil when it has only one tab, so ⌘W closes the window).
    @Entry var closeActiveTab: (() -> Void)?
}

extension Notification.Name {
    static let vibedeckFlushPendingSaves = Notification.Name("vibedeckFlushPendingSaves")
}

struct AppCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.claudeSession) private var claude
    @FocusedValue(\.closeActiveTab) private var closeActiveTab

    var body: some Commands {
        CommandGroup(replacing: .saveItem) {
            if let closeActiveTab {
                Button("Fechar Aba", action: closeActiveTab)
                    .keyboardShortcut("w")
                Button("Fechar Janela") { NSApp.keyWindow?.performClose(nil) }
                    .keyboardShortcut("w", modifiers: [.command, .shift])
            } else {
                Button("Fechar Janela") { NSApp.keyWindow?.performClose(nil) }
                    .keyboardShortcut("w")
            }
        }
        CommandGroup(after: .newItem) {
            Button("Abrir Projeto…") {
                if let url = FolderPicker.pick() { openWindow(value: url) }
            }
            .keyboardShortcut("o")
            Menu("Recentes") {
                ForEach(RecentProjects.shared.urls, id: \.self) { url in
                    Button(url.lastPathComponent) { openWindow(value: url) }
                }
            }
        }
        CommandGroup(after: .sidebar) {
            if let claude {
                if !AIProvider.installed.isEmpty {
                    Button("Abrir IA") { claude.requestedPage = .chat }
                        .keyboardShortcut("c", modifiers: [.command, .shift])
                }
                Button("Novo Terminal") { claude.openTerminal() }
                    .keyboardShortcut("`", modifiers: .control)
            }
        }
    }
}

enum FolderPicker {
    @MainActor
    static func pick() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Abrir"
        panel.message = "Escolha a pasta do projeto"
        return panel.runModal() == .OK ? panel.url : nil
    }
}

/// Recently opened project folders, stored as bookmarks so moved folders are still found.
@Observable
final class RecentProjects {
    @MainActor static let shared = RecentProjects()
    private let key = "recentProjects"
    private(set) var urls: [URL] = []

    private init() {
        let datas = UserDefaults.standard.array(forKey: key) as? [Data] ?? []
        urls = datas.compactMap { data in
            var stale = false
            return try? URL(resolvingBookmarkData: data, options: [.withoutUI], bookmarkDataIsStale: &stale)
        }
        .filter { ProjectStore.isProject($0) }
    }

    func add(_ url: URL) {
        urls.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
        urls.insert(url, at: 0)
        urls = Array(urls.prefix(12))
        persist()
    }

    func remove(_ url: URL) {
        urls.removeAll { $0 == url }
        persist()
    }

    private func persist() {
        let datas = urls.compactMap { try? $0.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) }
        UserDefaults.standard.set(datas, forKey: key)
    }
}

struct RootView: View {
    @Binding var root: URL?
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        content
            // `open -a VibeDeck <folder>` or dropping a folder on the Dock icon.
            .onOpenURL { url in
                guard url.isFileURL else { return }
                if root == nil, ProjectStore.isProject(url) { root = url } else { openWindow(value: url) }
            }
    }

    @ViewBuilder
    private var content: some View {
        if let root, ProjectStore.isProject(root) {
            ProjectWindow(root: root)
                .id(root)
                .navigationTitle(root.lastPathComponent)
                .onAppear { RecentProjects.shared.add(root) }
        } else {
            WelcomeView(root: $root)
        }
    }
}
