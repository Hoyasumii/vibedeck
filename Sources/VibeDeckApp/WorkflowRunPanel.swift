import SwiftUI
import VibeDeckCore

/// Run of the open chat, next to it: state, the workflow diagram with the current step and the path taken,
/// and the agents and subagents the provider reported. Hiding or expanding it never touches the run.
struct WorkflowRunPanel: View {
    @Environment(ProjectModel.self) private var model
    @Environment(AISession.self) private var claude
    /// `<workflow>/<run>` saved in the chat.
    let ref: String

    var body: some View {
        let run = model.runs.first { $0.slug == ref }?.value
        let workflow = run.flatMap { model.workflow($0.workflow) }
        VStack(spacing: 0) {
            header(run, workflow)
            Divider()
            if let run, let workflow, !workflow.steps.isEmpty {
                WorkflowDiagram(steps: workflow.steps, title: title, current: run.isFinished ? nil : run.current,
                                traversed: run.traversed, open: nil)
            } else {
                ContentUnavailableView(run == nil ? "Execução não encontrada" : "Workflow não encontrado",
                                       systemImage: "point.3.connected.trianglepath.dotted",
                                       description: Text(ref))
            }
            Divider()
            WorkflowRunProcesses(processes: claude.processes.processes)
        }
        .background(.background)
    }

    private func header(_ run: WorkflowRun?, _ workflow: Workflow?) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(workflow?.title ?? run?.workflow ?? "Workflow").font(.headline).lineLimit(1)
                if let run {
                    HStack(spacing: 6) {
                        // Waiting for an answer is not work: no spinner, only the question mark.
                        Label(run.status.title, systemImage: run.status.symbol)
                            .foregroundStyle(run.status.color)
                        if let current = run.current, !run.isFinished {
                            Text("· etapa \(current)").foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption)
                    if run.status != .running, let reason = run.reason {
                        Text(reason).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    }
                }
            }
            Spacer(minLength: 0)
            LoggedButton { claude.runPanelExpanded.toggle() } label: {
                Image(systemName: claude.runPanelExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
            }
            .loggedControl(control: "workflow_run_panel.button_1", label: claude.runPanelExpanded ? "Restaurar ao lado do chat" : "Expandir visualizador")
            .buttonStyle(.borderless)
            .help(claude.runPanelExpanded ? "Restaurar ao lado do chat" : "Expandir visualizador")
            LoggedButton { claude.runPanelVisible = false; claude.runPanelExpanded = false } label: { Image(systemName: "xmark") }
                .loggedControl(control: "workflow_run_panel.button_2", label: "Ocultar visualizador")
                .buttonStyle(.borderless)
                .help("Ocultar visualizador (a execução continua)")
        }
        .padding(10)
    }

    private func title(_ step: WorkflowStep) -> String? {
        switch step.kind {
        case .agent: model.agent(step.ref)?.title
        case .command: model.command(step.ref)?.title
        case .skill: model.skill(step.ref)?.title
        }
    }
}

/// Agents of the chat as a tree: each subagent under the agent that started it.
struct WorkflowRunProcesses: View {
    let processes: [AgentProcess]

    var body: some View {
        let ids = Set(processes.map(\.id))
        let roots = processes.filter { $0.parentID.map { !ids.contains($0) } ?? true }
        VStack(alignment: .leading, spacing: 6) {
            Text("Agentes").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if processes.isEmpty {
                Text("Nenhum agente informado pelo provedor ainda.").font(.caption).foregroundStyle(.tertiary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(rows(roots, depth: 0), id: \.process.id) { row in
                            WorkflowRunProcessRow(process: row.process, parent: parentName(row.process))
                                .padding(.leading, CGFloat(row.depth) * 16)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 220)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rows(_ list: [AgentProcess], depth: Int) -> [(process: AgentProcess, depth: Int)] {
        list.flatMap { p in [(p, depth)] + rows(processes.filter { $0.parentID == p.id }, depth: depth + 1) }
    }

    private func parentName(_ process: AgentProcess) -> String? {
        process.parentID.flatMap { id in processes.first { $0.id == id }?.name }
    }
}

private struct WorkflowRunProcessRow: View {
    let process: AgentProcess
    let parent: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Group {
                if process.state == .running {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: symbol).foregroundStyle(color)
                }
            }
            .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(process.name).font(.callout).lineLimit(1)
                Text(caption).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .help(process.id)
    }

    private var caption: String {
        var parts = [stateTitle]
        if let parent { parts.append("de \(parent)") }
        if let detail = process.detail { parts.append(detail) }
        return parts.joined(separator: " · ")
    }

    private var stateTitle: String {
        switch process.state {
        case .running: "Em andamento"
        case .succeeded: "Concluído"
        case .failed: "Falhou"
        case .interrupted: "Interrompido"
        case .unconfirmed: "Sem confirmação de atividade"
        }
    }

    private var symbol: String {
        switch process.state {
        case .running: "circle.dotted"
        case .succeeded: "checkmark.circle"
        case .failed: "xmark.octagon"
        case .interrupted: "stop.circle"
        case .unconfirmed: "questionmark.circle.dashed"
        }
    }

    private var color: Color {
        switch process.state {
        case .running: .accentColor
        case .succeeded: .green
        case .failed: .red
        case .interrupted, .unconfirmed: .secondary
        }
    }
}
