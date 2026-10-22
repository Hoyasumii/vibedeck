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

// MARK: - Idea dependencies

extension RulesTests {
    /// An approved idea with a current viable verdict, so only dependencies decide whether it can be implemented.
    private func viableIdea(_ store: ProjectStore, _ title: String) throws -> (slug: String, idea: Idea) {
        let (slug, _) = try store.createIdea(title: title)
        return try store.updateIdea(slug) { $0.rules = [Rule(text: "R")]; RuleDiscoverVerdict(viable: true).apply(to: &$0) }
    }

    @Test func dependenciesDecodeLegacyOmitEmptyAndRoundTripUnique() throws {
        let legacy = Data(#"{"id":"\#(UUID().uuidString)","title":"Antiga","status":"new","rules":[],"author":"human","createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-01T00:00:00Z"}"#.utf8)
        let old = try VDJSON.decoder.decode(Idea.self, from: legacy)
        #expect(old.dependencies.isEmpty)
        #expect(!String(decoding: try VDJSON.encode(old), as: UTF8.self).contains("dependencies"))
        var idea = Idea(title: "Nova")
        let a = UUID(), b = UUID()
        idea.dependencies = [a, b, a]
        let decoded = try VDJSON.decoder.decode(Idea.self, from: VDJSON.encode(idea))
        #expect(decoded.dependencies == [a, b])
        let store = try newStore()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let (x, _) = try viableIdea(store, "X"), (y, _) = try viableIdea(store, "Y"), (z, _) = try viableIdea(store, "Z")
        let saved = try store.setIdeaDependencies(x, [y, z, y]).idea
        #expect(try store.loadIdea(x).dependencies == saved.dependencies)
        #expect(saved.dependencies == [try store.loadIdea(y).id, try store.loadIdea(z).id])
    }

    @Test func dependencyIntegrityRejectsSelfMissingAndCyclesWithoutWriting() throws {
        let store = try newStore()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let (a, _) = try viableIdea(store, "A"), (b, _) = try viableIdea(store, "B"), (c, _) = try viableIdea(store, "C")
        let bytes = { (slug: String) in try Data(contentsOf: store.ideaURL(slug)) }
        let before = try bytes(a)
        #expect(throws: VibeDeckError.self) { try store.addIdeaDependencies(a, [a]) }
        #expect(throws: VibeDeckError.self) { try store.addIdeaDependencies(a, [UUID().uuidString]) }
        #expect(throws: VibeDeckError.self) { try store.addIdeaDependencies(a, ["nao-existe"]) }
        #expect(throws: VibeDeckError.self) { try store.addIdeaDependencies(a, [b, a]) }
        #expect(try bytes(a) == before)
        try store.addIdeaDependencies(a, [b])
        let bBefore = try bytes(b)
        #expect(throws: VibeDeckError.self) { try store.addIdeaDependencies(b, [a]) }
        #expect(try bytes(b) == bBefore)
        try store.addIdeaDependencies(b, [c])
        let cBefore = try bytes(c)
        #expect(throws: VibeDeckError.self) { try store.addIdeaDependencies(c, [a]) }
        #expect(try bytes(c) == cBefore)
    }

    @Test func onlyDoneSatisfiesAndBlockersNameEveryPendingDependency() throws {
        let store = try newStore()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let (main, _) = try viableIdea(store, "Principal")
        var refs: [String] = []
        for status in IdeaStatus.allCases {
            let (slug, _) = try store.createIdea(title: "Dep \(status.rawValue)")
            try store.updateIdea(slug) { $0.status = status }
            refs.append(slug)
        }
        let (gone, _) = try store.createIdea(title: "Apagada")
        let goneID = try store.loadIdea(gone).id
        try store.addIdeaDependencies(main, refs + [gone])
        try store.deleteIdea(gone)
        let blockers = try store.ideaDetail(main).dependencyBlockers
        #expect(blockers.map { $0.idea?.status } == [.new, .exploring, .approved, .discarded, nil])
        #expect(blockers.contains { $0.message == "Depende de \"Dep approved\" (aprovada)." })
        #expect(blockers.contains { $0.message == "Depende de \"Dep discarded\" (descartada)." })
        #expect(blockers.last?.message == "Depende de uma ideia ausente: \(goneID.uuidString).")
        do {
            _ = try store.implementableIdea(main)
            Issue.record("Implementação liberada com dependências pendentes")
        } catch let error as VibeDeckError {
            let text = error.localizedDescription
            #expect(blockers.allSatisfy { text.contains($0.message) })
            #expect(!text.contains("Dep done"))
        }
        // A stored link to a removed idea can stay while others are removed.
        try store.removeIdeaDependencies(main, [refs[0]])
        #expect(try store.loadIdea(main).dependencies.contains(goneID))
    }

    @Test func approvedIdeaWithOneOfTwoDependenciesDoneStaysBlockedUntilBoth() throws {
        let store = try newStore()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let (main, _) = try viableIdea(store, "Principal")
        let (d1, _) = try viableIdea(store, "D1"), (d2, _) = try viableIdea(store, "D2")
        try store.addIdeaDependencies(main, [d1, d2])
        try store.updateIdea(d1) { $0.status = .done }
        #expect(IdeaImplementation.isEligible(try store.loadIdea(main)))
        #expect(throws: VibeDeckError.self) { try store.implementableIdea(main) }
        #expect(try store.ideaDetail(main).dependencyBlockers.count == 1)
        #expect(throws: VibeDeckError.self) { try store.requireIdeaDependenciesMet(main) }
        try store.updateIdea(d2) { $0.status = .done }
        try store.requireIdeaDependenciesMet(main)
        #expect(try store.implementableIdea(main).slug == main)
        // Completing the last dependency only lifts the blocker: nothing is started.
        #expect(try store.listRuns().isEmpty)
        #expect(try store.listTopics().isEmpty)
    }

    @Test func dependentsAreDirectAndDerivedWithoutInverseField() throws {
        let store = try newStore()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let (a, _) = try viableIdea(store, "A"), (b, _) = try viableIdea(store, "B")
        let (c, _) = try viableIdea(store, "C"), (d, _) = try viableIdea(store, "D")
        let bBytes = try Data(contentsOf: store.ideaURL(b))
        try store.addIdeaDependencies(a, [b]); try store.addIdeaDependencies(c, [b]); try store.addIdeaDependencies(d, [a])
        #expect(Set(try store.ideaDetail(b).dependents.map(\.slug)) == [a, c])
        #expect(try Data(contentsOf: store.ideaURL(b)) == bBytes)
        try store.removeIdeaDependencies(a, [b])
        #expect(try store.ideaDetail(b).dependents.map(\.slug) == [c])
        try store.addIdeaDependencies(a, [b, c])
        try store.addIdeaDependencies(a, [store.loadIdea(c).id.uuidString])
        #expect(try store.loadIdea(a).dependencies.count == 2)
        // Removing one of three keeps the other two.
        let (e, _) = try viableIdea(store, "E")
        try store.addIdeaDependencies(e, [a, b, c])
        try store.removeIdeaDependencies(e, [b])
        #expect(try store.loadIdea(e).dependencies == [try store.loadIdea(a).id, try store.loadIdea(c).id])
        #expect(try Data(contentsOf: store.ideaURL(b)) == bBytes)
    }

    @Test func dependenciesStayOutOfTheAssessmentFingerprint() throws {
        var idea = Idea(title: "Avaliada")
        idea.rules = [Rule(text: "R")]
        RuleDiscoverVerdict(viable: true).apply(to: &idea)
        idea.dependencies = [UUID()]
        #expect(idea.implementBlocker == nil)
        #expect(IdeaImplementation.isEligible(idea))
    }

    @Test func ideaSchemaDeclaresUniqueUUIDDependencies() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "schema/v1/idea.schema.json")
        let schema = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let properties = schema?["properties"] as? [String: Any]
        let dependencies = properties?["dependencies"] as? [String: Any]
        let items = dependencies?["items"] as? [String: Any]
        #expect(dependencies?["type"] as? String == "array")
        #expect(dependencies?["uniqueItems"] as? Bool == true)
        #expect(items?["format"] as? String == "uuid")
        let pattern = try #require(items?["pattern"] as? String)
        #expect(UUID().uuidString.range(of: pattern, options: .regularExpression) != nil)
        #expect("nao-e-uuid".range(of: pattern, options: .regularExpression) == nil)
        #expect((schema?["required"] as? [String])?.contains("dependencies") == false)
    }
}
