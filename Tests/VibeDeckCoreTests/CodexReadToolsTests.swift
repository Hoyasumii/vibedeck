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
}
