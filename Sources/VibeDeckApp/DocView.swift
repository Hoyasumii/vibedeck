import SwiftUI
import VibeDeckCore

struct DocView: View {
    let slug: String
    @Environment(ProjectModel.self) private var model
    @State private var text = ""
    @State private var savedText = ""
    @State private var loaded = false
    @State private var conflict: String?
    @State private var insertion: MarkdownInsertion?
    @AppStorage("docViewMode") private var mode: MarkdownViewMode = .edit

    private var isDirty: Bool { text != savedText }

    var body: some View {
        content
            .navigationTitle(model.docs.first { $0.slug == slug }?.title ?? slug)
            .navigationSubtitle(isDirty ? "Editando…" : "Salvo")
            .toolbar {
                ToolbarItem { AttachButton(onPick: attach) }
                ToolbarItem { MarkdownModePicker(mode: $mode) }
            }
            .markdownModeShortcut($mode)
            .safeAreaInset(edge: .top) {
                if let conflict {
                    ConflictBanner {
                        text = conflict
                        savedText = conflict
                        self.conflict = nil
                    } keep: {
                        self.conflict = nil
                        save()
                    }
                }
            }
            .onAppear(perform: load)
            .onChange(of: text) { _, _ in saveIfNeeded() }
            .onChange(of: model.externalDocChange[slug]) { _, _ in handleExternalChange() }
            .onDisappear(perform: flush)
            .onReceive(NotificationCenter.default.publisher(for: .vibedeckFlushPendingSaves)) { _ in flush() }
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .edit:
            editor
        case .read:
            preview
        case .split:
            HSplitView {
                editor.frame(minWidth: 280)
                preview.frame(minWidth: 280)
            }
        }
    }

    private var editor: some View {
        MarkdownEditor(
            text: $text,
            undoManager: model.undoManager(forDoc: slug),
            baseURL: model.store.docsDir,
            importFiles: { model.importAttachments($0, owner: slug) },
            importImage: { model.importAttachment(data: $0, name: "colagem-\(Date.now.formatted(.iso8601)).png", owner: slug) },
            insertion: insertion
        )
    }

    private var preview: some View {
        MarkdownPreview(text: text, baseURL: model.store.docsDir)
    }

    /// Files from the "Anexar" button go in through the editor (so ⌘Z undoes them): at the cursor, or
    /// at the end after opening the editor beside the preview when only the preview is showing.
    private func attach(_ urls: [URL]) {
        let links = model.importAttachments(urls, owner: slug).joined(separator: "\n")
        guard !links.isEmpty else { return }
        guard mode == .read else { return insertion = MarkdownInsertion(text: links) }
        mode = .split
        DispatchQueue.main.async { insertion = MarkdownInsertion(text: links, atEnd: true) }
    }

    // MARK: Persistence

    private func load() {
        guard !loaded else { return }
        text = model.readDoc(slug)
        savedText = text
        loaded = true
    }

    private func saveIfNeeded() {
        guard loaded, isDirty else { return }
        save()
    }

    private func save() {
        guard conflict == nil else { return }
        model.saveDoc(slug, text: text)
        savedText = text
    }

    private func flush() {
        if isDirty { save() }
    }

    private func handleExternalChange() {
        let disk = model.readDoc(slug)
        guard disk != savedText, disk != text else { return }
        if isDirty {
            conflict = disk
        } else {
            savedText = disk
            text = disk
        }
    }
}

private struct ConflictBanner: View {
    let reload: () -> Void
    let keep: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
            Text("Este documento foi alterado fora do app enquanto você editava.")
            Spacer()
            Button("Recarregar do disco", action: reload).buttonStyle(.glass)
            Button("Manter minha versão", action: keep).buttonStyle(.glassProminent)
        }
        .padding(12)
        .glassEffect(.regular.tint(.orange.opacity(0.25)), in: .rect(cornerRadius: 14))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}
