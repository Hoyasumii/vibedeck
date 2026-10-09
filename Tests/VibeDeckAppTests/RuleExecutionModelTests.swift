import Foundation
import SwiftUI
import Testing
@testable import VibeDeckCore
@testable import VibeDeckApp

@Suite(.serialized) @MainActor
struct RuleExecutionModelTests {
    private func fixture() throws -> (ProjectModel, String, UUID, UUID) {
        let store = try ProjectStore.initialize(at: FileManager.default.temporaryDirectory.appending(path: "rule-flow-\(UUID())"))
        let (slug, script) = try store.addRule(Rule(text: "Script rule"), toTopic: "Flow")
        _ = try store.setRuleTest(script.id.uuidString, mode: .script, command: "stub")
        let (_, manual) = try store.addRule(Rule(text: "Manual rule"), toTopic: slug)
        return (ProjectModel(store: store), slug, script.id, manual.id)
    }
    private func wait(_ model: ProjectModel) async throws {
        for _ in 0..<500 {
            if model.ruleExecution?.active != true { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Execution did not finish")
    }

    @Test func scriptsBeforeAIAndPersistFailure() async throws {
        let (model, slug, script, manual) = try fixture()
        defer { try? FileManager.default.removeItem(at: model.store.root) }
        var aiCalls = 0
        model.startRuleExecution(topic: slug, withAI: true, runner: .init { _, _ in .init(exitCode: 1, output: "failure") }, providerAvailable: { _ in true }) { _, _, _, topic, rules, scripts in
            aiCalls += 1
            #expect(model.testRuns[script]?.verdict == .fail)
            #expect(scripts.count == 1)
            #expect(rules.map(\.id) == [manual])
            return [RuleResult(topic: topic, ruleId: manual, verdict: .pass, note: "Evidence")]
        }
        try await wait(model)
        #expect(aiCalls == 1)
        #expect(model.ruleExecution?.saved == true)
        #expect(model.ruleExecution?.progress == 1)
        #expect(try model.store.listChecks().first?.passed == false)
    }

    @Test func scriptsOnlyAndUnavailableProvider() async throws {
        let (model, slug, _, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: model.store.root) }
        model.startRuleExecution(topic: slug, withAI: true, providerAvailable: { _ in false }) { _, _, _, _, _, _ in
            Issue.record("Unavailable provider was called"); return []
        }
        #expect(model.ruleExecution == nil)
        model.startRuleExecution(topic: slug, runner: .init { _, _ in .init(exitCode: 77, output: "not applicable") }, verify: { _, _, _, _, _, _ in
            Issue.record("AI was called in script mode"); return []
        })
        try await wait(model)
        #expect(model.ruleExecution?.steps.count == 1)
        #expect(model.ruleExecution?.omitted == 1)
        #expect(model.ruleExecution?.steps.first?.result?.verdict == .na)
        #expect(try model.store.listChecks().isEmpty)
    }

    @Test func providerFailureContinuesOtherTopicsWithoutSaving() async throws {
        let (model, _, _, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: model.store.root) }
        _ = try model.store.addRule(Rule(text: "Another"), toTopic: "Second")
        var calls = 0
        model.startRuleExecution(withAI: true, runner: .init { _, _ in .init(exitCode: 124, output: "timeout") }, providerAvailable: { _ in true }) { _, _, _, slug, rules, _ in
            calls += 1
            if calls == 1 { throw RuleExecutionError.invalidAnswer }
            return rules.map { RuleResult(topic: slug, ruleId: $0.id, verdict: .pass, note: "Evidence") }
        }
        try await wait(model)
        #expect(calls == 2)
        #expect(model.ruleExecution?.steps.contains { $0.error != nil } == true)
        #expect(model.ruleExecution?.saved == false)
        #expect(try model.store.listChecks().isEmpty)
    }

