import Foundation
import Testing
@testable import VibeDeckCore

private func newStore() throws -> ProjectStore {
    let url = FileManager.default.temporaryDirectory.appending(path: "vibedeck-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return try ProjectStore.initialize(at: url)
}

/// Last line of `claude -p --output-format json --json-schema …` (2.1.x), trimmed.
private func output(structured: String, isError: Bool = false, subtype: String = "success") -> Data {
    Data(#"{"type":"result","subtype":"\#(subtype)","is_error":\#(isError),"result":"","structured_output":\#(structured)}"#.utf8)
}

@Suite struct ReviewDiscoverTests {
    private let topics: [(slug: String, topic: RuleTopic)] = [
        ("geral", RuleTopic(title: "Geral")),
        ("interface", RuleTopic(title: "Interface", paths: ["Sources/App/**"])),
        ("core", RuleTopic(title: "Core", paths: ["Sources/Core/**"])),
    ]

    @Test func argumentsAreReadOnly() {
        let args = ReviewDiscover.arguments()
        let tools = args[args.firstIndex(of: "--tools")! + 1]
        #expect(tools == "Read,Grep,Glob")
        #expect(args[args.firstIndex(of: "--allowedTools")! + 1] == tools)
        #expect(args.contains("--strict-mcp-config"))
        #expect(args.contains("--json-schema"))
        #expect(!args.joined(separator: " ").contains("Bash"))
        #expect(!args.contains("--dangerously-skip-permissions"))
    }

    @Test func promptListsOnlyCandidateTopics() {
        let item = ReviewItem(kind: "fix", title: "Botão quebrado", details: "Na tela de login",
                              target: ReviewTarget(route: "/login"), rules: ["core"])
        let candidates = ReviewDiscover.candidateTopics(topics, item: item)
        #expect(candidates.map(\.slug) == ["interface"])
        let prompt = ReviewDiscover.prompt(item: item, kind: "Corrigir", topics: candidates)
        #expect(prompt.contains("Título: Botão quebrado"))
        #expect(prompt.contains("Detalhes: Na tela de login"))
        #expect(prompt.contains("route = /login"))
        #expect(prompt.contains("- interface: Interface"))
        #expect(!prompt.contains("- geral"))
        #expect(!prompt.contains("- core"))

        let onFile = ReviewItem(kind: "fix", title: "x", target: ReviewTarget(file: "Sources/App/View.swift"))
        #expect(ReviewDiscover.candidateTopics(topics, item: onFile).map(\.slug) == ["core"])
    }

    @Test func parsesStructuredOutput() throws {
        let data = Data("hook noise\n".utf8) + output(structured: #"{"fields":[{"field":"file","value":"a.swift","reason":"a.swift:3"}],"rules":[{"slug":"core","reason":"x"}]}"#)
        let answer = try ReviewDiscover.parse(data)
        #expect(answer.fields.map(\.value) == ["a.swift"])
        #expect(answer.fields.first?.reason == "a.swift:3")
        #expect(answer.rules.map(\.slug) == ["core"])
    }

    @Test func invalidOrFailedOutputThrows() {
        #expect(throws: VibeDeckError.discoverInvalidAnswer) { try ReviewDiscover.parse(Data("não é json".utf8)) }
        #expect(throws: VibeDeckError.discoverInvalidAnswer) { try ReviewDiscover.parse(output(structured: #"{"fields":"x"}"#)) }
        #expect(throws: VibeDeckError.discoverFailed("error_max_turns")) {
            try ReviewDiscover.parse(output(structured: "null", isError: true, subtype: "error_max_turns"))
        }
    }

    @Test func proposalDropsMissingFilesAndUnknownTopics() throws {
        let store = try newStore()
        try AtomicFile.write(Data("x".utf8), to: store.root.appending(path: "Sources/App/View.swift"))
        let item = ReviewItem(kind: "fix", title: "x")
        let answer = ReviewDiscover.Answer(
            fields: [
                .init(field: .file, value: "Sources/App/Nope.swift", reason: nil),
                .init(field: .file, value: "../outside.swift", reason: nil),
                .init(field: .component, value: "LoginView", reason: "View.swift:3"),
            ],
            rules: [.init(slug: "inventado", reason: nil), .init(slug: "interface", reason: "tela")]
        )
        let proposal = ReviewDiscover.proposal(answer, item: item, topics: topics, store: store)
        #expect(proposal.fields.map(\.field) == [.component])
        #expect(proposal.topics.map(\.slug) == ["interface"])
        #expect(proposal.discarded.count == 3)

        let found = ReviewDiscover.Answer(fields: [.init(field: .file, value: store.root.path + "/Sources/App/View.swift", reason: nil)])
        #expect(ReviewDiscover.proposal(found, item: item, topics: topics, store: store).fields.map(\.suggested) == ["Sources/App/View.swift"])
        let directory = ReviewDiscover.Answer(fields: [.init(field: .file, value: "Sources/App", reason: nil)])
        #expect(ReviewDiscover.proposal(directory, item: item, topics: topics, store: store).fields.isEmpty)
    }

    @Test func replacingNeedsOptInAndTopicsOnlyAdd() throws {
        let store = try newStore()
        var item = ReviewItem(kind: "fix", title: "x", target: ReviewTarget(component: "Velho"), rules: ["core"])
        let answer = ReviewDiscover.Answer(
            fields: [.init(field: .component, value: "Novo", reason: nil), .init(field: .route, value: "/login", reason: nil),
                     .init(field: .selector, value: "", reason: nil)],
            rules: [.init(slug: "core", reason: nil), .init(slug: "geral", reason: nil), .init(slug: "interface", reason: nil)]
        )
        let proposal = ReviewDiscover.proposal(answer, item: item, topics: topics, store: store)
        #expect(proposal.fields.first { $0.field == .component }?.replaces == true)
        #expect(proposal.defaultFields == [.route])
        // Already linked and global topics are not proposed (and not reported as discarded).
        #expect(proposal.topics.map(\.slug) == ["interface"])
        #expect(proposal.discarded.isEmpty)

        proposal.apply(fields: proposal.defaultFields, topics: [], to: &item)
        #expect(item.target == ReviewTarget(route: "/login", component: "Velho"))
        #expect(item.rules == ["core"])

        proposal.apply(fields: [.component], topics: ["interface"], to: &item)
        #expect(item.target?.component == "Novo")
        #expect(item.rules == ["core", "interface"])
    }
}
