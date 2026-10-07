import SwiftUI
import VibeDeckCore

struct ProjectWindow: View {
    @State private var model: ProjectModel
    @State private var selection: SidebarItem?
    @State private var newName: NewNamePrompt?

    init(root: URL) {
        _model = State(initialValue: ProjectModel(store: ProjectStore(root: root)))
    }

    enum NewNamePrompt: Identifiable {
        case doc, group
        var id: Self { self }
        var title: String { self == .doc ? "Novo documento" : "Novo grupo de revisão" }
        var placeholder: String { self == .doc ? "Título do documento" : "Tema (ex.: Tela de login)" }
    }

    private var selectionKey: String { "selection.\(model.project.id.uuidString)" }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            detail
        }
        .environment(model)
        .task {
            model.startWatching()
            selection = SidebarItem(storageKey: UserDefaults.standard.string(forKey: selectionKey)) ?? .links
        }
        .onChange(of: selection) { _, new in
            UserDefaults.standard.set(new?.storageKey, forKey: selectionKey)
        }
        .onDisappear { model.stopWatching() }
        .sheet(item: $newName) { prompt in
            NamePromptSheet(title: prompt.title, placeholder: prompt.placeholder) { name in
                switch prompt {
                case .doc: if let slug = model.createDoc(title: name) { selection = .doc(slug) }
                case .group: if let slug = model.createGroup(title: name) { selection = .group(slug) }
                }
            }
        }
        .alert("Erro", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    private var sidebar: some View {
        List(selection: $selection) {
            Section {
                Label("Links", systemImage: "link")
                    .badge(model.project.links.count)
                    .tag(SidebarItem.links)
            }

            Section {
                ForEach(model.docs) { doc in
                    Label(doc.title, systemImage: "doc.text")
                        .tag(SidebarItem.doc(doc.slug))
                        .contextMenu {
                            Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.store.docURL(doc.slug)]) }
                            Button("Mover para o Lixo", role: .destructive) {
                                if selection == .doc(doc.slug) { selection = .links }
                                model.deleteDoc(doc.slug)
                            }
                        }
                }
            } header: {
                SectionHeader(title: "Docs") { newName = .doc }
            }

            Section {
                ForEach(model.groups) { entry in
                    Label(entry.group.title, systemImage: "checklist")
                        .badge(entry.group.openCount)
                        .tag(SidebarItem.group(entry.slug))
                        .contextMenu {
                            Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.store.groupURL(entry.slug)]) }
                            Button("Mover para o Lixo", role: .destructive) {
                                if selection == .group(entry.slug) { selection = .links }
                                model.deleteGroup(entry.slug)
                            }
                        }
                }
            } header: {
                SectionHeader(title: "Revisões") { newName = .group }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Image(systemName: "folder")
                Text(model.store.root.path(percentEncoded: false))
                    .lineLimit(1).truncationMode(.head)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onTapGesture { NSWorkspace.shared.activateFileViewerSelecting([model.store.manifestURL]) }
            .help("Mostrar vibedeck.json no Finder")
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .links, .none:
            LinksView()
        case .doc(let slug):
            if model.docs.contains(where: { $0.slug == slug }) {
                DocView(slug: slug).id(slug)
            } else {
                ContentUnavailableView("Documento não encontrado", systemImage: "doc.questionmark")
            }
        case .group(let slug):
            if model.group(slug) != nil {
                ReviewGroupView(slug: slug).id(slug)
            } else {
                ContentUnavailableView("Grupo não encontrado", systemImage: "questionmark.folder")
            }
        }
    }
}

private struct SectionHeader: View {
    let title: String
    let onAdd: () -> Void

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Button(action: onAdd) { Image(systemName: "plus") }
                .buttonStyle(.borderless)
                .help("Adicionar")
        }
    }
}

struct NamePromptSheet: View {
    let title: String
    let placeholder: String
    let onSubmit: (String) -> Void
    @State private var name = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.headline)
            TextField(placeholder, text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)
            HStack {
                Spacer()
                Button("Cancelar", role: .cancel) { dismiss() }.buttonStyle(.glass)
                Button("Criar", action: submit)
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 380)
    }

    private func submit() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onSubmit(trimmed)
        dismiss()
    }
}
