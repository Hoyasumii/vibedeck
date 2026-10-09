import AppKit
import SwiftUI
import Testing
@testable import VibeDeckApp

@Suite(.serialized) @MainActor struct MarkdownHighlighterTests {
    private func color(_ storage: NSTextStorage, _ index: Int) -> NSColor? {
        storage.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor
    }

    @Test func sourceAndMarkersFollowCursor() {
        let source = "**a**\n# t\n`code`\n- item\n> quote\n[label](../attachments/file.pdf)"
        let storage = NSTextStorage(string: source)
        MarkdownHighlighter.apply(to: storage)
        #expect(storage.string == source)
        #expect(color(storage, 0) == .textColor)
        #expect(color(storage, 6) == .tertiaryLabelColor)
        let font = storage.attribute(.font, at: 2, effectiveRange: nil) as! NSFont
        #expect(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
        MarkdownHighlighter.apply(to: storage, selection: NSRange(location: 8, length: 0))
        #expect(color(storage, 0) == .tertiaryLabelColor)
        #expect(color(storage, 6) == .textColor)
        #expect(storage.string == source)
        #expect(MarkdownHighlighter.baseAttributes[.backgroundColor] == nil)
        storage.enumerateAttribute(.backgroundColor, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            #expect(value == nil)
        }
    }

    @Test func codeBlockShowsWholeBlockAndDoesNotParseEmphasis() {
        let source = "outside\n```swift\n**literal**\nlet x = 1\n```\n# title"
        let storage = NSTextStorage(string: source)
        MarkdownHighlighter.apply(to: storage, selection: NSRange(location: 22, length: 0))
        #expect(color(storage, 8) == .textColor)
        #expect(color(storage, 38) == .textColor)
        let font = storage.attribute(.font, at: 19, effectiveRange: nil) as! NSFont
        #expect(!NSFontManager.shared.traits(of: font).contains(.boldFontMask))
        MarkdownHighlighter.apply(to: storage, selection: NSRange(location: 0, length: 0))
        #expect(color(storage, 8) == .tertiaryLabelColor)
        #expect(storage.string == source)
    }

    @Test func relativeImagesRenderOnlyOutsideCursorWithoutReplacingSource() {
        let base = URL(fileURLWithPath: "/tmp/project/.vibedeck/docs", isDirectory: true)
        let source = "intro\n![foto](../attachments/foto.png)\n[arquivo](../attachments/file.pdf)"
        let storage = NSTextStorage(string: source)
        let bitmap = NSImage(size: NSSize(width: 1000, height: 500))
        var requested: URL?
        MarkdownHighlighter.apply(to: storage, baseURL: base, imageWidth: 200) { url in
            requested = url
            return bitmap
        }
        #expect(requested?.standardizedFileURL.path == "/tmp/project/.vibedeck/attachments/foto.png")
        #expect(storage.attribute(MarkdownHighlighter.imageKey, at: 6, effectiveRange: nil) is NSImage)
        let size = storage.attribute(MarkdownHighlighter.imageSizeKey, at: 6, effectiveRange: nil) as? NSSize
        #expect(size == NSSize(width: 200, height: 100))
        let label = (source as NSString).range(of: "arquivo").location
        let url = storage.attribute(.link, at: label, effectiveRange: nil) as? URL
        #expect(url?.standardizedFileURL.path == "/tmp/project/.vibedeck/attachments/file.pdf")
        MarkdownHighlighter.apply(to: storage, selection: NSRange(location: 10, length: 0), baseURL: base) { _ in bitmap }
        #expect(storage.attribute(MarkdownHighlighter.imageKey, at: 6, effectiveRange: nil) == nil)
        #expect(color(storage, 6) == .textColor)
        #expect(storage.string == source)
    }

    @Test func scopedRenderingLeavesRestOfLargeDocumentUntouched() {
        let source = (0..<5000).map { "# Linha \($0) **texto**" }.joined(separator: "\n")
        let storage = NSTextStorage(string: source)
        MarkdownHighlighter.apply(to: storage)
        let sentinel = NSAttributedString.Key("Sentinel")
        storage.addAttribute(sentinel, value: true, range: NSRange(location: 0, length: 1))
        let last = (source as NSString).range(of: "# Linha 4999").location
        let scoped = MarkdownHighlighter.activeRange(in: storage, selection: NSRange(location: last, length: 0))
        #expect(scoped.length < 100)
        for _ in 0..<100 {
            MarkdownHighlighter.apply(to: storage, selection: NSRange(location: last, length: 0), range: scoped)
        }
        #expect(storage.attribute(sentinel, at: 0, effectiveRange: nil) as? Bool == true)
        #expect(color(storage, last) == .textColor)
        #expect(storage.string == source)
    }

    @Test func promptEditorsKeepSourceSyntaxVisible() {
        let storage = NSTextStorage(string: "# Heading\n**bold**")
        MarkdownHighlighter.apply(to: storage, rendered: false)
        #expect(color(storage, 10) == .textColor)
        #expect(storage.string == "# Heading\n**bold**")
    }

