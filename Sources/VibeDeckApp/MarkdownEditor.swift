import AppKit
import SwiftUI

/// Markdown editor with presentation-only formatting, backed by NSTextView so Cmd+Z / Cmd+Shift+Z come from AppKit's
/// native undo. Each doc gets its own UndoManager, kept alive across autosaves and doc switches.
/// With `importFiles`, dropped or pasted files are handed over and the returned markdown is inserted.
struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    let undoManager: UndoManager
    var autoFocus = true
    /// Docs/ideas opt into live rendering; prompts retain source editing.
    var baseURL: URL?
    var importFiles: (([URL]) -> [String])?
    var importImage: ((Data) -> String?)?
    /// Text to insert at the cursor (e.g. links from the "Anexar" button); a new id inserts again.
    var insertion: MarkdownInsertion?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = AttachmentTextView.markdownView()
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.documentView = textView
        textView.importFiles = importFiles
        textView.importImage = importImage
        textView.onWidthChange = { [weak coordinator = context.coordinator] in coordinator?.render() }
        context.coordinator.lastInsertion = insertion?.id
        textView.delegate = context.coordinator
        context.coordinator.textView = textView
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
        context.coordinator.render()
        scrollView.drawsBackground = false
        if autoFocus { DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) } }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? AttachmentTextView else { return }
        textView.importFiles = importFiles
        textView.importImage = importImage
        if let insertion, insertion.id != context.coordinator.lastInsertion {
            context.coordinator.lastInsertion = insertion.id
            DispatchQueue.main.async {
                if insertion.atEnd { textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0)) }
                textView.insertBlock(insertion.text)
            }
        }
        guard textView.string != text else { return }
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
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditor
        var lastInsertion: UUID?
        weak var textView: AttachmentTextView?
        private var activeRange = NSRange(location: 0, length: 0)
        private var pendingRange: NSRange?
        private var scheduled = false
        private var imageTasks: [URL: Task<Void, Never>] = [:]
        private var failedImages: Set<URL> = []

        func render(_ range: NSRange? = nil) {
            guard let textView, let storage = textView.textStorage else { return }
            let manager = parent.undoManager
            manager.disableUndoRegistration()
            storage.beginEditing()
            MarkdownHighlighter.apply(to: storage, selection: textView.selectedRange(), range: range,
                                      baseURL: parent.baseURL, rendered: parent.baseURL != nil,
                                      imageWidth: max(40, textView.bounds.width - 66)) { [weak self] url in
                if let image = MarkdownImageLoader.cached(url) { return image }
                guard let self, self.imageTasks[url] == nil, !self.failedImages.contains(url) else { return nil }
                self.imageTasks[url] = Task { [weak self] in
                    do { _ = try await MarkdownImageLoader.image(at: url) }
                    catch { self?.failedImages.insert(url) }
                    self?.imageTasks[url] = nil
                    // Image arrival is outside typing; render against current source/selection.
                    self?.render()
                }
                return nil
            }
            storage.endEditing()
            manager.enableUndoRegistration()
            textView.typingAttributes = MarkdownHighlighter.baseAttributes
            activeRange = MarkdownHighlighter.activeRange(in: storage, selection: textView.selectedRange())
            textView.needsDisplay = true
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView, let storage = textView.textStorage else { return }
            let next = MarkdownHighlighter.activeRange(in: storage, selection: textView.selectedRange())
            guard next != activeRange else { return }
            let old = activeRange
            activeRange = next
            // Two separate regions: crossing a large document doesn't reformat everything between them.
            DispatchQueue.main.async { [weak self] in
                guard let self, let storage = self.textView?.textStorage else { return }
                self.render(MarkdownHighlighter.clamped(old, length: storage.length))
                self.render(MarkdownHighlighter.clamped(next, length: storage.length))
            }
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange,
                      replacementString: String?) -> Bool {
            guard let storage = textView.textStorage else { return true }
            let line = (storage.string as NSString).lineRange(for: affectedCharRange)
            let old = (storage.string as NSString).substring(with: line)
            let updated = (old as NSString).replacingCharacters(
                in: NSRange(location: affectedCharRange.location - line.location, length: affectedCharRange.length),
                with: replacementString ?? "")
            let block = MarkdownHighlighter.activeRange(in: storage, selection: affectedCharRange)
            let delta = ((replacementString ?? "") as NSString).length - affectedCharRange.length
            // A delimiter edit can change the remainder's block structure; ordinary edits stay local.
            let requiresFull = old.contains("```") || old.contains("~~~") || updated.contains("```") || updated.contains("~~~")
            let changed = NSRange(location: block.location, length: max(0, block.length + delta))
            if requiresFull || (scheduled && pendingRange == nil) {
                pendingRange = nil
            } else if scheduled, let pendingRange {
                self.pendingRange = NSUnionRange(pendingRange, changed)
            } else {
                pendingRange = changed
            }
            return true
        }

        private func scheduleRender() {
            guard !scheduled else { return }
            scheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.scheduled = false
                let range = self.pendingRange
                self.pendingRange = nil
                self.render(range)
            }
        }

        init(_ parent: MarkdownEditor) { self.parent = parent }

        func undoManager(for view: NSTextView) -> UndoManager? { parent.undoManager }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if parent.text != textView.string { parent.text = textView.string }
            scheduleRender()
        }


    }
}

