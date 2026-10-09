import Foundation
import Testing
@testable import VibeDeckCore

private func tempStore() throws -> ProjectStore {
    let url = FileManager.default.temporaryDirectory.appending(path: "vibedeck-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return try ProjectStore.initialize(at: url, name: "Demo")
}

private let fixture = [
    SkillIcon(id: "swift", name: "Swift", category: "language"),
    SkillIcon(id: "kubernetes", name: "Kubernetes", category: "devops", aliases: ["k8s"]),
    SkillIcon(id: "nextjs", name: "Next.js", category: "frontend", themed: true, aliases: ["next"]),
    SkillIcon(id: "postgresql", name: "PostgreSQL", category: "database", aliases: ["postgres"]),
]

/// Offline stand-in for the Skill Icons MCP server.
private struct FakeSkillIcons: SkillIconsAPI {
    var failing = false

    func search(query: String?, category: String?, limit: Int?) async throws -> [SkillIcon] {
        if failing { throw VibeDeckError.skillIconsUnavailable("offline") }
        return fixture.filter { $0.matches(containing: query ?? "") }
    }

    func badge(icons: [String], theme: SkillIconTheme?, perLine: Int?) async throws -> SkillBadge {
        if failing { throw VibeDeckError.skillIconsUnavailable("offline") }
        let url = "https://icons.test/icons?i=\(icons.joined(separator: ","))"
        let json = #"{"url":"\#(url)","markdown":"![Stack](\#(url))","html":"","icons":[]}"#
        return try JSONDecoder().decode(SkillBadge.self, from: Data(json.utf8))
    }

    func image(url: String) async throws -> Data { Data() }
}

@Suite struct StackTests {
    @Test func emptyStackIsOmittedAndHandWrittenItemsDecode() throws {
        let store = try tempStore()
        #expect(try !String(contentsOf: store.manifestURL, encoding: .utf8).contains("\"stack\""))

        var raw = try String(contentsOf: store.manifestURL, encoding: .utf8)
        raw = raw.replacingOccurrences(of: "\"name\" : \"Demo\"", with: #""name" : "Demo", "stack": [{"icon": "swift"}]"#)
        try Data(raw.utf8).write(to: store.manifestURL)
        let item = try #require(try store.loadProject().stack.first)
        #expect(item == StackItem(icon: "swift", name: "swift"))

        try store.updateProject { _ in }
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: store.manifestURL)) as? [String: Any]
        let saved = try #require((json?["stack"] as? [[String: Any]])?.first)
        #expect(Set(saved.keys) == ["icon", "name", "author"])
    }

    @Test func resolveAcceptsIdsNamesAndAliases() throws {
        let icons = try SkillIcons.resolve(["k8s", "Next.js", "swift", "kubernetes"], in: fixture)
        #expect(icons.map(\.id) == ["kubernetes", "nextjs", "swift"])
        #expect(throws: VibeDeckError.unknownStackIcons(["post": ["postgresql"]])) {
            try SkillIcons.resolve(["swift", "post"], in: fixture)
        }
    }

    @Test func addRemoveNoteAndMove() async throws {
        let store = try tempStore()
        let service = StackService(store: store, icons: FakeSkillIcons())

        let added = try await service.add(["swift", "k8s"], note: "base", author: .ai)
        #expect(added.stack.map(\.icon) == ["swift", "kubernetes"])
        #expect(added.stack.allSatisfy { $0.author == .ai && $0.note == "base" })
        #expect(added.readmeWarning == nil)

        // Adding again keeps the place; a note replaces the old one.
        _ = try await service.add(["postgres", "swift"], note: "Swift 6", author: .human)
        var stack = try store.loadProject().stack
        #expect(stack.map(\.icon) == ["swift", "kubernetes", "postgresql"])
        #expect(stack[0].note == "Swift 6")
        #expect(stack[0].author == .ai)

        _ = try await service.move("postgresql", to: 0)
        _ = try await service.setNote("Kubernetes", "")
        stack = try store.loadProject().stack
        #expect(stack.map(\.icon) == ["postgresql", "swift", "kubernetes"])
        #expect(stack[2].note == nil)

        // Aliases resolve through the catalog; unknown refs remove nothing.
        await #expect(throws: VibeDeckError.stackItemNotFound("nope")) { try await service.remove(["k8s", "nope"]) }
        #expect(try store.loadProject().stack.count == 3)
        let removed = try await service.remove(["k8s", "postg"])
        #expect(removed.items.map(\.icon) == ["postgresql", "kubernetes"])
        #expect(removed.stack.map(\.icon) == ["swift"])
    }

    @Test func readmeBadgeFollowsTheStack() async throws {
        let store = try tempStore()
        try Data("# Demo\n\nTexto.\n".utf8).write(to: store.readmeURL)
        let service = StackService(store: store, icons: FakeSkillIcons())

        _ = try await service.add(["swift"], author: .human)
        var readme = try String(contentsOf: store.readmeURL, encoding: .utf8)
        #expect(readme == "# Demo\n\n\(ReadmeStack.start)\n![Stack](https://icons.test/icons?i=swift)\n\(ReadmeStack.end)\n\nTexto.\n")

        _ = try await service.add(["k8s"], author: .human)
        readme = try String(contentsOf: store.readmeURL, encoding: .utf8)
        #expect(readme.contains("i=swift,kubernetes"))
        #expect(readme.components(separatedBy: ReadmeStack.start).count == 2)

        _ = try await service.remove(["swift", "kubernetes"])
        #expect(try String(contentsOf: store.readmeURL, encoding: .utf8) == "# Demo\n\nTexto.\n")
    }

    @Test func offlineSkillIconsStillSavesWithWarning() async throws {
        let store = try tempStore()
        try store.addStackItems([fixture[0]], author: .human)
        let change = try await StackService(store: store, icons: FakeSkillIcons(failing: true)).setNote("swift", "x")
        #expect(change.stack.first?.note == "x")
        #expect(change.readmeWarning?.contains("README.md não foi atualizado") == true)
    }

    @Test func markersQuotedInProseAreIgnored() {
        let prose = "# T\n\nUse `\(ReadmeStack.start)` e `\(ReadmeStack.end)`.\n"
        let applied = ReadmeStack.apply("B", to: prose)
        #expect(applied == "# T\n\n\(ReadmeStack.start)\nB\n\(ReadmeStack.end)\n\nUse `\(ReadmeStack.start)` e `\(ReadmeStack.end)`.\n")
        #expect(ReadmeStack.apply(nil, to: applied) == prose)
    }

    @Test func readmeBlockWithoutHeading() {
        #expect(ReadmeStack.apply("B", to: "texto\n") == "\(ReadmeStack.start)\nB\n\(ReadmeStack.end)\n\ntexto\n")
        #expect(ReadmeStack.apply(nil, to: "texto\n") == "texto\n")
    }

    @Test func decodesToolResponses() throws {
        let plain = #"{"result":{"content":[{"type":"text","text":"{\"total\":1,\"icons\":[{\"id\":\"swift\",\"name\":\"Swift\",\"category\":\"language\",\"themed\":false,\"aliases\":[]}]}"}]},"jsonrpc":"2.0","id":1}"#
        struct Result: Decodable { var icons: [SkillIcon] }
        #expect(try SkillIcons.decodeToolText(Result.self, from: Data(plain.utf8)).icons == [fixture[0]])

        let sse = "event: message\ndata: " + plain + "\n\n"
        #expect(try SkillIcons.decodeToolText(Result.self, from: Data(sse.utf8)).icons.count == 1)

        let error = #"{"jsonrpc":"2.0","id":1,"error":{"code":-32601,"message":"Method not found"}}"#
        #expect(throws: VibeDeckError.skillIconsUnavailable("Method not found")) {
            try SkillIcons.decodeToolText(Result.self, from: Data(error.utf8))
        }
    }
}
