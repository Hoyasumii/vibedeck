import AppKit
import Observation
import SwiftTerm
import SwiftUI

/// The project's interactive terminal: the user's login shell in a pty, rooted at the project folder.
/// The view is created once and reused, so switching panel tabs never kills the shell.
@Observable @MainActor
final class ProjectTerminal {
    let root: URL
    private(set) var isRunning = false
    /// Whether a shell was ever started; an ended one waits for the user instead of restarting by itself.
    private(set) var hasStarted = false

    @ObservationIgnored private var delegate: Delegate?
    @ObservationIgnored private(set) lazy var view: LocalProcessTerminalView = makeView()

    init(root: URL) {
        self.root = root
    }

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
        hasStarted = true
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
        let view = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 340, height: 400))
        view.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        view.nativeForegroundColor = .textColor
        view.nativeBackgroundColor = .textBackgroundColor
        view.caretColor = .controlAccentColor
        let delegate = Delegate(owner: self)
        self.delegate = delegate
        view.processDelegate = delegate
        return view
    }

    fileprivate func ended() {
        isRunning = false
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

/// Terminal tab of the Claude panel.
struct TerminalPane: View {
    let terminal: ProjectTerminal
    /// The pane stays mounted behind the chat; the shell only starts once the tab is shown.
    let isActive: Bool

    var body: some View {
        ZStack {
            TerminalHost(terminal: terminal)
                .padding(.leading, 8)
                .padding(.vertical, 4)
            if !terminal.isRunning, terminal.hasStarted {
                VStack(spacing: 8) {
                    Text("O terminal foi encerrado.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Abrir de novo") {
                        terminal.start()
                        terminal.focus()
                    }
                    .buttonStyle(.glass)
                }
                .padding()
                .glassEffect(.regular, in: .rect(cornerRadius: 12))
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onChange(of: isActive, initial: true) { _, active in
            guard active else { return }
            if !terminal.hasStarted { terminal.start() }
            DispatchQueue.main.async { terminal.focus() }
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