    @Test func pastedFilesAndImagesUseImportCallbacks() {
        let view = AttachmentTextView.markdownView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let file = URL(fileURLWithPath: "/tmp/anexo.pdf")
        var imported: [URL] = []
        view.importFiles = { urls in imported = urls; return ["[anexo](../attachments/anexo.pdf)"] }
        pasteboard.writeObjects([file as NSURL])
        #expect(view.pasteContents(of: pasteboard))
        #expect(imported == [file])
        #expect(view.string == "[anexo](../attachments/anexo.pdf)")
        pasteboard.clearContents()
        let data = Data([1, 2, 3])
        pasteboard.setData(data, forType: .png)
        var importedImage: Data?
        view.importImage = { data in importedImage = data; return "![foto](../attachments/foto.png)" }
        view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
        #expect(view.pasteContents(of: pasteboard))
        #expect(importedImage == data)
        #expect(view.string.hasSuffix("\n![foto](../attachments/foto.png)"))
        pasteboard.clearContents()
        pasteboard.setString("markdown **original**", forType: .string)
        #expect(!view.pasteContents(of: pasteboard))
    }

    @Test func imageDrawingAndTransparentBackgroundInBothAppearances() throws {
        let source = "# Título\n![foto](../attachments/foto.png)\nTexto depois da imagem."
        let bitmap = NSImage(size: NSSize(width: 160, height: 80), flipped: false) { rect in
            NSColor.systemBlue.setFill()
            rect.fill()
            return true
        }
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: appearance)
            let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
            scroll.drawsBackground = false
            let view = AttachmentTextView.markdownView(frame: scroll.bounds)
            view.textContainerInset = NSSize(width: 28, height: 24)
            scroll.documentView = view
            window.contentView = scroll
            view.string = source
            MarkdownHighlighter.apply(to: view.textStorage!, baseURL: URL(fileURLWithPath: "/tmp/docs/")) { _ in bitmap }
            view.layoutManager?.ensureLayout(for: view.textContainer!)
            let rep = try #require(scroll.bitmapImageRepForCachingDisplay(in: scroll.bounds))
            window.appearance?.performAsCurrentDrawingAppearance {
                scroll.cacheDisplay(in: scroll.bounds, to: rep)
                // The editor is transparent; composite the actual window backdrop for visual inspection.
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                NSGraphicsContext.current?.cgContext.setBlendMode(.destinationOver)
                NSColor.windowBackgroundColor.setFill()
                NSRect(x: 0, y: 0, width: rep.pixelsWide, height: rep.pixelsHigh).fill()
                NSGraphicsContext.restoreGraphicsState()
            }
            let data = try #require(rep.representation(using: .png, properties: [:]))
            try data.write(to: URL(fileURLWithPath: "/tmp/vibedeck-md-\(name).png"))
            #expect(view.string == source)
            #expect(!view.drawsBackground && !scroll.drawsBackground)
            window.close()
        }
    }

    @Test func typingAttachmentsExternalChangeAndUndoKeepBindingExact() async {
        var bound = ""
        let undo = UndoManager()
        undo.groupsByEvent = false
        let editor = MarkdownEditor(text: Binding(get: { bound }, set: { bound = $0 }), undoManager: undo,
                                    baseURL: URL(fileURLWithPath: "/tmp/docs", isDirectory: true))
        let coordinator = editor.makeCoordinator()
        let view = AttachmentTextView.markdownView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        view.isRichText = false
        view.allowsUndo = true
        view.drawsBackground = false
        view.delegate = coordinator
        coordinator.textView = view
        undo.beginUndoGrouping()
        view.insertText("**a**\n# t", replacementRange: NSRange(location: 0, length: 0))
        undo.endUndoGrouping()
        coordinator.render()
        #expect(view.string == "**a**\n# t")
        #expect(bound == view.string)
        #expect(!view.drawsBackground)
        undo.undo()
        #expect(view.string == "")
        #expect(bound == "")
        undo.redo()
        #expect(bound == "**a**\n# t")
        undo.beginUndoGrouping()
        view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
        view.insertBlock("![foto](../attachments/foto.png)")
        undo.endUndoGrouping()
        #expect(bound.hasSuffix("\n![foto](../attachments/foto.png)"))
        undo.undo()
        #expect(bound == "**a**\n# t")
        undo.beginUndoGrouping()
        let full = NSRange(location: 0, length: (view.string as NSString).length)
        if view.shouldChangeText(in: full, replacementString: "externo") {
            view.textStorage?.replaceCharacters(in: full, with: "externo")
            view.didChangeText()
            undo.setActionName("Alteração externa")
        }
        undo.endUndoGrouping()
        #expect(bound == "externo")
        #expect(undo.undoActionName == "Alteração externa")
        undo.undo()
        #expect(bound == "**a**\n# t")
        // Allow queued presentation updates to run, also checking they add no undo operations.
        try? await Task.sleep(for: .milliseconds(20))
        #expect(bound == view.string)
    }
}
