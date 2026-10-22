import SwiftUI

struct KitCatalogButton: View {
    @Environment(ProjectModel.self) private var model
    @Environment(\.undoManager) private var undo
    @State private var showingCatalog = false

    var body: some View {
        LoggedButton { showingCatalog = true } label: {
            Label("Kits pré-definidos", systemImage: "square.grid.2x2")
        }.loggedControl(control: "kit_catalog.open", label: "Kits pré-definidos")
        .sheet(isPresented: $showingCatalog) {
            KitCatalogSheet { model.addKitItems($0, undo: undo) }
        }
    }
}

/// Selection is local until the user explicitly confirms the creation dialog.
struct KitCatalogSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.logProject) private var logProject
    let onAdd: ([String]) -> Bool
    @State private var selected = Set<String>()
    @State private var preview: String?

    private var items: [KitCatalogItem] { KitCatalog.kits.flatMap(\.items) }
    private var missing: [String] { (try? KitCatalog.missingDependencies(Array(selected))) ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Kits pré-definidos").font(.title2.bold())
            Text("Escolha os itens para adicionar. Depois, você pode editá-los manualmente ou por IA.")
                .foregroundStyle(.secondary)
            HSplitView {
                List {
                    ForEach(KitCatalog.kits) { kit in
                        Section {
                            LoggedButton(selected.isSuperset(of: kit.items.map(\.id)) ? "Desmarcar kit" : "Selecionar kit") {
                                let ids = Set(kit.items.map(\.id))
                                if selected.isSuperset(of: ids) { selected.subtract(ids) }
                                else { selected.formUnion(ids) }
                            }.loggedControl(control: "kit_catalog.kit." + kit.id, label: "Selecionar kit")
                            ForEach(kit.items) { item in
                                HStack {
                                    Toggle(isOn: Binding(get: { selected.contains(item.id) }, set: { value in
                                        if value { selected.insert(item.id) } else { selected.remove(item.id) }
                                    }).logging(control: "kit_catalog.item." + item.id, label: item.title, project: logProject)) {
                                        VStack(alignment: .leading) {
                                            Text(item.title)
                                            Text(item.kind.title).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    LoggedButton { preview = item.id } label: {
                                        Image(systemName: "info.circle")
                                    }.loggedControl(control: "kit_catalog.preview." + item.id, label: "Ver conteúdo e dependências")
                                    .help("Ver conteúdo e dependências")
                                }
                            }
                        } header: {
                            Text(kit.title)
                            Text(kit.summary).font(.caption)
                        }
                    }
                }.frame(width: 330)
                ScrollView {
                    if let item = items.first(where: { $0.id == preview }) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(item.title).font(.headline)
                            Text(item.summary)
                            Text(item.prompt).textSelection(.enabled)
                            if !item.steps.isEmpty {
                                Text("Etapas").font(.headline)
                                ForEach(item.steps) { step in
                                    Text("\(step.id): \(items.first { $0.id == step.ref }?.title ?? step.ref)")
                                    ForEach(Array(step.transitions.enumerated()), id: \.offset) { _, transition in
                                        Text("\(transition.label) → \(transition.to)").foregroundStyle(.secondary)
                                    }
                                }
                            }
                            if !item.dependencies.isEmpty {
                                Text("Dependências: " + item.dependencies.map { id in
                                    items.first { $0.id == id }?.title ?? id
                                }.joined(separator: ", "))
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding()
                    } else {
                        Text("Use o botão de informações para conferir o conteúdo de um item.")
                            .foregroundStyle(.secondary).padding()
                    }
                }.frame(minWidth: 300)
            }
            HStack {
                Text("\(selected.count) item(ns) selecionado(s)").foregroundStyle(.secondary)
                Spacer()
                LoggedButton("Cancelar") { dismiss() }.loggedControl(control: "kit_catalog.cancel", label: "Cancelar").keyboardShortcut(.cancelAction)
                LoggedButton("Adicionar selecionados") {
                    if onAdd(items.filter { selected.contains($0.id) }.map(\.id)) { dismiss() }
                }.loggedControl(control: "kit_catalog.add", label: "Adicionar selecionados")
                .keyboardShortcut(.defaultAction).disabled(selected.isEmpty || !missing.isEmpty)
            }
            if !missing.isEmpty {
                Text("Selecione também: " + missing.map { id in items.first { $0.id == id }?.title ?? id }.joined(separator: ", "))
                    .font(.callout).foregroundStyle(.orange)
            }
        }.padding().frame(width: 760, height: 560)
    }
}
