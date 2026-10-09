import AppKit
import SwiftTerm
import Testing
@testable import VibeDeckApp

@Suite(.serialized) @MainActor
struct TerminalDropTests {
    @Test func pathsRoundTripThroughShellWithoutExecutingContent() throws {
        let paths = ["/tmp/an image.png", "/tmp/João's image.png", "/tmp/$(echo unexpected);`echo no`.png"]
        let data = try TerminalDrop.pasteBytes(paths.map { URL(fileURLWithPath: $0) }, bracketed: false)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-f", "-c", "printf '%s\\0' " + String(decoding: data, as: UTF8.self)]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        let result = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        #expect(String(decoding: result, as: UTF8.self).split(separator: "\0").map(String.init) == paths)
    }

    @Test func bracketedPasteAndControlCharacters() throws {
        let url = URL(fileURLWithPath: "/tmp/image.png")
        let bytes = try TerminalDrop.pasteBytes([url], bracketed: true)
        #expect(String(decoding: bytes, as: UTF8.self) == "\u{1B}[200~'/tmp/image.png' \u{1B}[201~")
        for control in ["\n", "\r", "\t", "\u{1B}"] {
            #expect(throws: TerminalDrop.ImportError.self) {
                try TerminalDrop.pasteBytes([URL(fileURLWithPath: "/tmp/a" + control + "b")], bracketed: false)
            }
        }
        #expect(try TerminalDrop.pasteBytes([], bracketed: true).isEmpty)
    }

    @Test func pasteboardPrefersFilesOverThumbnailsAndRejectsRemoteURLs() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let file = NSPasteboardItem()
        file.setString(URL(fileURLWithPath: "/tmp/example.png").absoluteString, forType: .fileURL)
        file.setData(try imageData(), forType: .png)
        let screenshot = NSPasteboardItem()
        screenshot.setData(try imageData(), forType: .tiff)
        board.writeObjects([file, screenshot])
        #expect(TerminalDrop.supports(board))
        let items = TerminalDrop.items(from: board)
        #expect(items.count == 2)
        guard case .file(let url) = items.first else { Issue.record("Expected original file"); return }
        #expect(url.path == "/tmp/example.png")
        guard case .image = items.last else { Issue.record("Expected raw screenshot"); return }
        board.clearContents()
        board.writeObjects([NSURL(string: "https://example.com/image.png")!])
        #expect(!TerminalDrop.supports(board))
        #expect(TerminalDrop.items(from: board).isEmpty)
    }

    @Test func materializesImagesUniquelyAndKeepsOriginalFiles() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("original.txt")
        try Data("original".utf8).write(to: original)
        let image = try imageData()
        let urls = try await TerminalDrop.materialize([.file(original), .image(image), .image(image)], directory: directory)
        #expect(urls.count == 3)
        #expect(urls[0] == original)
        #expect(urls[1] != urls[2])
        for url in urls.dropFirst() {
            #expect(url.pathExtension == "png")
            #expect(NSBitmapImageRep(data: try Data(contentsOf: url)) != nil)
        }
    }

    @Test func failuresDoNotReturnInvalidPaths() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        await #expect(throws: TerminalDrop.ImportError.self) {
            try await TerminalDrop.materialize([.image(Data("invalid".utf8))], directory: directory)
        }
        await #expect(throws: TerminalDrop.ImportError.self) {
            try await TerminalDrop.materialize([.file(directory.appendingPathComponent("missing"))], directory: directory)
        }
        let blocked = directory.appendingPathComponent("file-not-directory")
        try Data().write(to: blocked)
        let image = try imageData()
        await #expect(throws: (any Error).self) {
            try await TerminalDrop.materialize([.image(image)], directory: blocked)
        }
    }

    @Test func promisesWaitForEveryFileAndPreserveOrder() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = TestFilePromise(names: ["first.png", "second.png"])
        let second = TestFilePromise(names: ["third.png"])
        let urls = try await TerminalDrop.materialize([.promise(first), .promise(second)], directory: directory)
        #expect(urls.map(\.lastPathComponent) == ["first.png", "second.png", "third.png"])
        #expect(first.destination == second.destination)
        #expect(urls.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    }

    @Test func failedPromiseThrows() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let promise = TestFilePromise(names: ["missing.png"], fails: true)
        await #expect(throws: (any Error).self) {
            try await TerminalDrop.materialize([.promise(promise)], directory: directory)
        }
    }

    @Test func terminalReceivesOnePasteAndIgnoresDropAfterExit() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let view = ProjectTerminalView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let recorder = TerminalRecorder()
        view.terminalDelegate = recorder
        view.canReceiveDrop = { true }
        view.feed(text: "\u{1B}[?2004h")
        await view.receiveDrop([.promise(TestFilePromise(names: ["image.png"]))], directory: directory)
        #expect(recorder.messages.count == 1)
        let text = String(decoding: try #require(recorder.messages.first), as: UTF8.self)
        #expect(text.hasPrefix("\u{1B}[200~'"))
        #expect(text.hasSuffix("image.png' \u{1B}[201~"))
        #expect(!text.contains("\r") && !text.contains("\n"))

        let delayed = TestFilePromise(names: ["late.png"])
        delayed.onReceive = { view.canReceiveDrop = { false } }
        await view.receiveDrop([.promise(delayed)], directory: directory)
        #expect(recorder.messages.count == 1)
    }

    @Test func mouseEventsFollowTheApplicationsNegotiatedMode() throws {
        let view = ProjectTerminalView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let recorder = TerminalRecorder()
        view.terminalDelegate = recorder
        let down = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 10, y: 10),
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        let up = try #require(NSEvent.mouseEvent(with: .leftMouseUp, location: NSPoint(x: 10, y: 10),
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 2, clickCount: 1, pressure: 0))
        view.mouseDown(with: down)
        view.mouseUp(with: up)
        #expect(recorder.messages.isEmpty)
        view.feed(text: "\u{1B}[?1000h\u{1B}[?1006h")
        view.mouseDown(with: down)
        view.mouseUp(with: up)
        #expect(recorder.messages.count == 2)
        #expect(String(decoding: recorder.messages[0], as: UTF8.self).hasPrefix("\u{1B}[<"))
        #expect(String(decoding: recorder.messages[1], as: UTF8.self).hasSuffix("m"))
        view.feed(text: "\u{1B}[?1000l\u{1B}[?1006l")
        view.mouseDown(with: down)
        view.mouseUp(with: up)
        #expect(recorder.messages.count == 2)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func imageData() throws -> Data {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.setColor(.red, atX: 0, y: 0)
        return try #require(bitmap.representation(using: .tiff, properties: [:]))
    }
}

