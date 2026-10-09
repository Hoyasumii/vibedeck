import Foundation
import Testing
@testable import VibeDeckCore

private func newStore() throws -> ProjectStore {
    let url = FileManager.default.temporaryDirectory.appending(path: "vibedeck-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return try ProjectStore.initialize(at: url)
}

@Suite struct RulesTests {
    @Test func globs() {
        #expect(Glob.matches("Sources/**/*.swift", path: "Sources/App/View.swift"))
        #expect(Glob.matches("Sources/**/*.swift", path: "Sources/View.swift"))
        #expect(!Glob.matches("Sources/**/*.swift", path: "Tests/View.swift"))
        #expect(Glob.matches("*.swift", path: "deep/nested/File.swift"))
        #expect(!Glob.matches("Sources/*.swift", path: "Sources/App/View.swift"))
        #expect(Glob.matches("worker/", path: "worker/src/index.ts"))
        #expect(Glob.matches("./src/?.ts", path: "src/a.ts"))
        #expect(!Glob.matches("src/a.ts", path: "src/aXts"))
    }

    @Test func topicsAndRules() throws {
        let store = try newStore()
        let (slug, _) = try store.createTopic(title: "Interface", paths: ["Sources/App/**"])
        #expect(slug == "interface")
        let (_, rule) = try store.addRule(Rule(text: "Sem minWidth no root"), toTopic: "interface")
        try store.addRule(Rule(text: "Textos em pt-BR", severity: .should), toTopic: "Global novo")
        #expect(Set(try store.listTopics().map(\.slug)) == ["interface", "global-novo"])

        let updated = try store.updateRule(String(rule.id.uuidString.prefix(6))) { $0.text = "Nunca minWidth no root" }
        #expect(updated.text == "Nunca minWidth no root")
        #expect(try store.loadTopic(slug).rules.first?.text == "Nunca minWidth no root")
        try store.deleteRule(rule.id.uuidString)
        #expect(try store.loadTopic(slug).rules.isEmpty)
    }

    @Test func lenientHandWrittenTopicAndIdea() throws {
        let store = try newStore()
        try store.ensureDirectories()
        try Data(#"{"title":"API","rules":[{"text":"Sempre paginar"}]}"#.utf8).write(to: store.topicURL("api"))
        try Data(#"{"title":"Modo offline"}"#.utf8).write(to: store.ideaURL("offline"))
        let topic = try store.loadTopic("api")
        #expect(topic.rules.first?.severity == .must)
        #expect(topic.isGlobal)
        let idea = try store.loadIdea("offline")
        #expect(idea.status == .new)
        #expect(idea.rules.isEmpty)
    }

    @Test func applicableTopics() throws {
        let store = try newStore()
        try store.createTopic(title: "Global")
        try store.createTopic(title: "UI", paths: ["Sources/App/**"])
        try store.createTopic(title: "Worker", paths: ["worker/"])
        #expect(try store.applicableTopics(files: []).map(\.slug) == ["global"])
        #expect(try store.applicableTopics(files: ["Sources/App/A.swift"]).map(\.slug).sorted() == ["global", "ui"])
        let absolute = store.root.appending(path: "worker/src/index.ts").path
        #expect(try store.applicableTopics(files: [absolute]).map(\.slug).sorted() == ["global", "worker"])
        #expect(try store.applicableTopics(files: [], explicit: ["UI"]).map(\.slug).sorted() == ["global", "ui"])
    }

    @Test func submitCheck() throws {
        let store = try newStore()
        let (_, must) = try store.addRule(Rule(text: "Testes passam"), toTopic: "Qualidade")
        let (_, should) = try store.addRule(Rule(text: "Docs atualizadas", severity: .should), toTopic: "Qualidade")

        #expect(throws: VibeDeckError.self) {
            try store.submitCheck(task: "x", files: [], answers: [RuleAnswer(ruleId: must.id.uuidString, verdict: .pass)], verifyManual: true)
        }
        #expect(throws: VibeDeckError.ruleNotFound("zzzz")) {
            try store.submitCheck(task: "x", files: [], answers: [RuleAnswer(ruleId: "zzzz", verdict: .pass)])
        }

        let warned = try store.submitCheck(task: "x", files: [], answers: [
            RuleAnswer(ruleId: String(must.id.uuidString.prefix(8)), verdict: .pass),
            RuleAnswer(ruleId: should.id.uuidString, verdict: .fail, note: "faltou README"),
        ])
        #expect(warned.passed)
        #expect(warned.warnings == ["Docs atualizadas"])

        let failed = try store.submitCheck(task: "y", files: [], answers: [
            RuleAnswer(ruleId: must.id.uuidString, verdict: .fail),
            RuleAnswer(ruleId: should.id.uuidString, verdict: .na),
        ])
        #expect(!failed.passed)
        #expect(failed.failures == ["Testes passam"])
        #expect(try store.listChecks().count == 2)
    }

    @Test func reviewItemGate() throws {
        let store = try newStore()
        let (_, rule) = try store.addRule(Rule(text: "Sem minWidth"), toTopic: "UI")
        try store.updateTopic("ui") { $0.paths = ["Sources/App/**"] }

        // An item without matching topics is never gated.
        let (_, free) = try store.addItem(ReviewItem(kind: "fix", title: "Livre", target: ReviewTarget(file: "README.md")), toGroup: "G")
        try store.ensureVerified(free.id.uuidString)

        let (_, item) = try store.addItem(ReviewItem(kind: "fix", title: "Sidebar", target: ReviewTarget(file: "Sources/App/Side.swift")), toGroup: "G")
        let ref = item.id.uuidString
        #expect(throws: VibeDeckError.self) { try store.ensureVerified(ref) }

        try store.submitCheck(task: "fix", files: [], reviewItem: ref, answers: [RuleAnswer(ruleId: rule.id.uuidString, verdict: .fail)])
        #expect(throws: VibeDeckError.self) { try store.ensureVerified(ref) }

        let check = try store.submitCheck(task: "fix", files: [], reviewItem: ref, answers: [RuleAnswer(ruleId: rule.id.uuidString, verdict: .pass)])
        #expect(check.reviewItem == item.id)
        #expect(check.topics == ["ui"])
        try store.ensureVerified(ref)

        // A rule added after the check requires a new one.
        try store.addRule(Rule(text: "Responsivo"), toTopic: "ui")
        #expect(throws: VibeDeckError.self) { try store.ensureVerified(ref) }

        // Explicit rules on the item gate it too.
        try store.addRule(Rule(text: "Regra de API"), toTopic: "API")
        try store.updateTopic("api") { $0.paths = ["api/**"] }
        let (_, linked) = try store.addItem(ReviewItem(kind: "fix", title: "Endpoint", rules: ["api"]), toGroup: "G")
        #expect(try store.requiredTopics(for: linked).map(\.slug) == ["api"])
        #expect(throws: VibeDeckError.self) { try store.ensureVerified(linked.id.uuidString) }
    }

    @Test func ideasAndPromotion() throws {
        let store = try newStore()
        let (slug, idea) = try store.createIdea(title: "Modo offline", body: "Cache local", tags: ["futuro"])
        try store.addRule(Rule(text: "Funciona sem rede"), toIdea: "modo offline")
        let (_, updated) = try store.updateIdea(String(idea.id.uuidString.prefix(6))) { $0.status = .exploring }
        #expect(updated.status == .exploring)
        #expect(try store.applicableTopics(files: []).isEmpty, "idea rules are not enforced")

        let topicSlug = try store.promoteIdea(slug)
        let topic = try store.loadTopic(topicSlug)
        #expect(topic.sourceIdea == idea.id)
        #expect(topic.rules.map(\.text) == ["Funciona sem rede"])
        let promoted = try store.loadIdea(slug)
        #expect(promoted.promotedTopic == topicSlug)
        #expect(promoted.status == .approved)

        // Re-promoting syncs new rules into the same topic.
        try store.addRule(Rule(text: "Sincroniza ao voltar"), toIdea: slug)
        #expect(try store.promoteIdea(slug) == topicSlug)
        #expect(try store.loadTopic(topicSlug).rules.count == 2)
        #expect(try store.listTopics().count == 1)
    }

    @Test func unpromote() throws {
        let store = try newStore()
        let (slug, _) = try store.createIdea(title: "Modo offline")
        try store.addRule(Rule(text: "Funciona sem rede"), toIdea: slug)

        // Deleting the topic through the store releases the idea.
        try store.deleteTopic(store.promoteIdea(slug))
        var idea = try store.loadIdea(slug)
        #expect(idea.promotedTopic == nil)
        #expect(idea.status == .exploring)
        #expect(idea.rules.count == 1, "draft rules stay in the idea")

        // Deleting the file by hand is picked up by releaseOrphanedIdeas (idempotent).
        let topicSlug = try store.promoteIdea(slug)
        try FileManager.default.removeItem(at: store.topicURL(topicSlug))
        #expect(try store.releaseOrphanedIdeas() == [slug])
        #expect(try store.releaseOrphanedIdeas().isEmpty)
        #expect(try store.loadIdea(slug).promotedTopic == nil)

        // unpromoteIdea deletes the topic; closed statuses are kept.
        let again = try store.promoteIdea(slug)
        try store.updateIdea(slug) { $0.status = .discarded }
        #expect(try store.unpromoteIdea(slug) == again)
        #expect(!FileManager.default.fileExists(atPath: store.topicURL(again).path))
        idea = try store.loadIdea(slug)
        #expect(idea.promotedTopic == nil)
        #expect(idea.status == .discarded)
        #expect(try store.unpromoteIdea(slug) == nil, "not promoted: no-op")
    }

    @Test func reviewItemRulesRoundTrip() throws {
        let store = try newStore()
        try store.addItem(ReviewItem(kind: "note", title: "Sem regras"), toGroup: "g")
        let raw = try String(contentsOf: store.groupURL("g"), encoding: .utf8)
        #expect(!raw.contains("\"rules\""))
        try store.addItem(ReviewItem(kind: "note", title: "Com regras", rules: ["ui"]), toGroup: "g")
        #expect(try store.loadGroup("g").items.last?.rules == ["ui"])
    }

    @Test func agentsGuideRefresh() throws {
        let store = try newStore()
        try Data("old".utf8).write(to: store.agentsURL)
        try store.refreshAgentsGuideIfNeeded()
        let guide = try String(contentsOf: store.agentsURL, encoding: .utf8)
        #expect(guide.contains("submit_rule_check"))
        #expect(guide.contains("verify_manual=true"), "projetos existentes recebem o fluxo só-script ao abrir")
    }
}