struct MarkdownInsertion: Equatable {
    let id = UUID()
    let text: String
    /// Append at the end of the text instead of at the cursor.
    var atEnd = false
}

/// Plain-text view that turns dropped files (and pasted files/images) into attachment links.
final class AttachmentTextView: NSTextView {
    /// Use TextKit 1 explicitly: drawing images over source glyphs never changes the backing string.
    static func markdownView(frame: NSRect = .zero) -> AttachmentTextView {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: frame.width, height: .greatestFiniteMagnitude))
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        container.widthTracksTextView = true
        let view = AttachmentTextView(frame: frame, textContainer: container)
        view.isEditable = true
        view.isSelectable = true
        view.drawsBackground = false
        return view
    }

    var onWidthChange: (() -> Void)?

    override func setFrameSize(_ newSize: NSSize) {
        let changed = abs(frame.width - newSize.width) > 1
        super.setFrameSize(newSize)
        if changed { onWidthChange?() }
    }
    var importFiles: (([URL]) -> [String])?
    var importImage: ((Data) -> String?)?

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let storage = textStorage, let layout = layoutManager, let container = textContainer else { return }
        let origin = textContainerOrigin
        let visible = layout.glyphRange(forBoundingRect: dirtyRect.offsetBy(dx: -origin.x, dy: -origin.y), in: container)
        let characters = layout.characterRange(forGlyphRange: visible, actualGlyphRange: nil)
        storage.enumerateAttribute(MarkdownHighlighter.imageKey, in: characters) { value, range, _ in
            guard let image = value as? NSImage,
                  let size = storage.attribute(MarkdownHighlighter.imageSizeKey, at: range.location, effectiveRange: nil) as? NSSize else { return }
            let glyph = layout.glyphRange(forCharacterRange: NSRange(location: range.location, length: 1), actualCharacterRange: nil)
            let rect = layout.boundingRect(forGlyphRange: glyph, in: container)
            image.draw(in: NSRect(x: origin.x + rect.minX, y: origin.y + rect.minY + 4,
                                  width: size.width, height: size.height), from: .zero,
                       operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
    }

    override var acceptableDragTypes: [NSPasteboard.PasteboardType] {
        importFiles == nil ? super.acceptableDragTypes : super.acceptableDragTypes + [.fileURL]
    }

    private func fileURLs(_ pasteboard: NSPasteboard) -> [URL] {
        guard importFiles != nil else { return [] }
        return pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let op = super.draggingEntered(sender)
        return fileURLs(sender.draggingPasteboard).isEmpty ? op : .copy
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let op = super.draggingUpdated(sender)
        return fileURLs(sender.draggingPasteboard).isEmpty ? op : .copy
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let urls = fileURLs(sender.draggingPasteboard)
        guard let importFiles, !urls.isEmpty else { return super.performDragOperation(sender) }
        let index = characterIndexForInsertion(at: convert(sender.draggingLocation, from: nil))
        setSelectedRange(NSRange(location: index, length: 0))
        insertBlock(importFiles(urls).joined(separator: "\n"))
        window?.makeFirstResponder(self)
        return true
    }

    override func paste(_ sender: Any?) {
        if !pasteContents(of: .general) { super.paste(sender) }
    }

    /// Import attachments without using rich-text paste (also accepts isolated pasteboards in tests).
    @discardableResult
    func pasteContents(of pasteboard: NSPasteboard) -> Bool {
        if let importFiles, case let urls = fileURLs(pasteboard), !urls.isEmpty {
            insertBlock(importFiles(urls).joined(separator: "\n"))
            return true
        } else if let importImage, pasteboard.string(forType: .string) == nil, let data = Self.pngData(pasteboard) {
            if let link = importImage(data) { insertBlock(link) }
            return true
        }
        return false
    }

    private static func pngData(_ pasteboard: NSPasteboard) -> Data? {
        if let png = pasteboard.data(forType: .png) { return png }
        guard let tiff = pasteboard.data(forType: .tiff) else { return nil }
        return NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
    }

    /// Inserts `text` at the cursor on a line of its own, as one undoable edit.
    func insertBlock(_ text: String) {
        guard !text.isEmpty else { return }
        let string = self.string as NSString
        let range = selectedRange()
        let before = range.location > 0 && string.character(at: range.location - 1) != 10 ? "\n" : ""
        let end = NSMaxRange(range)
        let after = end < string.length && string.character(at: end) != 10 ? "\n" : ""
        insertText(before + text + after, replacementRange: range)
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

    static let codeBlockKey = NSAttributedString.Key("VibeDeckCodeBlock")
    static let imageKey = NSAttributedString.Key("VibeDeckImage")
    static let imageSizeKey = NSAttributedString.Key("VibeDeckImageSize")
    private static let heading = regex(#"^(#{1,6})[ \t]+.*$"#)
    private static let fence = regex(#"^(`{3,}|~{3,})[^\n]*\n[\s\S]*?(?:^\1[ \t]*$|\z)"#)
    private static let inlineCode = regex(#"`[^`\n]+`"#)
    private static let bold = regex(#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#)
    private static let italic = regex(#"(?<![\*_])([\*_])(?![\*_])(?=\S)([^\n]+?)(?<=\S)(?<![\*_])\1(?![\*_])"#)
    private static let link = regex(#"(!?)\[([^\]\n]*)\]\(([^)\n]+)\)"#)
    private static let listMarker = regex(#"^[ \t]*([-*+]|\d+\.)[ \t]+(\[[ xX]\][ \t]+)?"#)
    private static let quote = regex(#"^>[ \t]?"#)

    static func clamped(_ range: NSRange, length: Int) -> NSRange {
        let start = min(range.location, length)
        return NSRange(location: start, length: min(range.length, length - start))
    }

    static func activeRange(in storage: NSTextStorage, selection: NSRange) -> NSRange {
        let selection = clamped(selection, length: storage.length)
        var line = (storage.string as NSString).lineRange(for: selection)
        if storage.length > 0 {
            // Persisted block attributes let cursor/typing updates locate a fenced block without rescanning.
            var block = NSRange()
            if storage.attribute(codeBlockKey, at: min(selection.location, storage.length - 1),
                                 longestEffectiveRange: &block, in: NSRange(location: 0, length: storage.length)) != nil {
                line = NSUnionRange(line, block)
            }
        }
        return line
    }

    /// Only attributes change: original UTF-16 characters, selection and undo history are untouched.
    /// `range` is the edited/previous/current paragraph (or fenced block); delimiter edits rebuild block context.
    static func apply(to storage: NSTextStorage, selection: NSRange = NSRange(location: 0, length: 0),
                      range: NSRange? = nil, baseURL: URL? = nil, rendered: Bool = true,
                      imageWidth: CGFloat = 480, image: (URL) -> NSImage? = { _ in nil }) {
        let source = storage.string as NSString
        var active = activeRange(in: storage, selection: selection)
        let target = range.map { source.lineRange(for: clamped($0, length: source.length)) }
            ?? NSRange(location: 0, length: source.length)
        guard target.length > 0 else { return }
        storage.beginEditing()
        defer { storage.endEditing() }
        // Regexes see only the scoped substring; anchors don't inspect the remaining document.
        let string = source.substring(with: target)
        let full = NSRange(location: 0, length: (string as NSString).length)
        storage.setAttributes(baseAttributes, range: target)
        func absolute(_ range: NSRange) -> NSRange { NSRange(location: target.location + range.location, length: range.length) }
        func each(_ re: NSRegularExpression, _ body: (NSTextCheckingResult) -> Void) {
            re.enumerateMatches(in: string, range: full) { m, _, _ in if let m { body(m) } }
        }
        var codeRanges: [NSRange] = []
        each(fence) {
            let block = absolute($0.range)
            codeRanges.append(block)
            if NSLocationInRange(selection.location, block) || NSIntersectionRange(selection, block).length > 0 {
                active = NSUnionRange(active, block)
            }
        }
        each(inlineCode) { codeRanges.append(absolute($0.range)) }
        func inCode(_ range: NSRange) -> Bool { codeRanges.contains { NSIntersectionRange($0, range).length > 0 } }
        func marker(_ range: NSRange) {
            guard rendered, NSIntersectionRange(active, range).length == 0 else { return }
            storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: range)
        }
        each(heading) { m in
            guard !inCode(absolute(m.range)) else { return }
            let size: CGFloat = [26, 21, 18, 16, 15, 14][m.range(at: 1).length - 1]
            storage.addAttribute(.font, value: NSFont.systemFont(ofSize: size, weight: .bold), range: absolute(m.range))
            marker(absolute(m.range(at: 1)))
        }
        func emphasis(_ m: NSTextCheckingResult, _ trait: NSFontTraitMask) {
            guard !inCode(absolute(m.range)) else { return }
            storage.applyFontTraits(trait, range: absolute(m.range(at: 2)))
            marker(absolute(m.range(at: 1)))
            marker(NSRange(location: NSMaxRange(absolute(m.range)) - m.range(at: 1).length, length: m.range(at: 1).length))
        }
        each(bold) { emphasis($0, .boldFontMask) }
        each(italic) { emphasis($0, .italicFontMask) }
        each(listMarker) { if !inCode(absolute($0.range)) { marker(absolute($0.range)) } }
        each(quote) { if !inCode(absolute($0.range)) { marker(absolute($0.range)) } }
        each(link) { m in
            let whole = absolute(m.range), label = absolute(m.range(at: 2))
            guard !inCode(whole) else { return }
            let destination = (string as NSString).substring(with: m.range(at: 3))
            guard let url = URL(string: destination, relativeTo: baseURL)?.absoluteURL else { return }
            storage.addAttributes([.foregroundColor: NSColor.linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue], range: label)
            if rendered, NSIntersectionRange(active, whole).length == 0 {
                storage.addAttribute(.link, value: url, range: label)
            }
            marker(NSRange(location: whole.location, length: label.location - whole.location))
            marker(NSRange(location: NSMaxRange(label), length: NSMaxRange(whole) - NSMaxRange(label)))
            if rendered, m.range(at: 1).length > 0, NSIntersectionRange(active, whole).length == 0,
               let image = image(url), image.size.width > 0, image.size.height > 0 {
                let scale = min(1, min(imageWidth / image.size.width, 320 / image.size.height))
                let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
                let paragraph = baseAttributes[.paragraphStyle] as! NSParagraphStyle
                let style = paragraph.mutableCopy() as! NSMutableParagraphStyle
                style.minimumLineHeight = size.height + 8
                storage.addAttribute(.paragraphStyle, value: style, range: source.lineRange(for: whole))
                storage.addAttributes([.font: NSFont.systemFont(ofSize: 0.1), .foregroundColor: NSColor.clear,
                                       .underlineStyle: 0], range: whole)
                // Reserve horizontal space and draw the bitmap over the original syntax, without U+FFFC.
                storage.addAttributes([imageKey: image, imageSizeKey: size, .kern: size.width],
                                      range: NSRange(location: whole.location, length: 1))
            }
        }
        each(inlineCode) { m in
            storage.addAttribute(.font, value: monoFont, range: absolute(m.range))
            marker(NSRange(location: absolute(m.range).location, length: 1))
            marker(NSRange(location: NSMaxRange(absolute(m.range)) - 1, length: 1))
        }
        each(fence) { m in
            let block = absolute(m.range)
            storage.setAttributes(baseAttributes.merging([.font: monoFont, codeBlockKey: true]) { _, new in new }, range: block)
            let first = source.lineRange(for: NSRange(location: block.location, length: 0))
            let last = source.lineRange(for: NSRange(location: NSMaxRange(block) - 1, length: 0))
            marker(first); marker(NSIntersectionRange(last, block))
        }
    }
}
