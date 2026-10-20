import AppKit
import ObjectiveC
import SwiftUI
import VibeDeckCore

/// Standard AppKit menu commands keep their responder-chain behavior and validation.
/// SwiftUI controls are instrumented at their call sites; typing selectors are deliberately excluded.
@MainActor enum NativeActionLogging {
    static var roots: [ObjectIdentifier: URL] = [:]
    private static var installed = false

    static func install() {
        guard !installed,
              let original = class_getInstanceMethod(NSApplication.self, #selector(NSApplication.sendAction(_:to:from:))),
              let logged = class_getInstanceMethod(NSApplication.self, #selector(NSApplication.vdSendAction(_:to:from:))) else { return }
        method_exchangeImplementations(original, logged)
        installed = true
    }
}

extension NSApplication {
    @objc fileprivate func vdSendAction(_ action: Selector, to target: Any?, from sender: Any?) -> Bool {
        let name = NSStringFromSelector(action)
        let labels = ["undo:": "Desfazer", "redo:": "Refazer", "copy:": "Copiar", "cut:": "Recortar",
                      "paste:": "Colar", "selectAll:": "Selecionar tudo", "toggleSidebar:": "Alternar barra lateral",
                      "performClose:": "Fechar janela", "performMiniaturize:": "Minimizar", "performZoom:": "Ampliar",
                      "terminate:": "Encerrar", "orderFrontStandardAboutPanel:": "Sobre o VibeDeck",
                      "hide:": "Ocultar VibeDeck", "hideOtherApplications:": "Ocultar outros", "unhideAllApplications:": "Mostrar tudo"]
        guard VDLog.actionID == nil, let label = labels[name] else {
            return vdSendAction(action, to: target, from: sender)
        }
        let root = keyWindow.flatMap { NativeActionLogging.roots[ObjectIdentifier($0)] }
        return VDLog.withAction(control: "native." + name.replacingOccurrences(of: ":", with: ""),
                                label: (sender as? NSMenuItem)?.title ?? label, project: root) {
            vdSendAction(action, to: target, from: sender)
        }
    }
}

struct LoggingWindowContext: NSViewRepresentable {
    let root: URL
    func makeNSView(context: Context) -> ContextView { ContextView(root: root) }
    func updateNSView(_ view: ContextView, context: Context) { view.root = root }

    final class ContextView: NSView {
        var root: URL
        private weak var registeredWindow: NSWindow?
        init(root: URL) { self.root = root; super.init(frame: .zero) }
        required init?(coder: NSCoder) { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let registeredWindow { NativeActionLogging.roots.removeValue(forKey: ObjectIdentifier(registeredWindow)) }
            registeredWindow = window
            if let window { NativeActionLogging.roots[ObjectIdentifier(window)] = root }
        }
    }
}
