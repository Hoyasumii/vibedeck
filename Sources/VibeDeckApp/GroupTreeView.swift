import SwiftUI
import VibeDeckCore

extension SidebarSection {
    var groupedConcept: ItemConcept? {
        switch self { case .docs: .docs; case .ideas: .ideas; case .groups: .reviews; case .skills: .skills; default: nil }
    }
}

extension SidebarItem {
    var groupedReference: String? {
        switch self { case .doc(let ref), .idea(let ref), .group(let ref), .skill(let ref): ref; default: nil }
    }
    static func grouped(_ concept: ItemConcept, reference: String) -> SidebarItem {
        switch concept { case .docs: .doc(reference); case .ideas: .idea(reference); case .reviews: .group(reference); case .skills: .skill(reference) }
    }
}

/// The same group tree is used in the sidebar and the section list. Directory entries include empty groups.
struct GroupTreeView: View {
    let concept: ItemConcept
    let rows: [SectionRow]
    let filtering: Bool
    let onOpen: (SidebarItem) -> Void
    let onOpenInNewTab: (SidebarItem) -> Void
    @Environment(ProjectModel.self) private var model
    @Environment(\.undoManager) private var undo
    @Environment(\.logProject) private var logProject
    @State private var expanded = Set<String>()
    @State private var prompt: GroupPrompt?
    @State private var deleting: String?
    @State private var editingTags: SectionRow?

