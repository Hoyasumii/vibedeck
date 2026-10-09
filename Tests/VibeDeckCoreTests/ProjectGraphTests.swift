import Foundation
import Testing
@testable import VibeDeckCore

@Suite struct ProjectGraphTests {
    private func data(_ value: JSONValue) throws -> Data { try VDJSON.encode(value) }
    private var value: JSONValue {
        .object(["nodes": .array([.object(["id": .string("a"), "label": .string("A"), "_origin": .string("ast")])]), "links": .array([])])
    }

    @Test func validatesAndPreservesAttributesAndGeneration() throws {
        let graph = try ProjectGraph(data: data(value))
        let addition: JSONValue = .object([
            "nodes": .array([.object(["id": .string("b"), "label": .string("Documento"), "_origin": .string("semantic")])]),
            "links": .array([.object(["source": .string("a"), "target": .string("b"), "relation": .string("documented_by"), "confidence": .string("INFERRED"), "_origin": .string("semantic")])])])
        let merged = try graph.merging(addition).generated(at: Date(timeIntervalSince1970: 100), provider: .codex)
        #expect(merged.nodes.count == 2)
        #expect(merged.nodes[0]["_origin"]?.string == "ast")
        #expect(merged.links[0]["confidence"]?.string == "INFERRED")
        #expect(merged.summary["provider"]?.string == "codex")
        #expect(merged.summary["generatedAt"]?.string == "1970-01-01T00:01:40Z")
        #expect(throws: (any Error).self) { try graph.merging(.object(["nodes": .array(graph.nodes), "links": .array([])])) }
        #expect(throws: (any Error).self) { try graph.merging(.object(["nodes": .array([]), "links": .array([.object(["source": .string("a"), "target": .string("missing")])])])) }
        #expect(throws: (any Error).self) { try ProjectGraph(data: Data("invalid".utf8)) }
        #expect(throws: (any Error).self) { try ProjectGraph(data: Data("{}".utf8)) }
    }

    @Test func offlineHTMLTreatsGraphContentAsDataAndConstrainsScripts() throws {
        var object = value.object!
        object["nodes"] = .array([.object(["id": .string("a"), "label": .string("</script><script>alert('x')</script>"), "source_file": .string("/etc/passwd")])])
        let graph = try ProjectGraph(data: data(.object(object)))
        let html = String(decoding: try GraphHTML.render(graph, root: FileManager.default.temporaryDirectory), as: UTF8.self)
        #expect(html.contains("Content-Security-Policy"))
        #expect(html.contains("default-src 'none'"))
        #expect(html.contains("script-src 'nonce-"))
        #expect(!html.contains("<script>alert("))
        #expect(html.contains("\\u003c/script\\u003e"))
        #expect(html.contains("\"vibedeck_source_available\" : false"))
        #expect(!html.contains("src=\"https:"))
        #expect(html.contains("const LIMIT = 180"))
        #expect(html.contains("Visão geral"))
        #expect(html.contains("Abrir origem no Finder"))
    }

    @Test func sourcesCannotEscapeProjectIncludingSymlinks() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "graph-source-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appending(path: "doc.md")
        try AtomicFile.write(Data("Documento".utf8), to: source)
        try FileManager.default.createSymbolicLink(at: root.appending(path: "escape"), withDestinationURL: URL(fileURLWithPath: "/etc/passwd"))
        #expect(ProjectGraph.sourceURL("doc.md", root: root) == source.resolvingSymlinksInPath())
        #expect(ProjectGraph.sourceURL("../outside", root: root) == nil)
        #expect(ProjectGraph.sourceURL("escape", root: root) == nil)
        #expect(ProjectGraph.sourceURL("missing", root: root) == nil)
        #expect(ProjectGraph.sourceURL("/etc/passwd", root: root) == nil)
    }
}
