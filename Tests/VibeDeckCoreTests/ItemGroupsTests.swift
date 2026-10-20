import Foundation
import Testing
@testable import VibeDeckCore

@Suite struct ItemGroupsTests {
    private func withStore(_ body: (ProjectStore) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "groups-\(UUID())")
        let store = try ProjectStore.initialize(at: root)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(store)
    }

    @Test func recursiveCreationAmbiguityAndCompatibility() throws {
        try withStore { store in
            let (_, flat) = try store.createIdea(title: "Plano")
            let bytes = try Data(contentsOf: store.ideaURL("plano"))
            for group in ["a/b", "c"] {
                #expect(try store.createIdea(title: "X", reference: group + "/x").slug == group + "/x")
                #expect(try store.createDoc(title: "X", reference: group + "/x") == group + "/x")
                #expect(try store.createGroup(title: "Tema", reference: group + "/x").slug == group + "/x")
                #expect(try store.createSkill(title: "X", reference: group + "/x").slug == group + "/x")
            }
            #expect(try store.listIdeas().count == 3)
            #expect(try store.listIdeas().first(where: { $0.slug == "a/b/x" })?.group == "a/b")
            #expect(try store.listSkills().map(\.group).sorted() == ["a/b", "c"])
            #expect(try store.listGroups().map(\.directoryGroup).sorted() == ["a/b", "c"])
            #expect(try store.listDocs().map(\.group).sorted() == ["a/b", "c"])
            #expect(try store.resolveIdeaSlug(flat.id.uuidString) == "plano")
            #expect(try store.resolveIdeaSlug("a/b/x") == "a/b/x")
            #expect(throws: VibeDeckError.ambiguousReference("x", ["a/b/x", "c/x"])) { try store.resolveIdeaSlug("x") }
            #expect(throws: VibeDeckError.self) { try store.resolveSkillSlug("x") }
            #expect(throws: VibeDeckError.self) { try store.resolveDocSlug("x") }
            #expect(try Data(contentsOf: store.ideaURL("plano")) == bytes)
            #expect(ProjectStore.groupPath(of: "plano").isEmpty)
            _ = try store.createItemDirectory(.ideas, path: "vazio/sub")
            try Data().write(to: store.ideasDir.appending(path: "a/.DS_Store"))
            #expect(try store.listItemDirectories(.ideas).map(\.path).contains("vazio/sub"))
            #expect(try store.listIdeas().count == 3)
        }
    }

    @Test func movesPreserveBytesRejectConflictsAndRequireConfirmation() throws {
        try withStore { store in
            let (_, idea) = try store.createIdea(title: "X", author: .human, reference: "a/b/x")
            let before = try Data(contentsOf: store.ideaURL("a/b/x"))
            _ = try store.createIdea(title: "X", reference: "c/x")
            let destination = try Data(contentsOf: store.ideaURL("c/x"))
            #expect(throws: VibeDeckError.self) { try store.moveGroupedItem(.ideas, reference: "a/b/x", to: "c") }
            #expect(try Data(contentsOf: store.ideaURL("a/b/x")) == before)
            #expect(try Data(contentsOf: store.ideaURL("c/x")) == destination)
            #expect(throws: VibeDeckError.self) { try store.moveItemDirectory(.ideas, from: "a", to: "a/b") }
            #expect(throws: VibeDeckError.self) { try store.deleteItemDirectory(.ideas, path: "a") }
            try store.moveItemDirectory(.ideas, from: "a", to: "novo")
            #expect(try Data(contentsOf: store.ideaURL("novo/b/x")) == before)
            #expect(try store.loadIdea("novo/b/x").id == idea.id)
            try store.deleteItemDirectory(.ideas, path: "novo", confirmed: true)
            #expect(!FileManager.default.fileExists(atPath: store.ideaURL("novo/b/x").path))
            _ = try store.createIdea(title: "Nome original", reference: "temporario/item")
            try FileManager.default.moveItem(at: store.ideasDir.appending(path: "temporario"), to: store.ideasDir.appending(path: "Grupo Antigo"))
            let receipt = try store.moveWithReceipt(.ideas, from: "Grupo Antigo", to: "outro", directory: true)
            _ = try store.undoGroupedMove(receipt)
            #expect(FileManager.default.fileExists(atPath: store.ideaURL("Grupo Antigo/item").path))
        }
    }

    @Test func traversalAndSymlinksNeverEscape() throws {
        try withStore { store in
            let outside = store.root.appending(path: "outside")
            try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: store.ideasDir.appending(path: "escape"), withDestinationURL: outside)
            for path in ["../x", "/tmp", "a//b", "escape/x"] {
                #expect(throws: VibeDeckError.self) { try store.createIdea(title: "X", reference: path) }
                #expect(throws: VibeDeckError.self) { try store.createItemDirectory(.ideas, path: path) }
            }
            _ = try store.createIdea(title: "Seguro")
            #expect(throws: VibeDeckError.self) { try store.moveGroupedItem(.ideas, reference: "seguro", to: "escape") }
            #expect(throws: VibeDeckError.self) { try store.deleteItemDirectory(.ideas, path: "escape", confirmed: true) }
            #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
            #expect(FileManager.default.fileExists(atPath: store.ideaURL("seguro").path))
            #expect(throws: VibeDeckError.self) { try store.createSkill(title: "X", reference: "../x") }
        }
    }

    @Test func groupedReviewsAndPromotionKeepIdentity() throws {
        try withStore { store in
            let (theme, _) = try store.createGroup(title: "Tema", reference: "a/tema")
            _ = try store.addItem(ReviewItem(kind: "note", title: "Nota"), toGroup: theme)
            #expect(try store.loadGroup(theme).openCount == 1)
            #expect(try store.listGroups().first?.group.items.count == 1)
            let (slug, idea) = try store.createIdea(title: "Promovida", reference: "a/promovida")
            _ = try store.addRule(Rule(text: "Regra"), toIdea: slug)
            let topic = try store.promoteIdea(slug)
            try store.moveItemDirectory(.ideas, from: "a", to: "b")
            #expect(try store.loadIdea("b/promovida").promotedTopic == topic)
            #expect(try store.loadTopic(topic).sourceIdea == idea.id)
            #expect(try store.promoteIdea("b/promovida") == topic)
            try store.deleteTopic(topic)
            #expect(try store.loadIdea("b/promovida").promotedTopic == nil)
        }
    }

    @Test func ruleGroupsRetainChecksAndApplicability() throws {
        try withStore { store in
            let (_, rule) = try store.addRule(Rule(text: "R"), toTopic: "Qualidade")
            let unrelated = RuleTopic(title: "Tópico aninhado com escopo independente", paths: ["Unrelated/**"], rules: [Rule(text: "Não aplicável")])
            try AtomicFile.write(VDJSON.encode(unrelated), to: store.rulesDir.appending(path: "nested/extra.json"))
            #expect(try Set(store.listTopics().map(\.slug)) == ["qualidade", "nested/extra"])
            #expect(try Set(store.applicableTopics(files: ["Unrelated/x.swift"]).map(\.slug)) == ["qualidade", "nested/extra"])
            let check = try store.submitCheck(task: "Antes", files: [], answers: [.init(ruleId: rule.id.uuidString, verdict: .pass)], verifyManual: true)
            let moved = try store.moveRuleToGroup(rule.id.uuidString, group: "a/b")
            #expect(moved.id == rule.id)
            #expect(moved.group == "a/b")
            #expect(try store.listChecks().first?.results.first?.ruleId == rule.id)
            #expect(check.passed)
            #expect(throws: VibeDeckError.self) { try store.submitCheck(task: "Depois", files: [], answers: [], verifyManual: true) }
            try store.renameRuleGroup(topic: "qualidade", from: "a", to: "c")
            #expect(try store.loadTopic("qualidade").rules.first?.group == "c/b")
        }
    }

    @Test func skillReferencesUndoAndAttachments() throws {
        try withStore { store in
            let (slug, skill) = try store.createSkill(title: "Revisar", reference: "a/revisar")
            let agent = try store.createAgent(title: "Agente").slug
            _ = try store.updateAgent(agent) { $0.nextSteps = [.init(kind: .skill, ref: skill.id.uuidString)] }
            let original = try Data(contentsOf: store.agentURL(agent))
            let receipt = try store.moveWithReceipt(.skills, from: slug, to: "b", directory: false)
            #expect(try store.loadAgent(agent).nextSteps.first?.ref == "b/revisar")
            let inverse = try store.undoGroupedMove(receipt)
            #expect(try Data(contentsOf: store.agentURL(agent)) == original)
            _ = try store.undoGroupedMove(inverse)
            #expect(try store.loadAgent(agent).nextSteps.first?.ref == "b/revisar")
            let outside = store.root.appending(path: "outside-agents")
            try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
            let expected = try Data(contentsOf: store.agentURL(agent))
            try expected.write(to: outside.appending(path: agent + ".json"))
            try FileManager.default.moveItem(at: store.agentDefsDir, to: store.root.appending(path: "agents-backup"))
            try FileManager.default.createSymbolicLink(at: store.agentDefsDir, withDestinationURL: outside)
            #expect(throws: VibeDeckError.self) { try store.undoGroupedMove(receipt) }
            #expect(try Data(contentsOf: outside.appending(path: agent + ".json")) == expected)
            let link = try store.importAttachment(data: Data("image".utf8), name: "f.png", owner: "a/b/x")
            #expect(link.contains("../../../attachments/"))
            let text = ProjectStore.markdownForGroupedRecord("![F](../attachments/f.png)", reference: "a/b/x")
            #expect(text == "![F](../../../attachments/f.png)")
            let base = store.docURL("a/b/x").deletingLastPathComponent()
            #expect(URL(string: "../../../attachments/f.png", relativeTo: base)?.standardizedFileURL == store.attachmentsDir.appending(path: "f.png").standardizedFileURL)
            let object = try JSONSerialization.jsonObject(with: VDJSON.encode(GroupedRecord(slug: "b/revisar", value: skill))) as? [String: Any]
            #expect(object?["group"] as? String == "b")
            #expect(object?["slug"] as? String == "b/revisar")
        }
    }
}

