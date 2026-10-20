import Foundation
import Testing
@testable import VibeDeckCore

private func newStore() throws -> ProjectStore {
    let url = FileManager.default.temporaryDirectory.appending(path: "vibedeck-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return try ProjectStore.initialize(at: url)
}

private func snapshot(_ store: ProjectStore) throws -> [String: Data] {
    var files: [String: Data] = [:]
    let walker = FileManager.default.enumerator(at: store.dataDir, includingPropertiesForKeys: [.isRegularFileKey])
    while let url = walker?.nextObject() as? URL {
        guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
        files[url.path] = try Data(contentsOf: url)
    }
    return files
}

@Suite struct ItemDiscoverTests {
    @Test func parsesValidAgent() throws {
        let data = Data(#"{"title":" Revisor ","summary":"Revisa PRs","model":"","tools":["Read"," "],"prompt":" Você revisa. ","tags":["a","a"," "]}"#.utf8)
        let p = try ItemDiscover.parse(.agent, data)
        #expect(p.title == "Revisor")
        #expect(p.model == nil)
        #expect(p.tools == ["Read"])
        #expect(p.prompt == "Você revisa.")
        #expect(p.tags == ["a"])
    }

    @Test func invalidJSONThrowsPortugueseErrorAndWritesNothing() throws {
        let store = try newStore()
        let before = try snapshot(store)
        #expect(throws: VibeDeckError.self) { try ItemDiscover.parse(.skill, Data("não é json".utf8)) }
        do { _ = try ItemDiscover.parse(.skill, Data("{".utf8)) } catch {
            #expect(error.localizedDescription.contains("JSON válido"))
        }
        #expect(try snapshot(store) == before)
    }

    @Test func emptyOrBlankFieldsAreRejected() {
        #expect(ItemDiscover.validated(.agent, .init(title: "   ", prompt: "x")) == nil)
        #expect(ItemDiscover.validated(.command, .init(title: "x", prompt: " \n ")) == nil)
        #expect(ItemDiscover.validated(.workflow, .init(title: "x")) == nil)
        #expect(throws: VibeDeckError.self) { try ItemDiscover.parse(.agent, Data(#"{"title":"","prompt":"x"}"#.utf8)) }
    }

    @Test func contentIsLimited() {
        let big = String(repeating: "a", count: ItemDiscover.maxContentLength + 1)
        #expect(ItemDiscover.validated(.agent, .init(title: "x", prompt: big)) == nil)
        let ok = String(repeating: "a", count: ItemDiscover.maxContentLength)
        #expect(ItemDiscover.validated(.agent, .init(title: "x", prompt: ok)) != nil)
    }

    @Test func workflowStepsAreCheckedAgainstExistingItems() throws {
        let refs = ItemDiscover.Refs(agents: ["revisor"])
        let json = #"{"title":"Fluxo","steps":[{"id":"Revisor","kind":"agent","ref":"revisor","transitions":[{"verdict":"OK","to":"revisor"},{"to":"fantasma"}]}]}"#
        let p = try ItemDiscover.parse(.workflow, Data(json.utf8), refs: refs)
        #expect(p.steps.map(\.id) == ["revisor"])
        #expect(p.steps[0].transitions.count == 1)
        #expect(throws: VibeDeckError.self) { try ItemDiscover.parse(.workflow, Data(json.utf8), refs: .init(agents: ["outro"])) }
    }

    @Test func slugCollisionNeverOverwrites() throws {
        let store = try newStore()
        let existing = try store.createAgent(title: "Revisor", prompt: "original")
        let slug = try store.createItem(.agent, .init(title: "Revisor", prompt: "novo"))
        #expect(slug != existing.slug)
        #expect(try store.loadAgent(existing.slug).prompt == "original")
        let created = try store.loadAgent(slug)
        #expect(created.prompt == "novo")
        #expect(created.author == .ai)
    }

    @Test func createsAllKindsAsAI() throws {
        let store = try newStore()
        let a = try store.createItem(.agent, .init(title: "A", prompt: "p"))
        let c = try store.createItem(.command, .init(title: "C", argumentHint: "<x>", prompt: "p"))
        let s = try store.createItem(.skill, .init(title: "S", summary: "quando", prompt: "p"))
        let w = try store.createItem(.workflow, .init(title: "W", steps: [WorkflowStep(id: "a", ref: a)]))
        #expect(try store.loadCommand(c).argumentHint == "<x>")
        #expect(try store.loadSkill(s).author == .ai)
        #expect(try store.loadWorkflow(w).steps.count == 1)
        #expect(try store.loadWorkflow(w).author == .ai)
    }

    @Test func promptIncludesCurrentProposalAndGeneratingWritesNothing() throws {
        let store = try newStore()
        _ = try store.createAgent(title: "Revisor", prompt: "texto atual único")
        let before = try snapshot(store)
        let current = try store.itemProposal(.agent, ref: "revisor")
        let prompt = ItemDiscover.prompt(kind: .agent, request: "mais curto", current: current, existing: try store.existingItems(.agent))
        #expect(prompt.contains("texto atual único"))
        #expect(prompt.contains("mais curto"))
        #expect(prompt.contains("COMPLETO"))
        #expect(!ItemDiscover.prompt(kind: .agent, request: "x").contains("Conteúdo atual"))
        #expect(try snapshot(store) == before)
    }

    @Test func editReplacesContentKeepingIdentityAndFlow() throws {
        let store = try newStore()
        let created = try store.createAgent(title: "Revisor", prompt: "velho")
        _ = try store.createAgent(title: "Outro")
        try store.addNextStep(to: created.slug, target: "outro")
        try store.applyItem(.agent, ref: created.slug, .init(title: "Revisor 2", prompt: "novo"))
        let agent = try store.loadAgent(created.slug)
        #expect(agent.prompt == "novo")
        #expect(agent.title == "Revisor 2")
        #expect(agent.id == created.agent.id)
        #expect(agent.nextSteps.count == 1)
    }

    @Test func schemaIsValidJSONForEveryKind() throws {
        for kind in ItemDiscover.Kind.allCases {
            let object = try JSONSerialization.jsonObject(with: Data(ItemDiscover.schema(kind).utf8)) as? [String: Any]
            #expect(object?["additionalProperties"] as? Bool == false)
        }
    }
}
