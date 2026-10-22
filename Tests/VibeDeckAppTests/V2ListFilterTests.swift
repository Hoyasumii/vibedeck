import Foundation
import Testing
@testable import VibeDeckApp

@Suite("V2ListFilter e docs vinculados")
struct V2ListFilterTests {
    private func row(_ title: String, tags: [String] = [], detail: String = "") -> SectionRow {
        SectionRow(id: .doc(title), title: title, symbol: "doc.text", detail: detail, count: "", tags: tags)
    }

    @Test func textAndTagTokensFilterTogether() {
        var filter = V2ListFilter()
        filter.search = "arq #ui"
        #expect(filter.matches(row("Arquitetura", tags: ["ui"])))
        #expect(!filter.matches(row("Arquitetura", tags: ["core"])))
        #expect(!filter.matches(row("Outro", tags: ["ui"])))
    }

    @Test func tagChipsAreRequiredAndResetClears() {
        var filter = V2ListFilter()
        filter.toggle(tag: "ui")
        #expect(filter.isActive)
        #expect(filter.matches(row("A", tags: ["UI"])))
        #expect(!filter.matches(row("B", tags: [])))
        filter.reset()
        #expect(!filter.isActive)
        #expect(filter.matches(row("B")))
    }

    @Test func emptySummaryUsesTagsWhenThereIsNoText() {
        var filter = V2ListFilter()
        filter.toggle(tag: "b")
        filter.toggle(tag: "a")
        #expect(filter.summary == "#a #b")
        filter.search = "zzz"
        #expect(filter.summary == "zzz")
    }

    @Test func docInfoLinkDefaultsToNil() throws {
        let doc = DocInfo(slug: "readme", title: "README", modified: Date(timeIntervalSince1970: 0))
        #expect(!doc.isLinked && !doc.isBroken)
        let linked = DocInfo(slug: "readme", title: "README", modified: Date(timeIntervalSince1970: 0),
                             link: DocLink(target: "README.md", broken: true))
        #expect(linked.isLinked && linked.isBroken)
        let data = try JSONEncoder().encode(doc)
        #expect(try JSONDecoder().decode(DocInfo.self, from: data).link == nil)
    }
}
