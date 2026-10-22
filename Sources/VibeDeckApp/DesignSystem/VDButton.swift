import SwiftUI

enum VDButtonKind { case primary, secondary, quiet, danger }
enum VDButtonSize { case md, lg }

/// Botão em pílula do DS (.vd-btn). Ação simples; desabilita via `.disabled(_:)`.
struct VDButton: View {
    let title: String?
    var icon: VDIconName?
    var kind: VDButtonKind = .secondary
    var size: VDButtonSize = .md
    let action: () -> Void

    init(_ title: String? = nil, icon: VDIconName? = nil, kind: VDButtonKind = .secondary,
         size: VDButtonSize = .md, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.kind = kind
        self.size = size
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignTokens.Space.s2) {
                if let icon {
                    VDIcon(icon, size: size == .lg ? 16 : 13)
                }
                if let title {
                    Text(title)
                }
            }
        }
        .buttonStyle(VDButtonStyle(kind: kind, size: size))
    }
}

struct VDButtonStyle: ButtonStyle {
    var kind: VDButtonKind
    var size: VDButtonSize
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let height: CGFloat = size == .lg ? 44 : 30
        let hPad: CGFloat = size == .lg ? DesignTokens.Space.s6 : DesignTokens.Space.s3
        let fontSize: CGFloat = size == .lg ? 15 : 13
        let pressed = configuration.isPressed
        return configuration.label
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundStyle(foreground)
            .lineLimit(1)
            .padding(.horizontal, hPad)
            .frame(height: height)
            .background(Capsule().fill(background(pressed: pressed)))
            .overlay(Capsule().strokeBorder(border, lineWidth: 1))
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.45)
    }

    private var foreground: Color {
        switch kind {
        case .primary: return DesignTokens.Colors.onBrand
        case .secondary, .quiet: return DesignTokens.Colors.ink
        case .danger: return DesignTokens.Colors.fix
        }
    }

    private func background(pressed: Bool) -> Color {
        switch kind {
        case .primary: return pressed ? DesignTokens.Colors.brandHover : DesignTokens.Colors.brand
        case .secondary: return pressed ? DesignTokens.Colors.surface200 : DesignTokens.Colors.surface100
        case .quiet: return pressed ? DesignTokens.Colors.surface200 : Color.clear
        case .danger: return pressed ? DesignTokens.Colors.fixSoft : DesignTokens.Colors.surface100
        }
    }

    private var border: Color {
        switch kind {
        case .secondary, .danger: return DesignTokens.Colors.lineStrong
        case .primary, .quiet: return Color.clear
        }
    }
}
