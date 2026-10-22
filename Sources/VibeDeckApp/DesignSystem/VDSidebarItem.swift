import SwiftUI

/// Item de barra lateral (.vd-side): ícone na cor da marca, rótulo e contagem.
struct VDSidebarItem: View {
    let title: String
    var icon: VDIconName?
    var count: Int?
    var isSelected: Bool = false
    var isMuted: Bool = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        LoggedButton(action: action) {
            HStack(spacing: 10) {
                if let icon {
                    VDIcon(icon, size: 14)
                        .foregroundStyle(DesignTokens.Colors.brandText)
                        .frame(width: 18)
                }
                Text(title)
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(isMuted ? DesignTokens.Colors.inkMuted : DesignTokens.Colors.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let count {
                    Text("\(count)")
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(DesignTokens.Colors.inkMuted)
                }
            }
            .padding(.horizontal, DesignTokens.Space.s3)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous)
                    .fill(backgroundColor)
            )
            .contentShape(Rectangle())
        }
        .loggedControl(control: "vd_sidebar_item.select", label: title)
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var backgroundColor: Color {
        if isSelected { return DesignTokens.Colors.surface300 }
        if hovering { return DesignTokens.Colors.surface200 }
        return Color.clear
    }
}
