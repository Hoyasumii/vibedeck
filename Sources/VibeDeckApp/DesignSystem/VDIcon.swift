import SwiftUI

/// Nomes de ícone do protótipo (vibedeck-components.js, ICONS) mapeados para SF Symbols.
/// `terminal` e `link` reaproveitam os ícones do protótipo via SF Symbols equivalentes.
enum VDIconName: String, CaseIterable {
    case fix, change, remove, disable, hide, note, folder, link, review, doc, all
    case plus, minus, check, close, updown, chevron, arrow, send, more, search
    case play, stop, attach, copy, tag, clock, warn, help, archive, seal, inspector
    case kit, flow, stack, pattern, claude, graph, terminal, rule, must, should
    case scope, globe, idea, agent, command, skill, workflow, script, manual, ai, human

    var symbolName: String {
        switch self {
        case .fix: return "wrench.adjustable"
        case .change: return "pencil"
        case .remove: return "trash"
        case .disable: return "nosign"
        case .hide: return "eye.slash"
        case .note: return "text.bubble"
        case .folder: return "folder"
        case .link: return "link"
        case .review: return "list.bullet"
        case .doc: return "doc.text"
        case .all: return "square.grid.2x2"
        case .plus: return "plus"
        case .minus: return "minus"
        case .check: return "checkmark"
        case .close: return "xmark"
        case .updown: return "chevron.up.chevron.down"
        case .chevron: return "chevron.right"
        case .arrow: return "arrow.right"
        case .send: return "arrow.up"
        case .more: return "ellipsis"
        case .search: return "magnifyingglass"
        case .play: return "play.fill"
        case .stop: return "stop.fill"
        case .attach: return "paperclip"
        case .copy: return "doc.on.doc"
        case .tag: return "tag"
        case .clock: return "clock"
        case .warn: return "exclamationmark.triangle"
        case .help: return "questionmark.circle"
        case .archive: return "archivebox"
        case .seal: return "checkmark.seal"
        case .inspector: return "sidebar.right"
        case .kit: return "shippingbox"
        case .flow: return "arrow.turn.down.right"
        case .stack: return "square.3.layers.3d"
        case .pattern: return "building.columns"
        case .claude: return "doc.on.doc.fill"
        case .graph: return "point.3.connected.trianglepath.dotted"
        case .terminal: return "terminal"
        case .rule: return "checkmark.shield"
        case .must: return "exclamationmark.shield"
        case .should: return "shield"
        case .scope: return "scope"
        case .globe: return "globe"
        case .idea: return "lightbulb"
        case .agent: return "person.crop.square"
        case .command: return "command"
        case .skill: return "wand.and.stars"
        case .workflow: return "point.topleft.down.to.point.bottomright.curvepath"
        case .script: return "gearshape"
        case .manual: return "hand.point.up.left"
        case .ai: return "sparkle"
        case .human: return "person"
        }
    }
}

/// Ícone do Design System: SF Symbol com traço leve, herda `foregroundStyle`.
struct VDIcon: View {
    let name: VDIconName
    var size: CGFloat = 15
    var weight: Font.Weight = .medium

    init(_ name: VDIconName, size: CGFloat = 15, weight: Font.Weight = .medium) {
        self.name = name
        self.size = size
        self.weight = weight
    }

    var body: some View {
        Image(systemName: name.symbolName)
            .font(.system(size: size, weight: weight))
            .imageScale(.medium)
            .accessibilityHidden(true)
    }
}
