import SwiftUI

/// Selo em pílula (.vd-badge) com tom semântico.
struct VDBadge: View {
    let title: String
    var icon: VDIconName?
    var tone: VDTone = .neutral

    init(_ title: String, icon: VDIconName? = nil, tone: VDTone = .neutral) {
        self.title = title
        self.icon = icon
        self.tone = tone
    }

    var body: some View {
        HStack(spacing: DesignTokens.Space.s1) {
            if let icon {
                VDIcon(icon, size: 11)
            }
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(tone.foreground)
        .padding(.horizontal, DesignTokens.Space.s2)
        .frame(height: 22)
        .background(Capsule().fill(tone.soft))
    }
}
