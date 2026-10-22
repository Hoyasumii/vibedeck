import Foundation
import Testing
@testable import VibeDeckCore

@Suite struct CodexReadToolsTests {
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "vd-read-tools-\(UUID())")
        try FileManager.default.createDirectory(at: root.appending(path: "Sources"), withIntermediateDirectories: true)
        try "primeira\nagulha $(touch /tmp/never-execute)\nterceira\n".write(to: root.appending(path: "Sources/file.swift"), atomically: true, encoding: .utf8)
        return root
    }

    @Test func readsAndSearchesSourceWithoutCommandsOrChanges() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "Sources/file.swift")
        let original = try Data(contentsOf: file)
        let read = try CodexReadTools.execute(root: root, tool: "Read", arguments: .object([
            "path": .string("Sources/file.swift"), "offset": .number(2), "limit": .number(1)
        ]))
        #expect(read == "Sources/file.swift:2:agulha $(touch /tmp/never-execute)")
        let grep = try CodexReadTools.execute(root: root, tool: "Grep", arguments: .object([
            "pattern": .string("$(touch /tmp/never-execute)"), "glob": .string("Sources/*.swift")
        ]))
        #expect(grep == read)
        let glob = try CodexReadTools.execute(root: root, tool: "Glob", arguments: .object(["pattern": .string("**/*.swift")]))
        #expect(glob.contains("Sources/file.swift"))
        #expect(try Data(contentsOf: file) == original)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["Sources"])
    }

    @Test func existingProjectDocumentsRemainReadableAndDiscoverable() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let docs = root.appending(path: ".vibedeck/docs")
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        try "# Documento existente".write(to: docs.appending(path: "existing.md"), atomically: true, encoding: .utf8)
        let read = try CodexReadTools.execute(root: root, tool: "Read", arguments: .object([
            "path": .string(".vibedeck/docs/existing.md")
        ]))
        #expect(read.contains("# Documento existente"))
        let glob = try CodexReadTools.execute(root: root, tool: "Glob", arguments: .object([
            "pattern": .string(".vibedeck/docs/*.md")
        ]))
        #expect(glob.contains(".vibedeck/docs/existing.md"))
        let grep = try CodexReadTools.execute(root: root, tool: "Grep", arguments: .object([
            "pattern": .string("existente"), "glob": .string(".vibedeck/docs/**")
        ]))
        #expect(grep.contains(".vibedeck/docs/existing.md:1:"))
    }

    @Test func rejectsOutsideFilesSymlinksCommandsAndInvalidOffsets() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = FileManager.default.temporaryDirectory.appending(path: "outside-\(UUID())")
        try "outside".write(to: outside, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(at: root.appending(path: "escape.txt"), withDestinationURL: outside)
        for path in [outside.path, "../\(outside.lastPathComponent)", "escape.txt"] {
            let response = CodexReadTools.response(root: root, tool: "Read", arguments: .object(["path": .string(path)]))
            #expect(response["success"] == .bool(false))
        }
        for tool in ["Bash", "exec_command", "Write", "Edit"] {
            #expect(CodexReadTools.response(root: root, tool: tool, arguments: .object([:]))["success"] == .bool(false))
        }
        for offset in [-1.0, 0.0, 1.5, 1e30] {
            #expect(CodexReadTools.response(root: root, tool: "Read", arguments: .object([
                "path": .string("Sources/file.swift"), "offset": .number(offset)
            ]))["success"] == .bool(false))
        }
        #expect(try String(contentsOf: outside, encoding: .utf8) == "outside")
    }

    @Test func outputIsBoundedAndGlobCanPage() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try String(repeating: "a", count: 20_000).write(to: root.appending(path: "long.txt"), atomically: true, encoding: .utf8)
        let response = CodexReadTools.response(root: root, tool: "Read", arguments: .object(["path": .string("long.txt")]))
        #expect(response["success"] == .bool(true))
        #expect(response["contentItems"]?.array?.first?["text"]?.string?.count == 16_000)
        let first = try CodexReadTools.execute(root: root, tool: "Glob", arguments: .object([
            "pattern": .string("**"), "limit": .number(1)
        ]))
        let second = try CodexReadTools.execute(root: root, tool: "Glob", arguments: .object([
            "pattern": .string("**"), "offset": .number(2), "limit": .number(1)
        ]))
        #expect(first.split(separator: "\n").first != second.split(separator: "\n").first)
    }

    @Test @MainActor func readOnlyDisablesShellButWriteGenerationKeepsItsMode() {
        let config: JSONValue = .object(["config": .object(["mcp_servers": .object([
            "external": .object(["enabled": .bool(true)])
        ])])])
        let read = CodexReadOnly.overrides(config: config, workspaceWrites: false)
        #expect(read["features.shell_tool"] == .bool(false))
        #expect(read["features.unified_exec"] == .bool(false))
        #expect(read["mcp_servers.external.enabled"] == .bool(false))
        let write = CodexReadOnly.overrides(config: config, workspaceWrites: true)
        #expect(write["features.shell_tool"] == nil)
        #expect(write["features.unified_exec"] == nil)
        #expect(write["mcp_servers.external.enabled"] == .bool(false))
        #expect(Set(CodexReadTools.specs.array!.compactMap { $0["name"]?.string }) == ["Read", "Grep", "Glob"])
    }

    @Test @MainActor func writingJobsUseAppMCPWhileReadOnlyKeepsIntegrationsDisabled() {
        let root = URL(fileURLWithPath: "/tmp/project with spaces")
        let config: JSONValue = .object(["config": .object(["mcp_servers": .object([
            "vibedeck": .object(["command": .string("untrusted"), "enabled": .bool(false)]),
            "external": .object(["enabled": .bool(true)])
        ])])])
        let write = CodexReadOnly.overrides(config: config, workspaceWrites: true, root: root, cli: "/app/Helpers/vibedeck")
        let server = write["mcp_servers.vibedeck"]
        #expect(server?["command"] == .string("python3"))
        #expect(server?["required"] == .bool(true))
        #expect(server?["args"]?.array?.suffix(3) == [.string("mcp"), .string("--root"), .string(root.path)].suffix(3))
        #expect(server?["args"]?.array?.contains(.string("/app/Helpers/vibedeck")) == true)
        #expect(write["mcp_servers.vibedeck.enabled"] == .bool(true))
        #expect(write["mcp_servers.external.enabled"] == .bool(false))
        #expect(write["features.shell_tool"] == nil)
        #expect(write["features.unified_exec"] == nil)

        let read = CodexReadOnly.overrides(config: config, workspaceWrites: false, root: root, cli: "/app/Helpers/vibedeck")
        #expect(read["mcp_servers.vibedeck"] == nil)
        #expect(read["mcp_servers.vibedeck.enabled"] == .bool(false))
        #expect(read["mcp_servers.external.enabled"] == .bool(false))
        #expect(read["features.shell_tool"] == .bool(false))
        #expect(read["features.unified_exec"] == .bool(false))
    }

    /// Exercises the real app-server/MCP transport, without starting a model turn or spending tokens.
    @Test @MainActor func liveWritingMCPRunsRuleScriptsOutsideCommandSandboxWhenRequested() async throws {
        guard ProcessInfo.processInfo.environment["VIBEDECK_CODEX_MCP_SMOKE"] == "1" else { return }
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ProjectStore.initialize(at: root)
        var rule = Rule(text: "Script pode usar sandbox-exec")
        rule.test = RuleTest(mode: .script, command: "/usr/bin/sandbox-exec -p '(version 1)(allow default)' /usr/bin/true", ruleHash: rule.contentHash)
        _ = try store.addRule(rule, toTopic: "Validação")
        let cli = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: ".build/debug/vibedeck").path
        let rpc = CodexRPC()
        defer { rpc.stop() }
        try await rpc.start(root: root)
        let config = try await rpc.request("config/read", params: ["includeLayers": .bool(false)])
        var params = CodexProtocol.threadParameters(root: root, mode: .default)
        params["approvalPolicy"] = .string("never")
        params["ephemeral"] = .bool(true)
        params["config"] = .object(CodexReadOnly.overrides(config: config, workspaceWrites: true, root: root, cli: cli))
        let started = try await rpc.request("thread/start", params: params)
        let thread = try #require(started["thread"]?["id"]?.string)
        let result = try await rpc.request("mcpServer/tool/call", params: [
            "threadId": .string(thread), "server": .string("vibedeck"), "tool": .string("submit_rule_check"),
            "arguments": .object(["task": .string("Smoke MCP do Resolver"), "files": .array([]), "results": .array([])])
        ])
        #expect(result["isError"] != .bool(true))
        let check = try #require(store.listChecks().first)
        #expect(check.passed)
        #expect(check.results.first?.source == .script)
        #expect(check.results.first?.exitCode == 0)
    }
}
