import Foundation
import Testing
@testable import VibeDeckApp

@Suite struct LineSplitterTests {
    @Test func joinsChunksIntoLinesAndKeepsTheRemainder() {
        let splitter = LineSplitter()
        #expect(splitter.feed(Data("{\"a\":".utf8)).isEmpty)
        let lines = splitter.feed(Data("1}\n{\"b\":2}\n{\"c\"".utf8))
        #expect(lines.map { String(decoding: $0, as: UTF8.self) } == ["{\"a\":1}", "{\"b\":2}"])
        #expect(splitter.flush().map { String(decoding: $0, as: UTF8.self) } == "{\"c\"")
        #expect(splitter.flush() == nil)
    }

    @Test func skipsEmptyLines() {
        let splitter = LineSplitter()
        #expect(splitter.feed(Data("\n\nx\n".utf8)).count == 1)
    }
}

/// Servidor MCP falso em `/bin/sh`: responde `initialize` e `tools/call` pelo id da requisição.
@Suite(.serialized) struct CoreClientTests {
    private func fakeServer() throws -> (CoreClient, URL) {
        let dir = FileManager.default.temporaryDirectory.appending(path: "fake-mcp-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let script = dir.appending(path: "fake.sh")
        let body = """
        #!/bin/sh
        while IFS= read -r line; do
          id=$(printf '%s' "$line" | sed -n 's/.*"id":\\([0-9][0-9]*\\).*/\\1/p')
          case "$line" in
            *'"method":"initialize"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{"protocolVersion":"2025-06-18","capabilities":{},"serverInfo":{"name":"fake","version":"0"},"instructions":"oi"}}\\n' "$id";;
            *'"name":"falha"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{"content":[{"type":"text","text":"deu ruim"}],"isError":true}}\\n' "$id";;
            *'"method":"tools/call"'*)
              printf '{"jsonrpc":"2.0","id":%s,"result":{"content":[{"type":"text","text":"ola"}],"isError":false}}\\n' "$id";;
          esac
        done
        """
        try body.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let invocation = CoreInvocation(executable: script, arguments: [], environment: ProcessInfo.processInfo.environment)
        return (CoreClient(location: .local(root: dir), invocationOverride: invocation), dir)
    }

    @Test func handshakeThenToolCall() async throws {
        let (client, dir) = try fakeServer()
        defer { client.close(); try? FileManager.default.removeItem(at: dir) }
        let text = try await client.callTool("qualquer", arguments: ["x": 1])
        #expect(text == "ola")
        #expect(client.serverInstructions == "oi")
    }

    @Test func toolErrorBecomesCoreError() async throws {
        let (client, dir) = try fakeServer()
        defer { client.close(); try? FileManager.default.removeItem(at: dir) }
        do {
            _ = try await client.callTool("falha")
            Issue.record("isError deveria lançar")
        } catch let error as CoreError {
            #expect(error.localizedDescription == "deu ruim")
        }
    }

    @Test func concurrentCallsAreMatchedById() async throws {
        let (client, dir) = try fakeServer()
        defer { client.close(); try? FileManager.default.removeItem(at: dir) }
        let results = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<8 { group.addTask { try await client.callTool("x") } }
            var all: [String] = []
            for try await text in group { all.append(text) }
            return all
        }
        #expect(results.count == 8 && Set(results) == ["ola"])
    }

    @Test func missingBinaryFailsClearly() async throws {
        let missing = CoreInvocation(executable: URL(fileURLWithPath: "/nao/existe/vibedeck"), arguments: [], environment: [:])
        let client = CoreClient(location: .local(root: FileManager.default.temporaryDirectory), invocationOverride: missing)
        defer { client.close() }
        do {
            try await client.connect()
            Issue.record("deveria falhar")
        } catch let error as CoreError {
            if case .launchFailed = error {} else { Issue.record("erro inesperado: \(error)") }
        }
    }
}
