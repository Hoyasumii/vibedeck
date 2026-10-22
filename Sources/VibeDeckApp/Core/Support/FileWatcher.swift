#if canImport(CoreServices)
import CoreServices
import Foundation

/// Watches a project's vibedeck.json and .vibedeck/ tree with FSEvents and reports changed paths.
/// Changes made by the app itself are reported too; callers compare against what they wrote.
final class FileWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let root: URL
    private let handler: @Sendable ([URL]) -> Void
    private let queue = DispatchQueue(label: "vibedeck.filewatcher")

    init(root: URL, handler: @escaping @Sendable ([URL]) -> Void) {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
        self.handler = handler
    }

    deinit { stop() }

    func start() {
        guard stream == nil else { return }
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
            let cfPaths = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
            watcher.dispatch(cfPaths.prefix(count).map { URL(fileURLWithPath: $0) })
        }
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagUseCFTypes)
        guard let s = FSEventStreamCreate(
            nil, callback, &context, [root.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.25, flags
        ) else { return }
        FSEventStreamSetDispatchQueue(s, queue)
        FSEventStreamStart(s)
        stream = s
    }

    func stop() {
        guard let s = stream else { return }
        FSEventStreamStop(s)
        FSEventStreamInvalidate(s)
        FSEventStreamRelease(s)
        stream = nil
    }

    private func dispatch(_ urls: [URL]) {
        let rootPath = root.path
        let relevant = urls.filter { url in
            let p = CoreStore.canonicalURL(url).path
            return p == rootPath + "/" + CoreStore.manifestName
                || p.hasPrefix(rootPath + "/" + CoreStore.dataDirName + "/")
        }
        if !relevant.isEmpty { handler(relevant) }
    }
}
#endif
