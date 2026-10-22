import Foundation
import Testing
@testable import VibeDeckApp

/// Os tipos Swift da UI decodificam o JSON que o Core Rust grava e devolve nos recursos `vibedeck://`.
@Suite struct CoreModelsTests {
    @Test func decodesIdeaFromTheCoreResource() throws {
        let json = """
        {"$schema":"https://vibedeck-schema.alanreisanjo.workers.dev/v1/idea.schema.json","author":"human","body":"corpo",
         "createdAt":"2026-10-22T18:10:26Z","id":"0F2B0C08-955E-4F6E-B623-F3FE84945A9D","rules":[],"status":"new","title":"Ideia teste",
         "updatedAt":"2026-10-22T18:10:26Z"}
        """
        let idea = try CoreStore.decode(Idea.self, from: json, what: "idea")
        #expect(idea.title == "Ideia teste" && idea.status == .new && idea.author == .human)
    }

    @Test func projectRoundTripsWithoutCloudField() throws {
        let project = Project(name: "App")
        let text = try CoreStore.encodeString(project)
        #expect(!text.contains("codexCloudEnvironment"))
        let back = try CoreStore.decode(Project.self, from: text, what: "project")
        #expect(back == project)
    }

    @Test func groupPathsAreValidated() throws {
        #expect(try CoreStore.normalizedGroupPath("Minha Pasta/Sub Grupo") == "minha-pasta/sub-grupo")
        #expect(throws: (any Error).self) { try CoreStore.normalizedGroupPath("../fora") }
        #expect(throws: (any Error).self) { try CoreStore.normalizedGroupPath("") }
        #expect(try CoreStore.normalizedGroupPath("", allowRoot: true) == "")
        #expect(CoreStore.groupPath(of: "a/b/c") == "a/b")
    }

    @Test func attachmentLinksFollowTheRecordDepth() {
        let text = "![x](../attachments/a.png)"
        #expect(CoreStore.markdownForGroupedRecord(text, reference: "pasta/doc") == "![x](../../attachments/a.png)")
        #expect(CoreStore.markdownForGroupedRecord(text, reference: "doc") == text)
    }

    @Test func remoteRootsRoundTripThroughTheURL() throws {
        let destination = try SSHDestination(host: "exemplo.com", port: 2222, user: "ana", directory: "/srv/app")
        let url = RemoteWorkspace.rootURL(for: destination)
        let back = try #require(RemoteWorkspace.existing(at: url))
        #expect(back.destination.host == "exemplo.com" && back.destination.port == 2222 && back.destination.directory == "/srv/app")
        #expect(RemoteWorkspace.existing(at: URL(fileURLWithPath: "/tmp")) == nil)
    }

    @Test func reconnectBackoffGrowsUpToSixtySeconds() {
        let delays = (0..<9).map { RemoteBackoff.delay(attempt: $0) }
        #expect(delays == [1, 2, 4, 8, 16, 32, 60, 60, 60])
    }

    @Test func remoteCacheRoundTrips() throws {
        let cache = RemoteCache(savedAt: Date(timeIntervalSince1970: 1_700_000_000), project: Project(name: "Remoto"), docs: [],
                                groups: [], topics: [], ideas: [], agents: [], commands: [], skills: [], workflows: [],
                                runs: [], checks: [], docTexts: ["a": "# A"])
        let data = try VDJSON.compactEncoder.encode(cache)
        let back = try VDJSON.decoder.decode(RemoteCache.self, from: data)
        #expect(back.project == cache.project && back.docTexts == cache.docTexts)
        #expect(back.snapshot.project.name == "Remoto")
    }

    @Test func patternCatalogDecodesTheCoreRows() throws {
        let json = """
        [{"id":"tdd","name":"TDD","category":"practices","summary":"Teste primeiro","rules":["Teste antes"],"inProject":false,"aliases":["test first"]}]
        """
        let rows = try CoreStore.decode([PatternCatalogEntry].self, from: json, what: "pattern_catalog")
        #expect(rows.count == 1 && rows[0].id == "tdd" && rows[0].rules == ["Teste antes"] && !rows[0].inProject)
    }
}
