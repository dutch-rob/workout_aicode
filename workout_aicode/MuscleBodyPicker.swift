import SwiftUI

// MARK: - Muscle group picker on a body diagram
//
// Two stylised figures, front and back, with a labelled button for each muscle
// group beside the figure it belongs to and a thin connector to roughly where
// that muscle is. Finding "rear delts" in a list means already knowing the
// word; here you can point at the part of you that aches.
//
// Front and back are separate figures on purpose: it puts chest-side labels on
// the left and back-side labels on the right, so no connector has to cross the
// body or another connector.
//
// The drawing is deliberately schematic — a neutral arrangement of limbs, not
// an anatomical illustration or a particular body.

struct MuscleBodyPicker: View {
    @Binding var selection: MuscleGroup?

    /// Where each muscle sits on its figure, in fractions of that figure's box
    /// (0,0 top-left → 1,1 bottom-right), and which side its label goes on.
    private struct Anchor {
        let group: MuscleGroup
        let point: CGPoint
        let onBack: Bool
    }

    private static let anchors: [Anchor] = [
        // Front figure — labels to its left.
        .init(group: .frontDelts, point: CGPoint(x: 0.30, y: 0.205), onBack: false),
        .init(group: .chest,      point: CGPoint(x: 0.50, y: 0.245), onBack: false),
        .init(group: .sideDelts,  point: CGPoint(x: 0.245, y: 0.225), onBack: false),
        .init(group: .biceps,     point: CGPoint(x: 0.215, y: 0.315), onBack: false),
        .init(group: .forearms,   point: CGPoint(x: 0.165, y: 0.415), onBack: false),
        .init(group: .absCore,    point: CGPoint(x: 0.50, y: 0.355), onBack: false),
        .init(group: .quads,      point: CGPoint(x: 0.395, y: 0.605), onBack: false),

        // Back figure — labels to its right.
        .init(group: .traps,      point: CGPoint(x: 0.50, y: 0.175), onBack: true),
        .init(group: .rearDelts,  point: CGPoint(x: 0.735, y: 0.215), onBack: true),
        .init(group: .back,       point: CGPoint(x: 0.50, y: 0.275), onBack: true),
        .init(group: .triceps,    point: CGPoint(x: 0.785, y: 0.315), onBack: true),
        .init(group: .lowerBack,  point: CGPoint(x: 0.50, y: 0.375), onBack: true),
        .init(group: .glutes,     point: CGPoint(x: 0.50, y: 0.455), onBack: true),
        .init(group: .hamstrings, point: CGPoint(x: 0.605, y: 0.605), onBack: true),
        .init(group: .calves,     point: CGPoint(x: 0.615, y: 0.795), onBack: true),
    ]

