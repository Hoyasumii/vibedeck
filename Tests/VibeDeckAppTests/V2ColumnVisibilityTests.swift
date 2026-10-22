import Foundation
import Testing
@testable import VibeDeckApp

/// Coluna de conteúdo V2: omite grupos sem item aberto e ideias Implementadas; a tabela do detalhe mostra tudo.
@Suite @MainActor struct V2ColumnVisibilityTests {
    private func model(groups: [ProjectModel.GroupEntry] = [], ideas: [Idea] = []) throws -> ProjectModel {
        let root = FileManager.default.temporaryDirectory.appending(path: "vd-col-\(UUID().uuidString)")
        let model = try ProjectModel.forTesting(root: root, groups: groups)
        model.ideas = ideas.enumerated().map { ProjectModel.Entry(slug: "ideia-\($0.offset)", value: $0.element) }
        return model
    }

    private func group(_ title: String, _ statuses: [ReviewStatus]) -> ProjectModel.GroupEntry {
        var value = ReviewGroup(title: title)
        value.items = statuses.map { ReviewItem(kind: "note", title: "x", status: $0) }
        return ProjectModel.GroupEntry(slug: title.lowercased(), group: value)
    }

    @Test func sidebarGroupsUseOpenCountAndKeepSectionAccess() throws {
        let m = try model(groups: [group("Aberto", [.open, .done]), group("Fechado", [.done, .wontfix])])
        #expect(m.columnRows(for: .groups, keeping: nil).map(\.title) == ["Aberto"])
        #expect(m.rows(for: .groups).count == 2)
    }

    @Test func sidebarIdeasOnlyOmitDoneIncludingPromotedIdeas() throws {
        var done = Idea(title: "Feita"); done.status = .done
        var approved = Idea(title: "Aprovada"); approved.status = .approved
        let m = try model(ideas: [done, approved, Idea(title: "Nova")])
        #expect(m.columnRows(for: .ideas, keeping: nil).map(\.title) == ["Aprovada", "Nova"])
        #expect(m.rows(for: .ideas).count == 3)
    }

    @Test func sidebarSelectedTargetsRemainResolvableAcrossStatusChanges() throws {
        let m = try model(groups: [group("Fechado", [.done])])
        let selected = SidebarItem.group("fechado")
        #expect(m.columnRows(for: .groups, keeping: nil).isEmpty)
        #expect(m.columnRows(for: .groups, keeping: selected).count == 1)
    }

    @Test func sidebarGroupReappearsAfterUndoAndExternalEdit() throws {
        let m = try model(groups: [group("Volta", [.done])])
        #expect(m.columnRows(for: .groups, keeping: nil).isEmpty)
        m.groups[0].group.items[0].status = .open
        #expect(m.columnRows(for: .groups, keeping: nil).count == 1)
    }

    @Test func sidebarSearchFiltersVisibleRowsAcrossAllSections() throws {
        let m = try model(groups: [group("Alpha", [.open]), group("Beta", [.open])])
        var filter = V2ListFilter()
        filter.search = "alp"
        let visible = m.columnRows(for: .groups, keeping: nil).filter { filter.matches($0) }
        #expect(visible.map(\.title) == ["Alpha"])
    }
}
