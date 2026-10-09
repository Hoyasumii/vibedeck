import Foundation
import Testing
@testable import VibeDeckCore

@Suite struct DocGenerateTests {
    @Test func strictJSONAndEmptyDocuments() throws {
        for text in ["not JSON", "{}", #"{"documents":null}"#, #"{"documents":[{"title":"A"}]}"#] {
            #expect(throws: VibeDeckError.docGenerationInvalidAnswer) { try DocGenerate.parse(Data(text.utf8)) }
        }
        let proposal = try DocGenerate.parse(Data(#"{"documents":[{"title":" ","content":"x"},{"title":"x","content":"\n "},{"title":" Rodar ","content":" Conteúdo "}]}"#.utf8))
        #expect(proposal.count == 1)
        #expect(proposal.first?.title == "Rodar")
        #expect(proposal.first?.content == "Conteúdo")
        #expect(try DocGenerate.parse(Data(#"{"documents":[]}"#.utf8)).isEmpty)
    }

    @Test func limitsAndPrompt() throws {
        let oversized = DocGenerate.Document(title: "Grande", content: String(repeating: "x", count: 40_001))
        let valid = (0..<10).map { DocGenerate.Document(title: "Doc \($0)", content: "Sources/App.swift:1") }
        let data = try VDJSON.encode(["documents": [oversized] + valid])
        let proposal = try DocGenerate.parse(data)
        #expect(proposal.count == 8)
        #expect(proposal.map(\.title) == (0..<8).map { "Doc \($0)" })
        #expect(DocGenerate.validated([.init(title: "Limite", content: String(repeating: "x", count: 40_000))]).count == 1)
        let prompt = DocGenerate.prompt(existing: [])
        #expect(prompt.contains("arquivo:linha"))
        #expect(prompt.contains("40"))
        #expect(prompt.contains("Não altere"))
    }

    @Test func uniqueSlugsPreserveOriginalAndAuthor() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "doc-generate-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ProjectStore.initialize(at: root)
        let original = try store.createDoc(title: "Como rodar", body: "Original")
        let bytes = try Data(contentsOf: store.docURL(original))
        let first = try store.createGeneratedDoc(title: "Como rodar", body: "Primeiro")
        let second = try store.createGeneratedDoc(title: "Como rodar", body: "Segundo")
        #expect(Set([original, first, second]).count == 3)
        #expect(try Data(contentsOf: store.docURL(original)) == bytes)
        #expect(try store.readDoc(first).hasPrefix("---\nauthor: ai\n---\n# Como rodar"))
        #expect(try store.listDocs().filter { $0.title == "Como rodar" }.count == 3)
    }
}