/// Models a legacy source: one file type, several names, callbacks in reverse order.
private final class TestFilePromise: NSFilePromiseReceiver {
    let names: [String]
    let fails: Bool
    var destination: URL?
    var onReceive: (() -> Void)?
    override var fileTypes: [String] { ["public.png"] }
    override var fileNames: [String] { destination == nil ? [] : names }

    init(names: [String], fails: Bool = false) {
        self.names = names
        self.fails = fails
        super.init()
    }

    required init?(pasteboardPropertyList propertyList: Any, ofType type: NSPasteboard.PasteboardType) {
        fatalError("Not used by the test promise")
    }

    override func receivePromisedFiles(atDestination destinationDir: URL, options: [AnyHashable: Any] = [:],
        operationQueue: OperationQueue, reader: @escaping (URL, (any Error)?) -> Void) {
        destination = destinationDir
        onReceive?()
        for name in names.reversed() {
            operationQueue.addOperation { [fails] in
                let url = destinationDir.appendingPathComponent(name)
                if fails { reader(url, CocoaError(.fileWriteUnknown)); return }
                do {
                    try Data("file".utf8).write(to: url)
                    reader(url, nil)
                } catch { reader(url, error) }
            }
        }
    }
}

private final class TerminalRecorder: TerminalViewDelegate {
    var messages: [[UInt8]] = []
    func send(source: TerminalView, data: ArraySlice<UInt8>) { messages.append(Array(data)) }
    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func scrolled(source: TerminalView, position: Double) {}
    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}
    func bell(source: TerminalView) {}
    func clipboardCopy(source: TerminalView, content: Data) {}
    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}
