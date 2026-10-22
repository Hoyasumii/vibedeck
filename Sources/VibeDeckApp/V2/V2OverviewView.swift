import SwiftUI

/// Projeto › Visão geral (prancha 17): o que a IA lê sobre o projeto antes de agir, com atalhos para as páginas.
/// Integrações e consumo de IA ainda não têm página própria nesta fatia.
struct V2OverviewView: View {
    let onOpen: (SidebarItem) -> Void
    @Environment(ProjectModel.self) private var model

    private let columns = [GridItem(.adaptive(minimum: 140), spacing: DesignTokens.Space.s2, alignment: .leading)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Space.s6) {
                header
                stackBlock
                patternsBlock
                graphBlock
                referencesBlock
            }
            .padding(DesignTokens.Space.s6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Visão geral")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.s1) {
            Text(model.project.name).font(DesignTokens.Typography.displayLG)
            Text("O que a IA lê sobre este projeto antes de agir.")
                .font(DesignTokens.Typography.body)
                .foregroundStyle(DesignTokens.Colors.inkMuted)
        }
    }

    private var stackBlock: some View {
        block("Stack", action: "Escolher tecnologias", target: .stack) {
            if model.project.stack.isEmpty {
                empty("Nenhuma tecnologia escolhida.")
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: DesignTokens.Space.s2) {
                    ForEach(model.project.stack) { item in
                        VDBadge(item.name, tone: .neutral)
                    }
                }
            }
        }
    }

    private var patternsBlock: some View {
        block("Padrões", action: "Adicionar padrão", target: .patterns) {
            if model.project.patterns.isEmpty {
                empty("Nenhum padrão adotado.")
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: DesignTokens.Space.s2) {
                    ForEach(model.project.patterns) { pattern in
                        VDBadge(pattern.name, tone: .brand)
                    }
                }
            }
        }
    }

    private var graphBlock: some View {
        block("Grafo", action: "Abrir", target: .graph) {
            empty("Relações entre arquivos e conceitos do código, geradas com o graphify.")
        }
    }

    private var referencesBlock: some View {
        block("Referências", action: "Abrir links", target: .links) {
            let links = model.project.links.count
            let claude = model.project.claude.count
            empty("\(links) link(s) · \(claude) item(ns) da coleção do Claude")
        }
    }

    private func empty(_ text: String) -> some View {
        Text(text)
            .font(DesignTokens.Typography.body)
            .foregroundStyle(DesignTokens.Colors.inkMuted)
    }

    private func block<Content: View>(_ title: String, action: String, target: SidebarItem,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.s3) {
            HStack {
                Text(title).font(DesignTokens.Typography.title)
                Spacer()
                LoggedButton(action) { onOpen(target) }
                    .loggedControl(control: "v2_overview.open", label: action)
                    .buttonStyle(VDButtonStyle(kind: .secondary, size: .md))
            }
            content()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}
