import SwiftUI
import VibeDeckCore

/// Diagram of a workflow: steps stacked in order, with an arrow per transition labelled with its condition.
/// Going to the next step is a straight arrow; skipping ahead runs on the right, going back (loops) on the left,
/// and "Fim" shows where the run ends when no transition applies. Hovering a step highlights where it can go.
struct WorkflowDiagram: View {
    let steps: [WorkflowStep]
    let title: (WorkflowStep) -> String?
    let open: (WorkflowStep) -> Void

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            WorkflowDiagramCanvas(steps: steps, title: title, open: open)
                .padding(20)
        }
    }
}

/// The drawing itself, at its natural size (see `WorkflowDiagramLayout`).
struct WorkflowDiagramCanvas: View {
    let steps: [WorkflowStep]
    let title: (WorkflowStep) -> String?
    let open: (WorkflowStep) -> Void
    @State private var focus: Int?

    var body: some View {
        let layout = WorkflowDiagramLayout(steps: steps)
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                let startTop = layout.center(0).y - layout.halfHeight(0)
                arrow(from: CGPoint(x: layout.centerX, y: startTop - 22), to: CGPoint(x: layout.centerX, y: startTop),
                      color: .secondary, width: 1.5, dashed: false, in: &context)
                for edge in layout.edges {
                    let on = isOn(edge)
                    var path = Path()
                    path.move(to: edge.start)
                    if let lane = edge.laneX {
                        path.addLine(to: CGPoint(x: lane, y: edge.start.y))
                        path.addLine(to: CGPoint(x: lane, y: edge.end.y))
                    }
                    path.addLine(to: edge.end)
                    let color = self.color(edge).opacity(on ? 1 : 0.18)
                    let width: CGFloat = on && focus != nil ? 2.5 : 1.5
                    context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineJoin: .round, dash: edge.style == .end ? [5, 4] : []))
                    let before = edge.laneX.map { CGPoint(x: $0, y: edge.end.y) } ?? edge.start
                    head(at: edge.end, from: before, color: color, in: &context)
                }
            }

            pill("Início", color: .green)
                .position(x: layout.centerX, y: layout.center(0).y - layout.halfHeight(0) - 34)

            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                node(index, step)
                    .frame(width: layout.halfWidth(index) * 2, height: layout.halfHeight(index) * 2)
                    .position(layout.center(index))
            }

            pill("Fim", color: .gray)
                .frame(width: layout.halfWidth(steps.count) * 2, height: layout.halfHeight(steps.count) * 2)
                .position(layout.center(steps.count))

            ForEach(layout.edges) { edge in
                if let text = edge.label {
                    let on = isOn(edge)
                    // Padding and capsule before the width cap, so the capsule hugs short labels.
                    Text(text)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(.background, in: Capsule())
                        .overlay(Capsule().stroke(color(edge).opacity(0.5)))
                        .foregroundStyle(color(edge))
                        .frame(maxWidth: WorkflowDiagramLayout.labelWidth)
                        .opacity(on ? 1 : 0.25)
                        .position(edge.labelPoint)
                        .help(text)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(width: layout.size.width, height: layout.size.height)
    }

    private func node(_ index: Int, _ step: WorkflowStep) -> some View {
        let name = title(step)
        return HStack(spacing: 8) {
            Text("\(index + 1)")
                .font(.caption.weight(.bold)).monospacedDigit()
                .frame(width: 22, height: 22)
                .background(.tint.opacity(0.15), in: Circle())
            Image(systemName: symbol(step.kind))
            VStack(alignment: .leading, spacing: 1) {
                Text(name ?? step.ref).font(.callout.weight(.semibold)).lineLimit(1)
                Text(name == nil ? "não encontrado" : step.id)
                    .font(.caption2.monospaced())
                    .foregroundStyle(name == nil ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(focus == index ? Color.accentColor : .secondary.opacity(0.3), lineWidth: focus == index ? 2 : 1))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onHover { inside in
            if inside { focus = index } else if focus == index { focus = nil }
        }
        .onTapGesture(count: 2) { if name != nil { open(step) } }
        .help(name == nil ? step.ref : "Duplo clique abre \(name ?? step.ref)")
    }

    private func pill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12).padding(.vertical, 4)
            .background(color.opacity(0.18), in: Capsule())
    }

    private func isOn(_ edge: WorkflowDiagramLayout.Edge) -> Bool { focus == nil || edge.from == focus }

    private func color(_ edge: WorkflowDiagramLayout.Edge) -> Color {
        switch edge.style {
        case .end: .gray
        case .fallback: edge.isBack ? .orange : .secondary
        case .condition: edge.isBack ? .orange : .accentColor
        }
    }

    private func symbol(_ kind: NextStepKind) -> String {
        switch kind {
        case .agent: "person.crop.rectangle"
        case .command: "command"
        case .skill: "wand.and.stars"
        }
    }

    private func arrow(from: CGPoint, to: CGPoint, color: Color, width: CGFloat, dashed: Bool, in context: inout GraphicsContext) {
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, dash: dashed ? [5, 4] : []))
        head(at: to, from: from, color: color, in: &context)
    }

    private func head(at tip: CGPoint, from: CGPoint, color: Color, in context: inout GraphicsContext) {
        let angle = atan2(tip.y - from.y, tip.x - from.x)
        let size: CGFloat = 8, spread: CGFloat = .pi / 7
        var path = Path()
        path.move(to: tip)
        path.addLine(to: CGPoint(x: tip.x - size * cos(angle - spread), y: tip.y - size * sin(angle - spread)))
        path.addLine(to: CGPoint(x: tip.x - size * cos(angle + spread), y: tip.y - size * sin(angle + spread)))
        path.closeSubpath()
        context.fill(path, with: .color(color))
    }
}

