import Foundation
import Testing
@testable import VibeDeckCore

@Suite struct ReorganizeDiscoverTests {
    typealias Action = ReorganizeDiscover.Action
    private func fixture() throws -> ProjectStore {
        try ProjectStore.initialize(at: FileManager.default.temporaryDirectory.appending(path: "reorganize-\(UUID())"))
    }
    private func proposal(_ actions: [Action], _ store: ProjectStore) throws -> ReorganizeDiscover.Proposal {
        try ReorganizeDiscover.parse(VDJSON.encode(ReorganizeDiscover.Answer(actions: actions)), store: store, fingerprint: store.reorganizeFingerprint())
    }
    @Test func allConceptsAndInvalidReferencesNeverWrite() throws {
        let store = try fixture(); defer { try? FileManager.default.removeItem(at: store.root) }
        let topic = try store.createTopic(title: "Regras")
        let doc = try store.createDoc(title: "Docs")
        let idea = try store.createIdea(title: "Ideia")
        let group = try store.createGroup(title: "Revisões")
        let refs: [(ReorganizeDiscover.Concept, String)] = [(.rules, topic.slug), (.docs, doc), (.ideas, idea.slug), (.reviews, group.slug)]
        let actions: [Action] = refs.map {
            .init(kind: .move, item: .init($0.0, $0.1), reason: "Agrupar item citado: \($0.1)", destination: "grupo")
        }
        let fingerprint = try store.reorganizeFingerprint()
        let result = try proposal(actions + [.init(kind: .move, item: .init(.docs, "inexistente"), reason: "Inválido", destination: "grupo")], store)
        #expect(result.actions.count == 4)
        #expect(result.discarded == 1)
        #expect(try store.reorganizeFingerprint() == fingerprint)
        for invalid in ["not json", "{}", "{\"actions\":null}"] {
            #expect(throws: ReorganizeError.self) { try ReorganizeDiscover.parse(Data(invalid.utf8), store: store, fingerprint: fingerprint) }
        }
        #expect(ReorganizeError.invalidJSON.localizedDescription.contains("Nenhum arquivo"))
        #expect(try store.reorganizeFingerprint() == fingerprint)
    }
    @Test func mergeUnionAndUndoPreserveRulesAndUnknownFields() throws {
        let store = try fixture(); defer { try? FileManager.default.removeItem(at: store.root) }
        let firstRule = Rule(text: "Primeira")
        var secondRule = Rule(text: "Segunda")
        secondRule.test = RuleTest(mode: .script, command: "sh .vibedeck/tests/repetido/check.sh", ruleHash: secondRule.contentHash)
        let left = try store.createTopic(title: "Mantido", description: "Primeira descrição", tags: ["a"], paths: ["Sources/**"], rules: [firstRule])
        let right = try store.createTopic(title: "Repetido", description: "Outra descrição", tags: ["b"], paths: ["Tests/**"], rules: [secondRule])
        var raw = try JSONSerialization.jsonObject(with: Data(contentsOf: store.topicURL(right.slug))) as! [String: Any]
        raw["custom"] = ["preservar": true]
        try AtomicFile.write(VDJSON.encodeObject(raw), to: store.topicURL(right.slug))
        let beforeLeft = try Data(contentsOf: store.topicURL(left.slug))
        let beforeRight = try Data(contentsOf: store.topicURL(right.slug))
        let expectedTest = try store.loadTopic(right.slug).rules.first?.test
        let action = Action(kind: .merge, item: .init(.rules, left.slug), involved: [.init(.rules, right.slug)], reason: "Mesclar ambos")
        let receipt = try store.applyReorganization(proposal([action], store), acceptance: .init(selected: [action.id]))
        let merged = try store.loadTopic(left.slug)
        #expect(Set(merged.tags) == ["a", "b"])
        #expect(Set(merged.paths) == ["Sources/**", "Tests/**"])
        #expect(Set(merged.rules.map(\.id)) == [firstRule.id, secondRule.id])
        #expect(merged.id == left.topic.id)
        #expect(merged.rules.first { $0.id == secondRule.id }?.test == expectedTest)
        let mergedRaw = try JSONSerialization.jsonObject(with: Data(contentsOf: store.topicURL(left.slug))) as! [String: Any]
        #expect((mergedRaw["custom"] as? [String: Bool])?["preservar"] == true)
        #expect(merged.description?.contains("Outra descrição") == true)
        #expect(try store.listTopics().count == 1)
        try store.restoreReorganization(receipt, forward: false)
        #expect(try Data(contentsOf: store.topicURL(left.slug)) == beforeLeft)
        #expect(try Data(contentsOf: store.topicURL(right.slug)) == beforeRight)
        try store.restoreReorganization(receipt, forward: true)
        #expect(try store.listTopics().count == 1)
    }
    @Test func conflictNeedsExplicitChoiceAndArchivesOriginalBytes() throws {
        let store = try fixture(); defer { try? FileManager.default.removeItem(at: store.root) }
        let a = try store.createDoc(title: "A", body: "Escolha A")
        let b = try store.createDoc(title: "B", body: "Escolha B")
        let original = try Data(contentsOf: store.docURL(b))
        let action = Action(kind: .conflict, item: .init(.docs, a), involved: [.init(.docs, b)], reason: "A contradiz B")
        let p = try proposal([action], store)
        let empty = try store.applyReorganization(p, acceptance: .init(selected: [action.id]))
        #expect(empty.before.isEmpty && empty.after.isEmpty)
        #expect(try store.listDocs().count == 2)
        #expect(throws: ReorganizeError.self) { try store.applyReorganization(p, acceptance: .init(selected: [action.id], conflicts: [action.id: "inexistente"])) }
        let receipt = try store.applyReorganization(p, acceptance: .init(selected: [action.id], conflicts: [action.id: action.item.key]))
        #expect(receipt.after.first { $0.key.hasPrefix(".vibedeck/archive/") }?.value == original)
        #expect(try store.listDocs().map(\.slug) == [a])
        try store.restoreReorganization(receipt, forward: false)
        #expect(try Data(contentsOf: store.docURL(b)) == original)
    }
    @Test func moveTopicPreservesReferencesPromotionsAndHistoricalChecks() throws {
        let store = try fixture(); defer { try? FileManager.default.removeItem(at: store.root) }
        let idea = try store.createIdea(title: "Promovida")
        let promoted = try store.promoteIdea(idea.slug)
        let topic = try store.loadTopic(promoted)
        let review = try store.addItem(ReviewItem(kind: "note", title: "Revisão", rules: [promoted]), toGroup: "Área")
        let checkURL = store.checksDir.appending(path: "historico.json")
        let check = Data("{\"topic\":\"\(promoted)\"}".utf8)
        try AtomicFile.write(check, to: checkURL)
        let doc = try store.createDoc(title: "Referências", body: "[Tópico](../rules/\(promoted).json)")
        let action = Action(kind: .move, item: .init(.rules, promoted), reason: "Mover tópico citado", destination: "especifico")
        let receipt = try store.applyReorganization(proposal([action], store), acceptance: .init(selected: [action.id]))
        let target = "especifico/" + promoted
        #expect(try store.resolveTopicSlug(topic.id.uuidString) == target)
        #expect(try store.loadIdea(idea.slug).promotedTopic == target)
        #expect(try store.findItem(review.item.id.uuidString).group.items.first?.rules == [target])
        #expect(try store.readDoc(doc).contains("../rules/\(target).json"))
        #expect(try Data(contentsOf: checkURL) == check)
        #expect(try store.listTopics().map(\.slug) == [target])
        try store.restoreReorganization(receipt, forward: false)
        #expect(try store.loadIdea(idea.slug).promotedTopic == promoted)
    }
    @Test func docMoveRebasesIncomingAndOutgoingLinksWithoutChangingProse() throws {
        let store = try fixture(); defer { try? FileManager.default.removeItem(at: store.root) }
        let a = try store.createDoc(title: "A", body: "[B](b.md)\nProsa: b.md")
        _ = try store.createDoc(title: "B", body: "[A](a.md#secao)")
        let action = Action(kind: .move, item: .init(.docs, a), reason: "Mover A", destination: "grupo")
        _ = try store.applyReorganization(proposal([action], store), acceptance: .init(selected: [action.id]))
        #expect(try store.readDoc("grupo/a").contains("[B](../b.md)"))
        #expect(try store.readDoc("grupo/a").contains("Prosa: b.md"))
        #expect(try store.readDoc("b").contains("[A](grupo/a.md#secao)"))
    }
    @Test func protectedAndIncompatibleItemsRejectWholeBatch() throws {
        let store = try fixture(); defer { try? FileManager.default.removeItem(at: store.root) }
        let idea = try store.createIdea(title: "Promovida")
        _ = try store.promoteIdea(idea.slug)
        let other = try store.createIdea(title: "Outra")
        let action = Action(kind: .merge, item: .init(.ideas, other.slug), involved: [.init(.ideas, idea.slug)], reason: "Inválida")
        let create = Action(kind: .flow, item: .init(.ideas, other.slug), reason: "Fluxo", title: "Melhoria", content: "Corpo")
        let p = try proposal([create, action], store)
        #expect(throws: ReorganizeError.self) { try store.applyReorganization(p, acceptance: .init(selected: p.actions.map(\.id))) }
        #expect(try store.reorganizeFingerprint() == p.fingerprint)
        var closed = ReviewItem(kind: "note", title: "Encerrada")
        closed.status = .done
        let group = try store.addItem(closed, toGroup: "Revisões")
        let open = try store.addItem(ReviewItem(kind: "note", title: "Aberta"), toGroup: group.slug)
        let conflict = Action(kind: .conflict, item: .init(.reviews, group.slug, itemID: closed.id.uuidString),
            involved: [.init(.reviews, group.slug, itemID: open.item.id.uuidString)], reason: "Contradição")
        let cp = try proposal([conflict], store)
        #expect(throws: ReorganizeError.self) { try store.applyReorganization(cp, acceptance: .init(selected: [conflict.id], conflicts: [conflict.id: conflict.involved[0].key])) }
        #expect(try store.findItem(closed.id.uuidString).group.items.first?.status == .done)
    }
    @Test func blockersAllowExplicitAcceptanceOfRemainingActionsWithoutPreflightWrites() throws {
        let store = try fixture(); defer { try? FileManager.default.removeItem(at: store.root) }
        let promoted = try store.createIdea(title: "Promovida")
        _ = try store.promoteIdea(promoted.slug)
        let other = try store.createIdea(title: "Outra")
        let blocked = Action(kind: .merge, item: .init(.ideas, other.slug), involved: [.init(.ideas, promoted.slug)], reason: "Mesclar")
        let flow = Action(kind: .flow, item: .init(.ideas, other.slug), reason: "Fluxo", title: "Melhoria", content: "Corpo")
        let p = try proposal([blocked, flow], store)
        let blockers = try store.reorganizationBlockers(p, acceptance: .init(selected: p.actions.map(\.id)))
        #expect(Set(blockers.keys) == [blocked.id])
        #expect(try store.reorganizeFingerprint() == p.fingerprint)
        _ = try store.applyReorganization(p, acceptance: .init(selected: p.actions.map(\.id).filter { blockers[$0] == nil }))
        #expect(try store.listIdeas().count == 3)
        #expect(try store.loadIdea(promoted.slug).promotedTopic != nil)
    }
    @Test func blockersDetectOverlappingActionsAndOccupiedDestinations() throws {
        let store = try fixture(); defer { try? FileManager.default.removeItem(at: store.root) }
        let doc = try store.createDoc(title: "Doc")
        let first = Action(kind: .move, item: .init(.docs, doc), reason: "Primeiro", destination: "grupo")
        let second = Action(kind: .move, item: .init(.docs, doc), reason: "Segundo", destination: "outro")
        let p = try proposal([first, second], store)
        #expect(Set(try store.reorganizationBlockers(p, acceptance: .init(selected: [first.id, second.id])).keys) == [second.id])
        #expect(try store.reorganizeFingerprint() == p.fingerprint)
        try FileManager.default.createDirectory(at: store.docsDir.appending(path: "ocupado"), withIntermediateDirectories: true)
        try AtomicFile.write(Data("# Existente".utf8), to: store.docURL("ocupado/doc"))
        let occupied = Action(kind: .move, item: .init(.docs, doc), reason: "Ocupado", destination: "ocupado")
        let op = try proposal([occupied], store)
        #expect(Set(try store.reorganizationBlockers(op, acceptance: .init(selected: [occupied.id])).keys) == [occupied.id])
        #expect(try store.reorganizeFingerprint() == op.fingerprint)
        _ = try store.createDoc(title: "Mudança")
        #expect(throws: ReorganizeError.self) { try store.reorganizationBlockers(op, acceptance: .init(selected: [occupied.id])) }
    }
    @Test func flowAndTopicCreationUseAIAndUniqueSlugs() throws {
        let store = try fixture(); defer { try? FileManager.default.removeItem(at: store.root) }
        let topic = try store.createTopic(title: "Tópico")
        let create = Action(kind: .create, item: .init(.rules, topic.slug), reason: "Agrupar", destination: "grupo", title: "Novo")
        let flow = Action(kind: .flow, item: .init(.rules, topic.slug), reason: "Melhorar", title: "Fluxo", content: "Melhoria proposta")
        for _ in 0..<2 {
            let p = try proposal([create, flow], store)
            _ = try store.applyReorganization(p, acceptance: .init(selected: p.actions.map(\.id)))
        }
        let topics = try store.listTopics().filter { $0.slug.hasPrefix("grupo/") }
        #expect(topics.count == 2)
        #expect(topics.allSatisfy { $0.topic.author == .ai && $0.topic.rules.isEmpty })
        #expect(try store.listIdeas().allSatisfy { $0.idea.author == .ai && $0.idea.promotedTopic == nil })
    }
    @Test func staleCollisionTraversalAndUnsafeUndo() throws {
        let store = try fixture(); defer { try? FileManager.default.removeItem(at: store.root) }
        let doc = try store.createDoc(title: "Doc")
        let action = Action(kind: .move, item: .init(.docs, doc), reason: "Mover", destination: "grupo")
        let p = try proposal([action], store)
        try store.writeDoc(doc, "Alterado")
        #expect(throws: ReorganizeError.self) { try store.applyReorganization(p, acceptance: .init(selected: [action.id])) }
        let unsafe = Action(kind: .move, item: .init(.docs, doc), reason: "Inválido", destination: "../fora")
        #expect(try proposal([unsafe], store).actions.isEmpty)
        try store.writeDoc("grupo/" + doc, "Ocupado")
        let occupied = try proposal([action], store)
        #expect(throws: ReorganizeError.self) { try store.applyReorganization(occupied, acceptance: .init(selected: [action.id])) }
        #expect(try String(contentsOf: store.docURL(doc), encoding: .utf8) == "Alterado")
        try store.deleteDoc("grupo/" + doc)
        let receipt = try store.applyReorganization(proposal([action], store), acceptance: .init(selected: [action.id]))
        try store.writeDoc("grupo/" + doc, "Edição posterior")
        #expect(throws: ReorganizeError.self) { try store.restoreReorganization(receipt, forward: false) }
        #expect(try store.readDoc("grupo/" + doc) == "Edição posterior")
    }
    @Test func leasePreventsConcurrentAnalysisWithoutWriting() async throws {
        let store = try fixture(); defer { try? FileManager.default.removeItem(at: store.root) }
        let fingerprint = try store.reorganizeFingerprint()
        let lease = try await ReorganizeLease.shared.acquire(store.root)
        do { _ = try await ReorganizeLease.shared.acquire(store.root); Issue.record("Concurrent lease accepted") }
        catch { #expect(error is ReorganizeError) }
        await ReorganizeLease.shared.release(lease)
        let next = try await ReorganizeLease.shared.acquire(store.root)
        await ReorganizeLease.shared.release(next)
        #expect(try store.reorganizeFingerprint() == fingerprint)
        #expect(try JSONDecoder().decode(JSONValue.self, from: Data(ReorganizeDiscover.schema.utf8))["properties"] != nil)
        #expect(ReviewDiscover.tools == ["Read", "Grep", "Glob"])
    }
}
