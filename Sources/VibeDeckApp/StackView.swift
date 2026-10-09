import SwiftUI
import UniformTypeIdentifiers
import VibeDeckCore

/// pt-BR labels for the Skill Icons categories.
enum StackCategory {
    static func label(_ id: String?) -> String {
        switch id {
        case "language": "Linguagens"
        case "frontend": "Frontend"
        case "backend": "Backend"
        case "database": "Bancos de dados"
        case "cloud": "Nuvem"
        case "devops": "DevOps"
        case "tooling": "Ferramentas"
        case "testing": "Testes"
        case "observability": "Observabilidade"
        case "auth": "Autenticação"
        case "ide": "IDEs"
        case "ai": "IA"
        case "design": "Design"
        case "game": "Jogos"
        case "payments": "Pagamentos"
        case "os": "Sistemas"
        case "social": "Social"
        case "productivity": "Produtividade"
        case let other?: other.capitalized
        case nil: "Outros"
        }
    }
}

/// The project's highlighted technologies: what someone opening the project sees first, and what the AI
/// reads (list_stack / `vibedeck stack`) before implementing anything.
struct StackView: View {
    @Environment(ProjectModel.self) private var model
    @Environment(\.undoManager) private var undo
    @State private var selection = Set<StackItem.ID>()
    @State private var picking = false
    @State private var editingNote: StackItem?
    @State private var search = ""
    @State private var copied = false

