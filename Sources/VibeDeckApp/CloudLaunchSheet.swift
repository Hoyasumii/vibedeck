import AppKit
import SwiftUI
import VibeDeckCore

/// Creates a Claude Code cloud session on the project's GitHub repo, after checking that the local default
/// branch matches origin. Differing branches stop here; uncommitted changes only need a confirmation.
struct CloudLaunchSheet: View {
    @Environment(\.logProject) private var logProject
    let root: URL
    var provider: AIProvider = .claude
    @State private var environment = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(ProjectModel.self) private var model
    @Environment(\.undoManager) private var undo
    @State private var phase = Phase.checking
    @State private var task = ""
    @State private var allowDirty = false

    enum Phase {
        case checking
        case checked(CloudSync)
        case launching(CloudSync)
        case launched(URL?, output: String)
        case failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Sessão na nuvem", systemImage: "cloud")
                .font(.headline)
            content
        }
        .padding(24)
        .frame(width: 440)
        .task { environment = (try? ProjectStore(root: root).loadProject().codexCloudEnvironment) ?? ""; await check() }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .checking:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Verificando o GitHub…").foregroundStyle(.secondary)
            }
            buttons { EmptyView() }

        case .checked(let sync) where sync.blocked:
            Label(sync.message, systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
            buttons {
                LoggedButton("Verificar de novo") { Task { await check() } }.loggedControl(control: "cloud_launch_sheet.button_1", label: "Verificar de novo")
                    .buttonStyle(.glassProminent)
            }

        case .checked(let sync), .launching(let sync):
            Label(sync.dirty.isEmpty ? sync.message : "A \(sync.branch) local e a origin/\(sync.branch) são iguais.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            if !sync.dirty.isEmpty { dirtyWarning(sync) }
            if provider == .codex {
                LoggedTextField("ID do ambiente Codex Cloud", text: $environment).loggedField(control: "cloudlaunchsheet.text_1", label: "ID do ambiente Codex Cloud").textFieldStyle(.roundedBorder)
                Text("O ambiente fica salvo neste projeto.").font(.caption).foregroundStyle(.secondary)
            }
            LoggedTextField("O que a sessão deve fazer?", text: $task, axis: .vertical).loggedField(control: "cloudlaunchsheet.text_2", label: "O que a sessão deve fazer?")
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...6)
            buttons {
                if case .launching = phase {
                    ProgressView().controlSize(.small)
                }
                LoggedButton("Criar na nuvem") { launch() }.loggedControl(control: "cloud_launch_sheet.button_2", label: "Criar na nuvem")
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canLaunch(sync))
            }

        case .launched(let url, let output):
            if let url {
                Label("Sessão criada e aberta no navegador.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                LoggedButton("Abrir sessão na nuvem") { NSWorkspace.shared.open(url) }.loggedControl(control: "cloud_launch_sheet.button_3", label: "Abrir sessão na nuvem")
                    .buttonStyle(.link)
                    .font(.callout)
                    .textSelection(.enabled)
            } else {
                Label("O provedor respondeu sem um link de sessão:", systemImage: "questionmark.circle")
                Text(output).font(.callout.monospaced()).textSelection(.enabled)
            }
            buttons { EmptyView() }

        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            buttons {
                LoggedButton("Verificar de novo") { Task { await check() } }.loggedControl(control: "cloud_launch_sheet.button_4", label: "Verificar de novo")
                    .buttonStyle(.glassProminent)
            }
        }
    }

    private func dirtyWarning(_ sync: CloudSync) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("\(sync.dirty.count) arquivo(s) não commitado(s): a sessão na nuvem não vai ver essas mudanças.", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            Text((sync.dirty.prefix(5) + (sync.dirty.count > 5 ? ["… e mais \(sync.dirty.count - 5)"] : [])).joined(separator: "\n"))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            Toggle("Criar mesmo assim", isOn: $allowDirty.logging(control: "cloud_launch_sheet.selection_6", label: "Criar mesmo assim", project: logProject))
        }
    }

    private func buttons(@ViewBuilder _ actions: () -> some View) -> some View {
        HStack {
            Spacer()
            LoggedButton("Fechar", role: .cancel) { dismiss() }.loggedControl(control: "cloud_launch_sheet.button_5", label: "Fechar").buttonStyle(.glass)
            actions()
        }
    }

    private func canLaunch(_ sync: CloudSync) -> Bool {
        if case .launching = phase { return false }
        return !task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (provider != .codex || !environment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) && (sync.dirty.isEmpty || allowDirty)
    }

    private func check() async {
        phase = .checking
        let root = root
        phase = .checked(await VDLog.detached { CloudSession.check(root: root) }.value)
    }

    private func launch() {
        guard case .checked(let sync) = phase else { return }
        phase = .launching(sync)
        let provider = provider, environment = environment.trimmingCharacters(in: .whitespacesAndNewlines)
        let root = root, description = task.trimmingCharacters(in: .whitespacesAndNewlines), allowDirty = allowDirty
        Task {
            do {
                let result = try await VDLog.detached {
                    try CloudSession.launch(root: root, description: description, allowDirty: allowDirty, provider: provider, environment: environment)
                }.value
                if provider == .codex {
                    model.mutateProject("Alterar ambiente da nuvem", undo: undo) { $0.codexCloudEnvironment = environment }
                }
                if let url = result.url { NSWorkspace.shared.open(url) }
                phase = .launched(result.url, output: result.output)
            } catch {
                // The branch may have changed since the check: show the fresh state, which blocks again.
                if case VibeDeckError.cloudNotSynced(let fresh) = error { phase = .checked(fresh) } else { phase = .failed(error.localizedDescription) }
            }
        }
    }
}
