import Foundation

/// All remote data is cached with a durable last-confirmed snapshot. The difference between
/// that snapshot and the working files IS the pending journal, including durable deletions.
/// No filesystem watcher is needed to recover an edit after a crash.
public final class RemoteWorkspace: @unchecked Sendable {
    public typealias Snapshot = [String: Data]
    public struct Conflict: Identifiable, Codable, Sendable {
        public let path: String
        public let local: Data?
        public let remote: Data?
        public var id: String { path }
    }
    public protocol Transport: Sendable {
        func snapshot() throws -> Snapshot
        func replace(_ path: String, expected: Data?, with data: Data?) throws
    }
    private struct State: Codable { var destination: SSHDestination; var base: Snapshot; var conflicts: [String: Conflict]? = nil }
    public let root: URL
    public let destination: SSHDestination
    private let stateURL: URL
    private var base: Snapshot
    private let stateLock = NSRecursiveLock()
    private let syncLock = NSLock()
    private var conflictFiles: [String: Conflict] = [:]
    private static let registry = Registry()
    private final class Registry: @unchecked Sendable {
        let lock = NSLock(); var values: [String: RemoteWorkspace] = [:]
    }
    public static let filesLock = NSRecursiveLock()
    public static func open(_ destination: SSHDestination, cache: URL = SSHConnection.support.appending(path: "projects")) throws -> RemoteWorkspace {
        let folder = cache.appending(path: destination.id)
        let root = folder.appending(path: "files").resolvingSymlinksInPath().standardizedFileURL
        return try registry.lock.withLock {
            if let value = registry.values[root.path] { return value }
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let value = try RemoteWorkspace(root: root, destination: destination)
            registry.values[root.path] = value
            return value
        }
    }
    public static func existing(at root: URL) -> RemoteWorkspace? {
        let root = root.resolvingSymlinksInPath().standardizedFileURL
        return registry.lock.withLock {
            if let value = registry.values[root.standardizedFileURL.path] { return value }
            let stateURL = root.deletingLastPathComponent().appending(path: "ssh-workspace.json")
            guard root.lastPathComponent == "files", let data = try? Data(contentsOf: stateURL),
                  let state = try? VDJSON.decoder.decode(State.self, from: data),
                  let value = try? RemoteWorkspace(root: root, destination: state.destination) else { return nil }
            registry.values[root.standardizedFileURL.path] = value; return value
        }
    }
    init(root: URL, destination: SSHDestination) throws {
        self.root = root.resolvingSymlinksInPath().standardizedFileURL; self.destination = destination
        stateURL = self.root.deletingLastPathComponent().appending(path: "ssh-workspace.json")
        if FileManager.default.fileExists(atPath: stateURL.path) {
            let state = try VDJSON.decoder.decode(State.self, from: Data(contentsOf: stateURL))
            guard state.destination == destination else { throw VibeDeckError.ssh("O cache pertence a outro destino SSH.") }
            base = state.base; conflictFiles = state.conflicts ?? [:]
        } else { base = [:]; try persist() }
    }
    private func persist() throws {
        try AtomicFile.write(VDJSON.encode(State(destination: destination, base: base, conflicts: conflictFiles.isEmpty ? nil : conflictFiles)), to: stateURL)
    }
    public static func validPath(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        return !path.hasPrefix("/") && !path.contains("\0") && !parts.contains("..") && !parts.contains(".") &&
            (path == "vibedeck.json" || path == "README.md" || path == ".vibedeck/" || path.hasPrefix(".vibedeck/") || path.hasPrefix("graphify-out/"))
    }
    public static func localSnapshot(_ root: URL) throws -> Snapshot {
        let root = root.resolvingSymlinksInPath().standardizedFileURL
        return try filesLock.withLock {
            var result: Snapshot = [:]
            let fm = FileManager.default
            for path in ["vibedeck.json", "README.md"] {
                let url = root.appending(path: path)
                if fm.fileExists(atPath: url.path) { result[path] = try Data(contentsOf: url) }
            }
            func walk(_ relative: String) throws {
                let url = root.appending(path: relative)
                let info = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey])
                guard info.isSymbolicLink != true else { throw VibeDeckError.ssh("Link simbólico nos dados do projeto: \(url.lastPathComponent)") }
                if info.isDirectory == true {
                    result[relative + "/"] = Data()
                    // Enumeration errors must propagate, never masquerade as deleted files.
                    for child in try fm.contentsOfDirectory(atPath: url.path) { try walk(relative + "/" + child) }
                } else if info.isRegularFile == true { result[relative] = try Data(contentsOf: url) }
            }
            for directory in [".vibedeck", "graphify-out"] where fm.fileExists(atPath: root.appending(path: directory).path) {
                try walk(directory)
            }
            return result
        }
    }
    public var pendingCount: Int {
        guard let local = try? Self.localSnapshot(root) else { return 1 }
        return stateLock.withLock { Set(base.keys).union(local.keys).filter { base[$0] != local[$0] }.count }
    }
    public var conflicts: [Conflict] { stateLock.withLock { conflictFiles.values.sorted { $0.path < $1.path } } }
    public func requireSynchronized() throws {
        guard pendingCount == 0, conflicts.isEmpty else { throw VibeDeckError.ssh("Sincronize as alterações pendentes e resolva os conflitos antes de executar IA ou regras. O terminal SSH continua disponível.") }
    }
    public func synchronize(using transport: any Transport) throws {
        try syncLock.withLock {
            let remote = try transport.snapshot()
            guard remote.keys.allSatisfy(Self.validPath) else { throw VibeDeckError.ssh("Caminho remoto inválido.") }
            let initial = try Self.localSnapshot(root)
            let previous = stateLock.withLock { base }
            let paths = Set(previous.keys).union(initial.keys).union(remote.keys).sorted {
                // Children are deleted before parents; parents are created before children.
                let deletingA = initial[$0] == nil || (initial[$0] == previous[$0] && remote[$0] == nil), deletingB = initial[$1] == nil || (initial[$1] == previous[$1] && remote[$1] == nil)
                if deletingA != deletingB { return deletingA }
                return deletingA ? $0 > $1 : $0 < $1
            }
            for path in paths {
                let local = initial[path], server = remote[path], ancestor = previous[path]
                if local == ancestor {
                    try Self.filesLock.withLock {
                        // An edit made while downloading is retained for the next round.
                        let current = try Self.localSnapshot(root)[path]
                        guard current == local else { return }
                        if current != server { try apply(server, path: path) }
                        try stateLock.withLock { base[path] = server; conflictFiles[path] = nil; try persist() }
                    }
                } else if local == server {
                    try stateLock.withLock { base[path] = server; conflictFiles[path] = nil; try persist() }
                } else if server == ancestor || (server == nil && local != nil) {
                    // A previous conflict remains blocked until an explicit choice, even if the
                    // server is subsequently deleted or changed back to the original base.
                    guard stateLock.withLock({ conflictFiles[path] == nil }) else { continue }
                    try transport.replace(path, expected: server, with: local)
                    // Only acknowledge this exact sent revision, never a newer concurrent edit.
                    try stateLock.withLock { base[path] = local; try persist() }
                } else {
                    try stateLock.withLock { conflictFiles[path] = Conflict(path: path, local: local, remote: server); try persist() }
                }
            }
        }
    }
    public func resolve(_ path: String, keepLocal: Bool, using transport: any Transport) throws {
        try syncLock.withLock {
            guard let conflict = stateLock.withLock({ conflictFiles[path] }) else { return }
            let latest = try transport.snapshot()[path]
            guard latest == conflict.remote else { throw VibeDeckError.ssh("A versão remota mudou novamente. Reconecte para revisar o conflito atualizado.") }
            let current = try Self.localSnapshot(root)[path]
            guard current == conflict.local else { throw VibeDeckError.ssh("A versão local mudou. Reconecte para revisar o conflito atualizado.") }
            if keepLocal {
                try transport.replace(path, expected: latest, with: current)
                try stateLock.withLock { base[path] = current; conflictFiles[path] = nil; try persist() }
            } else {
                try Self.filesLock.withLock {
                    guard try Self.localSnapshot(root)[path] == conflict.local else { throw VibeDeckError.ssh("A versão local mudou. Revise o conflito novamente.") }
                    try apply(latest, path: path)
                    try stateLock.withLock { base[path] = latest; conflictFiles[path] = nil; try persist() }
                }
            }
        }
    }
    private func apply(_ data: Data?, path: String) throws {
        guard Self.validPath(path) else { throw VibeDeckError.ssh("Caminho inválido.") }
        let url = root.appending(path: path)
        if let data {
            if path.hasSuffix("/") { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
            else { try AtomicFile.write(data, to: url) }
        } else if FileManager.default.fileExists(atPath: url.path) {
            if path.hasSuffix("/"), !(try FileManager.default.contentsOfDirectory(atPath: url.path)).isEmpty { return }
            try FileManager.default.removeItem(at: url)
        }
    }
}

