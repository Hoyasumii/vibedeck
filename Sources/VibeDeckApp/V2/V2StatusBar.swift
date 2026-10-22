import SwiftUI

/// Barra de status inferior (prancha 19): uso da IA, tarefa em andamento, ambiente (Local / SSH),
/// último check, terminal e branch.
struct V2StatusBar: View {
    let workspace: RemoteWorkspace?
    let onOpenChecks: () -> Void
    let onOpenTerminal: (UUID) -> Void

    @Environment(ProjectModel.self) private var model
    @Environment(AISession.self) private var claude
    @State private var usage: ClaudeUsage?
    @State private var now = Date.now
    @State private var branch: String?
    @State private var showingUsage = false

    var body: some View {
        HStack(spacing: DesignTokens.Space.s1) {
            aiSegment
            taskSegment
            Spacer(minLength: DesignTokens.Space.s2)
            environmentSegment
            V2StatusDivider()
            checkSegment
            terminalSegment
            branchSegment
        }
        .font(DesignTokens.Typography.callout)
        .foregroundStyle(DesignTokens.Colors.inkMuted)
        .padding(.horizontal, DesignTokens.Space.s2)
        .frame(height: DesignTokens.V2Layout.statusBarHeight)
        .background(DesignTokens.Colors.bgSidebar)
        .overlay(alignment: .top) { topEdge }
        .task { await refreshLoop() }
    }

    private var topEdge: some View {
        Rectangle().fill(DesignTokens.Colors.line).frame(height: 1)
    }

    private func refreshLoop() async {
        while !Task.isCancelled {
            now = Date.now
            usage = ClaudeCode.loadUsage()
            branch = V2Git.branch(at: model.store.root)
            do { try await Task.sleep(for: .seconds(15)) } catch { break }
        }
    }

    // MARK: IA

    @ViewBuilder
    private var aiSegment: some View {
        if !AIProvider.installed(in: model.store.root).isEmpty {
            V2StatusSegment(control: "v2_status_bar.ai", label: "Uso da IA") {
                showingUsage.toggle()
            } content: {
                VDIcon(.ai, size: 13)
                Text(claude.provider == .claude ? "Claude Code" : claude.provider.title)
                meters
            }
            .popover(isPresented: $showingUsage) {
                AIUsageView()
                    .padding(DesignTokens.Space.s3)
                    .frame(width: 300)
            }
        }
    }

    @ViewBuilder
    private var meters: some View {
        if claude.provider == .claude, let usage, usage.hasLimits {
            if let window = usage.session {
                V2Meter(title: "Sessão", percent: window.percentage(at: now), tint: DesignTokens.Colors.ai)
            }
            if let window = usage.weekly {
                V2Meter(title: "Semana", percent: window.percentage(at: now), tint: DesignTokens.Colors.brand)
            }
        }
    }

    // MARK: Tarefa em andamento

    @ViewBuilder
    private var taskSegment: some View {
        if let execution = model.ruleExecution, execution.active {
            V2StatusDivider()
            HStack(spacing: DesignTokens.Space.s2) {
                VDIcon(.play, size: 12)
                Text("Regras · \(execution.completed)/\(execution.steps.count)").monospacedDigit()
                ProgressView(value: Double(execution.completed), total: Double(max(execution.steps.count, 1)))
                    .progressViewStyle(.linear)
                    .tint(DesignTokens.Colors.ai)
                    .frame(width: 48)
            }
            .foregroundStyle(DesignTokens.Colors.aiText)
            .padding(.horizontal, DesignTokens.Space.s2)
        } else if claude.isWorking {
            V2StatusDivider()
            HStack(spacing: DesignTokens.Space.s2) {
                ProgressView().controlSize(.mini)
                Text(claude.isThinking ? "IA pensando…" : "IA trabalhando…")
            }
            .foregroundStyle(DesignTokens.Colors.aiText)
            .padding(.horizontal, DesignTokens.Space.s2)
        }
    }

    // MARK: Ambiente

    @ViewBuilder
    private var environmentSegment: some View {
        if let workspace {
            V2RemoteEnvironmentSegment(workspace: workspace)
        } else {
            HStack(spacing: DesignTokens.Space.s2) {
                VDIcon(.folder, size: 13)
                Text("Local")
            }
            .padding(.horizontal, DesignTokens.Space.s2)
            .help(model.store.root.path(percentEncoded: false))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Ambiente: local")
        }
    }

