import SwiftUI

/// Filtro único da lista de um conceito (regra A999B857): texto livre, tokens `#tag` digitados e chips de tag ligados.
/// O estado fica na janela e é compartilhado pela coluna de conteúdo (campo e chips) e pela tabela do detalhe,
/// que só aplica o filtro e não tem campo próprio.
struct V2ListFilter: Equatable {
    var search = ""
    var tags = Set<String>()

    var isActive: Bool { !search.isEmpty || !tags.isEmpty }

    /// Texto livre e tags exigidas (chips ligados mais os tokens `#tag` digitados).
    var parsed: (text: String, tags: [String]) {
        let terms = search.split(whereSeparator: { $0.isWhitespace })
        let typed = terms.filter { $0.hasPrefix("#") }.map { String($0.dropFirst()) }.filter { !$0.isEmpty }
        let text = terms.filter { !$0.hasPrefix("#") }.joined(separator: " ")
        return (text, tags.sorted() + typed)
    }

    func matches(_ row: SectionRow) -> Bool {
        let filter = parsed
        let hasTags = filter.tags.allSatisfy { tag in row.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame } }
        if !hasTags { return false }
        if filter.text.isEmpty { return true }
        return row.title.localizedCaseInsensitiveContains(filter.text)
            || row.detail.localizedCaseInsensitiveContains(filter.text)
            || row.tags.contains { $0.localizedCaseInsensitiveContains(filter.text) }
    }

    mutating func toggle(tag: String) {
        if tags.contains(tag) { tags.remove(tag) } else { tags.insert(tag) }
    }

    mutating func reset() {
        search = ""
        tags = []
    }

    /// Texto mostrado quando nada casa com o filtro.
    var summary: String {
        search.isEmpty ? tags.sorted().map { "#" + $0 }.joined(separator: " ") : search
    }
}
