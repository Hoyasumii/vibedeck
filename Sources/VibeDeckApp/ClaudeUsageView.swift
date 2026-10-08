import SwiftUI
import VibeDeckCore

/// Limites do Claude Code (sessão de 5h e semana) no rodapé da sidebar. Só existe quando o Claude Code
/// está na máquina; os números vêm da statusline dele, via `vibedeck usage record`.
struct ClaudeUsageView: View {
    @State private var usage: ClaudeUsage?
    @State private var connected = false
    @State private var now = Date.now
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let usage, usage.hasLimits {
                VStack(alignment: .leading, spacing: 6) {
                    if let session = usage.session {
                        meter("Sessão", session, resetStyle: .time)
                    }
                    if let weekly = usage.weekly {
                        meter("Semana", weekly, resetStyle: .dayAndTime)
                    }
                }
                .help("Limites do Claude Code\(usage.model.map { " (\($0))" } ?? "") — atualizado \(usage.updatedAt.formatted(.relative(presentation: .named)))")
            } else if connected {
                Label("Aguardando o Claude Code…", systemImage: "gauge.with.dots.needle.0percent")
                    .foregroundStyle(.secondary)
                    .help("O uso aparece depois da próxima resposta do Claude Code")
            } else if let cli = Self.cliPath {
                Button {
                    do {
                        try ClaudeCode.installStatusLine(executable: cli)
                        reload()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                } label: {
                    Label("Mostrar limites do Claude Code", systemImage: "gauge.with.dots.needle.33percent")
                }
                .buttonStyle(.borderless)
                .help("Liga a statusline do Claude Code (~/.claude/settings.json) ao VibeDeck; uma statusline existente continua aparecendo")
            }
        }
        .font(.caption)
        .task {
            while !Task.isCancelled {
                reload()
                try? await Task.sleep(for: .seconds(15))
            }
        }
        .alert("Erro", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private enum ResetStyle { case time, dayAndTime }

    private func meter(_ title: String, _ window: ClaudeUsage.Window, resetStyle: ResetStyle) -> some View {
        let percent = window.percentage(at: now)
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(percent.rounded()))%").monospacedDigit()
            }
            ProgressView(value: percent, total: 100)
                .progressViewStyle(.linear)
                .tint(percent >= 90 ? .red : percent >= 70 ? .orange : .accentColor)
            if let reset = window.resetsAt, reset > now {
                Text("Reinicia \(resetStyle == .time ? reset.formatted(date: .omitted, time: .shortened) : reset.formatted(.dateTime.weekday(.abbreviated).hour().minute()))")
                    .foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(.secondary)
    }

    private func reload() {
        now = .now
        usage = ClaudeCode.loadUsage()
        if case .vibedeck = try? ClaudeCode.statusLineState() { connected = true } else { connected = false }
    }

    /// CLI a registrar na statusline: o do PATH do usuário (estável entre builds) ou o que vem dentro do app.
    static let cliPath: String? = {
        let fm = FileManager.default
        let candidates = [
            fm.homeDirectoryForCurrentUser.appending(path: ".local/bin/vibedeck").path,
            Bundle.main.bundleURL.appending(path: "Contents/Helpers/vibedeck").path,
        ]
        return candidates.first { fm.isExecutableFile(atPath: $0) }
    }()
}