    private struct GroupPrompt: Identifiable {
        var path: String
        var rename: Bool
        var item = false
        var id: String { path + String(rename) }
    }
    private var groups: [String] {
        let all = model.directoryGroups[concept] ?? []
        guard filtering else { return all }
        return all.filter { group in rows.contains { ($0.id.groupedReference ?? "").hasPrefix(group + "/") } }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label("Raiz", systemImage: "folder")
                .foregroundStyle(.secondary)
                .dropDestination(for: String.self) { values, _ in return drop(values, into: "") }
                .contextMenu {
                    LoggedButton("Novo item…") { prompt = .init(path: "", rename: false, item: true) }.loggedControl(control: "group_tree.new_item_root", label: "Novo item")
                    LoggedButton("Novo grupo…") { prompt = .init(path: "", rename: false) }
                        .loggedControl(control: "group_tree.new_root", label: "Novo grupo")
                }
            branch("")
        }
        .sheet(item: $prompt) { p in
            NamePromptSheet(title: p.item ? "Novo item" : p.rename ? "Renomear grupo" : "Novo grupo", placeholder: p.item ? "Título do item" : "Nome do grupo") { name in
                let parent = p.rename ? ProjectStore.groupPath(of: p.path) : p.path
                let target = (parent.isEmpty ? "" : parent + "/") + name
                if p.item {
                    let ref = (p.path.isEmpty ? "" : p.path + "/") + Slug.make(name)
                    let created: String?
                    switch concept {
                    case .docs: created = model.createDoc(title: name, reference: ref)
                    case .ideas: created = model.createIdea(title: name, reference: ref)
                    case .reviews: created = model.createGroup(title: name, reference: ref)
                    case .skills: created = model.createSkill(title: name, reference: ref)
                    }
                    if let created { onOpen(.grouped(concept, reference: created)) }
                } else if p.rename { model.moveDirectoryGroup(concept, from: p.path, to: target, undo: undo) }
                else { model.createDirectoryGroup(concept, path: target, undo: undo) }
            }
        }
        .sheet(item: $editingTags) { row in
            TagsEditor(title: row.title, tags: row.tags) { model.setTags($0, for: row.id, undo: undo) }
        }
        .confirmationDialog("Apagar grupo e todos os seus itens?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            LoggedButton("Apagar grupo", role: .destructive) {
                if let path = deleting { model.deleteDirectoryGroup(concept, path: path, confirmed: true, undo: undo) }
                deleting = nil
            }.loggedControl(control: "group_tree.confirm_delete", label: "Apagar grupo")
        } message: { Text("Os itens de todos os subgrupos, inclusive de autoria humana, serão apagados.") }
    }

    private func branch(_ parent: String) -> AnyView {
        AnyView(VStack(alignment: .leading, spacing: 3) {
            ForEach(groups.filter { ProjectStore.groupPath(of: $0) == parent }, id: \.self) { group in
                VStack(alignment: .leading, spacing: 3) {
                    let isExpanded = filtering || expanded.contains(group)
                    LoggedButton {
                        if expanded.contains(group) { expanded.remove(group) } else { expanded.insert(group) }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Label(String(group.split(separator: "/").last ?? ""), systemImage: "folder")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                        .loggedControl(control: "group_tree.toggle", label: "Expandir ou recolher pasta")
                        .buttonStyle(.borderless)
                        .accessibilityLabel(String(group.split(separator: "/").last ?? ""))
                        .accessibilityValue(isExpanded ? "Expandida" : "Recolhida")
                        .draggable("group:\(concept.rawValue):\(group)")
                        .dropDestination(for: String.self) { values, _ in return drop(values, into: group) }
                        .contextMenu {
                            LoggedButton("Novo item…") { prompt = .init(path: group, rename: false, item: true) }.loggedControl(control: "group_tree.new_item", label: "Novo item")
                            LoggedButton("Novo subgrupo…") { prompt = .init(path: group, rename: false) }.loggedControl(control: "group_tree.new_child", label: "Novo subgrupo")
                            LoggedButton("Renomear…") { prompt = .init(path: group, rename: true) }.loggedControl(control: "group_tree.rename", label: "Renomear grupo")
                            destinationMenu(group: group, item: nil)
                            LoggedButton("Apagar grupo…", role: .destructive) { deleting = group }.loggedControl(control: "group_tree.delete", label: "Apagar grupo")
                        }
                    if isExpanded { branch(group).padding(.leading, 16) }
                }
            }
            ForEach(rows.filter { ProjectStore.groupPath(of: $0.id.groupedReference ?? "") == parent }) { row in
                LoggedButton { onOpen(row.id) } label: {
                    Label { HStack { Text(row.title).foregroundStyle(row.dimmed ? .secondary : .primary); if !row.count.isEmpty { Text(row.count).foregroundStyle(.secondary).font(.caption) } } } icon: { Image(systemName: row.symbol) }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                    .loggedControl(control: "group_tree.open", label: "Abrir item")
                    .buttonStyle(.borderless)
                    .tag(row.id)
                    .help([row.detail, row.tags.map { "#" + $0 }.joined(separator: " ")].filter { !$0.isEmpty }.joined(separator: " · "))
                    .draggable("item:\(concept.rawValue):\(row.id.groupedReference ?? "")")
                    .contextMenu {
                        LoggedButton("Abrir") { onOpen(row.id) }.loggedControl(control: "group_tree.open", label: "Abrir")
                        LoggedButton("Abrir em Nova Aba") { onOpenInNewTab(row.id) }.loggedControl(control: "group_tree.open_tab", label: "Abrir em Nova Aba")
                        destinationMenu(group: nil, item: row.id)
                        LoggedButton("Editar tags…") { editingTags = row }.loggedControl(control: "group_tree.tags", label: "Editar tags")
                        if case .idea(let ref) = row.id {
                            Menu("Status") {
                                ForEach(IdeaStatus.allCases, id: \.self) { status in
                                    LoggedButton(status.label) { model.mutateIdea(ref, "Alterar status", undo: undo) { $0.status = status } }.loggedControl(control: "group_tree.status", label: "Alterar status")
                                }
                            }
                        }
                        if let url = model.fileURL(for: row.id) {
                            LoggedButton("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }.loggedControl(control: "group_tree.finder", label: "Mostrar no Finder")
                        }
                        LoggedButton("Mover para o Lixo", role: .destructive) {
                            switch row.id {
                            case .doc(let ref): model.deleteDoc(ref)
                            case .idea(let ref): model.deleteIdea(ref)
                            case .group(let ref): model.deleteGroup(ref)
                            case .skill(let ref): model.deleteSkill(ref)
                            default: break
                            }
                        }.loggedControl(control: "group_tree.trash", label: "Mover para o Lixo")
                    }
            }
        })
    }

    private func destinationMenu(group: String?, item: SidebarItem?) -> some View {
        Menu("Mover para") {
            ForEach([""] + (model.directoryGroups[concept] ?? []), id: \.self) { destination in
                if group == nil || (destination != group! && !destination.hasPrefix(group! + "/")) {
                    LoggedButton(destination.isEmpty ? "Raiz" : destination) {
                        if let item { model.moveGroupedItem(item, to: destination, undo: undo) }
                        else if let group {
                            let leaf = String(group.split(separator: "/").last!)
                            model.moveDirectoryGroup(concept, from: group, to: (destination.isEmpty ? "" : destination + "/") + leaf, undo: undo)
                        }
                    }.loggedControl(control: "group_tree.move", label: "Mover para grupo")
                }
            }
        }
    }

    private func drop(_ values: [String], into destination: String) -> Bool {
        guard values.count == 1 else { return false }
        let parts = values[0].split(separator: ":", maxSplits: 2).map(String.init)
        guard parts.count == 3, parts[1] == concept.rawValue else { return false }
        if parts[0] == "item" {
            model.moveGroupedItem(.grouped(concept, reference: parts[2]), to: destination, undo: undo)
        } else if parts[0] == "group" {
            let source = parts[2]
            guard destination != source, !destination.hasPrefix(source + "/") else { return false }
            let leaf = String(source.split(separator: "/").last!)
            model.moveDirectoryGroup(concept, from: source, to: (destination.isEmpty ? "" : destination + "/") + leaf, undo: undo)
        } else { return false }
        return true
    }
}

struct ItemGroupDestinationPicker: View {
    let concept: ItemConcept
    @Binding var selection: String
    @Environment(ProjectModel.self) private var model
    @Environment(\.logProject) private var logProject
    var body: some View {
        Picker("Grupo de destino", selection: $selection.logging(control: "group_destination.selection", label: "Grupo de destino", project: logProject)) {
            Text("Raiz").tag("")
            ForEach(model.directoryGroups[concept] ?? [], id: \.self) { Text($0).tag($0) }
        }
    }
}
