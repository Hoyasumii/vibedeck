import SwiftUI
import UniformTypeIdentifiers
import VibeDeckCore

struct LinksView: View {
    @Environment(ProjectModel.self) private var model
    @Environment(\.undoManager) private var undo
    @Environment(\.openURL) private var openURL
    @State private var selection = Set<ProjectLink.ID>()
    @State private var editing: ProjectLink?
    @State private var search = ""

    private var links: [ProjectLink] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return model.project.links }
        return model.project.links.filter {
            $0.title.localizedCaseInsensitiveContains(q) || $0.url.localizedCaseInsensitiveContains(q)
                || $0.tags.contains { $0.localizedCaseInsensitiveContains(q) }
        }
    }

    var body: some View {
        Group {
            if model.project.links.isEmpty {
                ContentUnavailableView {
                    Label("Sem links", systemImage: "link")
                } description: {
                    Text("Adicione com + ou cole uma URL (⌘V).")
                } actions: {
                    Button("Adicionar link") { editing = ProjectLink(title: "", url: "") }.buttonStyle(.glass)
                }
            } else {
                Table(links, selection: $selection) {
                    TableColumn("Título") { link in
                        Text(link.title).fontWeight(.medium)
                    }
                    TableColumn("URL") { link in
                        Text(link.url).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    TableColumn("Tags") { link in
                        TagChips(tags: link.tags)
                    }
                    .width(min: 80, ideal: 160)
                }
                .contextMenu(forSelectionType: ProjectLink.ID.self) { ids in
                    if let id = ids.first, let link = model.project.links.first(where: { $0.id == id }) {
                        Button("Abrir") { open(link) }
                        Button("Copiar URL") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(link.url, forType: .string) }
                        Button("Editar…") { editing = link }
                        Divider()
                    }
                    Button("Remover", role: .destructive) { remove(ids) }
                } primaryAction: { ids in
                    ids.compactMap { id in model.project.links.first { $0.id == id } }.forEach(open)
                }
                .onDeleteCommand { remove(selection) }
            }
        }
        .navigationTitle("Links")
        .searchable(text: $search, placement: .toolbar, prompt: "Filtrar links")
        .toolbar {
            ToolbarItem {
                Button { editing = ProjectLink(title: "", url: "") } label: { Label("Novo link", systemImage: "plus") }
            }
        }
        .onPasteCommand(of: [.url, .plainText]) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: NSString.self) { string, _ in
                    guard let text = (string as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                          let url = URL(string: text), url.scheme?.hasPrefix("http") == true else { return }
                    Task { @MainActor in
                        add(ProjectLink(title: url.host() ?? text, url: text))
                    }
                }
            }
        }
        .sheet(item: $editing) { link in
            LinkEditor(link: link) { saved in
                if model.project.links.contains(where: { $0.id == saved.id }) {
                    model.mutateProject("Editar link", undo: undo) { p in
                        if let i = p.links.firstIndex(where: { $0.id == saved.id }) { p.links[i] = saved }
                    }
                } else {
                    add(saved)
                }
            }
        }
    }

    private func open(_ link: ProjectLink) {
        if let url = URL(string: link.url) { openURL(url) }
    }

    private func add(_ link: ProjectLink) {
        model.mutateProject("Adicionar link", undo: undo) { $0.links.append(link) }
    }

    private func remove(_ ids: Set<ProjectLink.ID>) {
        guard !ids.isEmpty else { return }
        model.mutateProject("Remover link", undo: undo) { $0.links.removeAll { ids.contains($0.id) } }
        selection.subtract(ids)
    }
}

struct TagChips: View {
    let tags: [String]
    /// When set, chips are clickable (e.g. to filter by that tag).
    var onTap: ((String) -> Void)? = nil

    var body: some View {
        GlassEffectContainer(spacing: 4) {
            HStack(spacing: 4) {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .glassEffect(onTap == nil ? .regular : .regular.interactive(), in: .capsule)
                        .onTapGesture { onTap?(tag) }
                        .help(onTap == nil ? "" : "Filtrar por #\(tag)")
                }
            }
        }
    }
}

/// Comma-separated tag editor in a glass capsule; commits on submit/blur.
struct TagsField: View {
    let tags: [String]
    let onCommit: ([String]) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "number").foregroundStyle(.secondary)
            CommitTextField("tags, separadas, por vírgula", value: tags.joined(separator: ", ")) { text in
                onCommit(Tags.parse(text))
            }
            .textFieldStyle(.plain)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .glassEffect(.regular, in: .capsule)
        .frame(minWidth: 180, maxWidth: 360)
    }
}

enum Tags {
    static func parse(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

private struct LinkEditor: View {
    @State var link: ProjectLink
    let onSave: (ProjectLink) -> Void
    @State private var tagsText = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            TextField("URL", text: $link.url)
            TextField("Título", text: $link.title)
            TextField("Tags (separadas por vírgula)", text: $tagsText)
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .onAppear { tagsText = link.tags.joined(separator: ", ") }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Salvar") {
                    var saved = link
                    saved.url = saved.url.trimmingCharacters(in: .whitespaces)
                    if saved.title.trimmingCharacters(in: .whitespaces).isEmpty {
                        saved.title = URL(string: saved.url)?.host() ?? saved.url
                    }
                    saved.tags = Tags.parse(tagsText)
                    onSave(saved)
                    dismiss()
                }
                .disabled(link.url.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}
