import AppKit
import SwiftTerm

/// Native drops become pasted paths, independently of the program running in the pty.
final class ProjectTerminalView: LocalProcessTerminalView {
    var canReceiveDrop: () -> Bool = { false }
    private var clickMonitor: Any?
    private var scrollMonitor: Any?
    /// Precise (trackpad) scroll deltas left over until they add up to a whole line.
    private var pendingScrollLines: CGFloat = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        allowMouseReporting = true
        let promiseTypes = NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
        registerForDraggedTypes([.fileURL, .png, .tiff] + promiseTypes)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        clickMonitor = nil
        scrollMonitor = nil
        guard window != nil else { return }
        // SwiftTerm's mouseDown is not open for overriding. Observe only our own clicks,
        // without consuming them, so SwiftTerm still encodes the negotiated mouse protocol.
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            if let self, event.window === self.window, !self.isHiddenOrHasHiddenAncestor,
               self.visibleRect.contains(self.convert(event.locationInWindow, from: nil)) {
                self.window?.makeFirstResponder(self)
            }
            return event
        }
        // SwiftTerm's scrollWheel is not open either, and it only moves the scrollback: it never reports
        // the wheel to programs that asked for the mouse, does nothing in the alternate screen (no
        // scrollback there) and turns trackpad fractions into one line per event. Handle it here instead.
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, event.window === self.window, !self.isHiddenOrHasHiddenAncestor,
                  self.visibleRect.contains(self.convert(event.locationInWindow, from: nil)) else { return event }
            self.scroll(with: event)
            return nil
        }
    }

    deinit {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
    }

    private func scroll(with event: NSEvent) {
        let terminal = getTerminal()
        let lineHeight = max(1, bounds.height / CGFloat(max(1, terminal.rows)))
        pendingScrollLines += event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / lineHeight : event.scrollingDeltaY
        let lines = Int(pendingScrollLines.rounded(.towardZero))
        guard lines != 0 else { return }
        pendingScrollLines -= CGFloat(lines)
        let up = lines > 0
        let count = abs(lines)

        if allowMouseReporting && terminal.mouseMode != .off {
            // The program (e.g. a TUI with mouse support) scrolls its own content.
            let point = convert(event.locationInWindow, from: nil)
            let cellWidth = bounds.width / CGFloat(max(1, terminal.cols))
            let y = isFlipped ? point.y : bounds.height - point.y
            let col = max(0, min(terminal.cols - 1, Int(point.x / cellWidth)))
            let row = max(0, min(terminal.rows - 1, Int(y / lineHeight)))
            let flags = event.modifierFlags
            let button = terminal.encodeButton(
                button: up ? 4 : 5, release: false,
                shift: flags.contains(.shift), meta: flags.contains(.option), control: flags.contains(.control)
            )
            for _ in 0..<count { terminal.sendEvent(buttonFlags: button, x: col, y: row) }
        } else if terminal.isCurrentBufferAlternate {
            // Full-screen programs without mouse support (less, man…): the wheel moves like the arrow keys.
            let arrow = (terminal.applicationCursor ? "\u{1B}O" : "\u{1B}[") + (up ? "A" : "B")
            send(data: Array(String(repeating: arrow, count: count).utf8)[...])
        } else if up {
            scrollUp(lines: count)
        } else {
            scrollDown(lines: count)
        }
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        dropOperation(sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        dropOperation(sender)
    }

    private func dropOperation(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard canReceiveDrop(), sender.draggingSourceOperationMask.contains(.copy),
              TerminalDrop.supports(sender.draggingPasteboard) else { return [] }
        return .copy
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        dropOperation(sender) == .copy
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard dropOperation(sender) == .copy else { return false }
        let items = TerminalDrop.items(from: sender.draggingPasteboard)
        guard !items.isEmpty else { return false }
        window?.makeFirstResponder(self)
        Task { @MainActor [weak self] in
            await self?.receiveDrop(items)
        }
        return true
    }

    func receiveDrop(_ items: [TerminalDrop.Item], directory: URL? = nil) async {
        guard canReceiveDrop() else { return }
        do {
            let urls = try await TerminalDrop.materialize(items, directory: directory)
            // The owner may have exited or closed while a promised file was being written.
            guard canReceiveDrop() else { return }
            let bytes = try TerminalDrop.pasteBytes(urls, bracketed: getTerminal().bracketedPasteMode)
            send(data: bytes[...])
        } catch {
            guard canReceiveDrop(), let window else { return }
            let alert = NSAlert()
            alert.messageText = "Could not insert dropped files"
            alert.informativeText = error.localizedDescription
            alert.beginSheetModal(for: window, completionHandler: nil)
        }
    }
}

