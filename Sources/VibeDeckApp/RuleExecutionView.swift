import SwiftUI
import VibeDeckCore

struct RuleExecutionControls: View {
    var topic: String? = nil
    @Environment(ProjectModel.self) private var model
    @Environment(AISession.self) private var session

    var body: some View {
        Menu {
            Button("Executar sem IA") { model.startRuleExecution(topic: topic) }
            if session.provider.isInstalled {
                Button("Executar com IA (\(session.provider.title))") {
                    model.startRuleExecution(topic: topic, withAI: true, provider: session.provider)
                }
            }
        } label: {
            Label("Executar regras", systemImage: "play")
        } primaryAction: {
            model.startRuleExecution(topic: topic)
        }
        .disabled(model.ruleExecution?.active == true || model.isGeneratingTests)
        .help("Executar scripts ou scripts seguidos da verificação das regras restantes por IA")
    }
}

struct RuleExecutionPanel: View {
    let execution: RuleExecutionModel
    @State private var expanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    phase(ai: false)
                    if execution.withAI { phase(ai: true) }
                    else if execution.omitted > 0 {
                        Text("\(execution.omitted) regra(s) precisam de IA e não entram neste modo.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 240)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(execution.withAI ? "Scripts → IA · \(execution.provider.title)" : "Somente scripts").font(.headline)
                    Spacer()
                    Text("\(execution.completed)/\(execution.steps.count)").monospacedDigit()
                    if execution.active { ProgressView().controlSize(.mini) }
                }
                ProgressView(value: execution.progress)
                    .accessibilityLabel("Progresso das regras")
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    timing(at: context.date)
                }
                if let message = execution.message { Text(message).font(.caption).foregroundStyle(execution.withAI && !execution.saved ? .orange : .secondary) }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.35))
        .textSelection(.enabled)
    }

    private func phase(ai: Bool) -> some View {
        let steps = execution.steps.filter { $0.ai == ai }
        return VStack(alignment: .leading, spacing: 6) {
            Text(ai ? "2. Verificação por IA" : "1. Scripts").font(.subheadline.bold())
            if steps.isEmpty { Text("Nenhuma regra nesta etapa.").font(.caption).foregroundStyle(.secondary) }
            ForEach(execution.scope, id: \.self) { slug in
                let group = steps.filter { $0.slug == slug }
                if let first = group.first {
                    Text(first.topic).font(.caption.bold()).foregroundStyle(.secondary)
                    ForEach(group) { step in
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 5) {
                                if let command = step.rule.scriptCommand { Text(command).font(.caption.monospaced()) }
                                if let text = step.error ?? step.result?.note { Text(text).font(.caption.monospaced()) }
                                if let start = step.started, let end = step.ended { Text("Duração: \(duration(end.timeIntervalSince(start)))").font(.caption) }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        } label: {
                            HStack {
                                Image(systemName: symbol(step)).foregroundStyle(color(step))
                                Text(step.rule.text).lineLimit(2)
                                Spacer()
                                Text(status(step)).font(.caption).foregroundStyle(color(step))
                            }
                        }
                    }
                }
            }
        }
    }

    private func timing(at now: Date) -> some View {
        let elapsed = duration((execution.ended ?? now).timeIntervalSince(execution.started))
        let text: String
        if !execution.active { text = "Tempo total: \(elapsed)" }
        else if let remaining = execution.remaining(at: now) {
            text = remaining < 0 ? "Decorrido: \(elapsed) · Recalculando estimativa…" :
                "Decorrido: \(elapsed) · Restam ~\(duration(remaining)) · Previsão: \(now.addingTimeInterval(remaining).formatted(date: .omitted, time: .standard))"
        } else { text = "Decorrido: \(elapsed) · Calculando estimativa…" }
        return Text(text).font(.caption).foregroundStyle(.secondary).monospacedDigit()
    }

    private func duration(_ seconds: TimeInterval) -> String {
        let seconds = max(0, Int(seconds))
        return seconds < 60 ? "\(seconds)s" : "\(seconds / 60)min \(seconds % 60)s"
    }
    private func status(_ step: RuleExecutionModel.Step) -> String {
        if step.error != nil { return "Erro" }
        if let result = step.result {
            switch result.verdict { case .pass: return "Aprovada"; case .fail: return "Reprovada"; case .na: return "Não aplicável" }
        }
        return step.started == nil ? "Aguardando" : "Executando"
    }
    private func symbol(_ step: RuleExecutionModel.Step) -> String {
        if step.error != nil { return "exclamationmark.triangle" }
        if let result = step.result {
            switch result.verdict { case .pass: return "checkmark.circle.fill"; case .fail: return "xmark.circle.fill"; case .na: return "minus.circle" }
        }
        return step.started == nil ? "clock" : "arrow.trianglehead.2.clockwise.rotate.90"
    }
    private func color(_ step: RuleExecutionModel.Step) -> Color {
        if step.error != nil { return .orange }
        switch step.result?.verdict { case .pass: return .green; case .fail: return .red; default: return .secondary }
    }
}