#if canImport(CoreServices)
private final class GroupEventPaths: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []
    func append(_ urls: [URL]) { lock.lock(); values += urls.map(\.path); lock.unlock() }
    func count(_ suffix: String) -> Int { lock.lock(); defer { lock.unlock() }; return values.filter { $0.hasSuffix(suffix) }.count }
    func contains(_ suffix: String) -> Bool { count(suffix) > 0 }
}

extension ItemGroupsTests {
    @Test func watcherReportsNestedCreationAndDirectoryMove() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "watch-groups-\(UUID())")
        let store = try ProjectStore.initialize(at: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let events = GroupEventPaths()
        let watcher = FileWatcher(root: root) { events.append($0) }
        watcher.start()
        defer { watcher.stop() }
        try await Task.sleep(for: .milliseconds(400))
        _ = try store.createIdea(title: "X", reference: "a/b/x")
        for _ in 0..<40 {
            if events.contains("/a/b/x.json") { break }
            try await Task.sleep(for: .milliseconds(125))
        }
        #expect(events.contains("/a/b/x.json"))
        try store.moveItemDirectory(.ideas, from: "a", to: "c")
        for _ in 0..<40 {
            if events.contains("/c") || events.contains("/c/b/x.json") { break }
            try await Task.sleep(for: .milliseconds(125))
        }
        #expect(events.contains("/c") || events.contains("/c/b/x.json"))
        let previous = events.count("/c")
        try store.deleteItemDirectory(.ideas, path: "c", confirmed: true)
        for _ in 0..<40 {
            if events.count("/c") > previous { break }
            try await Task.sleep(for: .milliseconds(125))
        }
        #expect(events.count("/c") > previous)
    }
}
#endif
