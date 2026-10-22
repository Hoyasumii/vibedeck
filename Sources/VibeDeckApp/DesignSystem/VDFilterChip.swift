import SwiftUI

/// Chip de filtro alternável (.vd-chip), com ícone, tom e contagem opcionais.
struct VDFilterChip: View {
    let title: String
    var icon: VDIconName?
    var tone: VDTone?
    var count: Int?
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 6) {
                if let icon {
                    VDIcon(icon, size: 13)
                        .foregroundStyle(tone?.foreground ?? DesignTokens.Colors.inkMuted)
                }
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                if let count {
                    Text("\(count)")
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(DesignTokens.Colors.ink)
                }
            }
            .foregroundStyle(isOn ? DesignTokens.Colors.ink : DesignTokens.Colors.inkMuted)
            .padding(.horizontal, DesignTokens.Space.s3)
            .frame(height: 30)
            .background(Capsule().fill(isOn ? DesignTokens.Colors.surface300 : Color.clear))
            .overlay(
                Capsule().strokeBorder(
                    isOn ? DesignTokens.Colors.lineStrong : DesignTokens.Colors.line, lineWidth: 1)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