    private var items: [StackItem] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return model.project.stack }
        let tag = q.hasPrefix("#") ? String(q.dropFirst()) : q
        return model.project.stack.filter {
            $0.tags.contains { $0.localizedCaseInsensitiveContains(tag) } || !q.hasPrefix("#") && (
                $0.name.localizedCaseInsensitiveContains(q) || $0.icon.localizedCaseInsensitiveContains(q)
                || ($0.note ?? "").localizedCaseInsensitiveContains(q)
                || StackCategory.label($0.category).localizedCaseInsensitiveContains(q))
        }
    }

    private let columns = [GridItem(.adaptive(minimum: 260, maximum: 380), spacing: 12)]

    var body: some View {
        Group {
            if model.project.stack.isEmpty {
                ContentUnavailableView {
                    Label("Sem tecnologias", systemImage: "square.stack.3d.up")
                } description: {
                    Text("Marque as tecnologias de destaque do projeto. Elas aparecem aqui, no README.md e para a IA antes de implementar.")
                } actions: {
                    Button("Escolher tecnologias") { picking = true }.buttonStyle(.glass)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let warning = model.readmeWarning {
                            Label(warning, systemImage: "exclamationmark.triangle")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                            ForEach(items) { item in card(item) }
                        }
                    }
                    .padding(20)
                }
                .contentShape(Rectangle())
                .onTapGesture { selection.removeAll() }
                .onDeleteCommand { remove(selection) }
            }
        }
        .navigationTitle("Stack")
        .searchable(text: $search, placement: .toolbar, prompt: "Filtrar stack (texto ou #tag)")
        .toolbar {
            ToolbarItem {
                Button(action: copyBadge) {
                    Label(copied ? "Copiado" : "Copiar badge", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .help("Copiar o badge da stack (Markdown) para colar num README")
                .disabled(model.project.stack.isEmpty)
            }
            ToolbarItem {
                Button { picking = true } label: { Label("Escolher tecnologias", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $picking) {
            StackPicker(current: model.project.stack) { stack in
                model.mutateStack("Alterar stack", undo: undo) { $0 = stack }
            }
        }
        .sheet(item: $editingNote) { item in
            StackNoteEditor(item: item) { note in
                model.mutateStack("Editar nota", undo: undo) { stack in
                    if let i = stack.firstIndex(where: { $0.id == item.id }) { stack[i].note = note.isEmpty ? nil : note }
                }
            } onTags: { tags in
                model.mutateStack("Editar tags", undo: undo) { stack in
                    if let i = stack.firstIndex(where: { $0.id == item.id }) { stack[i].tags = tags }
                }
            }
        }
        .task { await SkillIconCache.shared.loadCatalog() }
    }

    private func card(_ item: StackItem) -> some View {
        let selected = selection.contains(item.id)
        return HStack(alignment: .top, spacing: 10) {
            SkillIconImage(id: item.icon, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).fontWeight(.medium).lineLimit(1)
                Text(StackCategory.label(item.category)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                // Always laid out with room for three lines, so every card has the same height;
                // the full note is in the tooltip and the editor.
                Text(item.note ?? "").font(.caption).foregroundStyle(.secondary)
                    .lineLimit(3, reservesSpace: true)
                if !item.tags.isEmpty {
                    Text(item.tags.map { "#" + $0 }.joined(separator: " ")).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if item.author == .ai {
                Image(systemName: "sparkles").font(.caption2).foregroundStyle(.tertiary).help("Adicionada pela IA")
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(selected ? .regular.tint(.accentColor.opacity(0.35)).interactive() : .regular.interactive(), in: .rect(cornerRadius: 12))
        .contentShape(Rectangle())
        .onTapGesture {
            if NSEvent.modifierFlags.contains(.command) {
                if selected { selection.remove(item.id) } else { selection.insert(item.id) }
            } else {
                selection = [item.id]
            }
        }
        .onTapGesture(count: 2) { editingNote = item }
        .draggable(item.icon)
        .dropDestination(for: String.self) { ids, _ in
            guard let dragged = ids.first, dragged != item.icon else { return false }
            move(dragged, before: item.icon)
            return true
        }
        .help(item.note ?? item.name)
        .contextMenu {
            Button("Editar nota…") { editingNote = item }
            Button("Mover para o início") { move(item.icon, to: 0) }
            Button("Mover para o fim") { move(item.icon, to: model.project.stack.count) }
            Divider()
            Button("Remover", role: .destructive) { remove(selected ? selection : [item.id]) }
        }
    }

    private func remove(_ ids: Set<StackItem.ID>) {
        guard !ids.isEmpty else { return }
        model.mutateStack(ids.count == 1 ? "Remover tecnologia" : "Remover tecnologias", undo: undo) {
            $0.removeAll { ids.contains($0.id) }
        }
        selection.subtract(ids)
    }

    private func move(_ id: String, to position: Int) {
        model.mutateStack("Mover tecnologia", undo: undo) { stack in
            guard let from = stack.firstIndex(where: { $0.id == id }) else { return }
            let item = stack.remove(at: from)
            stack.insert(item, at: max(0, min(position, stack.count)))
        }
    }

    private func move(_ id: String, before target: String) {
        model.mutateStack("Mover tecnologia", undo: undo) { stack in
            guard let from = stack.firstIndex(where: { $0.id == id }) else { return }
            let item = stack.remove(at: from)
            let to = stack.firstIndex(where: { $0.id == target }) ?? stack.count
            stack.insert(item, at: to)
        }
    }

    private func copyBadge() {
        let service = StackService(store: model.store)
        Task {
            do {
                guard let badge = try await service.badge() else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(badge.markdown, forType: .string)
                copied = true
                try? await Task.sleep(for: .seconds(1.5))
                copied = false
            } catch {
                model.readmeWarning = error.localizedDescription
            }
        }
    }
}

/// Searchable grid of the whole Skill Icons catalog; toggling marks a draft that is applied on "Concluir"
/// as a single undo step.
private struct StackPicker: View {
    let current: [StackItem]
    let onDone: ([StackItem]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var picked: [String] = []
    @State private var search = ""
    @State private var category: String?
    private var cache: SkillIconCache { .shared }

    private var results: [SkillIcon] {
        let q = search.trimmingCharacters(in: .whitespaces)
        return cache.catalog.filter { (category == nil || $0.category == category) && $0.matches(containing: q) }
    }

    private var categories: [String] {
        SkillIcons.categories.filter { c in cache.catalog.contains { $0.category == c } }
    }

    private let columns = [GridItem(.adaptive(minimum: 88, maximum: 110), spacing: 8)]

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Procurar por nome ou alias (ex.: postgres, k8s, Next.js)", text: $search)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .glassEffect(.regular, in: .capsule)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        chip("Todas", selected: category == nil) { category = nil }
                        ForEach(categories, id: \.self) { c in
                            chip(StackCategory.label(c), selected: category == c) { category = category == c ? nil : c }
                        }
                    }
                }
            }
            .padding(14)
            Divider()
            content
                .frame(width: 640, height: 420)
            Divider()
            HStack {
                Text("\(picked.count) selecionada(s) · ícones do Skill Icons")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancelar") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Concluir") { apply(); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.glassProminent)
            }
            .padding(14)
        }
        .onAppear { picked = current.map(\.icon) }
        .task { await cache.loadCatalog() }
    }

    @ViewBuilder
    private var content: some View {
        if cache.catalog.isEmpty {
            if let error = cache.catalogError {
                ContentUnavailableView {
                    Label("Skill Icons indisponível", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(error)
                } actions: {
                    Button("Tentar de novo") { Task { await cache.loadCatalog(force: true) } }
                }
            } else {
                ProgressView("Carregando ícones…").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else if results.isEmpty {
            ContentUnavailableView.search(text: search)
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(results) { icon in cell(icon) }
                }
                .padding(14)
            }
        }
    }

    private func cell(_ icon: SkillIcon) -> some View {
        let isPicked = picked.contains(icon.id)
        return Button {
            if isPicked { picked.removeAll { $0 == icon.id } } else { picked.append(icon.id) }
        } label: {
            VStack(spacing: 6) {
                SkillIconImage(id: icon.id, size: 40)
                    .overlay(alignment: .topTrailing) {
                        if isPicked {
                            Image(systemName: "checkmark.circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, Color.accentColor)
                                .offset(x: 6, y: -6)
                        }
                    }
                Text(icon.name).font(.caption).lineLimit(1)
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(isPicked ? Color.accentColor.opacity(0.15) : .clear, in: .rect(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(([icon.id] + icon.aliases).joined(separator: ", "))
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.caption)
                .padding(.horizontal, 9).padding(.vertical, 3)
        }
        .buttonStyle(.plain)
        .glassEffect(selected ? .regular.tint(.accentColor.opacity(0.4)).interactive() : .regular.interactive(), in: .capsule)
    }

    /// Keeps the current items (and their notes/order) that are still picked, then appends new ones in pick order.
    private func apply() {
        var stack = current.filter { picked.contains($0.icon) }
        for id in picked where !stack.contains(where: { $0.icon == id }) {
            if let icon = cache.icon(id) { stack.append(StackItem(icon, author: .human)) }
        }
        onDone(stack)
    }
}

private struct StackNoteEditor: View {
    let item: StackItem
    let onSave: (String) -> Void
    let onTags: ([String]) -> Void
    @Environment(ProjectModel.self) private var model
    @State private var note = ""
    @State private var saved = ""
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            LabeledContent {
                Text(item.name)
            } label: {
                SkillIconImage(id: item.icon, size: 24)
            }
            TextField("Nota de uso (ex.: Swift 6, strict concurrency)", text: $note, axis: .vertical)
                .lineLimit(2...5)
                .focused($focused)
                .onSubmit(commit)
            Text("A IA recebe essa nota junto com a stack.").font(.caption).foregroundStyle(.secondary)
            // Live value: the sheet's `item` is a snapshot, the tags are committed one undo step at a time.
            TagsField(tags: model.project.stack.first { $0.id == item.id }?.tags ?? item.tags, onCommit: onTags)
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .onAppear { note = item.note ?? ""; saved = note }
        .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Concluído") { commit(); dismiss() } }
        }
    }

    /// Writes the note in place (one undo step) on Return, focus loss or "Concluído".
    private func commit() {
        let value = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value != saved else { return }
        saved = value
        onSave(value)
    }
}
