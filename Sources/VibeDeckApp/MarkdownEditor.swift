import AppKit
import SwiftUI

/// Plain-text markdown editor backed by NSTextView so Cmd+Z / Cmd+Shift+Z come from AppKit's
/// native undo. Each doc gets its own UndoManager, kept alive across autosaves and doc switches.
struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    let undoManager: UndoManager
    var autoFocus = true

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        textView.delegate = context.coordinator
        textView.textStorage?.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.importsGraphics = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 28, height: 24)
        textView.font = MarkdownHighlighter.baseFont
        textView.typingAttributes = MarkdownHighlighter.baseAttributes
        textView.string = text
        scrollView.drawsBackground = false
        if autoFocus { DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) } }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView, textView.string != text else { return }
        // External change (file edited by an AI/CLI): apply it as an undoable edit.
        let full = NSRange(location: 0, length: (textView.string as NSString).length)
        let selected = textView.selectedRanges
        if textView.shouldChangeText(in: full, replacementString: text) {
            textView.textStorage?.replaceCharacters(in: full, with: text)
            textView.didChangeText()
            undoManager.setActionName("Alteração externa")
        }
        let length = (text as NSString).length
        textView.selectedRanges = selected.map {
            let r = $0.rangeValue
            return NSValue(range: NSRange(location: min(r.location, length), length: 0))
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate, @preconcurrency NSTextStorageDelegate {
        var parent: MarkdownEditor

        init(_ parent: MarkdownEditor) { self.parent = parent }

        func undoManager(for view: NSTextView) -> UndoManager? { parent.undoManager }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if parent.text != textView.string { parent.text = textView.string }
        }

        func textStorage(_ storage: NSTextStorage, didProcessEditing mask: NSTextStorageEditActions, range: NSRange, changeInLength delta: Int) {
            guard mask.contains(.editedCharacters) else { return }
            MarkdownHighlighter.apply(to: storage)
        }
    }
}

@MainActor
enum MarkdownHighlighter {
    static let baseFont = NSFont.systemFont(ofSize: 14)
    static let monoFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

    static let baseAttributes: [NSAttributedString.Key: Any] = {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        return [.font: baseFont, .foregroundColor: NSColor.textColor, .paragraphStyle: paragraph]
    }()

    private static func regex(_ pattern: String, _ options: NSRegularExpression.Options = [.anchorsMatchLines]) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: options)
    }

    private static let heading = regex(#"^(#{1,6})\s.*$"#)
    private static let fence = regex(#"^```[^\n]*\n[\s\S]*?^```\s*$"#)
    private static let inlineCode = regex(#"`[^`\n]+`"#)
    private static let bold = regex(#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#)
    private static let italic = regex(#"(?<![\*_])([\*_])(?=\S)(.+?)(?<=\S)\1(?![\*_])"#)
    private static let link = regex(#"\[([^\]\n]+)\]\(([^)\n]+)\)"#)
    private static let listMarker = regex(#"^\s*([-*+]|\d+\.)\s(\[[ xX]\]\s)?"#)
    private static let quote = regex(#"^>.*$"#)
    private static let frontmatter = regex(#"\A---\n[\s\S]*?\n---\s*$"#)

    static func apply(to storage: NSTextStorage) {
        let string = storage.string
        let full = NSRange(location: 0, length: (string as NSString).length)
        storage.setAttributes(baseAttributes, range: full)

        func each(_ re: NSRegularExpression, _ body: (NSTextCheckingResult) -> Void) {
            re.enumerateMatches(in: string, range: full) { m, _, _ in if let m { body(m) } }
        }

        each(heading) { m in
            let level = m.range(at: 1).length
            let size: CGFloat = [26, 21, 18, 16, 15, 14][level - 1]
            storage.addAttribute(.font, value: NSFont.systemFont(ofSize: size, weight: .bold), range: m.range)
            storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: m.range(at: 1))
        }
        each(bold) { storage.applyFontTraits(.boldFontMask, range: $0.range) }
        each(italic) { storage.applyFontTraits(.italicFontMask, range: $0.range) }
        each(link) { m in
            storage.addAttribute(.foregroundColor, value: NSColor.linkColor, range: m.range(at: 1))
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: m.range(at: 2))
        }
        each(listMarker) { storage.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: $0.range) }
        each(quote) { storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: $0.range) }
        each(inlineCode) { m in
            storage.addAttributes([.font: monoFont, .backgroundColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.12)], range: m.range)
        }
        each(fence) { m in
            storage.addAttributes([.font: monoFont, .foregroundColor: NSColor.secondaryLabelColor], range: m.range)
        }
        each(frontmatter) { storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: $0.range) }
    }
}
