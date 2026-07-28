import SwiftUI

// MARK: - Muscle group picker on a body diagram
//
// Two figures, front and back, with a labelled button for each muscle group
// beside the figure it belongs to and a thin connector to that muscle. Finding
// "rear delts" in a list means already knowing the word; here you can point at
// the part of you that aches — the muscles themselves are tappable.
//
// The artwork is "Muscles front and back" from Wikimedia Commons by OpenStax,
// Tomáš Kebert and umimeto.org, CC BY-SA 4.0, annotated per muscle group and
// halved left/right to save width. See artwork/ART-CREDITS.md. All geometry
// comes from BodyDiagram.json — no shape is hard-coded here, so relabelling in
// Inkscape and re-running the converter is enough to change what is selectable.

struct MuscleBodyPicker: View {
    @Binding var selection: MuscleGroup?

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 0) {
                labelColumn(Self.frontLabels, trailing: true)
                figure(isBack: false, labels: Self.frontLabels)
                viewCaptions
                figure(isBack: true, labels: Self.backLabels)
                labelColumn(Self.backLabels, trailing: false)
            }
            // Taller than it was: each half is narrow (about 0.28 as wide as it
            // is high), so height — not width — is what limits how big the
            // bodies can be drawn, and bigger bodies are easier to hit.
            .frame(height: 360)

            Button {
                selection = nil
            } label: {
                Text("all muscle groups")
                    .font(.subheadline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(selection == nil
                                               ? Color.blue
                                               : Color.secondary.opacity(0.15)))
                    .foregroundStyle(selection == nil ? Color.white : Color.primary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Which label goes on which side
    //
    // Worked out from the drawing rather than listed by hand, so the labels
    // follow the artwork instead of drifting out of step with it — an earlier
    // version kept fifteen hand-tuned positions, and every one of them was
    // wrong the moment the artwork changed.
    //
    // A muscle drawn on both figures (traps, side delts) gets its label on the
    // side where more of it shows, and stays tappable on both: one label is
    // clearer than the same word twice, but you can still reach the traps from
    // the front if that is how you picture them.

    private static func split() -> (front: [MuscleGroup], back: [MuscleGroup]) {
        func area(_ group: MuscleGroup, _ fig: FigureGeometry) -> CGFloat {
            guard let e = fig.groups.first(where: { $0.group == group }) else { return 0 }
            let r = e.path.boundingRect
            return r.width * r.height
        }
        var front: [MuscleGroup] = [], back: [MuscleGroup] = []
        for group in MuscleGroup.displayOrder {
            let f = area(group, .front), b = area(group, .back)
            guard f > 0 || b > 0 else { continue }
            if f >= b { front.append(group) } else { back.append(group) }
        }
        return (ordered(front, .front, labelsOnLeft: true),
                ordered(back, .back, labelsOnLeft: false))
    }

    /// Put the labels in the row order that leaves the fewest crossed
    /// connectors.
    ///
    /// Sorting by the muscle's height gets close but not all the way: the
    /// labels sit at evenly spaced rows while the muscles bunch up (three
    /// shoulder groups within a few percent of each other), and two connectors
    /// reaching across that bunch can still cross. So start from the height
    /// order and then swap neighbouring labels for as long as swapping removes
    /// a crossing — with at most eight labels a side this settles immediately.
    private static func ordered(_ groups: [MuscleGroup], _ fig: FigureGeometry,
                                labelsOnLeft: Bool) -> [MuscleGroup] {
        var order = groups.sorted { (centre($0, fig)?.y ?? 0) < (centre($1, fig)?.y ?? 0) }
        guard order.count > 2 else { return order }
        let edgeX: CGFloat = labelsOnLeft ? -0.6 : 1.6

        func target(_ g: MuscleGroup) -> CGPoint { centre(g, fig) ?? .zero }
        func rowY(_ index: Int) -> CGFloat { CGFloat(index) / CGFloat(order.count - 1) }
        func crosses(_ i: Int, _ j: Int, _ order: [MuscleGroup]) -> Bool {
            segmentsCross(CGPoint(x: edgeX, y: rowY(i)), target(order[i]),
                          CGPoint(x: edgeX, y: rowY(j)), target(order[j]))
        }
        func crossings(_ order: [MuscleGroup]) -> Int {
            var n = 0
            for i in 0..<order.count {
                for j in (i + 1)..<order.count where crosses(i, j, order) { n += 1 }
            }
            return n
        }

        var best = crossings(order)
        var improved = true
        while improved && best > 0 {
            improved = false
            for i in 0..<(order.count - 1) {
                var candidate = order
                candidate.swapAt(i, i + 1)
                let score = crossings(candidate)
                if score < best {
                    order = candidate
                    best = score
                    improved = true
                }
            }
        }
        return order
    }

    /// Standard orientation test for two line segments.
    private static func segmentsCross(_ p1: CGPoint, _ p2: CGPoint,
                                      _ p3: CGPoint, _ p4: CGPoint) -> Bool {
        func side(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Int {
            let v = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
            if v > 1e-9 { return 1 }
            if v < -1e-9 { return -1 }
            return 0
        }
        return side(p1, p2, p3) != side(p1, p2, p4)
            && side(p3, p4, p1) != side(p3, p4, p2)
    }

    /// Centre of a group on a figure, in 0…1 of that figure — where its
    /// connector points.
    static func centre(_ group: MuscleGroup, _ fig: FigureGeometry) -> CGPoint? {
        guard let entry = fig.groups.first(where: { $0.group == group }) else { return nil }
        let r = entry.path.boundingRect
        return CGPoint(x: r.midX, y: r.midY)
    }

    private static let frontLabels = split().front
    private static let backLabels = split().back

    /// The same order the diagram uses, so the buttons-only layout reads the
    /// same way: down the front, then down the back.
    static var frontOrder: [MuscleGroup] { frontLabels }
    static var backOrder: [MuscleGroup] { backLabels }

    // MARK: Figure

    /// "front ◀ / ▶ back", in the gap between the two halves.
    ///
    /// The captions used to sit under each figure, which cost height — the very
    /// thing the bodies are short of — and left it ambiguous whether the two
    /// halves were one body or two. In the gap, with an arrow into each half,
    /// they say which is which and cost nothing: the halves are narrow enough
    /// that there is width to spare.
    private var viewCaptions: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            caption("front", pointsLeft: true)
            caption("back", pointsLeft: false)
            Spacer(minLength: 0)
        }
        .frame(width: 30)
    }

    private func caption(_ text: String, pointsLeft: Bool) -> some View {
        // Turned on its side so the word fits a narrow gap without widening it,
        // at the same size as the group buttons.
        HStack(spacing: 2) {
            if pointsLeft { arrow(pointsLeft: true) }
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize()
                .rotationEffect(.degrees(-90))
                .frame(width: 16, height: 44)
            if !pointsLeft { arrow(pointsLeft: false) }
        }
    }

    private func arrow(pointsLeft: Bool) -> some View {
        Image(systemName: pointsLeft ? "arrowtriangle.left.fill"
                                     : "arrowtriangle.right.fill")
            .font(.system(size: 12, weight: .black))
            .foregroundStyle(.secondary)
    }

    private func figure(isBack: Bool, labels: [MuscleGroup]) -> some View {
        GeometryReader { geo in
            let size = geo.size
            let fig = isBack ? FigureGeometry.back : FigureGeometry.front
            let art = Self.drawnRect(in: size, aspect: fig.aspect)
            ZStack {
                // One Canvas for the whole figure rather than a view per shape:
                // there are around a hundred of them, and as separate views the
                // simulator ground to a halt.
                Canvas { context, _ in
                    let scale = CGAffineTransform(scaleX: art.width, y: art.height)
                    for entry in fig.ordered {
                        let path = entry.path.applying(scale)
                            .offsetBy(dx: art.minX, dy: art.minY)
                        context.fill(path, with: .color(Self.fill(for: entry.muscle,
                                                                  selected: selection)))
                        context.stroke(path, with: .color(.primary.opacity(0.55)),
                                       lineWidth: 0.6)
                    }
                }

                // Invisible tap targets, smallest last so it wins the overlap.
                ForEach(fig.groups, id: \.group) { entry in
                    ScaledPath(unitPath: entry.path)
                        .fill(Color.clear)
                        .contentShape(ScaledPath(unitPath: entry.path))
                        .frame(width: art.width, height: art.height)
                        .position(x: art.midX, y: art.midY)
                        .onTapGesture {
                            selection = (selection == entry.group) ? nil : entry.group
                        }
                        .accessibilityLabel(entry.group.label)
                }

                // Connectors, from each label's edge to the muscle's centre.
                ForEach(Array(labels.enumerated()), id: \.offset) { index, group in
                    if let c = Self.centre(group, fig) {
                        let target = CGPoint(x: art.minX + c.x * art.width,
                                             y: art.minY + c.y * art.height)
                        let edgeX = isBack ? size.width : 0
                        let edgeY = rowCentre(index: index, count: labels.count,
                                              height: size.height)
                        Path { path in
                            path.move(to: CGPoint(x: edgeX, y: edgeY))
                            path.addLine(to: target)
                        }
                        .stroke(selection == group ? Color.blue : Color.secondary.opacity(0.45),
                                lineWidth: selection == group ? 2.2 : 0.8)
                    }
                }
            }
        }
    }

    /// Muscle groups keep the drawing's warm tone so they read as muscle;
    /// everything else — bone, tendon, outline, and the muscles outside our
    /// fifteen — goes grey, so what can be tapped is what stands out.
    private static func fill(for muscle: MuscleGroup?, selected: MuscleGroup?) -> Color {
        // Bright enough to sit at the same weight as the muscles: the drawing
        // should read as one body, with colour — not lightness — saying what is
        // selectable.
        guard let muscle else { return Color.secondary.opacity(0.42) }
        return muscle == selected
            ? Color.blue.opacity(0.80)
            : Color(red: 0.94, green: 0.56, blue: 0.47)
    }

    /// The rectangle the figure occupies inside `size`, preserving its aspect.
    private static func drawnRect(in size: CGSize, aspect: CGFloat) -> CGRect {
        let height = min(size.height, size.width / aspect)
        let width = height * aspect
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2,
                      width: width, height: height)
    }

    // MARK: Labels

    private func labelColumn(_ labels: [MuscleGroup], trailing: Bool) -> some View {
        GeometryReader { geo in
            ForEach(Array(labels.enumerated()), id: \.offset) { index, group in
                let y = rowCentre(index: index, count: labels.count, height: geo.size.height)
                Button {
                    selection = (selection == group) ? nil : group
                } label: {
                    Text(group.shortLabel)
                        .font(.caption)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(selection == group
                                           ? Color.blue
                                           : Color.secondary.opacity(0.15))
                        )
                        .foregroundStyle(selection == group ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
                .frame(width: geo.size.width, alignment: trailing ? .trailing : .leading)
                .position(x: geo.size.width / 2, y: y)
            }
        }
        // Narrow on purpose: whatever the labels take, the two figures divide
        // between them, and the artwork is width-limited here.
        .frame(width: 76)
    }

    /// Labels are spread evenly down the column rather than placed at their
    /// muscle's own height: at true heights the shoulder labels would overlap
    /// each other, and the connector is what carries the meaning anyway.
    private func rowCentre(index: Int, count: Int, height: CGFloat) -> CGFloat {
        let inset: CGFloat = 14
        guard count > 1 else { return height / 2 }
        let usable = height - inset * 2
        return inset + usable * CGFloat(index) / CGFloat(count - 1)
    }
}
