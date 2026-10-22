import SwiftUI

enum VDStepKind {
    case agent, command, skill

    var icon: VDIconName {
        switch self {
        case .agent: return .agent
        case .command: return .command
        case .skill: return .skill
        }
    }

    var label: String {
        switch self {
        case .agent: return "Agente"
        case .command: return "Comando"
        case .skill: return "Skill"
        }
    }
}

struct VDStepTransition: Identifiable {
    enum Kind { case always, ifTrue, otherwise }
    let id = UUID()
    var kind: Kind = .always
    var when: String?
    var target: String
    var isBack: Bool = false
}

/// Cartão de etapa de workflow (.vd-step).
struct VDStepCard: View {
    let index: Int
    var kind: VDStepKind = .agent
    let title: String
    var stepID: String?
    var isStart: Bool = false
    var isSelected: Bool = false
    var note: String?
    var transitions: [VDStepTransition] = []
    var maxVisits: Int?
    var onMore: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.s2) {
            header
            if let note, !note.isEmpty {
                Text(note)
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(DesignTokens.Colors.inkMuted)
            }
            VStack(alignment: .leading, spacing: 4) {
                if transitions.isEmpty {
                    Text("Sem transições: o workflow termina aqui.")
                        .font(DesignTokens.Typography.body)
                        .foregroundStyle(DesignTokens.Colors.inkFaint)
                        .padding(.horizontal, DesignTokens.Space.s2)
                        .frame(minHeight: 28, alignment: .leading)
                } else {
                    ForEach(transitions) { t in
                        transitionRow(t)
                    }
                }
            }
            if let maxVisits {
                Text("Máx. vezes: \(maxVisits)")
                    .font(.system(size: 12))
                    .foregroundStyle(DesignTokens.Colors.inkMuted)
            }
        }
        .padding(.horizontal, DesignTokens.Space.s4)
        .padding(.vertical, DesignTokens.Space.s3)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                .fill(DesignTokens.Colors.surface100)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                .strokeBorder(isSelected ? DesignTokens.Colors.brand : DesignTokens.Colors.line, lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(spacing: DesignTokens.Space.s2) {
            Text("\(index)")
                .font(.system(size: 12, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(DesignTokens.Colors.ink)
                .frame(width: 22, height: 22)
                .background(Circle().fill(DesignTokens.Colors.surface300))
            VDIcon(kind.icon, size: 14)
                .foregroundStyle(DesignTokens.Colors.brandText)
                .help(kind.label)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if isStart {
                Text("Início")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(DesignTokens.Colors.done)
                    .padding(.horizontal, DesignTokens.Space.s2)
                    .frame(height: 20)
                    .background(Capsule().fill(DesignTokens.Colors.doneSoft))
            }
            if let stepID {
                Text(stepID)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(DesignTokens.Colors.inkMuted)
            }
            if let onMore {
                LoggedButton(action: onMore) {
                    VDIcon(.more, size: 13)
                        .foregroundStyle(DesignTokens.Colors.inkMuted)
                        .frame(width: 28, height: 28)
                        .contentShape(Circle())
                }
                .loggedControl(control: "vd_step_card.more", label: "Opções da etapa")
                .buttonStyle(.plain)
                .accessibilityLabel("Opções da etapa \(title)")
            }
        }
    }

    private func transitionRow(_ t: VDStepTransition) -> some View {
        let op: String
        switch t.kind {
        case .always: op = "="
        case .ifTrue: op = "se"
        case .otherwise: op = "senão"
        }
        return HStack(spacing: DesignTokens.Space.s2) {
            Text(op)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(t.kind == .otherwise ? DesignTokens.Colors.inkMuted : DesignTokens.Colors.aiText)
                .frame(minWidth: 22)
            if let when = t.when {
                Text(when)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
            }
            VDIcon(.arrow, size: 11)
                .foregroundStyle(DesignTokens.Colors.inkMuted)
            Text(t.target)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(t.isBack ? DesignTokens.Colors.brandText : DesignTokens.Colors.ink)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DesignTokens.Space.s2)
        .frame(minHeight: 28)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous)
                .fill(DesignTokens.Colors.surface200)
        )
    }
}