@MainActor
enum TerminalDrop {
    enum Item {
        case file(URL)
        case promise(NSFilePromiseReceiver)
        case image(Data)
    }

    enum ImportError: LocalizedError {
        case invalidImage, invalidPath, missingFile

        var errorDescription: String? {
            switch self {
            case .invalidImage: "The dropped image could not be read."
            case .invalidPath: "The file path contains control characters that cannot be pasted into a terminal."
            case .missingFile: "A dropped file is no longer available on this Mac."
            }
        }
    }

    static func supports(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
            || pasteboard.canReadObject(forClasses: [NSFilePromiseReceiver.self], options: nil)
            || pasteboard.availableType(from: [.png, .tiff]) != nil
    }

    static func items(from pasteboard: NSPasteboard) -> [Item] {
        // AppKit chooses the first matching representation of each item. A file's thumbnail
        // must not cause a second import, and remote URLs must not trigger a download.
        let objects = pasteboard.readObjects(
            forClasses: [NSURL.self, NSFilePromiseReceiver.self, NSPasteboardItem.self],
            options: [.urlReadingFileURLsOnly: true]
        ) ?? []
        return objects.compactMap { object in
            if let url = object as? URL, url.isFileURL { return .file(url) }
            if let promise = object as? NSFilePromiseReceiver { return .promise(promise) }
            if let item = object as? NSPasteboardItem,
               let data = item.data(forType: .png) ?? item.data(forType: .tiff) {
                return .image(data)
            }
            return nil
        }
    }

    static var attachmentDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VibeDeck/TerminalAttachments", isDirectory: true)
    }

    static func materialize(_ items: [Item], directory: URL? = nil) async throws -> [URL] {
        var urls: [URL] = []
        var promiseDestination: URL?
        for item in items {
            switch item {
            case .file(let url):
                urls.append(url)
            case .image(let data):
                guard let bitmap = NSBitmapImageRep(data: data),
                      let png = bitmap.representation(using: .png, properties: [:]) else {
                    throw ImportError.invalidImage
                }
                let destination = try makeDestination(in: directory ?? attachmentDirectory)
                let url = destination.appendingPathComponent("image.png")
                try png.write(to: url, options: .atomic)
                urls.append(url)
            case .promise(let receiver):
                let destination = try promiseDestination ?? makeDestination(in: directory ?? attachmentDirectory)
                promiseDestination = destination
                urls += try await receive(receiver, at: destination)
            }
        }
        // Validate the whole drop before inserting anything into the running program.
        for url in urls {
            guard url.isFileURL, FileManager.default.fileExists(atPath: url.path) else {
                throw ImportError.missingFile
            }
        }
        return urls
    }

    private static func makeDestination(in directory: URL) throws -> URL {
        let destination = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        return destination
    }

    private static func receive(_ receiver: NSFilePromiseReceiver, at destination: URL) async throws -> [URL] {
        try await withCheckedThrowingContinuation { continuation in
            var urls: [URL] = []
            var finished = false
            // Legacy sources can promise several files in one pasteboard item.
            receiver.receivePromisedFiles(atDestination: destination, options: [:], operationQueue: .main) { url, error in
                guard !finished else { return }
                if let error {
                    finished = true
                    continuation.resume(throwing: error)
                } else {
                    urls.append(url)
                    // fileNames is populated only after calling in the promise. Unlike
                    // fileTypes, it includes every file from legacy multi-file sources.
                    if urls.count == max(1, receiver.fileNames.count) {
                        finished = true
                        let names = receiver.fileNames
                        urls.sort { (names.firstIndex(of: $0.lastPathComponent) ?? 0) < (names.firstIndex(of: $1.lastPathComponent) ?? 0) }
                        continuation.resume(returning: urls)
                    }
                }
            }
        }
    }

    static func pasteBytes(_ urls: [URL], bracketed: Bool) throws -> [UInt8] {
        guard !urls.isEmpty else { return [] }
        let paths = try urls.map { url in
            let path = url.path
            guard url.isFileURL, !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                throw ImportError.invalidPath
            }
            return "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }
        let text = paths.joined(separator: " ") + " "
        return Array((bracketed ? "\u{1B}[200~" + text + "\u{1B}[201~" : text).utf8)
    }
}
