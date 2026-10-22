import Foundation
import Testing
@testable import VibeDeckCore

@Suite struct StackPatternsAIContextTests {
    private func newStore() throws -> ProjectStore {
        let root = FileManager.default.temporaryDirectory.appending(path: "vibedeck-context-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return try ProjectStore.initialize(at: root, name: "Contexto IA")
    }

    @Test func providerPolicyAndGuidesRequireProjectContext() throws {
        for value in [".vibedeck/AGENTS.md", "vibedeck.json", "stack/patterns", "notas", ".vibedeck/rules/", "globs"] {
            #expect(AIPromptPolicy.instructions.contains(value))
            #expect(AgentsGuide.markdown.contains(value))
        }
        for value in ["Sem MCP/CLI", "sourcePattern", "topic", "rules_for", "lista vazia"] {
            #expect(AgentsGuide.referenceMarkdown.contains(value))
        }
        let arguments = ClaudeLaunch.headlessArguments(prompt: "Implementar")
        let index = try #require(arguments.firstIndex(of: "--append-system-prompt"))
        #expect(arguments[index + 1] == AIPromptPolicy.instructions)
        let store = try newStore()
        defer { try? FileManager.default.removeItem(at: store.root) }
        #expect(try String(contentsOf: store.agentsURL, encoding: .utf8) == AgentsGuide.markdown)
        #expect(try String(contentsOf: store.dataDir.appending(path: "guide.md"), encoding: .utf8) == AgentsGuide.referenceMarkdown)
    }

    @Test func fileContextPreservesNotesRulesAndScopesAndReloadsUpdates() throws {
        let store = try newStore()
        defer { try? FileManager.default.removeItem(at: store.root) }
        try store.updateProject {
            $0.stack = [StackItem(icon: "swift", name: "Swift", note: "Swift 6, concorrência estrita", author: .ai)]
        }
        let pattern = try store.addCustomPattern(
            name: "Feature folders", rules: ["Uma pasta por funcionalidade"], note: "Somente no Core",
            paths: ["Sources/Core/**"], author: .ai)
        // The same manifest and linked topic are read by CLI, MCP and file-only agents.
        let reader = ProjectStore(root: store.root)
        let project = try VDJSON.decoder.decode(Project.self, from: Data(contentsOf: reader.manifestURL))
        #expect(project.stack.first?.note == "Swift 6, concorrência estrita")
        #expect(project.patterns.first?.note == "Somente no Core")
        let topic = try #require(reader.patternTopic(pattern))
        #expect(project.patterns.first?.topic == topic.slug)
        #expect(topic.topic.sourcePattern == pattern.id)
        #expect(topic.topic.paths == ["Sources/Core/**"])
        #expect(topic.topic.description?.contains("Somente no Core") == true)
        #expect(topic.topic.rules.map(\.text) == ["Uma pasta por funcionalidade"])
        #expect(try reader.applicableTopics(files: ["Sources/Core/Nested/Order.swift"]).map(\.slug).contains(topic.slug))
        #expect(try !reader.applicableTopics(files: ["Sources/App/View.swift"]).map(\.slug).contains(topic.slug))

        try store.setPatternNote(pattern.id, "Agora em todo o projeto")
        try store.setPatternPaths(pattern.id, [])
        try store.updateProject { $0.stack[0].note = "Swift 6.2" }
        #expect(try reader.loadProject().stack.first?.note == "Swift 6.2")
        #expect(try reader.loadProject().patterns.first?.note == "Agora em todo o projeto")
        #expect(reader.patternTopic(pattern)?.topic.description?.contains("Agora em todo o projeto") == true)
        #expect(reader.patternTopic(pattern)?.topic.paths.isEmpty == true)
        #expect(try reader.applicableTopics(files: ["Sources/App/View.swift"]).map(\.slug).contains(topic.slug))
    }

    @Test func absentPatternsDoNotSuppressOtherRulesOrCreateDefaults() throws {
        let store = try newStore()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let topic = try store.createTopic(title: "Regras gerais", rules: [Rule(text: "Preserve escolhas do projeto")])
        #expect(try !String(contentsOf: store.manifestURL, encoding: .utf8).contains("\"patterns\""))
        #expect(try store.loadProject().patterns.isEmpty)
        #expect(try store.applicableTopics(files: ["Any.swift"]).map(\.slug) == [topic.slug])
        try store.updateProject { $0.patterns = [] }
        #expect(try store.loadProject().patterns.isEmpty)
        #expect(try store.listTopics().compactMap(\.topic.sourcePattern).isEmpty)
    }
}
