import Foundation
import Testing
@testable import VibeDeckCore

@Suite struct ClaudeItemsTests {
    @Test func oldProjectsAndHandWrittenItems() throws {
        let old = try VDJSON.decoder.decode(Project.self, from: Data(#"{"name":"Antigo"}"#.utf8))
        #expect(old.claude.isEmpty)
        #expect(!String(decoding: try VDJSON.encode(old), as: UTF8.self).contains("\"claude\""))
        let raw = #"{"name":"Demo","claude":[{"url":"https://claude.ai/public/artifacts/example","kind":"doc"}]}"#
        let project = try VDJSON.decoder.decode(Project.self, from: Data(raw.utf8))
        #expect(project.claude.first?.title == "example")
        #expect(project.claude.first?.kind == .doc)
        #expect(project.claude.first?.tags == [])
        let encoded = try VDJSON.encode(project)
        #expect(try VDJSON.encode(VDJSON.decoder.decode(Project.self, from: encoded)) == encoded)
        // A hand-written item may omit kind; explicit unknown kinds remain invalid.
        let missing = try VDJSON.decoder.decode(ClaudeItem.self, from: Data(#"{"url":"https://claude.ai/x"}"#.utf8))
        #expect(missing.kind == .artifact)
        #expect(throws: (any Error).self) {
            try VDJSON.decoder.decode(ClaudeItem.self, from: Data(#"{"url":"https://claude.ai/x","kind":"other"}"#.utf8))
        }
    }

    @Test func validatesDomainAndPreservesUserClassification() throws {
        for url in ["https://claude.ai/public/artifacts/abc", "http://claude.ai/x", "https://CLAUDE.AI/x"] {
            #expect(ClaudeItem.accepts(url))
        }
        for url in ["https://claude.ai.evil.test/x", "https://evil.test/claude.ai", "file://claude.ai/x",
                    "https://claude.ai@evil.test/x", "https://user@claude.ai/x", "claude.ai/x", ""] {
            #expect(!ClaudeItem.accepts(url))
            #expect(throws: VibeDeckError.invalidClaudeURL) { try ClaudeItem.make(url: url, kind: .doc) }
        }
        let url = "https://claude.ai/public/artifacts/abc"
        #expect(try ClaudeItem.make(url: url, kind: .artifact).kind == .artifact)
        let doc = try ClaudeItem.make(url: " \(url)\n", kind: .doc, title: " Meu doc ", tags: ["design"])
        #expect(doc.kind == .doc)
        #expect(doc.title == "Meu doc")
        #expect(doc.url == url)
        #expect(doc.tags == ["design"])
    }

    @Test func localCollectionRoundTripAndRemoval() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "claude-items-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ProjectStore.initialize(at: root, name: "Coleção")
        let first = try store.addClaudeItem(url: "https://claude.ai/public/artifacts/a", kind: .doc, title: "Doc", tags: ["ref"])
        let second = try store.addClaudeItem(url: "https://claude.ai/public/artifacts/b", kind: .artifact, title: "Artefato")
        let loaded = try store.loadProject().claude
        #expect(loaded.map(\.id) == [first.id, second.id])
        #expect(loaded.map(\.kind) == [.doc, .artifact])
        #expect(loaded.first?.tags == ["ref"])
        #expect(abs(loaded[0].addedAt.timeIntervalSince(first.addedAt)) < 1)
        let before = try Data(contentsOf: store.manifestURL)
        #expect(throws: VibeDeckError.invalidClaudeURL) { try store.addClaudeItem(url: "https://example.com", kind: .doc) }
        #expect(try Data(contentsOf: store.manifestURL) == before)
        try store.removeClaudeItem(String(first.id.uuidString.prefix(8)))
        #expect(try store.loadProject().claude.map(\.id) == [second.id])
        #expect(throws: VibeDeckError.claudeItemNotFound("absent")) { try store.removeClaudeItem("absent") }
        try store.removeClaudeItem("Artefato")
        #expect(try store.loadProject().claude.isEmpty)
        #expect(!String(decoding: try Data(contentsOf: store.manifestURL), as: UTF8.self).contains("\"claude\""))
    }

    @Test func ambiguousRemovalDoesNotChangeManifest() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "claude-ambiguous-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ProjectStore.initialize(at: root)
        for kind in ClaudeItemKind.allCases {
            _ = try store.addClaudeItem(url: "https://claude.ai/x", kind: kind, title: "Mesmo título")
        }
        let before = try Data(contentsOf: store.manifestURL)
        #expect(throws: VibeDeckError.ambiguousClaudeItem("Mesmo título")) { try store.removeClaudeItem("Mesmo título") }
        #expect(try Data(contentsOf: store.manifestURL) == before)
    }
}
