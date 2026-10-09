import AppKit
import SwiftUI

// Run the production editor through NSViewRepresentable, including its actual
// storage delegate and binding. No visible window or global clipboard changes.
@MainActor func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        print("Sources/VibeDeckApp/MarkdownEditor.swift:1: \(message)")
        exit(1)
    }
}

@MainActor func descendants(_ view: NSView) -> [NSTextView] {
    (view as? NSTextView).map { [$0] } ?? view.subviews.flatMap(descendants)
}

@MainActor func pump() {
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
}

@MainActor func main() {
_ = NSApplication.shared
var value = ""
let binding = Binding<String>(get: { value }, set: { value = $0 })
let mode = CommandLine.arguments.last!
let undo = UndoManager()
undo.groupsByEvent = mode != "undo" && mode != "prompt"
let editor = MarkdownEditor(text: binding, undoManager: undo, autoFocus: false,
                            baseURL: mode == "prompt" ? nil : URL(fileURLWithPath: "/tmp/docs", isDirectory: true))
let host = NSHostingView(rootView: editor)
host.frame = NSRect(x: 0, y: 0, width: 640, height: 480)
host.layoutSubtreeIfNeeded()
pump()
let views = descendants(host)
check(views.count == 1, "o editor hospedado deve conter um único NSTextView")
let view = views[0]
check(view.delegate != nil, "delegate de produção precisa estar conectado")

if mode == "raw" {
    for sample in ["**a**", "# t", "**a**\n# t\n[ação](../attachments/a.png)\n`código`\n- item\n🙂"] {
        view.setSelectedRange(NSRange(location: 0, length: (view.string as NSString).length))
        view.insertText(sample, replacementRange: view.selectedRange())
        pump()
        check(view.string == sample, "textView.string foi reescrito durante a digitação/renderização")
        check(value == sample, "binding não contém os caracteres markdown exatos")
        MarkdownHighlighter.apply(to: view.textStorage!)
        check(view.string == sample && value == sample, "highlighter alterou caracteres markdown")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            // Same Data(text.utf8) persistence contract enforced by check.py.
            try Data(value.utf8).write(to: url)
            let saved = try Data(contentsOf: url)
            check(saved == Data(sample.utf8), "salvar alterou os bytes do markdown")
        } catch {
            check(false, "round-trip em disco falhou: \(error)")
        }
    }
} else if mode == "cursor" {
    // Each syntax family must change appearance when its line becomes active.
    for (sample, marker) in [("# t", 0), ("**a**", 0), ("`a`", 0),
                              ("[a](../attachments/a.txt)", 0), ("- item", 0), ("> quote", 0)] {
        let text = sample + "\nlinha neutra"
        view.setSelectedRange(NSRange(location: 0, length: (view.string as NSString).length))
        view.insertText(text, replacementRange: view.selectedRange())
        view.setSelectedRange(NSRange(location: (sample as NSString).length + 1, length: 0))
        pump()
        let inactive = view.textStorage!.attributes(at: marker, effectiveRange: nil) as NSDictionary
        view.setSelectedRange(NSRange(location: 0, length: 0))
        pump()
        let active = view.textStorage!.attributes(at: marker, effectiveRange: nil) as NSDictionary
        check(!inactive.isEqual(active), "cursor não muda a visibilidade do marcador em '\(sample)'")
        check(view.string == text && value == text, "mover cursor alterou o markdown")
        let foreground = active[NSAttributedString.Key.foregroundColor] as? NSColor
        check(foreground == NSColor.textColor, "marcador da linha ativa deve estar visível na cor normal")
        view.setSelectedRange(NSRange(location: (sample as NSString).length + 1, length: 0))
        pump()
        check(inactive.isEqual(view.textStorage!.attributes(at: marker, effectiveRange: nil) as NSDictionary),
              "estilo fora do cursor não foi restaurado")
    }
} else if mode == "images" {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    do {
        let attachments = root.appendingPathComponent("attachments", isDirectory: true)
        try FileManager.default.createDirectory(at: attachments, withIntermediateDirectories: true)
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 2, bitsPerSample: 8,
                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.setColor(.red, atX: 0, y: 0)
        let imageURL = attachments.appendingPathComponent("image.png")
        try bitmap.representation(using: .png, properties: [:])!.write(to: imageURL)
        for directory in ["docs", "ideas"] {
            let base = root.appendingPathComponent(directory, isDirectory: true)
            let source = "intro\n![imagem](../attachments/image.png)\n[arquivo](../attachments/file.pdf)"
            let storage = NSTextStorage(string: source)
            var requested: URL?
            MarkdownHighlighter.apply(to: storage, baseURL: base) { url in
                requested = url
                return NSImage(contentsOf: url)
            }
            check(requested?.standardizedFileURL == imageURL.standardizedFileURL, "imagem relativa não resolve contra \(directory)")
            check(storage.attribute(MarkdownHighlighter.imageKey, at: 6, effectiveRange: nil) is NSImage,
                  "imagem não foi renderizada fora da linha do cursor")
            let label = (source as NSString).range(of: "arquivo").location
            let target = storage.attribute(.link, at: label, effectiveRange: nil) as? URL
            check(target?.standardizedFileURL == attachments.appendingPathComponent("file.pdf"), "link relativo não resolve contra \(directory)")
            MarkdownHighlighter.apply(to: storage, selection: NSRange(location: 10, length: 0), baseURL: base) { NSImage(contentsOf: $0) }
            check(storage.attribute(MarkdownHighlighter.imageKey, at: 6, effectiveRange: nil) == nil, "imagem deve revelar markdown na linha ativa")
            check(storage.string == source, "renderização de imagem substituiu os caracteres markdown")
        }
    } catch { check(false, "fixture local de imagem falhou: \(error)") }
} else if mode == "large" {
    let source = (0..<5000).map { "# Linha \($0) **texto**" }.joined(separator: "\n")
    let storage = NSTextStorage(string: source)
    MarkdownHighlighter.apply(to: storage)
    let sentinel = NSAttributedString.Key("RuleTestSentinel")
    storage.addAttribute(sentinel, value: true, range: NSRange(location: 0, length: 1))
    let last = (source as NSString).range(of: "# Linha 4999").location
    let range = MarkdownHighlighter.activeRange(in: storage, selection: NSRange(location: last, length: 0))
    check(range.length < 100, "digitação comum precisa limitar renderização à linha/bloco editado")
    for _ in 0..<100 {
        MarkdownHighlighter.apply(to: storage, selection: NSRange(location: last, length: 0), range: range)
    }
    check(storage.attribute(sentinel, at: 0, effectiveRange: nil) as? Bool == true, "renderização local alterou o início do documento de 5000 linhas")
    check(storage.string == source, "renderização local alterou os caracteres")
} else if mode == "undo" || mode == "prompt" {
    undo.beginUndoGrouping()
    view.insertText("**a**\n# t", replacementRange: NSRange(location: 0, length: 0))
    undo.endUndoGrouping()
    pump()
    check(value == "**a**\n# t" && view.string == value, "digitação não preserva o binding")
    undo.undo()
    pump()
    check(value == "" && view.string == "", "undo não restaura texto/binding")
    undo.redo()
    pump()
    check(value == "**a**\n# t", "redo não restaura texto/binding")
    check(!view.drawsBackground && !(view.enclosingScrollView?.drawsBackground ?? true), "editor precisa herdar fundo da janela")
    let secondUndo = UndoManager()
    check(secondUndo !== undo && !secondUndo.canUndo, "histórias de documentos devem ser isoladas")
    if mode == "prompt" {
        view.setSelectedRange(NSRange(location: 8, length: 0))
        pump()
        check(view.textStorage!.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == .textColor,
              "editor de prompts passou a ocultar sintaxe")
    } else {
        undo.beginUndoGrouping()
        view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
        (view as! AttachmentTextView).insertBlock("![foto](../attachments/foto.png)")
        undo.endUndoGrouping()
        pump()
        check(value == "**a**\n# t\n![foto](../attachments/foto.png)", "anexo não foi inserido como markdown")
        undo.undo()
        pump()
        check(value == "**a**\n# t", "undo do anexo não restaura markdown")
        let attachmentView = view as! AttachmentTextView
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let files = [URL(fileURLWithPath: "/tmp/anexo.pdf")]
        check(board.writeObjects(files.map { $0 as NSURL }), "serviço de pasteboard indisponível: não é possível verificar colagem neste ambiente")
        var imported: [URL] = []
        attachmentView.importFiles = { urls in imported = urls; return ["[anexo](../attachments/anexo.pdf)"] }
        undo.beginUndoGrouping()
        view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
        check(attachmentView.pasteContents(of: board), "paste de arquivo não foi tratado")
        undo.endUndoGrouping()
        pump()
        check(imported == files && value.hasSuffix("[anexo](../attachments/anexo.pdf)"), "paste de arquivo não importou/inseriu markdown")
        undo.undo()
        pump()
        check(value == "**a**\n# t", "paste de arquivo não é desfazível")
        board.clearContents()
        let png = Data([1, 2, 3])
        check(board.setData(png, forType: .png), "serviço de pasteboard indisponível para fixture de imagem")
        var importedImage: Data?
        attachmentView.importImage = { data in importedImage = data; return "![foto](../attachments/foto.png)" }
        undo.beginUndoGrouping()
        view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
        check(attachmentView.pasteContents(of: board), "paste de imagem não foi tratado")
        undo.endUndoGrouping()
        pump()
        check(importedImage == png && value.hasSuffix("![foto](../attachments/foto.png)"), "paste de imagem não importou/inseriu markdown")
        undo.undo()
        pump()
        check(value == "**a**\n# t", "paste de imagem não é desfazível")
        undo.beginUndoGrouping()
        host.rootView = MarkdownEditor(text: binding, undoManager: undo, autoFocus: false,
                                       baseURL: URL(fileURLWithPath: "/tmp/docs", isDirectory: true),
                                       insertion: MarkdownInsertion(text: "[botão](../attachments/botao.pdf)", atEnd: true))
        host.layoutSubtreeIfNeeded()
        pump()
        undo.endUndoGrouping()
        check(value.hasSuffix("[botão](../attachments/botao.pdf)"), "updateNSView não processou inserção do botão Anexar")
        undo.undo()
        pump()
        check(value == "**a**\n# t", "inserção do botão Anexar não é desfazível")
        value = "alteração externa"
        undo.beginUndoGrouping()
        host.rootView = MarkdownEditor(text: binding, undoManager: undo, autoFocus: false,
                                       baseURL: URL(fileURLWithPath: "/tmp/docs", isDirectory: true))
        host.layoutSubtreeIfNeeded()
        pump()
        undo.endUndoGrouping()
        check(view.string == "alteração externa" && value == view.string, "updateNSView não aplicou alteração externa")
        check(undo.undoActionName == "Alteração externa", "alteração externa não identificada no UndoManager")
        undo.undo()
        pump()
        check(value == "**a**\n# t" && view.string == value, "alteração externa não é desfazível")
    }
} else {
    check(false, "modo de teste desconhecido")
}
}

MainActor.assumeIsolated { main() }
