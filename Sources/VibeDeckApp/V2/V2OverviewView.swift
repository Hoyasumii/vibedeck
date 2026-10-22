import SwiftUI

/// Projeto › Visão geral (prancha 17): o que a IA lê sobre o projeto antes de agir, com atalhos para as páginas.
/// Integra o grafo (nós e relações), as integrações com os agentes e o consumo de IA. Se o projeto foi aberto com
/// "Pular por agora" no início guiado, oferece retomá-lo aqui.
struct V2OverviewView: View {
    let onOpen: (SidebarItem) -> Void
    @Environment(ProjectModel.self) private var model
    @State private var graphText: String?
    @State private var integrations: [V2Integration] = []
    @State private var usageText: String?
    var onResumeOnboarding: (() -> Void)?

    private let columns = [GridItem(.adaptive(minimum: 140), spacing: DesignTokens.Space.s2, alignment: .leading)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Space.s6) {
                header
                stackBlock
                patternsBlock
                graphBlock
                integrationsBlock
                usageBlock
                referencesBlock
            }
            .padding(DesignTokens.Space.s6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Visão geral")
        .task { await loadSummaries() }
    }

    private func loadSummaries() async {
        if model.store.isRemote { return }
        let root = model.store.root
        graphText = Self.graphSummary(root: root)
        integrations = V2IntegrationProbe.scan(root: root)
        usageText = Self.usageSummary(root: root)
    }

    private static func graphSummary(root: URL) -> String? {
        guard let graph = try? ProjectGraph.load(root: root) else { return nil }
        let nodes = graph.nodes.count
        let links = graph.links.count
        var text = "\(nodes) nós · \(links) relações"
        if let provider = graph.value["vibedeck_provider"]?.string { text += " · gerado com \(provider)" }
        return text
    }

    private static func usageSummary(root: URL) -> String? {
        guard let records = try? AIUsageStore(root: root).list(), !records.isEmpty else { return nil }
        let tasks = AIUsageTask.group(records)
        let input = records.reduce(0) { $0 + ($1.tokens.input ?? 0) }
        let output = records.reduce(0) { $0 + ($1.tokens.output ?? 0) }
        return "\(tasks.count) tarefa(s) · entrada \(input) · saída \(output) tokens"
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
            empty(graphText ?? "Relações entre arquivos e conceitos do código, geradas com o graphify.")
        }
    }

    private var integrationsBlock: some View {
        block("Integrações", action: "Abrir", target: .integrations) {
            if model.store.isRemote {
                empty("Disponível só em projetos locais.")
            } else {
                VStack(alignment: .leading, spacing: DesignTokens.Space.s2) {
                    ForEach(integrations) { item in
                        HStack(spacing: DesignTokens.Space.s2) {
                            Text(item.title).font(DesignTokens.Typography.body)
                            Spacer()
                            VDBadge(item.installed ? "instalado" : "não instalado", tone: item.installed ? .done : .neutral)
                        }
                    }
                }
            }
        }
    }

    private var usageBlock: some View {
        block("Consumo de IA", action: "Abrir", target: .usage) {
            empty(usageText ?? "Nenhum consumo registrado neste projeto.")
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
