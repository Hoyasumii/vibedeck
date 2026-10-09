import Foundation
import Testing
@testable import VibeDeckCore

private func tempStore() throws -> ProjectStore {
    let url = FileManager.default.temporaryDirectory.appending(path: "vibedeck-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return try ProjectStore.initialize(at: url, name: "Demo")
}

@Suite struct PatternsTests {
    @Test func emptyPatternsAreOmitted() throws {
        let store = try tempStore()
        #expect(try !String(contentsOf: store.manifestURL, encoding: .utf8).contains("\"patterns\""))
        #expect(try store.loadProject().patterns.isEmpty)
    }

    @Test func catalogIdsAreUniqueAndEveryPatternHasRules() {
        let ids = PatternCatalog.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(PatternCatalog.all.allSatisfy { !$0.rules.isEmpty })
        #expect(PatternCatalog.find("Ports & Adapters")?.id == "hexagonal")
        #expect(PatternCatalog.find("domain-driven design")?.id == "ddd")
    }

    @Test func addingFromCatalogCreatesAGlobalEnforcedTopic() throws {
        let store = try tempStore()
        let added = try store.addPatterns(["tdd"], note: "Swift Testing", author: .ai)
        #expect(added.map(\.id) == ["tdd"])
        let pattern = try store.loadProject().patterns[0]
        #expect(pattern.author == .ai)
        let (slug, topic) = try #require(store.patternTopic(pattern))
        #expect(topic.sourcePattern == "tdd")
        #expect(topic.isGlobal)
        #expect(topic.rules.count == PatternCatalog.find("tdd")!.rules.count)
        #expect(topic.description?.contains("Swift Testing") == true)
        let applicable = try store.applicableTopics(files: ["Sources/Any.swift"]).map(\.slug)
        #expect(applicable.contains(slug))
    }

    @Test func pathsScopeThePatternTopic() throws {
        let store = try tempStore()
        try store.addPatterns(["hexagonal"], paths: ["Sources/Core/**"], author: .human)
        let pattern = try store.loadProject().patterns[0]
        let slug = try #require(store.patternTopic(pattern)).slug
        #expect(try store.applicableTopics(files: ["Sources/Core/Order.swift"]).map(\.slug).contains(slug))
        #expect(try !store.applicableTopics(files: ["Sources/App/View.swift"]).map(\.slug).contains(slug))

        try store.setPatternPaths("hexagonal", [])
        #expect(try store.applicableTopics(files: ["Sources/App/View.swift"]).map(\.slug).contains(slug))
    }

    @Test func addingTwiceKeepsOneTopicAndUpdatesTheNote() throws {
        let store = try tempStore()
        try store.addPatterns(["cqrs"], author: .human)
        try store.addPatterns(["CQRS"], note: "Só no módulo de pedidos", author: .human)
        let patterns = try store.loadProject().patterns
        #expect(patterns.count == 1)
        #expect(patterns[0].note == "Só no módulo de pedidos")
        #expect(try store.listTopics().filter { $0.topic.sourcePattern == "cqrs" }.count == 1)
    }

    @Test func unknownRefsRefuseEverythingWithSuggestions() throws {
        let store = try tempStore()
        #expect(throws: VibeDeckError.self) { try store.addPatterns(["tdd", "hexagon"], author: .human) }
        #expect(try store.loadProject().patterns.isEmpty)
        #expect(try store.listTopics().isEmpty)
        do {
            try store.addPatterns(["hexagon"], author: .human)
        } catch VibeDeckError.unknownPatterns(let unknown) {
            #expect(unknown["hexagon"]?.contains("hexagonal") == true)
        }
    }

    @Test func customPatternGetsOneMustRulePerLine() throws {
        let store = try tempStore()
        let pattern = try store.addCustomPattern(
            name: "Feature folders", summary: "Código agrupado por funcionalidade", rules: ["Uma pasta por feature", " ", "Sem pasta utils"],
            author: .human)
        #expect(pattern.id == "feature-folders")
        #expect(pattern.category == "custom")
        let topic = try #require(store.patternTopic(pattern)).topic
        #expect(topic.rules.map(\.text) == ["Uma pasta por feature", "Sem pasta utils"])
        #expect(topic.rules.allSatisfy { $0.severity == .must })
        // A name clashing with a catalog id gets its own id.
        #expect(try store.addCustomPattern(name: "TDD", rules: ["x"], author: .human).id == "tdd-2")
    }

    @Test func removingDeletesTheTopic() throws {
        let store = try tempStore()
        try store.addPatterns(["ddd", "repository"], author: .human)
        let removed = try store.removePatterns(["ddd"])
        #expect(removed.map(\.id) == ["ddd"])
        #expect(try store.loadProject().patterns.map(\.id) == ["repository"])
        #expect(try store.listTopics().compactMap(\.topic.sourcePattern) == ["repository"])
        #expect(throws: VibeDeckError.self) { try store.removePatterns(["nope"]) }
    }

    @Test func deletingTheTopicDropsThePattern() throws {
        let store = try tempStore()
        try store.addPatterns(["solid", "mvvm"], author: .human)
        let slug = try #require(store.patternTopic(store.loadProject().patterns[0])).slug
        try store.deleteTopic(slug)
        #expect(try store.loadProject().patterns.map(\.id) == ["mvvm"])
        #expect(try store.releaseOrphanedPatterns().isEmpty)
    }

    @Test func noteRefreshesTopicDescriptionAndMoveReorders() throws {
        let store = try tempStore()
        try store.addPatterns(["tdd", "solid"], author: .human)
        try store.setPatternNote("solid", "Protocolos no Core")
        let solid = try store.loadProject().patterns[1]
        #expect(try store.patternTopic(solid)?.topic.description?.contains("Protocolos no Core") == true)
        try store.setPatternNote("solid", nil)
        #expect(try store.loadProject().patterns[1].note == nil)
        try store.movePattern("solid", to: 0)
        #expect(try store.loadProject().patterns.map(\.id) == ["solid", "tdd"])
    }

    @Test func patternTagsRoundTripAndAreOmittedWhenEmpty() throws {
        let store = try tempStore()
        try store.addPatterns(["tdd"], author: .human)
        #expect(!String(decoding: try Data(contentsOf: store.root.appending(path: "vibedeck.json")), as: UTF8.self).contains("\"tags\""))
        try store.setPatternTags("tdd", ["qualidade", "testes"])
        #expect(try store.loadProject().patterns[0].tags == ["qualidade", "testes"])
        try store.setPatternTags("tdd", [])
        #expect(try store.loadProject().patterns[0].tags.isEmpty)
        let handWritten = try VDJSON.decoder.decode(ProjectPattern.self, from: Data(#"{"id":"x"}"#.utf8))
        #expect(handWritten.tags.isEmpty)
    }
}
