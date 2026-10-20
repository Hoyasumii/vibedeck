import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
#if canImport(Security)
import Security
#endif

public struct SSHDestination: Codable, Hashable, Sendable {
    public var host: String
    public var port: Int
    public var user: String
    public var alias: String?
    public var directory: String
    public init(host: String, port: Int = 22, user: String, directory: String = "/", alias: String? = nil) throws {
        guard !host.isEmpty, !host.hasPrefix("-"), !host.contains(where: { $0.isWhitespace || $0.isNewline }),
              !host.contains("\0"), !user.isEmpty, !user.contains("\0"), !user.hasPrefix("-"), (1...65535).contains(port),
              directory.hasPrefix("/"), !directory.contains("\0") else { throw VibeDeckError.ssh("Destino SSH inválido.") }
        self.host = host; self.port = port; self.user = user; self.alias = alias
        // This is a POSIX path on another machine: Foundation's standardizingPath can
        // rewrite /private/var using the Mac's filesystem, which must never happen here.
        var parts: [String] = []
        for part in directory.split(separator: "/") {
            if part == "." { continue }
            if part == ".." { if !parts.isEmpty { parts.removeLast() } }
            else { parts.append(String(part)) }
        }
        self.directory = "/" + parts.joined(separator: "/")
    }
    public var connectionID: String { Self.digest("\(host)\u{0}\(port)\u{0}\(user)") }
    public var id: String { Self.digest("\(connectionID)\u{0}\(directory)") }
    public var title: String { "\(user)@\(host):\(port)\(directory)" }
    static func digest(_ text: String) -> String { PortableSHA256.hash(Data(text.utf8)).map { String(format: "%02x", $0) }.joined() }
}

/// OpenSSH performs authentication and configuration resolution. No server-side VibeDeck is used.
public struct SSHConnection: Sendable {
    public let destination: SSHDestination
    private let supportDirectory: URL
    public init(_ destination: SSHDestination, supportDirectory: URL = SSHConnection.support) {
        self.destination = destination; self.supportDirectory = supportDirectory
    }
    private var knownHostsFile: URL { supportDirectory.appending(path: "known_hosts") }
    public static var support: URL {
        AILocalStore.machineDirectory("SSH")
    }
    public var controlPath: String { FileManager.default.temporaryDirectory.appending(path: "vd-ssh-" + String(destination.connectionID.prefix(20))).path }
    public static var knownHosts: URL { support.appending(path: "known_hosts") }
    public var arguments: [String] {
        var args = ["-p", String(destination.port), "-o", "ConnectTimeout=10", "-o", "ServerAliveInterval=15", "-o", "ServerAliveCountMax=2",
                    "-o", "StrictHostKeyChecking=yes", "-o", "UserKnownHostsFile=\"\(knownHostsFile.path)\" \"\(FileManager.default.homeDirectoryForCurrentUser.appending(path: ".ssh/known_hosts").path)\"",
                    "-o", "ControlPath=\(controlPath)", "-o", "ControlMaster=auto", "-o", "ControlPersist=60"]
        if destination.alias != nil { args += ["-o", "Hostname=" + destination.host] }
        if !destination.user.isEmpty { args += ["-l", destination.user] }
        return args
    }
    public func commandArguments(_ command: String, terminal: Bool = false) -> [String] {
        arguments + (terminal ? ["-tt"] : ["-T", "-o", "BatchMode=yes"]) + ["--", destination.alias ?? destination.host, command]
    }
    public static func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    public func inDirectory(_ command: String) -> String { "cd " + Self.quote(destination.directory) + " && " + command }

