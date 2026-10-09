import SwiftUI
import VibeDeckCore

/// The code patterns the project follows (TDD, hexagonal, DDD…): what the AI reads (list_patterns /
/// `vibedeck patterns`) before implementing, each one enforced by its own rule topic.
struct PatternsView: View {
    let onOpen: (SidebarItem) -> Void
    @Environment(ProjectModel.self) private var model
    @Environment(\.undoManager) private var undo
    @State private var adding = false
    @State private var editing: ProjectPattern?
    @State private var removing: ProjectPattern?
    @State private var search = ""

    private var items: [ProjectPattern] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return model.project.patterns }
        return model.project.patterns.filter {
            $0.name.localizedCaseInsensitiveContains(q) || $0.id.localizedCaseInsensitiveContains(q)
                || ($0.summary ?? "").localizedCaseInsensitiveContains(q) || ($0.note ?? "").localizedCaseInsensitiveContains(q)
        }
    }

    private let columns = [GridItem(.adaptive(minimum: 260, maximum: 380), spacing: 12)]

    var body: some View {
        Group {
            if model.project.patterns.isEmpty {
                ContentUnavailableView {
                    Label("Sem padrões de projeto", systemImage: "building.columns")
                } description: {
                    Text("Escolha como o código deve ser escrito (TDD, arquitetura hexagonal, DDD, CQRS…). A IA segue esses padrões ao implementar, e as regras de cada um são cobradas antes de ela concluir uma tarefa.")
                } actions: {
                    Button("Escolher padrões") { adding = true }.buttonStyle(.glass)
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                        ForEach(items) { card($0) }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
        .navigationTitle("Padrões")
        .searchable(text: $search, placement: .toolbar, prompt: "Filtrar padrões")
        .toolbar {
            ToolbarItem {
                Button { adding = true } label: { Label("Adicionar padrão", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $adding) { PatternPicker() }
        .sheet(item: $editing) { PatternEditor(pattern: $0) }
        .confirmationDialog(
            "Remover o padrão \"\(removing?.name ?? "")\"?", isPresented: Binding { removing != nil } set: { if !$0 { removing = nil } }
        ) {
            Button("Remover", role: .destructive) {
                if let id = removing?.id { model.changePatterns("Remover padrão", undo: undo) { try $0.removePatterns([id]) } }
                removing = nil
            }
        } message: {
            Text("O tópico de regras do padrão também é apagado, e a IA deixa de ser cobrada por ele. Dá para desfazer com ⌘Z.")
        }
    }

    private func card(_ pattern: ProjectPattern) -> some View {
        let topic = pattern.topic.flatMap { ref in model.topics.first { $0.slug == ref } }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(pattern.name).font(.headline).lineLimit(1)
                Text(PatternCategory.label(pattern.category)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 0)
                if pattern.author == .ai {
                    Image(systemName: "sparkles").font(.caption2).foregroundStyle(.tertiary).help("Adicionado pela IA")
                }
            }
            if let summary = pattern.summary {
                Text(summary).font(.callout).foregroundStyle(.secondary).lineLimit(3)
            }
            if let note = pattern.note {
                Label(note, systemImage: "text.bubble").font(.caption).lineLimit(3)
            }
            HStack(spacing: 10) {
                if let topic {
                    Label(
                        topic.value.paths.isEmpty ? "Projeto inteiro" : topic.value.paths.joined(separator: ", "),
                        systemImage: topic.value.paths.isEmpty ? "globe" : "scope"
                    )
                    .lineLimit(1)
                    .truncationMode(.middle)
                    Spacer(minLength: 0)
                    Button("\(topic.value.rules.count) regra(s)") { onOpen(.topic(topic.slug)) }
                        .buttonStyle(.link)
                        .fixedSize()
                        .help("Abrir o tópico de regras do padrão")
                } else {
                    Label("Sem tópico de regras", systemImage: "exclamationmark.triangle")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { editing = pattern }
        .draggable(pattern.id)
        .dropDestination(for: String.self) { ids, _ in
            guard let dragged = ids.first, dragged != pattern.id,
                  let from = model.project.patterns.firstIndex(where: { $0.id == dragged }),
                  let to = model.project.patterns.firstIndex(where: { $0.id == pattern.id }) else { return false }
            model.movePatterns(from: [from], to: to > from ? to + 1 : to, undo: undo)
            return true
        }
        .contextMenu {
            Button("Editar nota e escopo…") { editing = pattern }
            if let topic { Button("Ver regras") { onOpen(.topic(topic.slug)) } }
            Divider()
            Button("Remover…", role: .destructive) { removing = pattern }
        }
    }
}

/// Splits a comma/newline separated list of globs.
private func parsePaths(_ text: String) -> [String] {
    text.split(whereSeparator: { $0 == "," || $0.isNewline }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
}

/// Catalog patterns (grouped by category) plus a form for a pattern of the project's own.
private struct PatternPicker: View {
    @Environment(ProjectModel.self) private var model
    @Environment(\.undoManager) private var undo
    @Environment(\.dismiss) private var dismiss
    @State private var custom = false
    @State private var picked: [String] = []
    @State private var name = ""
    @State private var summary = ""
    @State private var rules = ""
    @State private var note = ""
    @State private var paths = ""

    private var current: Set<String> { Set(model.project.patterns.map(\.id)) }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $custom) {
                Text("Catálogo").tag(false)
                Text("Personalizado").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 280)
            .padding(14)
            Divider()
            Group {
                if custom { customForm } else { catalog }
            }
            .frame(width: 640, height: 440)
            Divider()
            HStack {
                Text(custom ? "Cada linha de regras vira uma regra obrigatória." : "\(picked.count) selecionado(s) · cada padrão cria um tópico de regras")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancelar") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Adicionar", action: add)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.glassProminent)
                    .disabled(custom ? name.trimmingCharacters(in: .whitespaces).isEmpty || parseRules.isEmpty : picked.isEmpty)
            }
            .padding(14)
        }
    }

    private var catalog: some View {
        List {
            ForEach(["practices", "architecture", "domain"], id: \.self) { category in
                Section(PatternCategory.label(category)) {
                    ForEach(PatternCatalog.all.filter { $0.category == category }) { row($0) }
                }
            }
            Section("Escopo e nota (opcionais, valem para os selecionados)") {
                TextField("Globs, separados por vírgula (vazio = projeto inteiro)", text: $paths)
                    .font(.callout.monospaced())
                TextField("Como o projeto aplica (ex.: só no Core)", text: $note)
            }
        }
    }

    private func row(_ template: PatternTemplate) -> some View {
        let added = current.contains(template.id)
        let isPicked = added || picked.contains(template.id)
        return Button {
            guard !added else { return }
            if isPicked { picked.removeAll { $0 == template.id } } else { picked.append(template.id) }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isPicked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isPicked ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(template.name).fontWeight(.medium)
                        if added { Text("no projeto").font(.caption).foregroundStyle(.secondary) }
                    }
                    Text(template.summary).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(added)
        .help(template.rules.map { "• " + $0.text }.joined(separator: "\n"))
    }

    private var customForm: some View {
        Form {
            TextField("Nome", text: $name, prompt: Text("Ex.: Feature folders"))
            TextField("Resumo", text: $summary, prompt: Text("O que o padrão é, em uma frase"), axis: .vertical)
                .lineLimit(1...3)
            Section("Regras (uma por linha)") {
                TextEditor(text: $rules)
                    .font(.callout)
                    .frame(minHeight: 120)
            }
            TextField("Escopo", text: $paths, prompt: Text("Globs, separados por vírgula (vazio = projeto inteiro)"))
                .font(.callout.monospaced())
            TextField("Nota", text: $note, prompt: Text("Como o projeto aplica"))
        }
        .formStyle(.grouped)
    }

    private var parseRules: [String] {
        rules.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private func add() {
        let scope = parsePaths(paths)
        let ok: Void? = if custom {
            model.changePatterns("Adicionar padrão", undo: undo) {
                _ = try $0.addCustomPattern(name: name, summary: summary, rules: parseRules, note: note, paths: scope, author: .human)
            }
        } else {
            model.changePatterns("Adicionar padrões", undo: undo) { _ = try $0.addPatterns(picked, note: note.isEmpty ? nil : note, paths: scope, author: .human) }
        }
        if ok != nil { dismiss() }
    }
}

/// Edits a pattern's note and scope in place: each field is written (and undoable) on Return or when it loses focus.
private struct PatternEditor: View {
    let pattern: ProjectPattern
    @Environment(ProjectModel.self) private var model
    @Environment(\.undoManager) private var undo
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @State private var paths = ""
    @FocusState private var focus: Field?

    private enum Field { case note, paths }

    private var currentPaths: String {
        pattern.topic.flatMap { ref in model.topics.first { $0.slug == ref } }?.value.paths.joined(separator: ", ") ?? ""
    }

    var body: some View {
        Form {
            LabeledContent("Padrão", value: pattern.name)
            TextField("Nota", text: $note, prompt: Text("Como o projeto aplica (ex.: hexagonal só no Core)"))
                .focused($focus, equals: .note)
                .onSubmit(commitNote)
            TextField("Escopo", text: $paths, prompt: Text("Globs, separados por vírgula (vazio = projeto inteiro)"))
                .font(.callout.monospaced())
                .focused($focus, equals: .paths)
                .onSubmit(commitPaths)
                .disabled(pattern.topic == nil)
            Text("A nota vai para a descrição do tópico de regras; o escopo define em quais arquivos as regras são cobradas.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .onAppear {
            note = pattern.note ?? ""
            paths = currentPaths
        }
        .onChange(of: focus) { old, _ in
            if old == .note { commitNote() }
            if old == .paths { commitPaths() }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Concluído") { commitNote(); commitPaths(); dismiss() }
            }
        }
    }

    private func commitNote() {
        let value = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value != (model.project.patterns.first { $0.id == pattern.id }?.note ?? "") else { return }
        model.changePatterns("Editar nota do padrão", undo: undo) { try $0.setPatternNote(pattern.id, value) }
    }

    private func commitPaths() {
        guard pattern.topic != nil, parsePaths(paths) != parsePaths(currentPaths) else { return }
        model.changePatterns("Editar escopo do padrão", undo: undo) { try $0.setPatternPaths(pattern.id, parsePaths(paths)) }
    }
}