public struct SSHFileTransport: RemoteWorkspace.Transport {
    public let connection: SSHConnection
    public init(_ destination: SSHDestination) { connection = SSHConnection(destination) }
    private func checked(_ path: String) throws -> String {
        guard RemoteWorkspace.validPath(path) else { throw VibeDeckError.ssh("Caminho remoto inválido: \(path)") }
        var prefix = "", checks = ""
        for part in path.split(separator: "/") {
            prefix += prefix.isEmpty ? String(part) : "/" + part
            checks += "test ! -L " + SSHConnection.quote(prefix) + " || exit 45; "
        }
        return checks
    }
    public func snapshot() throws -> RemoteWorkspace.Snapshot {
        var result: RemoteWorkspace.Snapshot = [:]
        let listing = try connection.run("for p in vibedeck.json README.md .vibedeck graphify-out; do if test -L \"$p\"; then exit 45; fi; if test -e \"$p\"; then find \"$p\" -type l -print0 || exit; fi; done")
        guard listing.isEmpty else { throw VibeDeckError.ssh("Links simbólicos nos dados remotos não são suportados.") }
        let payload = try connection.run("for p in vibedeck.json README.md .vibedeck graphify-out; do if test -f \"$p\"; then printf '%s\\0' \"$p\"; wc -c < \"$p\" || exit; cat \"$p\" || exit; elif test -d \"$p\"; then find \"$p\" -type f ! -name \".vibedeck-transfer-*\" -exec sh -c 'for p do printf \"%s\\0\" \"$p\"; wc -c < \"$p\" || exit; cat \"$p\" || exit; done' sh {} + || exit; fi; done")
        var offset = payload.startIndex
        while offset < payload.endIndex {
            guard let separator = payload[offset...].firstIndex(of: 0),
                  let newline = payload[payload.index(after: separator)...].firstIndex(of: 10),
                  let size = Int(String(decoding: payload[payload.index(after: separator)..<newline], as: UTF8.self).trimmingCharacters(in: .whitespaces)),
                  size >= 0 else { throw VibeDeckError.ssh("Transferência remota incompleta. Tente reconectar.") }
            let path = String(decoding: payload[offset..<separator], as: UTF8.self)
            let content = payload.index(after: newline)
            guard RemoteWorkspace.validPath(path), size <= payload.distance(from: content, to: payload.endIndex) else { throw VibeDeckError.ssh("Transferência remota inválida.") }
            let end = payload.index(content, offsetBy: size)
            result[path] = Data(payload[content..<end]); offset = end
        }
        let dirs = try connection.run("for p in .vibedeck graphify-out; do if test -d \"$p\"; then find \"$p\" -type d -print0 || exit; fi; done")
        for bytes in dirs.split(separator: 0) { result[String(decoding: bytes, as: UTF8.self) + "/"] = Data() }
        return result
    }
    public func replace(_ path: String, expected: Data?, with data: Data?) throws {
        let check = try checked(path), quoted = SSHConnection.quote(path)
        if path.hasSuffix("/") {
            _ = try connection.run(check + (data != nil ? "mkdir -p " : "rmdir ") + quoted); return
        }
        let parent = (path as NSString).deletingLastPathComponent
        let temp = (parent.isEmpty ? "." : parent) + "/.vibedeck-transfer-" + UUID().uuidString
        let tempQuote = SSHConnection.quote(temp), baseQuote = SSHConnection.quote(temp + ".base")
        if let expected { _ = try connection.run("umask 077; " + check + "cat > " + baseQuote, input: expected) }
        defer { _ = try? connection.run("rm -f " + tempQuote + " " + baseQuote) }
        let compare = expected == nil ? "test ! -e " + quoted : "cmp -s " + quoted + " " + baseQuote
        if let data {
            _ = try connection.run("umask 077; " + check + "mkdir -p " + SSHConnection.quote(parent.isEmpty ? "." : parent) + " && cat > " + tempQuote, input: data)
            let permissions = "if test -e " + quoted + "; then mode=$(stat -c %a " + quoted + " 2>/dev/null || stat -f %Lp " + quoted + ") && chmod \"$mode\" " + tempQuote + " || exit; fi; "
            _ = try connection.run(check + permissions + compare + " && mv -f " + tempQuote + " " + quoted + " && cmp -s " + quoted + " /dev/stdin", input: data)
        } else {
            _ = try connection.run(check + compare + " && rm -f " + quoted + " && test ! -e " + quoted)
        }
    }
}

/// Small local critical sections let synchronization re-check a revision before applying downloads.
public enum ProjectFiles {
    public static func remove(_ url: URL) throws { try RemoteWorkspace.filesLock.withLock { try FileManager.default.removeItem(at: url) } }
    public static func move(_ source: URL, to target: URL) throws { try RemoteWorkspace.filesLock.withLock { try FileManager.default.moveItem(at: source, to: target) } }
}