    @Test func staleRulesGoToAIAndChangesPreventSaving() async throws {
        let (model, slug, script, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: model.store.root) }
        try model.store.updateTopic(slug) { $0.rules[0].text = "Changed rule" }
        var calls = 0
        model.startRuleExecution(topic: slug, withAI: true, runner: .init { _, _ in
            Issue.record("Stale script must not execute")
            return .init(exitCode: 0, output: "")
        }, providerAvailable: { _ in true }) { _, _, _, topic, rules, scripts in
            calls += 1
            #expect(scripts.isEmpty)
            #expect(rules.contains { $0.id == script })
            let executionID = model.ruleExecution?.id
            model.startRuleExecution(topic: slug)
            #expect(model.ruleExecution?.id == executionID, "A second execution must not replace the active one")
            try model.store.updateTopic(slug) { $0.rules[0].details = "Changed while running" }
            return rules.map { RuleResult(topic: topic, ruleId: $0.id, verdict: .pass, note: "Evidence") }
        }
        try await wait(model)
        #expect(calls == 1)
        #expect(model.ruleExecution?.saved == false)
        #expect(model.ruleExecution?.message?.contains("mudaram") == true)
        #expect(try model.store.listChecks().isEmpty)
    }

    @Test func progressEstimateAndEmptyScope() throws {
        let (model, slug, script, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: model.store.root) }
        let root = model.store.root
        let key = "ruleExecutionTimings:" + root.standardizedFileURL.path
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let snapshot = [(slug: slug, topic: try model.store.loadTopic(slug))]
        let start = Date(timeIntervalSince1970: 100)
        let first = RuleExecutionModel(snapshot: snapshot, withAI: false, provider: .claude, root: root, now: start)
        #expect(first.remaining(at: start) == nil)
        first.begin([script], now: start)
        first.finish([script], now: start.addingTimeInterval(10))
        #expect(first.progress == 1)
        let next = RuleExecutionModel(snapshot: snapshot, withAI: false, provider: .claude, root: root, now: start)
        next.begin([script], now: start)
        #expect(next.remaining(at: start.addingTimeInterval(4)) == 6)
        #expect(next.remaining(at: start.addingTimeInterval(11)) == -1)
        model.startRuleExecution(topic: "missing", withAI: false)
        #expect(model.ruleExecution?.active == false)
        #expect(model.ruleExecution?.progress == 1)
    }

    @Test func sidebarGroupsUseOpenCountAndKeepSectionAccess() throws {
        let (model, _, _, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: model.store.root) }
        for status in ReviewStatus.allCases {
            var group = ReviewGroup(title: status.rawValue)
            group.items = [ReviewItem(kind: "fix", title: "Item", status: status)]
            model.groups.append(.init(slug: status.rawValue, group: group))
        }
        model.groups.append(.init(slug: "empty", group: ReviewGroup(title: "Vazio")))
        #expect(Set(model.sidebarRows(for: .groups).map(\.id)) == [.group("open"), .group("in_progress")])
        #expect(model.rows(for: .groups).count == 5)
        #expect(model.count(.groups) == 5)
        for entry in model.groups { #expect(model.exists(.group(entry.slug))) }
    }

    @Test func sidebarGroupReappearsAfterUndoAndExternalEdit() async throws {
        let (model, _, _, _) = try fixture()
        defer { model.stopWatching(); try? FileManager.default.removeItem(at: model.store.root) }
        let (slug, _) = try model.store.createGroup(title: "Reabrir")
        _ = try model.store.updateGroup(slug) { $0.items = [ReviewItem(kind: "fix", title: "Item")] }
        model.reloadGroups()
        let undo = UndoManager()
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        model.mutateGroup(slug, "Concluir", undo: undo) { $0.items[0].status = .done }
        undo.endUndoGrouping()
        #expect(model.sidebarRows(for: .groups).isEmpty)
        #expect(model.exists(.group(slug)))
        #expect(try model.store.loadGroup(slug).items[0].status == .done)
        undo.undo()
        #expect(model.sidebarRows(for: .groups).map(\.id) == [.group(slug)])
        #expect(try model.store.loadGroup(slug).items[0].status == .open)
        undo.redo()
        #expect(model.sidebarRows(for: .groups).isEmpty)
        model.startWatching()
        _ = try model.store.updateGroup(slug) { $0.items[0].status = .inProgress }
        for _ in 0..<100 {
            if !model.sidebarRows(for: .groups).isEmpty { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(model.sidebarRows(for: .groups).map(\.id) == [.group(slug)])
        #expect(model.group(slug)?.items[0].status == .inProgress)
    }

    @Test func sidebarIdeasOnlyOmitDoneIncludingPromotedIdeas() throws {
        let (model, _, _, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: model.store.root) }
        for status in IdeaStatus.allCases {
            var idea = Idea(title: status.rawValue)
            idea.status = status
            model.ideas.append(.init(slug: status.rawValue, value: idea))
        }
        var promoted = Idea(title: "Promovida")
        promoted.status = .approved
        promoted.promotedTopic = "topic"
        model.ideas.append(.init(slug: "promoted", value: promoted))
        #expect(Set(model.sidebarRows(for: .ideas).map(\.id)) == Set(IdeaStatus.allCases.filter { $0 != .done }.map { .idea($0.rawValue) } + [.idea("promoted")]))
        #expect(model.rows(for: .ideas).count == 6)
        #expect(model.count(.ideas) == 6)
        #expect(model.exists(.idea("done")))
        #expect(model.idea("done")?.status == .done)
        model.mutateIdea("promoted", "Implementar", undo: nil) { $0.status = .done }
        #expect(!model.sidebarRows(for: .ideas).contains { $0.id == .idea("promoted") })
        #expect(model.exists(.idea("promoted")))
        #expect(model.rows(for: .ideas).contains { $0.id == .idea("promoted") })
    }

    @Test func sidebarSearchFiltersVisibleRowsAcrossAllSections() throws {
        let (model, _, _, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: model.store.root) }
        let tags = ["UI", "swift"]
        model.docs = [.init(slug: "doc", title: "Painel", tags: tags, modified: .now)]
        var group = ReviewGroup(title: "Painel", description: "Descrição relevante", tags: tags)
        group.items = [ReviewItem(kind: "fix", title: "Item")]
        var closed = group
        closed.items[0].status = .wontfix
        model.groups = [.init(slug: "group", group: group), .init(slug: "closed", group: closed)]
        var done = Idea(title: "Painel", tags: tags)
        done.status = .done
        model.ideas = [.init(slug: "idea", value: Idea(title: "Painel", tags: tags)), .init(slug: "done", value: done)]
        model.topics = [.init(slug: "topic", value: RuleTopic(title: "Painel", tags: tags))]
        model.agents = [.init(slug: "agent", value: Agent(title: "Painel", tags: tags))]
        model.commands = [.init(slug: "command", value: Command(title: "Painel", tags: tags))]
        model.skills = [.init(slug: "skill", value: Skill(title: "Painel", tags: tags))]
        model.workflows = [.init(slug: "workflow", value: Workflow(title: "Painel", tags: tags))]
        for section in SidebarSection.allCases {
            let expected = model.sidebarRows(for: section).map(\.id)
            #expect(expected.count == 1)
            for query in ["PAINEL", "#ui", "#UI #swift", " painel  #ui ", "swift", " "] {
                #expect(model.sidebarRows(for: section, search: query).map(\.id) == expected)
            }
            for query in ["ausente", "#ausente", "#u", "painel #ausente", "#ui #ausente"] {
                #expect(model.sidebarRows(for: section, search: query).isEmpty)
            }
            #expect(model.sidebarRows(for: section, search: "").map(\.id) == expected)
        }
        #expect(model.sidebarRows(for: .groups, search: "descrição relevante").map(\.id) == [.group("group")])
        #expect(model.rows(for: .groups).count == 2)
        #expect(model.rows(for: .ideas).count == 2)
    }

    @Test func sidebarSelectedTargetsRemainResolvableAcrossStatusChanges() throws {
        let (model, _, _, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: model.store.root) }
        let groupSlug = try #require(model.createGroup(title: "Selecionado"))
        model.mutateGroup(groupSlug, "Adicionar item", undo: nil) {
            $0.items = [ReviewItem(kind: "fix", title: "Último aberto")]
        }
        let ideaSlug = try #require(model.createIdea(title: "Selecionada"))
        let targets: [SidebarItem] = [.group(groupSlug), .idea(ideaSlug)]
        for target in targets { #expect(model.exists(target)) }
        model.mutateGroup(groupSlug, "Concluir", undo: nil) { $0.items[0].status = .done }
        model.mutateIdea(ideaSlug, "Implementar", undo: nil) { $0.status = .done }
        #expect(model.sidebarRows(for: .groups).isEmpty)
        #expect(model.sidebarRows(for: .ideas).isEmpty)
        // ProjectWindow prunes tabs with exists, and resolves details with group/idea.
        #expect(targets.filter(model.exists) == targets)
        #expect(model.group(groupSlug)?.items[0].status == .done)
        #expect(model.idea(ideaSlug)?.status == .done)
        #expect(model.rows(for: .groups).map(\.id) == [.group(groupSlug)])
        #expect(model.rows(for: .ideas).map(\.id) == [.idea(ideaSlug)])
    }

}
