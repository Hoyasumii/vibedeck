import SwiftUI

/// Qualidade › Histórico (prancha 13, "Verificações › Histórico"): todas as verificações do projeto, da mais recente
/// para a mais antiga, com o resultado de cada regra. Por tópico, as verificações também aparecem em Regras.
struct V2ChecksHistoryView: View {
    @Environment(ProjectModel.self) private var model

    private var checks: [RuleCheck] {
        model.checks.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        content
            .navigationTitle("Histórico")
            .navigationSubtitle("\(model.checks.count) verificação(ões)")
    }

    @ViewBuilder
    private var content: some View {
        if checks.isEmpty {
            ContentUnavailableView("Nenhuma verificação", systemImage: "clock",
                                   description: Text("Agentes registram verificações com submit_rule_check (MCP) ou `vibedeck rules check`."))
        } else {
            List {
                ForEach(checks) { check in
                    DisclosureGroup {
                        ForEach(check.results, id: \.ruleId) { result in
                            resultRow(result)
                        }
                    } label: {
                        CheckLabel(check: check)
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private func ruleText(_ result: RuleResult) -> String {
        let rules = model.topic(result.topic)?.rules ?? []
        return rules.first { $0.id == result.ruleId }?.text ?? "Regra removida"
    }

    private func resultRow(_ result: RuleResult) -> some View {
        HStack(alignment: .top, spacing: DesignTokens.Space.s2) {
            Image(systemName: result.verdict.symbol).foregroundStyle(result.verdict.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(ruleText(result)).font(DesignTokens.Typography.body)
                Text(model.topic(result.topic)?.title ?? result.topic)
                    .font(DesignTokens.Typography.callout)
                    .foregroundStyle(DesignTokens.Colors.inkMuted)
                if let note = result.note {
                    Text(note)
                        .font(DesignTokens.Typography.callout)
                        .foregroundStyle(DesignTokens.Colors.inkMuted)
                        .lineLimit(6)
                }
            }
        }
    }
}