    // MARK: Check, terminal, branch

    private var checkLabel: String {
        guard let check = model.checks.first else { return "Sem checks" }
        let time = check.createdAt.formatted(date: .omitted, time: .shortened)
        return (check.passed ? "Último check aprovado · " : "Último check reprovado · ") + time
    }

    private var checkSegment: some View {
        V2StatusSegment(control: "v2_status_bar.check", label: "Abrir Qualidade › Regras") {
            onOpenChecks()
        } content: {
            VDIcon(.rule, size: 13)
            Text(checkLabel)
        }
    }

    private var terminalIDs: [UUID] {
        claude.terminals.keys.sorted { (claude.terminals[$0]?.number ?? 0) < (claude.terminals[$1]?.number ?? 0) }
    }

    @ViewBuilder
    private var terminalSegment: some View {
        if claude.terminals.isEmpty {
            V2StatusSegment(control: "v2_status_bar.terminal", label: "Abrir terminal (⌃`)") {
                claude.openTerminal()
            } content: {
                VDIcon(.terminal, size: 13)
                Text("Terminal")
            }
        } else {
            Menu {
                ForEach(terminalIDs, id: \.self) { id in
                    LoggedButton(claude.terminals[id]?.title ?? "Terminal") { onOpenTerminal(id) }
                        .loggedControl(control: "v2_status_bar.terminal_open", label: "Abrir terminal")
                }
                Divider()
                LoggedButton("Novo terminal") { claude.openTerminal() }
                    .loggedControl(control: "v2_status_bar.terminal_new", label: "Novo terminal")
            } label: {
                HStack(spacing: DesignTokens.Space.s2) {
                    VDIcon(.terminal, size: 13)
                    Text("Terminal (\(claude.terminals.count))")
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Terminais abertos")
        }
    }

    @ViewBuilder
    private var branchSegment: some View {
        if let branch {
            Text(branch)
                .font(DesignTokens.Typography.mono)
                .padding(.horizontal, DesignTokens.Space.s2)
                .help("Branch atual")
        }
    }
}

/// Botão de segmento da barra de status (.v2-sb-btn).
struct V2StatusSegment<Content: View>: View {
    let control: String
    let label: String
    let action: () -> Void
    let content: Content
    @State private var hovering = false

    init(control: String, label: String, action: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.control = control
        self.label = label
        self.action = action
        self.content = content()
    }

    var body: some View {
        LoggedButton(action: action) { inner }
            .loggedControl(control: control, label: label)
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help(label)
    }

    private var inner: some View {
        HStack(spacing: DesignTokens.Space.s2) { content }
            .padding(.horizontal, DesignTokens.Space.s2)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous)
                    .fill(hovering ? DesignTokens.Colors.surface200 : Color.clear)
            )
            .contentShape(Rectangle())
    }
}

struct V2StatusDivider: View {
    var body: some View {
        Rectangle()
            .fill(DesignTokens.Colors.line)
            .frame(width: 1, height: 16)
            .accessibilityHidden(true)
    }
}

private struct V2Meter: View {
    let title: String
    let percent: Double
    let tint: Color
    private static let trackWidth: CGFloat = 36

    private var fraction: CGFloat { CGFloat(min(max(percent / 100, 0), 1)) }

    var body: some View {
        HStack(spacing: DesignTokens.Space.s1) {
            Text(title)
            Capsule()
                .fill(DesignTokens.Colors.surface300)
                .frame(width: Self.trackWidth, height: 4)
                .overlay(alignment: .leading) {
                    Capsule().fill(tint).frame(width: Self.trackWidth * fraction, height: 4)
                }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(Int(percent.rounded()))%")
    }
}

/// Lê a branch atual de `.git/HEAD`, sem executar Git.
enum V2Git {
    static func branch(at root: URL) -> String? {
        let head = root.appending(path: ".git/HEAD")
        guard let text = try? String(contentsOf: head, encoding: .utf8) else { return nil }
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "ref: refs/heads/"
        if line.hasPrefix(prefix) { return String(line.dropFirst(prefix.count)) }
        return line.isEmpty ? nil : String(line.prefix(7))
    }
}
