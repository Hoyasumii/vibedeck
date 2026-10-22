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
}
