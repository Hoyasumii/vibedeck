import MarkdownUI
import SwiftUI
import VibeDeckCore

struct DocView: View {
    let slug: String
    @Environment(ProjectModel.self) private var model
    @State private var text = ""
    @State private var savedText = ""
    @State private var loaded = false
    @State private var saveTask: Task<Void, Never>?
    @State private var conflict: String?
    @AppStorage("docViewMode") private var mode: Mode = .edit

    enum Mode: String, CaseIterable {
        case edit, split, read
        var label: String { ["edit": "Editar", "split": "Dividir", "read": "Ler"][rawValue]! }
        var symbol: String { ["edit": "pencil", "split": "rectangle.split.2x1", "read": "book"][rawValue]! }
    }

    private var isDirty: Bool { text != savedText }

    var body: some View {
        content
            .navigationTitle(model.docs.first { $0.slug == slug }?.title ?? slug)
            .navigationSubtitle(isDirty ? "Editando…" : "Salvo")
            .toolbar {
                ToolbarItem {
                    Picker("Modo", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { m in
                            Label(m.label, systemImage: m.symbol).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .help("Editar / Dividir / Ler (⌘E alterna)")
                }
            }
            .background {
                Button("") { mode = mode == .read ? .edit : .read }
                    .keyboardShortcut("e")
                    .hidden()
            }
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
            .onChange(of: text) { _, _ in scheduleSave() }
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
        MarkdownEditor(text: $text, undoManager: model.undoManager(forDoc: slug))
    }

    private var preview: some View {
        ScrollView {
            Markdown(text)
                .markdownTheme(.gitHub)
                .textSelection(.enabled)
                .padding(28)
                .frame(maxWidth: 820, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Persistence

    private func load() {
        guard !loaded else { return }
        text = model.readDoc(slug)
        savedText = text
        loaded = true
    }

    private func scheduleSave() {
        guard loaded, isDirty else { return }
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            save()
        }
    }

    private func save() {
        guard conflict == nil else { return }
        model.saveDoc(slug, text: text)
        savedText = text
    }

    private func flush() {
        saveTask?.cancel()
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
