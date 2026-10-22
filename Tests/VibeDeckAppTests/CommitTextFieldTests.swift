import AppKit
import SwiftUI
import Testing
@testable import VibeDeckApp

@Suite(.serialized) @MainActor struct CommitTextFieldTests {
    enum Exit: CaseIterable { case returnKey, blur, switchItem, switchScreen, closeInspector, closeWindow, quitApp }

    @Test(arguments: Exit.allCases, [Axis.horizontal, .vertical])
    func detailsPersistAfterLeavingEditor(exit: Exit, axis: Axis) async throws {
        let fixture = try Fixture(axis: axis)
        defer { fixture.close() }
        await fixture.render()
        let field = try #require(fixture.field())
        #expect(fixture.window.makeFirstResponder(field))
        await fixture.render()
        let editor = try #require(fixture.window.firstResponder as? NSTextView)
        editor.string = "  Detalhes editados\nsegunda linha  "
        editor.didChangeText()
        await fixture.render()
        #expect(try fixture.store.loadGroup(fixture.slug).items[0].details == "Original")

        switch exit {
        case .returnKey:
            // Send the same action the native text field dispatches on Return.
            _ = field.sendAction(field.action, to: field.target)
        case .blur:
            fixture.window.makeFirstResponder(nil)
        case .switchItem:
            fixture.state.itemIndex = 1
        case .switchScreen:
            fixture.state.onReviewScreen = false
        case .closeInspector:
            fixture.state.inspectorShown = false
        case .closeWindow:
            fixture.window.close()
        case .quitApp:
            // What AppDelegate.applicationWillTerminate posts on ⌘Q.
            NotificationCenter.default.post(name: .vibedeckFlushPendingSaves, object: nil)
        }
        await fixture.render()
        #expect(try fixture.store.loadGroup(fixture.slug).items[0].details == "Detalhes editados\nsegunda linha")
        #expect(try fixture.store.loadGroup(fixture.slug).items[1].details == "Outro item")
        let reopened = ProjectModel(store: fixture.store)
        #expect(reopened.group(fixture.slug)?.items[0].details == "Detalhes editados\nsegunda linha")
        let json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: fixture.store.groupURL(fixture.slug))) as? [String: Any])
        let items = try #require(json["items"] as? [[String: Any]])
        #expect(items[0]["details"] as? String == "Detalhes editados\nsegunda linha")

        // A second exit after Return/blur must not commit the same draft again.
        if exit == .closeWindow { fixture.window.makeKeyAndOrderFront(nil) }
        NotificationCenter.default.post(name: .vibedeckFlushPendingSaves, object: nil)
        fixture.state.inspectorShown = false
        await fixture.render()
        #expect(fixture.state.commits == 1)
        fixture.state.itemIndex = 0
        fixture.state.onReviewScreen = true
        fixture.state.inspectorShown = true
        await fixture.render()
        #expect(fixture.field()?.stringValue == "Detalhes editados\nsegunda linha")
        #expect(fixture.state.commits == 1)
    }

    @Test func returnThenImmediateBlurAndRemovalCommitsOnce() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        await fixture.render()
        try await fixture.type("Confirmado")
        let field = try #require(fixture.field())
        _ = field.sendAction(field.action, to: field.target)
        fixture.window.makeFirstResponder(nil)
        fixture.state.inspectorShown = false
        await fixture.render()
        #expect(fixture.state.commits == 1)
        #expect(try fixture.store.loadGroup(fixture.slug).items[0].details == "Confirmado")
        fixture.undo.undo()
        #expect(try fixture.store.loadGroup(fixture.slug).items[0].details == "Original")
        #expect(!fixture.undo.canUndo)
    }

    @Test(arguments: ["", " \n\t "])
    func clearingDetailsPersistsAndSupportsUndoRedo(text: String) async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        await fixture.render()
        try await fixture.type(text)
        fixture.state.inspectorShown = false
        await fixture.render()
        #expect(try fixture.store.loadGroup(fixture.slug).items[0].details == nil)
        #expect(ProjectModel(store: fixture.store).group(fixture.slug)?.items[0].details == nil)
        fixture.undo.undo()
        #expect(try fixture.store.loadGroup(fixture.slug).items[0].details == "Original")
        #expect(!fixture.undo.canUndo)
        fixture.undo.redo()
        #expect(try fixture.store.loadGroup(fixture.slug).items[0].details == nil)
        fixture.state.inspectorShown = true
        await fixture.render()
        #expect(fixture.field()?.stringValue == "")
    }

    @Test func undoRedoRefreshesEditorWithoutResavingOldDraft() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        await fixture.render()
        try await fixture.type("Novo texto")
        fixture.window.makeFirstResponder(nil)
        await fixture.render()
        fixture.undo.undo()
        await fixture.render()
        #expect(fixture.field()?.stringValue == "Original")
        #expect(try fixture.store.loadGroup(fixture.slug).items[0].details == "Original")
        fixture.undo.redo()
        await fixture.render()
        #expect(fixture.field()?.stringValue == "Novo texto")
        fixture.state.onReviewScreen = false
        await fixture.render()
        #expect(fixture.state.commits == 1)
        #expect(try fixture.store.loadGroup(fixture.slug).items[0].details == "Novo texto")
        #expect(ProjectModel(store: fixture.store).group(fixture.slug)?.items[0].details == "Novo texto")
    }

    @Test func unchangedEditorDoesNotWriteOrRegisterUndo() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let original = try Data(contentsOf: fixture.store.groupURL(fixture.slug))
        await fixture.render()
        fixture.state.inspectorShown = false
        await fixture.render()
        #expect(fixture.state.commits == 0)
        #expect(!fixture.undo.canUndo)
        #expect(try Data(contentsOf: fixture.store.groupURL(fixture.slug)) == original)
    }

    @MainActor @Observable class Screen {
        var itemIndex = 0
        var onReviewScreen = true
        var inspectorShown = true
        var commits = 0
    }

    private struct ScreenView: View {
        let model: ProjectModel
        let slug: String
        let state: Screen
        let undo: UndoManager
        let axis: Axis
        var body: some View {
            VStack {
                if state.onReviewScreen && state.inspectorShown,
                   let group = model.group(slug) {
                    let item = group.items[state.itemIndex]
                    CommitTextField(control: "test.details", "Detalhes", value: item.details ?? "", axis: axis) { text in
                        state.commits += 1
                        undo.beginUndoGrouping()
                        model.mutateItem(slug, item.id, "Editar detalhes", undo: undo) {
                            $0.details = text.isEmpty ? nil : text
                        }
                        undo.endUndoGrouping()
                    }
                    .id(item.id)
                }
                Text("Outra tela")
            }.padding().frame(width: 400, height: 240)
        }
    }

    @MainActor private class Fixture {
        let root: URL
        let store: CoreStore
        let model: ProjectModel
        let slug: String
        let state = Screen()
        let undo = UndoManager()
        let window: NSWindow
        let host: NSHostingView<ScreenView>

        init(axis: Axis = .vertical) throws {
            root = FileManager.default.temporaryDirectory.appending(path: "commit-field-\(UUID())")
            store = try CoreStore.initialize(at: root)
            let created = try store.createGroup(title: "Revisão")
            slug = created.slug
            var group = created.group
            group.items = [ReviewItem(kind: "note", title: "Primeiro", details: "Original"),
                           ReviewItem(kind: "note", title: "Segundo", details: "Outro item")]
            try store.saveGroup(group, slug: slug)
            model = ProjectModel(store: store)
            undo.groupsByEvent = false
            host = NSHostingView(rootView: ScreenView(model: model, slug: slug, state: state, undo: undo, axis: axis))
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 240),
                              styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.makeKeyAndOrderFront(nil)
        }

        func render() async {
            host.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(80))
            host.layoutSubtreeIfNeeded()
        }

        func type(_ text: String) async throws {
            // Distinct name: a local `field` would shadow `field()` inside the #require expansion.
            let textField = try #require(field())
            #expect(window.makeFirstResponder(textField))
            await render()
            let editor = try #require(window.firstResponder as? NSTextView)
            editor.string = text
            editor.didChangeText()
            await render()
        }

        func field() -> NSTextField? {
            func find(_ view: NSView) -> NSTextField? {
                if let field = view as? NSTextField, field.isEditable { return field }
                return view.subviews.lazy.compactMap(find).first
            }
            return find(host)
        }

        func close() {
            window.close()
            try? FileManager.default.removeItem(at: root)
        }
    }
}
