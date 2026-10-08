import AppKit
import SwiftUI
import VibeDeckCore

/// Creates a Claude Code cloud session on the project's GitHub repo, after checking that the local default
/// branch matches origin. Differing branches stop here; uncommitted changes only need a confirmation.
struct CloudLaunchSheet: View {
    let root: URL
    @Environment(\.dismiss) private var dismiss
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
        .task { await check() }
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
                Button("Verificar de novo") { Task { await check() } }
                    .buttonStyle(.glassProminent)
            }

        case .checked(let sync), .launching(let sync):
            Label(sync.dirty.isEmpty ? sync.message : "A \(sync.branch) local e a origin/\(sync.branch) são iguais.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            if !sync.dirty.isEmpty { dirtyWarning(sync) }
            TextField("O que a sessão deve fazer?", text: $task, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...6)
            buttons {
                if case .launching = phase {
                    ProgressView().controlSize(.small)
                }
                Button("Criar na nuvem") { launch() }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canLaunch(sync))
            }

        case .launched(let url, let output):
            if let url {
                Label("Sessão criada e aberta no navegador.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Button(url.absoluteString) { NSWorkspace.shared.open(url) }
                    .buttonStyle(.link)
                    .font(.callout)
                    .textSelection(.enabled)
            } else {
                Label("O Claude Code respondeu sem um link de sessão:", systemImage: "questionmark.circle")
                Text(output).font(.callout.monospaced()).textSelection(.enabled)
            }
            buttons { EmptyView() }

        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            buttons {
                Button("Verificar de novo") { Task { await check() } }
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
            Toggle("Criar mesmo assim", isOn: $allowDirty)
        }
    }

    private func buttons(@ViewBuilder _ actions: () -> some View) -> some View {
        HStack {
            Spacer()
            Button("Fechar", role: .cancel) { dismiss() }.buttonStyle(.glass)
            actions()
        }
    }

    private func canLaunch(_ sync: CloudSync) -> Bool {
        if case .launching = phase { return false }
        return !task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (sync.dirty.isEmpty || allowDirty)
    }

    private func check() async {
        phase = .checking
        let root = root
        phase = .checked(await Task.detached { CloudSession.check(root: root) }.value)
    }

    private func launch() {
        guard case .checked(let sync) = phase else { return }
        phase = .launching(sync)
        let root = root, description = task.trimmingCharacters(in: .whitespacesAndNewlines), allowDirty = allowDirty
        Task {
            do {
                let result = try await Task.detached {
                    try CloudSession.launch(root: root, description: description, allowDirty: allowDirty)
                }.value
                if let url = result.url { NSWorkspace.shared.open(url) }
                phase = .launched(result.url, output: result.output)
            } catch {
                // The branch may have changed since the check: show the fresh state, which blocks again.
                if case VibeDeckError.cloudNotSynced(let fresh) = error { phase = .checked(fresh) } else { phase = .failed(error.localizedDescription) }
            }
        }
    }
}
