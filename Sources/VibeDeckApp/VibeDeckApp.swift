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

        Window("Diagnóstico", id: DiagnosticsView.windowID) {
            DiagnosticsView()
        }
        .defaultSize(width: 900, height: 560)
        .windowToolbarStyle(.unified)

        Settings {
            AppSettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare SwiftPM executable (outside a .app bundle).
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        startLogging()
        NativeActionLogging.install()
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.post(name: .vibedeckFlushPendingSaves, object: nil)
        CrashSentinel.end(store: LogStore.default)
        VDLog.flush()
    }

    static var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev" }

    /// Logs previous unclean exits, then marks this run as running until a clean exit.
    private func startLogging() {
        let logs = LogStore.default
        VDLog.configure(component: .app, version: Self.version, store: logs)
        logs.prune()
        let crashes = CrashSentinel.detectUnclean(store: logs)
        for crash in crashes {
            var context = ["pid": String(crash.pid), "startedAt": crash.startedAt.formatted(Date.ISO8601FormatStyle())]
            context["version"] = crash.version
            context["report"] = crash.report
            VDLog.log(.crash, "app.unclean_exit",
                      crash.summary.map { "O app travou: \($0)" } ?? "O app encerrou de forma inesperada (sem relatório de crash do macOS).",
                      context: context)
        }
        do { try CrashSentinel.begin(store: logs, version: Self.version) } catch {
            VDLog.error(error, event: "app.sentinel_failed")
        }
        // Objective-C exceptions (AppKit) end the process right after this handler: write synchronously.
        NSSetUncaughtExceptionHandler { exception in
            VDLog.log(.crash, "app.uncaught_exception", exception.reason ?? exception.name.rawValue,
                      context: ["name": exception.name.rawValue, "stack": exception.callStackSymbols.joined(separator: "\n")], sync: true)
        }
        if !crashes.isEmpty {
            // After the first window exists, so RootView can open the diagnostics window.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { Self.showCrashNotice(count: crashes.count) }
        }
    }

    private static func showCrashNotice(count: Int) {
        let alert = NSAlert()
        alert.messageText = "O VibeDeck encerrou de forma inesperada"
        alert.informativeText = count == 1
            ? "A última execução não terminou normalmente. Os detalhes estão em Diagnóstico."
            : "\(count) execuções anteriores não terminaram normalmente. Os detalhes estão em Diagnóstico."
        alert.addButton(withTitle: "Ver Diagnóstico")
        alert.addButton(withTitle: "OK")
        if alert.runModal() == .alertFirstButtonReturn {
            NotificationCenter.default.post(name: .vibedeckOpenDiagnostics, object: nil)
        }
    }
}

/// Equatable wrapper so the focused value only changes when the tab it would close does.
struct CloseTabAction: Equatable {
    let tab: Int
    let run: () -> Void
    static func == (a: CloseTabAction, b: CloseTabAction) -> Bool { a.tab == b.tab }
}

extension FocusedValues {
    @Entry var logProjectRoot: URL?
    /// The Claude session of the focused project window (nil when Claude Code isn't installed).
    @Entry var claudeSession: AISession?
    /// Closes the focused window's active tab (nil when it has only one tab, so ⌘W closes the window).
    @Entry var closeActiveTab: CloseTabAction?
}

extension Notification.Name {
    static let vibedeckFlushPendingSaves = Notification.Name("vibedeckFlushPendingSaves")
    static let vibedeckOpenDiagnostics = Notification.Name("vibedeckOpenDiagnostics")
}

struct AppCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.claudeSession) private var claude
    @FocusedValue(\.closeActiveTab) private var closeActiveTab

    var body: some Commands {
        CommandGroup(replacing: .saveItem) {
            if let closeActiveTab {
                LoggedButton("Fechar Aba", action: closeActiveTab.run).loggedControl(control: "vibe_deck_app.button_1", label: "Fechar Aba")
                    .keyboardShortcut("w")
                LoggedButton("Fechar Janela") { NSApp.keyWindow?.performClose(nil) }.loggedControl(control: "vibe_deck_app.button_2", label: "Fechar Janela")
                    .keyboardShortcut("w", modifiers: [.command, .shift])
            } else {
                LoggedButton("Fechar Janela") { NSApp.keyWindow?.performClose(nil) }.loggedControl(control: "vibe_deck_app.button_3", label: "Fechar Janela")
                    .keyboardShortcut("w")
            }
        }
        CommandGroup(after: .newItem) {
            LoggedButton("Abrir Projeto…") {
                if let url = FolderPicker.pick() { openWindow(value: url) }
            }.loggedControl(control: "vibe_deck_app.button_4", label: "Abrir Projeto…")
            .keyboardShortcut("o")
            Menu("Recentes") {
                ForEach(RecentProjects.shared.urls, id: \.self) { url in
                    LoggedButton(url.lastPathComponent) { openWindow(value: url) }.loggedControl(control: "vibe_deck_app.button_5", label: "Ativar controle")
                }
            }
        }
        CommandGroup(after: .sidebar) {
            if let claude {
                if !AIProvider.installed(in: claude.root).isEmpty {
                    LoggedButton("Abrir IA") { claude.requestedPage = .chat }.loggedControl(control: "vibe_deck_app.button_6", label: "Abrir IA")
                        .keyboardShortcut("c", modifiers: [.command, .shift])
                }
                LoggedButton("Novo Terminal") { claude.openTerminal() }.loggedControl(control: "vibe_deck_app.button_7", label: "Novo Terminal")
                    .keyboardShortcut("`", modifiers: .control)
            }
        }
        CommandGroup(after: .help) {
            LoggedButton("Diagnóstico…") { openWindow(id: DiagnosticsView.windowID) }.loggedControl(control: "vibe_deck_app.button_8", label: "Diagnóstico…")
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
            .onReceive(NotificationCenter.default.publisher(for: .vibedeckOpenDiagnostics)) { _ in
                openWindow(id: DiagnosticsView.windowID)
            }
    }

    @ViewBuilder
    private var content: some View {
        if let root, ProjectStore.isProject(root) {
            ProjectWindow(root: root)
                .id(root)
                .navigationTitle(RemoteWorkspace.existing(at: root)?.destination.title ?? root.lastPathComponent)
                .onAppear { RecentProjects.shared.add(root) }
        } else {
            WelcomeView(root: $root)
        }
    }
}
