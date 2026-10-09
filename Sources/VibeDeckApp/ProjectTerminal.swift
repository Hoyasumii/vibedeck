import AppKit
import Observation
import SwiftTerm
import SwiftUI

/// One interactive terminal of the project: the user's login shell in a pty, rooted at the project folder.
/// Each lives in its own tab. The view is created once and reused, so switching tabs never kills the shell;
/// when the shell exits (`exit`), `onExit` runs so its tab can close.
@Observable @MainActor
final class ProjectTerminal {
    let root: URL
    /// 1, 2, … among the window's open terminals; shown in the tab title.
    let number: Int
    private(set) var isRunning = false

    @ObservationIgnored private let onExit: () -> Void
    @ObservationIgnored private var delegate: Delegate?
    @ObservationIgnored private(set) lazy var view: LocalProcessTerminalView = makeView()

    init(root: URL, number: Int, onExit: @escaping () -> Void) {
        self.root = root
        self.number = number
        self.onExit = onExit
    }

    var title: String { number == 1 ? "Terminal" : "Terminal \(number)" }

    /// Starts the shell if it isn't running.
    func start() {
        guard !isRunning else { return }
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        var environment = Terminal.getEnvironmentVariables(termName: "xterm-256color", trueColor: true)
        if let path = ProcessInfo.processInfo.environment["PATH"] { environment.append("PATH=\(path)") }
        environment.append("TERM_PROGRAM=VibeDeck")
        // A leading "-" in argv[0] makes it a login shell, which loads the user's PATH and aliases.
        view.startProcess(executable: shell, args: [], environment: environment, execName: "-" + (shell as NSString).lastPathComponent, currentDirectory: root.path)
        isRunning = true
        watchExit(of: view.process.shellPid)
    }

    /// SwiftTerm's own exit watcher is unreliable: when the pty hits EOF before the exit event is
    /// delivered, it cancels the watcher, so `processTerminated` never fires and the shell is left a
    /// zombie. Watching the pid here (and reaping it) makes `exit` close the tab every time. The
    /// watcher keeps itself alive until the shell is reaped, also after `terminate()` drops the terminal.
    private func watchExit(of pid: pid_t) {
        guard pid > 0 else { return }
        let monitor = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
        monitor.setEventHandler { [weak self] in
            var status: Int32 = 0
            waitpid(pid, &status, WNOHANG)
            monitor.cancel()
            MainActor.assumeIsolated { self?.ended() }
        }
        monitor.activate()
    }

    /// Types `command` into the shell and runs it.
    func run(_ command: String) {
        start()
        let text = command + "\r"
        view.send(data: ArraySlice(Array(text.utf8)))
        focus()
    }

    func focus() {
        view.window?.makeFirstResponder(view)
    }

    func terminate() {
        guard isRunning else { return }
        view.terminate()
        isRunning = false
    }

    private func makeView() -> LocalProcessTerminalView {
        let view = ProjectTerminalView(frame: NSRect(x: 0, y: 0, width: 340, height: 400))
        view.canReceiveDrop = { [weak self] in self?.isRunning == true }
        // SwiftTerm keeps only 500 lines by default; long builds and test runs scroll past that.
        view.getTerminal().changeHistorySize(10_000)
        view.font = Self.font(size: 12)
        view.nativeForegroundColor = .textColor
        // Same as the rest of the window, so the terminal doesn't read as a separate box.
        view.nativeBackgroundColor = .windowBackgroundColor
        view.caretColor = .controlAccentColor
        let delegate = Delegate(owner: self)
        self.delegate = delegate
        view.processDelegate = delegate
        return view
    }

    /// JetBrains Mono Nerd Font (OFL, bundled under Contents/Resources/Fonts by scripts/build-app.sh),
    /// falling back to the system monospaced font when it isn't there (e.g. `swift run`).
    private static func font(size: CGFloat) -> NSFont {
        registerBundledFonts
        return NSFont(name: "JetBrainsMonoNFM-Regular", size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    private static let registerBundledFonts: Void = {
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
              let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return }
        for url in urls where url.pathExtension == "ttf" {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()

    /// Called by both exit watchers (ours and SwiftTerm's); only the first one counts.
    fileprivate func ended() {
        guard isRunning else { return }
        isRunning = false
        onExit()
    }

    private final class Delegate: LocalProcessTerminalViewDelegate {
        weak var owner: ProjectTerminal?

        init(owner: ProjectTerminal) {
            self.owner = owner
        }

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

        func processTerminated(source: TerminalView, exitCode: Int32?) {
            Task { @MainActor in self.owner?.ended() }
        }
    }
}

/// One project terminal, shown as a page (and tab) of the detail column.
struct TerminalPage: View {
    let id: UUID
    @Environment(AISession.self) private var claude

    var body: some View {
        // The terminal is gone for a moment after `exit`, until the window closes its tab.
        if let terminal = claude.terminals[id] {
            TerminalHost(terminal: terminal)
                .padding(.leading, 8)
                .padding(.vertical, 4)
                .background(Color(nsColor: .textBackgroundColor))
                .onAppear { DispatchQueue.main.async { terminal.focus() } }
        } else {
            Color(nsColor: .textBackgroundColor)
        }
    }
}

private struct TerminalHost: NSViewRepresentable {
    let terminal: ProjectTerminal

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = terminal.view
        view.removeFromSuperview()
        return view
    }

    func updateNSView(_ view: LocalProcessTerminalView, context: Context) {}
}
