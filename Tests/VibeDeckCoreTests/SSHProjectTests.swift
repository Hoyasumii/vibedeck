import Foundation
import Testing
@testable import VibeDeckCore

@Suite("Projetos SSH") struct SSHProjectTests {
    final class Server: RemoteWorkspace.Transport, @unchecked Sendable {
        var files: RemoteWorkspace.Snapshot
        var fail = false
        var duringWrite: (() throws -> Void)?
        init(_ files: RemoteWorkspace.Snapshot = [:]) { self.files = files }
        func snapshot() throws -> RemoteWorkspace.Snapshot {
            if fail { throw VibeDeckError.ssh("Desconectado") }; return files
        }
        func replace(_ path: String, expected: Data?, with data: Data?) throws {
            if fail { throw VibeDeckError.ssh("Transferência interrompida") }
            guard files[path] == expected else { throw VibeDeckError.ssh("Conflito") }
            try duringWrite?(); files[path] = data
        }
    }
    func bytes(_ text: String) -> Data { Data(text.utf8) }
    func setup() throws -> (RemoteWorkspace, URL) {
        let dir = FileManager.default.temporaryDirectory.appending(path: "vibedeck-ssh-tests-" + UUID().uuidString)
        let dest = try SSHDestination(host: "server.example", port: 2222, user: "tester", directory: "/projects/a")
        return (try RemoteWorkspace.open(dest, cache: dir), dir)
    }
    @Test func destinationValidationAndIsolation() throws {
        let first = try SSHDestination(host: "a", port: 2222, user: "u", directory: "/p")
        let others = [try SSHDestination(host: "b", port: 2222, user: "u", directory: "/p"),
                      try SSHDestination(host: "a", port: 22, user: "u", directory: "/p"),
                      try SSHDestination(host: "a", port: 2222, user: "v", directory: "/p"),
                      try SSHDestination(host: "a", port: 2222, user: "u", directory: "/q")]
        #expect(others.allSatisfy { $0.id != first.id })
        #expect(try SSHDestination(host: "a", user: "u", directory: "/private/var/a").directory == "/private/var/a")
        #expect(throws: VibeDeckError.self) { try SSHDestination(host: "-oProxyCommand=bad", user: "u") }
        #expect(throws: VibeDeckError.self) { try SSHDestination(host: "a", port: 0, user: "u") }
        #expect(!RemoteWorkspace.validPath(".vibedeck/../../outside"))
        #expect(!RemoteWorkspace.validPath("/vibedeck.json"))
    }
    @Test func durableEditsDeletionAndRestart() throws {
        let (workspace, dir) = try setup(); defer { try? FileManager.default.removeItem(at: dir) }
        let server = Server(["vibedeck.json": bytes("original")])
        try workspace.synchronize(using: server)
        try AtomicFile.write(bytes("offline"), to: workspace.root.appending(path: "vibedeck.json"))
        let reopened = try RemoteWorkspace(root: workspace.root, destination: workspace.destination)
        #expect(reopened.pendingCount == 1)
        server.fail = true
        #expect(throws: VibeDeckError.self) { try reopened.synchronize(using: server) }
        #expect(reopened.pendingCount == 1)
        server.fail = false; try reopened.synchronize(using: server)
        #expect(server.files["vibedeck.json"] == bytes("offline"))
        #expect(reopened.pendingCount == 0)
        try ProjectFiles.remove(workspace.root.appending(path: "vibedeck.json"))
        let again = try RemoteWorkspace(root: workspace.root, destination: workspace.destination)
        #expect(again.pendingCount == 1)
        try again.synchronize(using: server)
        #expect(server.files["vibedeck.json"] == nil)
    }
    @Test func conflictPreservesBothAcrossRestartUntilChoice() throws {
        let (workspace, dir) = try setup(); defer { try? FileManager.default.removeItem(at: dir) }
        let server = Server(["vibedeck.json": bytes("original")])
        try workspace.synchronize(using: server)
        try AtomicFile.write(bytes("local"), to: workspace.root.appending(path: "vibedeck.json"))
        server.files["vibedeck.json"] = bytes("remote")
        try workspace.synchronize(using: server)
        #expect(workspace.conflicts.first?.local == bytes("local"))
        #expect(workspace.conflicts.first?.remote == bytes("remote"))
        let reopened = try RemoteWorkspace(root: workspace.root, destination: workspace.destination)
        try reopened.synchronize(using: server)
        #expect(server.files["vibedeck.json"] == bytes("remote"))
        #expect(reopened.conflicts.count == 1)
        #expect(throws: VibeDeckError.self) { try reopened.requireSynchronized() }
        try reopened.resolve("vibedeck.json", keepLocal: true, using: server)
        #expect(server.files["vibedeck.json"] == bytes("local"))
        #expect(reopened.pendingCount == 0 && reopened.conflicts.isEmpty)
    }
    @Test func chooseRemoteAndDetectChangedConflictVersion() throws {
        let (workspace, dir) = try setup(); defer { try? FileManager.default.removeItem(at: dir) }
        let server = Server(["vibedeck.json": bytes("original")])
        try workspace.synchronize(using: server)
        try AtomicFile.write(bytes("local"), to: workspace.root.appending(path: "vibedeck.json"))
        server.files["vibedeck.json"] = bytes("remote"); try workspace.synchronize(using: server)
        server.files["vibedeck.json"] = bytes("newer")
        #expect(throws: VibeDeckError.self) { try workspace.resolve("vibedeck.json", keepLocal: false, using: server) }
        try workspace.synchronize(using: server)
        try workspace.resolve("vibedeck.json", keepLocal: false, using: server)
        #expect(try Data(contentsOf: workspace.root.appending(path: "vibedeck.json")) == bytes("newer"))
        #expect(workspace.pendingCount == 0)
    }
    @Test func recreateFileDeletedOnServer() throws {
        let (workspace, dir) = try setup(); defer { try? FileManager.default.removeItem(at: dir) }
        let server = Server(["vibedeck.json": bytes("original")])
        try workspace.synchronize(using: server)
        try AtomicFile.write(bytes("local"), to: workspace.root.appending(path: "vibedeck.json"))
        server.files.removeAll(); try workspace.synchronize(using: server)
        #expect(server.files["vibedeck.json"] == bytes("local"))
    }
    @Test func concurrentEditDuringUploadRemainsPending() throws {
        let (workspace, dir) = try setup(); defer { try? FileManager.default.removeItem(at: dir) }
        let server = Server(["vibedeck.json": bytes("original")])
        try workspace.synchronize(using: server)
        try AtomicFile.write(bytes("first"), to: workspace.root.appending(path: "vibedeck.json"))
        server.duringWrite = { try AtomicFile.write(Data("second".utf8), to: workspace.root.appending(path: "vibedeck.json")) }
        try workspace.synchronize(using: server)
        #expect(server.files["vibedeck.json"] == bytes("first"))
        #expect(workspace.pendingCount == 1)
        server.duringWrite = nil; try workspace.synchronize(using: server)
        #expect(server.files["vibedeck.json"] == bytes("second"))
    }
    @Test func failedUploadRetainsDurablePendingAndBase() throws {
        let (workspace, dir) = try setup(); defer { try? FileManager.default.removeItem(at: dir) }
        let server = Server(["vibedeck.json": bytes("original")])
        try workspace.synchronize(using: server)
        try AtomicFile.write(bytes("pending"), to: workspace.root.appending(path: "vibedeck.json"))
        server.duringWrite = { throw VibeDeckError.ssh("Connection lost") }
        #expect(throws: VibeDeckError.self) { try workspace.synchronize(using: server) }
        #expect(workspace.pendingCount == 1)
        let reopened = try RemoteWorkspace(root: workspace.root, destination: workspace.destination)
        #expect(reopened.pendingCount == 1)
        server.duringWrite = nil; try reopened.synchronize(using: server)
        #expect(server.files["vibedeck.json"] == bytes("pending"))
    }
    @Test func remoteChangesRefreshCacheAndLocalFilesStayLocal() throws {
        let (workspace, dir) = try setup(); defer { try? FileManager.default.removeItem(at: dir) }
        let server = Server(["vibedeck.json": bytes("original")])
        try workspace.synchronize(using: server)
        server.files["vibedeck.json"] = bytes("remote change"); try workspace.synchronize(using: server)
        #expect(try Data(contentsOf: workspace.root.appending(path: "vibedeck.json")) == bytes("remote change"))
        let localRoot = dir.appending(path: "local"); try FileManager.default.createDirectory(at: localRoot, withIntermediateDirectories: true)
        #expect(RemoteWorkspace.existing(at: localRoot) == nil)
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/echo"); process.arguments = ["local"]
        try RemoteExecution.configure(process, root: localRoot)
        #expect(process.executableURL?.path == "/bin/echo")
    }
    @Test func remoteLaunchNeverUsesLocalBinaryAndBlocksPending() throws {
        let (workspace, dir) = try setup(); defer { try? FileManager.default.removeItem(at: dir) }
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/Mac/only/codex"); process.arguments = ["app-server", "--stdio"]
        try RemoteExecution.configure(process, root: workspace.root, program: "codex")
        #expect(process.executableURL?.path == "/usr/bin/ssh")
        #expect(process.arguments?.joined(separator: " ").contains("/Mac/only") == false)
        #expect(process.arguments?.joined(separator: " ").contains("/projects/a") == true)
        #expect(RemoteExecution.path(for: workspace.root) == "/projects/a")
        try AtomicFile.write(bytes("pending"), to: workspace.root.appending(path: "vibedeck.json"))
        #expect(throws: VibeDeckError.self) { try RemoteExecution.configure(Process(), root: workspace.root, program: "codex") }
    }
    @Test func workflowStateSynchronizesBeforeProviderAndStillBlocksConflicts() async throws {
        let (workspace, dir) = try setup(); defer { try? FileManager.default.removeItem(at: dir) }
        let server = Server(["vibedeck.json": bytes("base")])
        try workspace.synchronize(using: server)
        try AtomicFile.write(bytes("engine checkpoint"), to: workspace.root.appending(path: "vibedeck.json"))
        try await RemoteExecution.synchronize(root: workspace.root, using: server)
        #expect(server.files["vibedeck.json"] == bytes("engine checkpoint"))
        #expect(workspace.pendingCount == 0)
        try AtomicFile.write(bytes("new local"), to: workspace.root.appending(path: "vibedeck.json"))
        server.files["vibedeck.json"] = bytes("another writer")
        await #expect(throws: VibeDeckError.self) { try await RemoteExecution.synchronize(root: workspace.root, using: server) }
        #expect(workspace.conflicts.count == 1)
        #expect(server.files["vibedeck.json"] == bytes("another writer"))
    }
    @Test func remoteLauncherFindsToolsOutsideNonInteractivePath() throws {
        let (_, dir) = try setup(); defer { try? FileManager.default.removeItem(at: dir) }
        func install(_ relative: String, _ name: String) throws {
            let folder = dir.appending(path: relative); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appending(path: name); try Data("#!/bin/sh\necho \"\(relative) $*\"\n".utf8).write(to: file)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        }
        try install(".local/bin", "vd_tool_a"); try install(".nvm/versions/node/v22.1.0/bin", "vd_tool_b")
        func run(_ shell: String, _ name: String) throws -> (Int32, String) {
            let p = Process(); p.executableURL = URL(fileURLWithPath: shell)
            p.arguments = ["-c", RemoteExecution.launcher(name, arguments: ["-p", "a b"])]
            p.environment = ["HOME": dir.path, "PATH": "/usr/bin:/bin", "SHELL": "/usr/bin/false"]
            let out = Pipe(); p.standardOutput = out; p.standardError = FileHandle.nullDevice
            try p.run(); let data = out.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
            return (p.terminationStatus, String(decoding: data, as: UTF8.self))
        }
        for shell in ["/bin/sh", "/bin/zsh"] where FileManager.default.isExecutableFile(atPath: shell) {
            #expect(try run(shell, "vd_tool_a") == (0, ".local/bin -p a b\n"))
            #expect(try run(shell, "vd_tool_b") == (0, ".nvm/versions/node/v22.1.0/bin -p a b\n"))
            #expect(try run(shell, "vibedeck_tool_absent_7139").0 == 127)
        }
    }
    @Test func sshAliasesIncludeFilesAndExcludeWildcards() throws {
        let (_, dir) = try setup(); defer { try? FileManager.default.removeItem(at: dir) }
        let config = dir.appending(path: "config"), include = dir.appending(path: "hosts.conf")
        try Data("Host child\n HostName example.org\n".utf8).write(to: include)
        try Data("Host first second *.wild !excluded\nInclude hosts.conf\n".utf8).write(to: config)
        #expect(SSHConnection.aliases(config: config) == ["child", "first", "second"])
        #expect(SSHConnection.quote("a'b") == "'a'\\''b'")
    }
    @Test func connectionArgumentsUsePortUserAliasAndStrictHostKeys() throws {
        func value(_ args: [String], after flag: String) -> String? { args.firstIndex(of: flag).map { args[$0 + 1] } }
        let manual = SSHConnection(try SSHDestination(host: "server.example", port: 2222, user: "tester", directory: "/p")).commandArguments("pwd")
        #expect(value(manual, after: "-p") == "2222" && value(manual, after: "-l") == "tester")
        #expect(manual.contains("StrictHostKeyChecking=yes") && manual.contains("BatchMode=yes"))
        #expect(Array(manual.suffix(2)) == ["server.example", "pwd"])
        let aliased = SSHConnection(try SSHDestination(host: "10.0.0.5", port: 2200, user: "deploy", directory: "/p", alias: "staging"))
        let args = aliased.commandArguments("pwd")
        #expect(Array(args.suffix(2)) == ["staging", "pwd"] && args.contains("Hostname=10.0.0.5"))
        #expect(value(args, after: "-p") == "2200" && value(args, after: "-l") == "deploy")
        let terminal = aliased.commandArguments("sh", terminal: true)
        #expect(terminal.contains("-tt") && !terminal.contains("BatchMode=yes"))
        #expect(aliased.inDirectory("pwd") == "cd '/p' && pwd")
    }
    @Test func pendingEditsAreIsolatedPerDestination() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "vibedeck-ssh-tests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = try SSHDestination(host: "a.example", port: 22, user: "u", directory: "/same")
        let b = try SSHDestination(host: "b.example", port: 22, user: "u", directory: "/same")
        let first = try RemoteWorkspace.open(a, cache: dir), second = try RemoteWorkspace.open(b, cache: dir)
        #expect(first.root != second.root)
        let serverA = Server(["vibedeck.json": bytes("A")]), serverB = Server(["vibedeck.json": bytes("B")])
        try first.synchronize(using: serverA); try second.synchronize(using: serverB)
        try AtomicFile.write(bytes("A offline"), to: first.root.appending(path: "vibedeck.json"))
        try AtomicFile.write(bytes("B offline"), to: second.root.appending(path: "vibedeck.json"))
        try first.synchronize(using: serverA)
        #expect(serverA.files["vibedeck.json"] == bytes("A offline"))
        #expect(serverB.files["vibedeck.json"] == bytes("B") && second.pendingCount == 1)
        #expect(throws: VibeDeckError.self) { try RemoteWorkspace(root: first.root, destination: b) }
    }
    @Test func projectEditsSynchronizeAndContinueOffline() throws {
        let (workspace, dir) = try setup(); defer { try? FileManager.default.removeItem(at: dir) }
        let server = Server()
        let store = try ProjectStore.initialize(at: workspace.root, name: "Remoto")
        try workspace.synchronize(using: server)
        #expect(server.files["vibedeck.json"] != nil && server.files[".vibedeck/"] != nil && workspace.pendingCount == 0)
        let slug = try store.createDoc(title: "Documento remoto"), path = ".vibedeck/docs/" + slug + ".md"
        try workspace.synchronize(using: server)
        #expect(server.files[path] != nil)
        server.fail = true
        try store.writeDoc(slug, "Edição offline")
        #expect(throws: VibeDeckError.self) { try workspace.synchronize(using: server) }
        #expect(workspace.pendingCount > 0)
        server.fail = false; try workspace.synchronize(using: server)
        #expect(String(decoding: server.files[path] ?? Data(), as: UTF8.self).contains("Edição offline"))
        try store.deleteDoc(slug); try workspace.synchronize(using: server)
        #expect(server.files[path] == nil && workspace.pendingCount == 0)
    }
    @Test func unresolvedConflictNeverOverwritesEitherVersion() throws {
        let (workspace, dir) = try setup(); defer { try? FileManager.default.removeItem(at: dir) }
        let server = Server(["vibedeck.json": bytes("original")])
        try workspace.synchronize(using: server)
        try AtomicFile.write(bytes("local"), to: workspace.root.appending(path: "vibedeck.json"))
        server.files["vibedeck.json"] = bytes("remote")
        for _ in 0..<3 { try workspace.synchronize(using: server) }
        let reopened = try RemoteWorkspace(root: workspace.root, destination: workspace.destination)
        try reopened.synchronize(using: server)
        #expect(server.files["vibedeck.json"] == bytes("remote"))
        #expect(try Data(contentsOf: workspace.root.appending(path: "vibedeck.json")) == bytes("local"))
        #expect(reopened.conflicts.map(\.path) == ["vibedeck.json"] && reopened.pendingCount == 1)
    }
    @Test func remoteProjectsUseServerProviders() throws {
        let (workspace, dir) = try setup(); defer { try? FileManager.default.removeItem(at: dir) }
        #expect(RemoteExecution.providers(root: workspace.root) == AIProvider.allCases)
        #expect(AIProvider.allCases.allSatisfy { RemoteExecution.available($0, root: workspace.root) })
        #expect(RemoteExecution.executable(.codex, root: workspace.root)?.path == "/codex")
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/Mac/only/claude")
        try RemoteExecution.configure(process, root: workspace.root, program: "claude")
        #expect(process.executableURL?.path == "/usr/bin/ssh")
        #expect(process.arguments?.last?.contains("/projects/a") == true)
        #expect(process.arguments?.joined(separator: " ").contains("/Mac/only") == false)
    }
}

