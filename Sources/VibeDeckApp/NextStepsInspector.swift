import SwiftUI
import VibeDeckCore

/// Inspector shared by agents, commands and skills: the next steps (VibeDeck agents/commands/skills) that act on the
/// result of `owner`, forming a flow.
struct NextStepsInspector: View {
    /// The agent, command or skill whose steps these are (excluded from the candidates).
    let owner: SidebarItem
    let steps: [NextStep]
    let mutate: (_ actionName: String, _ change: @escaping (inout [NextStep]) -> Void) -> Void
    let open: (SidebarItem) -> Void
    @Environment(ProjectModel.self) private var model

    private struct Entry: Identifiable { var step: NextStep; var title: String; var id: String { "\(step.kind.rawValue):\(step.ref)" } }

    private func candidates(_ kind: NextStepKind) -> [Entry] {
        let taken = Set(steps.filter { $0.kind == kind }.map(\.ref))
        let all: [(slug: String, title: String)] = switch kind {
        case .agent: model.agents.map { ($0.slug, $0.value.title) }
        case .command: model.commands.map { ($0.slug, $0.value.title) }
        case .skill: model.skills.map { ($0.slug, $0.value.title) }
        }
        return all.filter { item($0.slug, kind) != owner && !taken.contains($0.slug) }
            .map { Entry(step: NextStep(kind: kind, ref: $0.slug), title: $0.title) }
    }

    private func item(_ ref: String, _ kind: NextStepKind) -> SidebarItem {
        switch kind {
        case .agent: .agent(ref)
        case .command: .command(ref)
        case .skill: .skill(ref)
        }
    }

    private func symbol(_ kind: NextStepKind) -> String {
        switch kind {
        case .agent: "person.crop.rectangle"
        case .command: "command"
        case .skill: "wand.and.stars"
        }
    }

    private func noun(_ kind: NextStepKind) -> (missing: String, open: String) {
        switch kind {
        case .agent: ("Agente não encontrado", "Abrir agente")
        case .command: ("Comando não encontrado", "Abrir comando")
        case .skill: ("Skill não encontrada", "Abrir skill")
        }
    }

    private func title(_ step: NextStep) -> String? {
        switch step.kind {
        case .agent: model.agent(step.ref)?.title
        case .command: model.command(step.ref)?.title
        case .skill: model.skill(step.ref)?.title
        }
    }

    var body: some View {
        let agents = candidates(.agent), commands = candidates(.command), skills = candidates(.skill)
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Próximos passos").font(.headline)
                Text("Agentes, comandos e skills do VibeDeck que atuam sobre o resultado deste. Formam um fluxo.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            List {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack {
                        Image(systemName: symbol(step.kind))
                        VStack(alignment: .leading) {
                            Text(title(step) ?? step.ref)
                            if title(step) == nil {
                                Text(noun(step.kind).missing)
                                    .font(.caption).foregroundStyle(.red)
                            } else if let note = step.note {
                                Text(note).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if title(step) != nil {
                            Button { open(item(step.ref, step.kind)) } label: { Image(systemName: "arrow.right.circle") }
                                .buttonStyle(.borderless)
                                .help(noun(step.kind).open)
                        }
                    }
                    .contextMenu {
                        Button("Remover", role: .destructive) {
                            mutate("Remover próximo passo") { $0.remove(at: index) }
                        }
                    }
                }
                .onMove { from, to in
                    mutate("Reordenar passos") { $0.move(fromOffsets: from, toOffset: to) }
                }
                .onDelete { offsets in
                    mutate("Remover próximo passo") { $0.remove(atOffsets: offsets) }
                }
            }
            .overlay {
                if steps.isEmpty {
                    ContentUnavailableView("Sem próximos passos", systemImage: "arrow.triangle.branch",
                                           description: Text("Escolha abaixo qual agente, comando ou skill atua depois deste."))
                }
            }

            Menu {
                if !agents.isEmpty {
                    Section("Agentes") {
                        ForEach(agents) { c in
                            Button(c.title) { mutate("Adicionar próximo passo") { $0.append(c.step) } }
                        }
                    }
                }
                if !commands.isEmpty {
                    Section("Comandos") {
                        ForEach(commands) { c in
                            Button(c.title) { mutate("Adicionar próximo passo") { $0.append(c.step) } }
                        }
                    }
                }
                if !skills.isEmpty {
                    Section("Skills") {
                        ForEach(skills) { c in
                            Button(c.title) { mutate("Adicionar próximo passo") { $0.append(c.step) } }
                        }
                    }
                }
            } label: {
                Label("Adicionar próximo passo", systemImage: "plus")
            }
            .menuStyle(.borderlessButton)
            .disabled(agents.isEmpty && commands.isEmpty && skills.isEmpty)
            .padding(16)
        }
    }
}