    public func connect(password: String? = nil) throws {
        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var environment = ProcessInfo.processInfo.environment
        var args = arguments
        if let password, !password.isEmpty {
            // The helper contains no credentials. The password exists only in this child environment.
            let helper = supportDirectory.appending(path: "askpass.sh")
            try AtomicFile.write(Data("#!/bin/sh\nprintf '%s' \"$VIBEDECK_SSH_PASSWORD\"\n".utf8), to: helper)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
            environment["SSH_ASKPASS"] = helper.path; environment["SSH_ASKPASS_REQUIRE"] = "force"
            environment["DISPLAY"] = "vibedeck"; environment["VIBEDECK_SSH_PASSWORD"] = password
            args += ["-o", "NumberOfPasswordPrompts=1"]
        } else { args += ["-o", "BatchMode=yes"] }
        let result = try Self.capture("/usr/bin/ssh", args + ["-fN", "--", destination.alias ?? destination.host], environment: environment)
        guard result.status == 0 else {
            if result.error.contains("REMOTE HOST IDENTIFICATION HAS CHANGED") {
                throw VibeDeckError.ssh("A chave conhecida do servidor mudou. Conexão bloqueada: confirme a identidade com o administrador antes de atualizar o known_hosts.")
            }
            throw VibeDeckError.ssh("Falha na conexão SSH. \(result.error)")
        }
    }
    public func run(_ command: String, input: Data? = nil) throws -> Data {
        let result = try Self.capture("/usr/bin/ssh", commandArguments(inDirectory(command)), input: input)
        guard result.status == 0 else { throw VibeDeckError.ssh("SSH (\(result.status)): \(result.error)") }
        return result.output
    }
    public func resolved(directory: String) throws -> SSHDestination {
        let path = String(decoding: try run("cd " + Self.quote(directory) + " && pwd -P"), as: UTF8.self).trimmingCharacters(in: .newlines)
        return try SSHDestination(host: destination.host, port: destination.port, user: destination.user, directory: path, alias: destination.alias)
    }
    public func directories() throws -> [String] {
        let data = try run("find . -mindepth 1 -maxdepth 1 -type d -print0")
        return data.split(separator: 0).map { String(decoding: $0, as: UTF8.self).replacingOccurrences(of: "./", with: "", options: .anchored) }.sorted()
    }
    public static func aliases(config: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".ssh/config")) -> [String] {
        var seen = Set<String>(), aliases = Set<String>()
        func visit(_ file: URL, depth: Int) {
            guard depth < 10, seen.insert(file.path).inserted, let text = try? String(contentsOf: file, encoding: .utf8) else { return }
            for line in text.components(separatedBy: .newlines) {
                let parts = line.split(separator: "#", maxSplits: 1).first?.split(whereSeparator: { $0.isWhitespace || $0 == "=" }).map(String.init) ?? []
                guard let key = parts.first?.lowercased() else { continue }
                if key == "host" { aliases.formUnion(parts.dropFirst().filter { !$0.contains(where: { "*?!".contains($0) }) }) }
                if key == "include" {
                    for pattern in parts.dropFirst() {
                        let expanded = (pattern as NSString).expandingTildeInPath
                        let absolute = expanded.hasPrefix("/") ? expanded : file.deletingLastPathComponent().appending(path: expanded).path
                        var matches = glob_t()
                        if glob(absolute, 0, nil, &matches) == 0, let paths = matches.gl_pathv {
                            for index in 0..<Int(matches.gl_pathc) { if let path = paths[index] { visit(URL(fileURLWithPath: String(cString: path)), depth: depth + 1) } }
                        }
                        globfree(&matches)
                    }
                }
            }
        }
        visit(config, depth: 0); return aliases.sorted()
    }
    public static func configuration(alias: String) throws -> SSHDestination {
        guard !alias.hasPrefix("-"), !alias.isEmpty else { throw VibeDeckError.ssh("Alias SSH inválido.") }
        let result = try capture("/usr/bin/ssh", ["-G", "--", alias])
        guard result.status == 0 else { throw VibeDeckError.ssh(result.error) }
        var values: [String: String] = [:]
        for line in String(decoding: result.output, as: UTF8.self).split(separator: "\n") {
            let pair = line.split(separator: " ", maxSplits: 1).map(String.init)
            if pair.count == 2 { values[pair[0]] = pair[1] }
        }
        // Keep the alias as the SSH target, preserving IdentityFile, ProxyJump and other OpenSSH settings.
        return try SSHDestination(host: values["hostname"] ?? alias, port: Int(values["port"] ?? "22") ?? 22, user: values["user"] ?? NSUserName(), alias: alias)
    }
    public func unknownHostKeys() throws -> String? {
        let lookup = destination.port == 22 ? destination.host : "[\(destination.host)]:\(destination.port)"
        for file in [knownHostsFile, FileManager.default.homeDirectoryForCurrentUser.appending(path: ".ssh/known_hosts")] {
            if FileManager.default.fileExists(atPath: file.path), try Self.capture("/usr/bin/ssh-keygen", ["-F", lookup, "-f", file.path]).status == 0 { return nil }
        }
        let result = try Self.capture("/usr/bin/ssh-keyscan", ["-T", "5", "-p", String(destination.port), destination.host])
        let keys = String(decoding: result.output, as: UTF8.self)
        guard result.status == 0, !keys.isEmpty else { throw VibeDeckError.ssh("Não foi possível obter a chave do servidor. Verifique o destino e a rede.") }
        return keys
    }
    public static func fingerprints(_ keys: String) throws -> String {
        String(decoding: try capture("/usr/bin/ssh-keygen", ["-lf", "-"], input: Data(keys.utf8)).output, as: UTF8.self)
    }
    public static func trust(_ keys: String, directory: URL = support) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let file = directory.appending(path: "known_hosts")
        var contents = (try? Data(contentsOf: file)) ?? Data()
        contents.append(Data(keys.utf8)); try AtomicFile.write(contents, to: file)
    }
    public struct Result: Sendable { public let status: Int32; public let output: Data; public let error: String }
    public static func capture(_ executable: String, _ arguments: [String], input: Data? = nil, environment: [String: String]? = nil, timeout: TimeInterval = 30) throws -> Result {
        let p = Process(), stdout = Pipe(), stderr = Pipe(), stdin = Pipe()
        p.executableURL = URL(fileURLWithPath: executable); p.arguments = arguments; p.environment = environment
        p.standardOutput = stdout; p.standardError = stderr; p.standardInput = stdin
        try p.run()
        let timer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
        let errors = LockedData()
        let group = DispatchGroup(); group.enter()
        DispatchQueue.global().async { errors.set(stderr.fileHandleForReading.readDataToEndOfFile()); group.leave() }
        DispatchQueue.global().async { if let input { try? stdin.fileHandleForWriting.write(contentsOf: input) }; try? stdin.fileHandleForWriting.close() }
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit(); group.wait(); timer.cancel()
        return Result(status: p.terminationStatus, output: output, error: String(decoding: errors.get(), as: UTF8.self))
    }
    private final class LockedData: @unchecked Sendable {
        private let lock = NSLock(); private var data = Data()
        func set(_ value: Data) { lock.withLock { data = value } }
        func get() -> Data { lock.withLock { data } }
    }
}

public enum SSHCredentials {
    public static func password(for destination: SSHDestination) -> String? {
        #if canImport(Security)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "VibeDeck.SSH", kSecAttrAccount as String: destination.connectionID, kSecReturnData as String: true]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
        #else
        return nil
        #endif
    }
    public static func store(_ password: String?, for destination: SSHDestination) throws {
        #if canImport(Security)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "VibeDeck.SSH", kSecAttrAccount as String: destination.connectionID]
        let removed = SecItemDelete(query as CFDictionary)
        guard removed == errSecSuccess || removed == errSecItemNotFound else { throw VibeDeckError.ssh("Não foi possível atualizar a senha no Chaves (\(removed)).") }
        if let password {
            var add = query; add[kSecValueData as String] = Data(password.utf8)
            let status = SecItemAdd(add as CFDictionary, nil)
            guard status == errSecSuccess else { throw VibeDeckError.ssh("Não foi possível guardar a senha no Chaves (\(status)).") }
        }
        #endif
    }
}