    private var frontAnchors: [Anchor] { Self.anchors.filter { !$0.onBack } }
    private var backAnchors: [Anchor] { Self.anchors.filter(\.onBack) }

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 0) {
                labelColumn(frontAnchors, trailing: true)
                captionedFigure(frontAnchors, isBack: false, labelsOnLeft: true)
                captionedFigure(backAnchors, isBack: true, labelsOnLeft: false)
                labelColumn(backAnchors, trailing: false)
            }
            .frame(height: 318)

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

    // MARK: Figure with its connectors

    /// The two figures are drawn identically, so without a caption there is
    /// nothing to say which one you are looking at — and "is that the front or
    /// the back?" is exactly the confusion this picker exists to remove.
    private func captionedFigure(_ anchors: [Anchor], isBack: Bool,
                                 labelsOnLeft: Bool) -> some View {
        VStack(spacing: 2) {
            figure(anchors, isBack: isBack, labelsOnLeft: labelsOnLeft)
            Text(isBack ? "back" : "front")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func figure(_ anchors: [Anchor], isBack: Bool, labelsOnLeft: Bool) -> some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                // Fill only. The subpaths overlap at the joints (see the
                // shape), so stroking the same path would trace every internal
                // seam and draw limb outlines straight across the body.
                BodySilhouette(isBack: isBack)
                    .fill(Color.secondary.opacity(0.22))

                // Connector from the label's edge to the muscle.
                ForEach(Array(anchors.enumerated()), id: \.offset) { index, anchor in
                    let target = CGPoint(x: anchor.point.x * size.width,
                                         y: anchor.point.y * size.height)
                    let edgeX = labelsOnLeft ? 0 : size.width
                    let edgeY = rowCentre(index: index, count: anchors.count, height: size.height)
                    Path { path in
                        path.move(to: CGPoint(x: edgeX, y: edgeY))
                        path.addLine(to: target)
                    }
                    .stroke(selection == anchor.group ? Color.blue : Color.secondary.opacity(0.4),
                            lineWidth: selection == anchor.group ? 1.6 : 0.8)

                    // The marker is a button too: pointing at the body is the
                    // reason for the diagram, so it should not be decoration
                    // that makes you go back to the label to tap.
                    Button {
                        selection = (selection == anchor.group) ? nil : anchor.group
                    } label: {
                        Circle()
                            .fill(selection == anchor.group ? Color.blue : Color.secondary.opacity(0.6))
                            .frame(width: selection == anchor.group ? 9 : 6)
                            // A 6pt dot is far below a usable tap target, so
                            // the touch area is padded well beyond the drawing.
                            .padding(11)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(anchor.group.label)
                    .position(target)
                }
            }
        }
    }

    // MARK: Labels

    private func labelColumn(_ anchors: [Anchor], trailing: Bool) -> some View {
        GeometryReader { geo in
            ForEach(Array(anchors.enumerated()), id: \.offset) { index, anchor in
                let y = rowCentre(index: index, count: anchors.count, height: geo.size.height)
                Button {
                    selection = (selection == anchor.group) ? nil : anchor.group
                } label: {
                    Text(anchor.group.shortLabel)
                        .font(.caption)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(selection == anchor.group
                                           ? Color.blue
                                           : Color.secondary.opacity(0.15))
                        )
                        .foregroundStyle(selection == anchor.group ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
                .frame(width: geo.size.width,
                       alignment: trailing ? .trailing : .leading)
                .position(x: geo.size.width / 2, y: y)
            }
        }
        .frame(width: 92)
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

// MARK: - The figure

/// A schematic human outline in the given rect. Front and back differ only
/// slightly — enough to tell them apart at a glance.
struct BodySilhouette: Shape {
    var isBack: Bool

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * w, y: rect.minY + y * h)
        }
        var path = Path()

        // Subpaths deliberately OVERLAP where limbs meet the trunk. Filled as
        // one path they merge into a single silhouette; drawn as separate
        // shapes that merely touch, hairline gaps open up at the joints and the
        // figure falls apart into sticks.

        // Head. The radius has to be set in the same axis as the position, or
        // the two disagree: sized from the width on a box twice as tall as it
        // is wide, the head ends up far too small and floats clear of the neck.
        // Capped against the width so it cannot outgrow the shoulders.
        let headRadius = min(h * 0.055, w * 0.17)
        let headCentre = pt(0.5, 0.075)
        path.addEllipse(in: CGRect(x: headCentre.x - headRadius,
                                   y: headCentre.y - headRadius,
                                   width: headRadius * 2, height: headRadius * 2))

        // Neck — spans from inside the head down into the chest.
        path.addRect(CGRect(x: pt(0.45, 0).x, y: pt(0.5, 0.10).y,
                            width: w * 0.10, height: h * 0.10))

        // Trunk: shoulders → waist → hips, with the shoulders rounded off so
        // the deltoids read as part of the body.
        path.move(to: pt(0.335, 0.175))
        path.addQuadCurve(to: pt(0.665, 0.175), control: pt(0.5, 0.155))
        path.addQuadCurve(to: pt(0.715, 0.235), control: pt(0.715, 0.19))
        path.addQuadCurve(to: pt(0.625, 0.40), control: pt(0.665, 0.33))
        // Flat across the hips. Bulging this edge downwards left the thigh
        // tops sitting proud of it, which read as white notches at the hips.
        path.addLine(to: pt(0.655, 0.505))
        path.addLine(to: pt(0.345, 0.505))
        path.addLine(to: pt(0.375, 0.40))
        path.addQuadCurve(to: pt(0.285, 0.235), control: pt(0.335, 0.33))
        path.addQuadCurve(to: pt(0.335, 0.175), control: pt(0.285, 0.19))
        path.closeSubpath()

        // Arms: shoulder → elbow → wrist, tapering, starting inside the trunk.
        for side in [CGFloat(-1), CGFloat(1)] {
            // Well inside the trunk: an arm that meets the shoulder exactly at
            // its edge leaves a wedge of background at the armpit, because the
            // trunk narrows towards the waist while the arm hangs straight.
            let shoulderInner = 0.5 + side * 0.145
            let shoulderOuter = 0.5 + side * 0.275
            let elbowInner = 0.5 + side * 0.245
            let elbowOuter = 0.5 + side * 0.325
            let wristInner = 0.5 + side * 0.295
            let wristOuter = 0.5 + side * 0.355

            path.move(to: pt(shoulderInner, 0.185))
            path.addQuadCurve(to: pt(shoulderOuter, 0.235), control: pt(shoulderOuter, 0.19))
            path.addLine(to: pt(elbowOuter, 0.335))
            path.addLine(to: pt(wristOuter, 0.475))
            path.addQuadCurve(to: pt(wristInner, 0.475), control: pt((wristInner + wristOuter) / 2, 0.50))
            path.addLine(to: pt(elbowInner, 0.335))
            path.addLine(to: pt(shoulderInner, 0.225))
            path.closeSubpath()
        }

        // Legs: hip → knee → ankle. They start above the hip line so they are
        // already inside the trunk where the two meet.
        for side in [CGFloat(-1), CGFloat(1)] {
            let hipInner = 0.5 + side * 0.015
            let hipOuter = 0.5 + side * 0.155
            let kneeInner = 0.5 + side * 0.04
            let kneeOuter = 0.5 + side * 0.145
            let ankleInner = 0.5 + side * 0.055
            let ankleOuter = 0.5 + side * 0.125

            path.move(to: pt(hipInner, 0.44))
            path.addLine(to: pt(hipOuter, 0.44))
            path.addQuadCurve(to: pt(kneeOuter, 0.70), control: pt(hipOuter, 0.60))
            path.addLine(to: pt(ankleOuter, 0.955))
            path.addQuadCurve(to: pt(ankleInner, 0.955),
                              control: pt((ankleInner + ankleOuter) / 2, 0.98))
            path.addLine(to: pt(kneeInner, 0.70))
            path.addLine(to: pt(hipInner, 0.44))
            path.closeSubpath()
        }

        return path
    }
}
