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

    /// Whether the aerobic filter is on, when there is one. Beside the muscles
    /// because that is where a user looks for "which sort of exercise", even
    /// though aerobic is a kind rather than a group.
    ///
    /// Optional because not every use of this picker is a filter: choosing
    /// which muscles an exercise works is not a place to offer "aerobic
    /// instead", and a button that means nothing is worse than no button.
    var aerobic: Binding<Bool>? = nil

    /// How tall to draw, at MOST. Height is what limits these — each half is
    /// only about 0.28 as wide as it is high — so this is the one dial worth
    /// having: a Mac window has room the phone does not.
    ///
    /// At most, because a column narrower than two figures this tall cannot
    /// have them: see `drawnHeight`.
    var height: CGFloat = 400

    /// The width this picker was actually given, once it has been laid out —
    /// 0 on the very first pass.
    @State private var offeredWidth: CGFloat = 0

    /// The height the figures are really drawn at.
    ///
    /// Both halves are drawn to ONE height, which is the whole point of
    /// working it out here rather than leaving it to the HStack. Left to
    /// itself the stack squeezes the two figures to the same WIDTH, and since
    /// the front half is the wider of the two — 0.280 against 0.247 — equal
    /// widths mean a shorter front body standing beside a taller back one.
    /// It looked like a drawing mistake and was reported as one.
    ///
    /// Squeezing is also how the picture ends up smaller than the space it
    /// was given: everything below comes out of the width, so what is left
    /// over after the labels decides the height, and a column with room to
    /// spare draws at `height`.
    private var drawnHeight: CGFloat {
        guard offeredWidth > 0 else { return height }
        return Self.heightThatFits(width: offeredWidth, atMost: height)
    }

    /// The tallest the two figures can be drawn side by side in `width`.
    ///
    /// The label columns and the captions between the figures are fixed, so
    /// they come off the top; what is left is divided by the two aspects,
    /// which is the width a figure of a given height needs.
    static func heightThatFits(width: CGFloat, atMost cap: CGFloat) -> CGFloat {
        let fixed = labelColumnWidth * 2 + captionColumnWidth
        let perPointOfHeight = FigureGeometry.front.aspect + FigureGeometry.back.aspect
        guard perPointOfHeight > 0 else { return cap }
        // A floor rather than nothing: a sliver of a body is still a body, and
        // a zero-height diagram would take the connectors and labels with it.
        return max(40, min(cap, (width - fixed) / perPointOfHeight))
    }

    /// Fixed furniture either side of, and between, the two figures.
    static let labelColumnWidth: CGFloat = 76
    static let captionColumnWidth: CGFloat = 18

    /// How big the aerobic heart is drawn and how far it keeps from the front
    /// figure's left and bottom edges.
    ///
    /// Fractions of the height, every one of them, because the dead corner it
    /// has to stay inside is a fraction of the height: the figure is only
    /// 0.28 as wide as it is tall, so a heart of a fixed 42 points sat in open
    /// space beside a 420-point figure and on the ankle of a 260-point one.
    /// The numbers are the ones that looked right at 420, kept as ratios.
    static func aerobicHeart(forHeight height: CGFloat)
        -> (size: CGFloat, leading: CGFloat, bottom: CGFloat) {
        (height / 10, height / 15, height / 70)
    }

    /// What the two figures come out as in `width` — the same height, always,
    /// which is the whole of the fix for a front body that used to stand
    /// shorter than the back one beside it.
    static func figureSizes(width: CGFloat, atMost cap: CGFloat)
        -> (front: CGSize, back: CGSize) {
        let height = heightThatFits(width: width, atMost: cap)
        return (CGSize(width: naturalWidth(of: .front, height: height), height: height),
                CGSize(width: naturalWidth(of: .back, height: height), height: height))
    }

    /// One answer at a time: clicking the selected group again clears it.
    /// This picker is a filter on both platforms — what an exercise's OWN
    /// muscle groups are is set from a list on its edit screen, not here.
    private func pick(_ group: MuscleGroup) {
        selection = (selection == group) ? nil : group
    }

    var body: some View {
        let drawn = drawnHeight
        HStack(alignment: .top, spacing: 0) {
            labelColumn(Self.frontLabels, trailing: true)
            // The aerobic filter sits in the empty corner beside the front
            // figure's foot: the legs taper, so the bottom-left of the artwork
            // is dead space, and it lands between "Quads/ul" and the foot
            // without pushing any muscle label out of its place. Reserving room
            // for it in the label column instead moved every label up, which
            // was a lot of disturbance for one button.
            figure(isBack: false, labels: Self.frontLabels)
                .frame(maxWidth: Self.naturalWidth(of: .front, height: drawn))
                .overlay(alignment: .bottomLeading) {
                    if let aerobic {
                        let heart = Self.aerobicHeart(forHeight: drawn)
                        // Clear of the Quads connector, which runs diagonally
                        // through the corner on its way up to the thigh. Far
                        // enough right to sit in open space, not so far as to
                        // touch the foot — see `aerobicHeart` for why none of
                        // these three is a fixed number of points.
                        AerobicFilterButton(isOn: aerobic, size: heart.size)
                            .padding(.leading, heart.leading)
                            .padding(.bottom, heart.bottom)
                    }
                }
            viewCaptions
            figure(isBack: true, labels: Self.backLabels)
                .frame(maxWidth: Self.naturalWidth(of: .back, height: drawn))
            labelColumn(Self.backLabels, trailing: false)
        }
        // The taller the frame the bigger the bodies. On the phone the row of
        // controls that used to sit above the picture now sits below it beside
        // "all muscle groups", which paid for some of this.
        .frame(height: drawn)
        // What came back is what this picker was allowed to take: its own
        // width where there was room, the column's where there was not. The
        // second case is the one worth knowing about, and it settles after one
        // pass — at the height it reports the figures fit exactly, so the
        // width that comes back next is the same one.
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { offeredWidth = $0 }
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

    /// Which half is which, in the gap between them.
    ///
    /// The arrow sits above "front" and below "back" rather than beside the
    /// word: stacked, the pair is only as wide as the rotated text, which lets
    /// the two halves sit closer together and the bodies grow.
    private var viewCaptions: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)
            VStack(spacing: 1) {
                arrow(pointsLeft: true)
                rotatedLabel("front")
            }
            VStack(spacing: 1) {
                rotatedLabel("back")
                arrow(pointsLeft: false)
            }
            Spacer(minLength: 0)
        }
        .frame(width: Self.captionColumnWidth)
    }

    private func rotatedLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            // Same weight as the group buttons: these are part of the diagram's
            // labelling, not a footnote about it.
            .foregroundStyle(.primary)
            .fixedSize()
            .rotationEffect(.degrees(-90))
            .frame(width: 16, height: 40)
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
                        context.fill(path, with: .color(fill(for: entry.muscle)))
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
                        .onTapGesture { pick(entry.group) }
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
    private func fill(for muscle: MuscleGroup?) -> Color {
        // A fixed mid grey rather than a semantic colour. `secondary` resolves
        // dark on a dark background, which left these parts of the body far
        // heavier than the muscles beside them; the drawing should read as one
        // body, with colour — not lightness — saying what is selectable.
        guard let muscle else { return Color(white: 0.72) }
        if muscle == selection { return Color.blue.opacity(0.80) }
        return Color(red: 0.94, green: 0.56, blue: 0.47)
    }

    /// The rectangle the figure occupies inside `size`, preserving its aspect.
    /// How wide a figure actually needs to be, which is decided by the height.
    ///
    /// A figure is drawn inside a `GeometryReader`, and a GeometryReader takes
    /// all the width it is offered. `drawnRect` then CENTRES the artwork in
    /// that box, so every extra point of window width became half a point of
    /// blank space on each side of each figure — and the two inner halves of
    /// that blank, meeting in the middle, read as the two bodies drifting
    /// apart as the window widened. The arrows between them went with it.
    ///
    /// Capping each figure at the width its own height implies keeps the
    /// diagram together: the figures, the captions and the arrows stay one
    /// picture, and the extra width goes to the label columns on the outside,
    /// where the labels are aligned towards the figures and so stay put.
    ///
    /// `maxWidth` rather than `width`, so a window too narrow for the natural
    /// size squeezes the figures instead of overflowing.
    private static func naturalWidth(of figure: FigureGeometry, height: CGFloat) -> CGFloat {
        height * figure.aspect
    }

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
                let y = rowCentre(index: index, count: labels.count,
                                  height: geo.size.height)
                Button {
                    pick(group)
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
        .frame(width: Self.labelColumnWidth)
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