@Suite("SSH real", .enabled(if: ProcessInfo.processInfo.environment["VIBEDECK_SSH_TEST_PORT"] != nil))
struct SSHIntegrationTests {
    @Test func realTransportInitializationEditingConflictsAndExecution() throws {
        let port = Int(ProcessInfo.processInfo.environment["VIBEDECK_SSH_TEST_PORT"] ?? "0") ?? 0
        let dir = FileManager.default.temporaryDirectory.appending(path: "vibedeck-real-ssh-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let remote = dir.appending(path: "server pasta ' ç")
        try FileManager.default.createDirectory(at: remote, withIntermediateDirectories: true)
        let requested = try SSHDestination(host: "127.0.0.1", port: port, user: NSUserName(), directory: remote.path)
        let destination = try SSHConnection(requested).resolved(directory: remote.path)
        let workspace = try RemoteWorkspace.open(destination, cache: dir.appending(path: "cache"))
        let transport = SSHFileTransport(destination), connection = SSHConnection(destination, supportDirectory: dir.appending(path: "ssh"))
        if let keys = try connection.unknownHostKeys() {
            #expect(try SSHConnection.fingerprints(keys).contains("SHA256:"))
            try SSHConnection.trust(keys, directory: dir.appending(path: "ssh"))
            #expect(try connection.unknownHostKeys() == nil)
        }
        try connection.connect(password: "temporary-test-only")
        let helper = try String(contentsOf: dir.appending(path: "ssh/askpass.sh"), encoding: .utf8)
        #expect(!helper.contains("temporary-test-only"))
        #expect(try transport.snapshot().isEmpty)
        // Merely browsing and declining initialization must not create anything remotely.
        #expect(!FileManager.default.fileExists(atPath: remote.appending(path: "vibedeck.json").path))
        try ProjectStore.initialize(at: workspace.root, name: "Servidor SSH")
        try workspace.synchronize(using: transport)
        #expect(workspace.pendingCount == 0)
        let independent = try SSHConnection.capture("/usr/bin/ssh", connection.commandArguments(connection.inDirectory("cat vibedeck.json")))
        #expect(independent.status == 0)
        #expect(try JSONDecoder().decode(Project.self, from: independent.output).name == "Servidor SSH")
        let store = ProjectStore(root: workspace.root)
        let slug = try store.createDoc(title: "Documento remoto")
        try store.writeDoc(slug, "Edição remota")
        try workspace.synchronize(using: transport)
        #expect(String(decoding: try connection.run("cat " + SSHConnection.quote(".vibedeck/docs/" + slug + ".md")), as: UTF8.self).contains("Edição remota"))
        let binaryPath = ".vibedeck/attachments/a '\nç.bin"
        try AtomicFile.write(Data([0, 1, 10, 255]), to: workspace.root.appending(path: binaryPath))
        try workspace.synchronize(using: transport)
        #expect(try transport.snapshot()[binaryPath] == Data([0, 1, 10, 255]))
        let command = ShellRunner.run("hostname; pwd; test -f vibedeck.json", in: workspace.root)
        #expect(command.status == 0 && command.output.contains(destination.directory))
        // A fake provider is installed ONLY in the fixture's remote bin, never invoked locally.
        let fake = remote.appending(path: "remote-provider")
        _ = try connection.run("printf '%s\\n' '#!/bin/sh' 'pwd' > remote-provider && chmod 700 remote-provider")
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/Mac/only/provider")
        try RemoteExecution.configure(p, root: workspace.root, program: fake.path)
        let output = Pipe(); p.standardOutput = output; try p.run()
        let data = output.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        #expect(p.terminationStatus == 0 && String(decoding: data, as: UTF8.self).contains(destination.directory))
        let missing = Process(); missing.executableURL = URL(fileURLWithPath: "/bin/echo")
        try RemoteExecution.configure(missing, root: workspace.root, program: "vibedeck_tool_absent_7139")
        missing.standardError = FileHandle.nullDevice; try missing.run(); missing.waitUntilExit()
        #expect(missing.terminationStatus == 127)
        // Tool reads must see code that was never copied into the data cache.
        _ = try connection.run("printf '%s' 'server-only-content' > server-only.txt")
        let answer = try CodexReadTools.execute(root: workspace.root, tool: "Read", arguments: .object(["path": .string("server-only.txt")]))
        #expect(answer.contains("server-only-content"))
        #expect(throws: VibeDeckError.self) {
            try CodexReadTools.execute(root: workspace.root, tool: "Read", arguments: .object(["path": .string("missing/server-only.txt")]))
        }
        try store.writeDoc(slug, "Local offline")
        _ = try connection.run("printf '%s' 'Outra conexão' > " + SSHConnection.quote(".vibedeck/docs/" + slug + ".md"))
        try workspace.synchronize(using: transport)
        #expect(workspace.conflicts.count == 1)
        try workspace.resolve(".vibedeck/docs/" + slug + ".md", keepLocal: true, using: transport)
        #expect(try transport.snapshot()[".vibedeck/docs/" + slug + ".md"] == Data("Local offline".utf8))
        try store.deleteDoc(slug); try workspace.synchronize(using: transport)
        #expect(try transport.snapshot()[".vibedeck/docs/" + slug + ".md"] == nil)
    }
}
