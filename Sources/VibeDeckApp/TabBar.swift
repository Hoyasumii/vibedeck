import AppKit
import SwiftUI

/// Horizontal strip of open tabs above the detail column. Shown only when more than one tab is open.
struct TabBar: View {
    let tabs: [SidebarItem]
    let active: Int
    let onSelect: (Int) -> Void
    let onClose: (Int) -> Void
    @Environment(ProjectModel.self) private var model

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                ForEach(Array(tabs.enumerated()), id: \.offset) { index, item in
                    TabButton(title: model.title(for: item), symbol: model.symbol(for: item), isActive: index == active) {
                        onSelect(index)
                    } onClose: {
                        onClose(index)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .scrollIndicators(.never)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}

private struct TabButton: View {
    let title: String
    let symbol: String
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    @State private var hovering = false
    @State private var middleClickMonitor: Any?

    private var background: AnyShapeStyle {
        if isActive { AnyShapeStyle(.selection.opacity(0.25)) }
        else if hovering { AnyShapeStyle(.quaternary) }
        else { AnyShapeStyle(Color.clear) }
    }

    var body: some View {
        HStack(spacing: 6) {
            Label(title, systemImage: symbol)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 180, alignment: .leading)
            Button(action: onClose) {
                Image(systemName: "xmark").font(.caption2.weight(.bold))
            }
            .buttonStyle(.borderless)
            .help("Fechar aba")
            .opacity(isActive || hovering ? 1 : 0)
        }
        .font(.callout)
        .foregroundStyle(isActive ? .primary : .secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(background, in: .capsule)
        .contentShape(.capsule)
        .onTapGesture(perform: onSelect)
        .onHover { inside in
            hovering = inside
            inside ? installMiddleClickMonitor() : removeMiddleClickMonitor()
        }
        .onDisappear(perform: removeMiddleClickMonitor)
        .help(title)
    }

    /// SwiftUI has no middle-click gesture, so while the pointer is over the tab we watch
    /// for an `otherMouseUp` of button 2 and treat it as "close", like browsers do.
    private func installMiddleClickMonitor() {
        guard middleClickMonitor == nil else { return }
        middleClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseUp) { event in
            guard event.buttonNumber == 2 else { return event }
            onClose()
            return nil
        }
    }

    private func removeMiddleClickMonitor() {
        if let middleClickMonitor { NSEvent.removeMonitor(middleClickMonitor) }
        middleClickMonitor = nil
    }
}
