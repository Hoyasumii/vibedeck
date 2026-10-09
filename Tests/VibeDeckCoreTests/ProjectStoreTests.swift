import Foundation
import Testing
@testable import VibeDeckCore

private func tempDir() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "vibedeck-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Suite struct ProjectStoreTests {
    @Test func initAndDetect() throws {
        let dir = try tempDir()
        #expect(!ProjectStore.isProject(dir))
        let store = try ProjectStore.initialize(at: dir, name: "Demo")
        #expect(ProjectStore.isProject(dir))
        #expect(FileManager.default.fileExists(atPath: store.agentsURL.path))
        let nested = dir.appending(path: "src/components")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        #expect(ProjectStore.find(from: nested)?.root.path == store.root.path)
        #expect(throws: VibeDeckError.alreadyAProject(store.root.path)) { try ProjectStore.initialize(at: dir) }
        let project = try store.loadProject()
        #expect(project.name == "Demo")
        #expect(project.reviewKinds == ReviewKind.defaults)
        #expect(project.schema == SchemaURL.project)
    }

    @Test func projectRoundTrip() throws {
        let store = try ProjectStore.initialize(at: tempDir())
        try store.updateProject { $0.links.append(Link(title: "Figma", url: "https://figma.com/x", tags: ["design"])) }
        let raw = try String(contentsOf: store.manifestURL, encoding: .utf8)
        #expect(raw.contains("\"$schema\""))
        #expect(raw.contains("https://figma.com/x"))
        #expect(try store.loadProject().links.first?.tags == ["design"])
    }

    @Test func lenientDecodingOfHandWrittenFiles() throws {
        let store = try ProjectStore.initialize(at: tempDir())
        let handWritten = #"{"title":"Feito pela IA","items":[{"title":"Esconder banner","kind":"hide","createdAt":"2026-10-07T12:00:00.123Z"}]}"#
        try Data(handWritten.utf8).write(to: store.groupURL("ia"))
        let group = try store.loadGroup("ia")
        #expect(group.items.count == 1)
        #expect(group.items[0].status == .open)
        #expect(group.items[0].priority == .normal)
    }

    @Test func docs() throws {
        let store = try ProjectStore.initialize(at: tempDir())
        let slug = try store.createDoc(title: "Visão Geral")
        #expect(slug == "visao-geral")
        #expect(try store.createDoc(title: "Visão Geral") == "visao-geral-2")
        try store.writeDoc(slug, "---\ntitle: Overview\n---\nbody")
        #expect(try store.listDocs().map(\.title).contains("Overview"))
        #expect(try store.readDoc(slug).hasSuffix("body"))
        try store.deleteDoc(slug)
        #expect(throws: VibeDeckError.docNotFound(slug)) { try store.readDoc(slug) }
    }

    @Test func attachments() throws {
        let store = try ProjectStore.initialize(at: tempDir())
        let source = try tempDir().appending(path: "Tela Inicial.PNG")
        try Data("img".utf8).write(to: source)
        #expect(try store.importAttachment(from: source, owner: "visao-geral") == "![Tela Inicial.PNG](../attachments/visao-geral-tela-inicial.png)")
        #expect(try store.importAttachment(from: source, owner: "visao-geral") == "![Tela Inicial.PNG](../attachments/visao-geral-tela-inicial-2.png)")
        #expect(FileManager.default.contents(atPath: store.attachmentsDir.appending(path: "visao-geral-tela-inicial.png").path) == Data("img".utf8))
        #expect(try store.importAttachment(data: Data("pdf".utf8), name: "spec [v2].pdf", owner: "ideia") == "[spec (v2).pdf](../attachments/ideia-spec-v2.pdf)")
        #expect(try store.importAttachment(data: Data(), name: "Makefile", owner: "ideia") == "[Makefile](../attachments/ideia-makefile)")
    }

    @Test func reviewGroupsAndItems() throws {
        let store = try ProjectStore.initialize(at: tempDir())
        let (slug, _) = try store.addItem(ReviewItem(kind: "disable", title: "Inativar botão salvar"), toGroup: "Tela de Login")
        #expect(slug == "tela-de-login")
        try store.addItem(ReviewItem(kind: "hide", title: "Ocultar banner", author: .ai), toGroup: "tela de login")
        let group = try store.loadGroup(slug)
        #expect(group.items.map(\.kind) == ["disable", "hide"])
        #expect(try store.listGroups().count == 1)

        let id = group.items[1].id.uuidString
        let updated = try store.updateItem(String(id.prefix(8))) { $0.status = .done }
        #expect(updated.status == .done)
        #expect(try store.loadGroup(slug).openCount == 1)

        try store.deleteItem(id)
        #expect(try store.loadGroup(slug).items.count == 1)
        #expect(throws: VibeDeckError.itemNotFound(id)) { try store.findItem(id) }
    }

    @Test func slugs() {
        #expect(Slug.make("Ação: Inativar Botão!") == "acao-inativar-botao")
        #expect(Slug.make("   ") == "untitled")
    }

    @Test func markdownTitle() {
        #expect(Markdown.title(of: "# Hello\ntext") == "Hello")
        #expect(Markdown.title(of: "---\ntitle: \"Front\"\n---\n# Heading") == "Front")
        #expect(Markdown.title(of: "no heading") == nil)
    }

    @Test func markdownTags() {
        #expect(Markdown.tags(of: "# Hello") == [])
        #expect(Markdown.tags(of: "---\ntags: [ui, \"api\"]\n---\n# H") == ["ui", "api"])
        #expect(Markdown.tags(of: "---\ntitle: T\ntags: a, b\n---\n") == ["a", "b"])

        let added = Markdown.settingTags(["x", "y"], in: "# Doc\n\nbody")
        #expect(added == "---\ntags: [x, y]\n---\n# Doc\n\nbody")
        #expect(Markdown.tags(of: added) == ["x", "y"])
        #expect(Markdown.title(of: added) == "Doc")

        let replaced = Markdown.settingTags(["z"], in: "---\ntitle: Front\ntags: [x]\n---\n# H")
        #expect(replaced == "---\ntitle: Front\ntags: [z]\n---\n# H")
        #expect(Markdown.settingTags([], in: replaced) == "---\ntitle: Front\n---\n# H")
        #expect(Markdown.settingTags([], in: added) == "# Doc\n\nbody")
    }

    @Test func tagsOnGroupsTopicsAndDocs() throws {
        let store = try ProjectStore.initialize(at: tempDir())
        let (group, _) = try store.createGroup(title: "Login")
        #expect(!(try String(contentsOf: store.groupURL(group), encoding: .utf8)).contains("tags"))
        try store.updateGroup(group) { $0.tags = ["ui"] }
        #expect(try store.loadGroup(group).tags == ["ui"])

        let (topic, _) = try store.createTopic(title: "API", tags: ["backend"])
        #expect(try store.loadTopic(topic).tags == ["backend"])

        let doc = try store.createDoc(title: "Sobre", body: "texto")
        try store.setDocTags(doc, ["intro"])
        #expect(try store.listDocs().first?.tags == ["intro"])
        #expect(try store.readDoc(doc).hasSuffix("# Sobre\n\ntexto"))
    }
    @Test func commitsIdeaRemovalAlone() throws {
        let store = try ProjectStore.initialize(at: tempDir())
        func git(_ args: String...) -> Git.Output { Git.run(args, in: store.root) }
        #expect(git("init", "--quiet").ok)
        for (key, value) in [("user.name", "T"), ("user.email", "t@t"), ("commit.gpgsign", "false")] {
            #expect(git("config", key, value).ok)
        }
        let (slug, _) = try store.createIdea(title: "Velha ideia")
        try Data("x".utf8).write(to: store.root.appending(path: "other.txt"))
        #expect(git("add", "-A").ok)
        #expect(git("commit", "--quiet", "-m", "init").ok)
        try Data("y".utf8).write(to: store.root.appending(path: "other.txt"))
        #expect(git("add", "other.txt").ok)

        #expect(!store.commitIdeaRemoval("nunca-rastreada", title: "x"))
        try store.deleteIdea(slug)
        #expect(store.commitIdeaRemoval(slug, title: "Velha ideia"))
        #expect(git("log", "-1", "--format=%s").stdout == "chore(ideas): remove \"Velha ideia\"\n")
        #expect(git("show", "--name-status", "--format=", "HEAD").stdout == "D\t.vibedeck/ideas/\(slug).json\n")
        #expect(git("diff", "--cached", "--name-only").stdout == "other.txt\n")
    }
}
