import SwiftUI

/// Trilho de espaços (prancha 18): Planejar, Automação, Qualidade e Projeto; busca, ajustes e projeto embaixo.
struct V2Rail: View {
    let selected: V2Space
    let projectName: String
    let onSelect: (V2Space) -> Void
    let onSearch: () -> Void
    let onSettings: () -> Void
    let onProject: () -> Void

    var body: some View {
        VStack(spacing: DesignTokens.Space.s2) {
            ForEach(V2Space.allCases) { space in
                V2RailButton(space: space, isOn: space == selected) { onSelect(space) }
            }
            Spacer(minLength: DesignTokens.Space.s2)
            bottom
        }
        .padding(.horizontal, DesignTokens.Space.s2)
        .padding(.vertical, DesignTokens.Space.s3)
        .frame(width: DesignTokens.V2Layout.railWidth)
        .frame(maxHeight: .infinity)
        .background { railBackground }
        .overlay(alignment: .trailing) { railEdge }
    }

    private var railBackground: some View {
        DesignTokens.Colors.bgSidebar.ignoresSafeArea(.container, edges: .top)
    }

    private var railEdge: some View {
        Rectangle()
            .fill(DesignTokens.Colors.line)
            .frame(width: 1)
            .ignoresSafeArea(.container, edges: .top)
    }

    private var bottom: some View {
        VStack(spacing: DesignTokens.Space.s2) {
            V2RailIconButton(icon: .search, label: "Buscar e filtrar (⌘K)", control: "v2_rail.search", action: onSearch)
            V2RailIconButton(icon: .script, label: "Ajustes", control: "v2_rail.settings", action: onSettings)
            projectButton
        }
    }

    private var projectButton: some View {
        LoggedButton(action: onProject) {
            VDLogo(size: 26)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                        .fill(DesignTokens.Colors.surface100)
                )
        }
        .loggedControl(control: "v2_rail.project", label: "Mostrar vibedeck.json no Finder")
        .buttonStyle(.plain)
        .help("Projeto: \(projectName). Mostra vibedeck.json no Finder")
        .accessibilityLabel("Projeto: \(projectName)")
    }
}

private struct V2RailButton: View {
    let space: V2Space
    let isOn: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        LoggedButton(action: action) { label }
            .loggedControl(control: "v2_rail.space", label: space.title)
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help(space.title)
            .accessibilityLabel(space.title)
            .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var label: some View {
        VStack(spacing: DesignTokens.Space.s1) {
            VDIcon(space.icon, size: 18)
                .foregroundStyle(isOn ? DesignTokens.Colors.brandText : DesignTokens.Colors.inkMuted)
            Text(space.title)
                .font(DesignTokens.Typography.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(isOn ? DesignTokens.Colors.ink : DesignTokens.Colors.inkMuted)
        }
        .frame(width: DesignTokens.V2Layout.railItemWidth, height: DesignTokens.V2Layout.railItemHeight)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous).fill(background)
        )
        .contentShape(Rectangle())
    }

    private var background: Color {
        if isOn { return DesignTokens.Colors.surface300 }
        if hovering { return DesignTokens.Colors.surface200 }
        return Color.clear
    }
}

private struct V2RailIconButton: View {
    let icon: VDIconName
    let label: String
    let control: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        LoggedButton(action: action) { content }
            .loggedControl(control: control, label: label)
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help(label)
            .accessibilityLabel(label)
    }

    private var content: some View {
        VDIcon(icon, size: 18)
            .foregroundStyle(DesignTokens.Colors.inkMuted)
            .frame(width: DesignTokens.V2Layout.railItemWidth, height: 44)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                    .fill(hovering ? DesignTokens.Colors.surface200 : Color.clear)
            )
            .contentShape(Rectangle())
    }
}
