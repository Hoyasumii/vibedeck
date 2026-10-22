import SwiftUI

/// Projeto › Consumo de IA (prancha 17): o histórico de tokens por tarefa, no detalhe e sem janela própria.
struct V2UsageView: View {
    @Environment(ProjectModel.self) private var model

    var body: some View {
        if model.store.isRemote {
            ContentUnavailableView("Consumo indisponível", systemImage: "clock",
                                   description: Text("O consumo de IA fica guardado na máquina que roda o app e só cobre projetos locais."))
        } else {
            AIUsageHistoryView(root: model.store.root, embedded: true)
                .navigationTitle("Consumo de IA")
        }
    }
}