/// Geometry of `WorkflowDiagram`. Rows are the steps in order plus "Fim" (row `steps.count`); side edges get lanes
/// so arrows spanning overlapping rows never share a vertical line.
struct WorkflowDiagramLayout {
    enum Style { case condition, fallback, end }

    struct Edge: Identifiable {
        let id: Int
        let from: Int
        /// Row of the target step; `count` is "Fim".
        let to: Int
        let label: String?
        let style: Style
        var side = 0  // 0 straight, 1 right, -1 left
        var lane = 0
        var start = CGPoint.zero
        var end = CGPoint.zero
        var laneX: CGFloat?
        var labelPoint = CGPoint.zero
        var isBack: Bool { to <= from }
    }

    static let nodeSize = CGSize(width: 240, height: 54)
    static let endSize = CGSize(width: 70, height: 26)
    static let gapY: CGFloat = 74
    static let top: CGFloat = 50
    static let laneWidth: CGFloat = 34
    static let laneInset: CGFloat = 26
    static let labelRoom: CGFloat = 85
    static let labelWidth: CGFloat = 160
    static let labelHeight: CGFloat = 21

    let count: Int
    private(set) var edges: [Edge] = []
    private(set) var centerX: CGFloat = 0
    private(set) var size = CGSize.zero

    init(steps: [WorkflowStep]) {
        count = steps.count
        let index = Dictionary(steps.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        var list: [Edge] = []
        for (i, step) in steps.enumerated() {
            for t in step.transitions {
                guard let j = index[t.to] else { continue }
                list.append(Edge(id: list.count, from: i, to: j, label: t.verdict ?? t.when ?? "senão", style: t.isFallback ? .fallback : .condition))
            }
            if !step.transitions.contains(where: \.isFallback) {
                list.append(Edge(id: list.count, from: i, to: count, label: step.transitions.isEmpty ? nil : "nenhuma vale", style: .end))
            }
        }

        // Routes: one straight arrow per step to the next row; the rest go around, on lanes.
        var straight = Set<Int>()
        for k in list.indices {
            if list[k].to == list[k].from + 1, straight.insert(list[k].from).inserted {
                list[k].side = 0
            } else {
                list[k].side = list[k].to > list[k].from ? 1 : -1
            }
        }
        var laneCount = [1: 0, -1: 0]
        for side in [1, -1] {
            var lanes: [[ClosedRange<Int>]] = []
            let ks = list.indices.filter { list[$0].side == side }
                .sorted { abs(list[$0].to - list[$0].from) < abs(list[$1].to - list[$1].from) }
            for k in ks {
                let rows = min(list[k].from, list[k].to)...max(list[k].from, list[k].to)
                if let free = lanes.firstIndex(where: { !$0.contains { $0.overlaps(rows) } }) {
                    lanes[free].append(rows)
                    list[k].lane = free
                } else {
                    lanes.append([rows])
                    list[k].lane = lanes.count - 1
                }
            }
            laneCount[side] = lanes.count
        }

        func extent(_ side: Int) -> CGFloat {
            let lanes = laneCount[side] ?? 0
            let base = Self.nodeSize.width / 2
            return lanes == 0 ? base + 20 : base + Self.laneInset + CGFloat(lanes - 1) * Self.laneWidth + Self.labelRoom
        }
        centerX = extent(-1)
        edges = list
        size = CGSize(width: centerX + extent(1), height: center(count).y + halfHeight(count) + 10)

        // Ports: edges touching the same side of a node are spread along its height.
        var ports: [String: [(edge: Int, isStart: Bool)]] = [:]
        for k in edges.indices where edges[k].side != 0 {
            let e = edges[k]
            ports["\(e.from):\(e.side)", default: []].append((k, true))
            ports["\(e.to):\(e.side)", default: []].append((k, false))
        }
        for k in edges.indices {
            let e = edges[k]
            if e.side == 0 {
                edges[k].start = CGPoint(x: centerX, y: center(e.from).y + halfHeight(e.from))
                edges[k].end = CGPoint(x: centerX, y: center(e.to).y - halfHeight(e.to))
                continue
            }
            let side = CGFloat(e.side)
            let laneX = centerX + side * (Self.nodeSize.width / 2 + Self.laneInset + CGFloat(e.lane) * Self.laneWidth)
            func port(_ row: Int, isStart: Bool) -> CGPoint {
                // Outer lanes take the outer ports so lines don't cross near the node.
                let list = (ports["\(row):\(e.side)"] ?? []).sorted { a, b in
                    let la = edges[a.edge].lane, lb = edges[b.edge].lane
                    return la != lb ? la > lb : (a.edge, a.isStart ? 0 : 1) < (b.edge, b.isStart ? 0 : 1)
                }
                let i = list.firstIndex { $0.edge == k && $0.isStart == isStart } ?? 0
                let fraction = CGFloat(i + 1) / CGFloat(list.count + 1)
                let h = halfHeight(row) * 0.8
                return CGPoint(x: centerX + side * halfWidth(row), y: center(row).y - h + 2 * h * fraction)
            }
            edges[k].start = port(e.from, isStart: true)
            edges[k].end = port(e.to, isStart: false)
            edges[k].laneX = laneX
        }

        // Labels sit in the gap right after the source (right before it when going back), away from the nodes;
        // labels sharing a gap are stacked.
        var gaps: [Int: [Int]] = [:]
        for k in edges.indices where edges[k].label != nil {
            let e = edges[k]
            gaps[e.to > e.from ? e.from + 1 : e.from, default: []].append(k)
        }
        for (gap, ks) in gaps {
            let ordered = ks.sorted { (edges[$0].side, edges[$0].lane) < (edges[$1].side, edges[$1].lane) }
            for (i, k) in ordered.enumerated() {
                let offset = (CGFloat(i) - CGFloat(ordered.count - 1) / 2) * (Self.labelHeight + 3)
                edges[k].labelPoint = CGPoint(x: edges[k].laneX ?? centerX, y: gapY(gap) + offset)
            }
        }
    }

    /// Middle of the gap above `row` (above the first step: between "Início" and it).
    func gapY(_ row: Int) -> CGFloat {
        guard row > 0 else { return center(0).y - halfHeight(0) - 14 }
        return (center(row - 1).y + halfHeight(row - 1) + center(row).y - halfHeight(row)) / 2
    }

    func halfWidth(_ row: Int) -> CGFloat { (row == count ? Self.endSize.width : Self.nodeSize.width) / 2 }
    func halfHeight(_ row: Int) -> CGFloat { (row == count ? Self.endSize.height : Self.nodeSize.height) / 2 }

    func center(_ row: Int) -> CGPoint {
        let pitch = Self.nodeSize.height + Self.gapY
        let y = Self.top + CGFloat(row) * pitch + (row == count ? Self.endSize.height / 2 : Self.nodeSize.height / 2)
        return CGPoint(x: centerX, y: y)
    }
}
