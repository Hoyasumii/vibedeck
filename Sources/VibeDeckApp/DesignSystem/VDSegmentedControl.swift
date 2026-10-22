import SwiftUI

struct VDSegmentOption<Value: Hashable>: Identifiable {
    let value: Value
    let label: String
    var id: Value { value }
}

/// Controle segmentado em pílula (.vd-seg).
struct VDSegmentedControl<Value: Hashable>: View {
    let options: [VDSegmentOption<Value>]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                let isOn = option.value == selection
                LoggedButton {
                    selection = option.value
                } label: {
                    Text(option.label)
                        .font(.system(size: 13, weight: isOn ? .semibold : .medium))
                        .foregroundStyle(isOn ? DesignTokens.Colors.ink : DesignTokens.Colors.inkMuted)
                        .padding(.horizontal, DesignTokens.Space.s4)
                        .frame(height: 26)
                        .background(
                            Capsule().fill(isOn ? DesignTokens.Colors.surface100 : Color.clear)
                        )
                        .contentShape(Capsule())
                }
                .loggedControl(control: "vd_segmented.select", label: option.label)
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(DesignTokens.Colors.surface200))
    }
}
