import SwiftUI

/// Espaço de nomes herdado da janela V1 (removida): o pedido de nome ao criar um item.
enum ProjectWindow {

    enum NewNamePrompt: Identifiable {
        case doc, group, topic, idea, agent, command, skill, workflow
        var id: Self { self }

        init(_ section: SidebarSection) {
            switch section {
            case .docs: self = .doc
            case .groups: self = .group
            case .topics: self = .topic
            case .ideas: self = .idea
            case .agents: self = .agent
            case .commands: self = .command
            case .skills: self = .skill
            case .workflows: self = .workflow
            }
        }

        var title: String {
            switch self {
            case .doc: "Novo documento"
            case .group: "Novo grupo de revisão"
            case .topic: "Novo tópico de regras"
            case .idea: "Nova ideia"
            case .agent: "Novo agente"
            case .command: "Novo comando"
            case .skill: "Nova skill"
            case .workflow: "Novo workflow"
            }
        }

        var placeholder: String {
            switch self {
            case .doc: "Título do documento"
            case .group: "Tema (ex.: Tela de login)"
            case .topic: "Tópico (ex.: Interface, API, Acessibilidade)"
            case .idea: "Ideia (ex.: Modo offline)"
            case .agent: "Nome do agente (ex.: Revisor de código)"
            case .command: "Nome do comando (ex.: commit)"
            case .skill: "Nome da skill (ex.: revisar-pr)"
            case .workflow: "Nome do workflow (ex.: Revisão até aprovar)"
            }
        }
    }
}

struct NamePromptSheet: View {
    @Environment(\.logProject) private var providerRoot
    @Environment(\.logProject) private var logProject
    let title: String
    let placeholder: String
    let onSubmit: (String) -> Void
    @State private var name = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.headline)
            LoggedTextField(placeholder, text: $name, onCommit: submit).loggedField(control: "projectwindow.text_2", label: "Confirmar campo")
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                LoggedButton("Cancelar", role: .cancel) { dismiss() }.loggedControl(control: "project_window.button_24", label: "Cancelar").buttonStyle(.glass)
                LoggedButton("Criar", action: submit).loggedControl(control: "project_window.button_25", label: "Criar")
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
