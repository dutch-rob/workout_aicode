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
// The figures are the "Muscles front and back" illustration from Wikimedia
// Commons by OpenStax, Tomáš Kebert and umimeto.org, CC BY-SA 4.0, cropped
// into two images and given a transparent background. See ART-CREDITS.md.
//
// They are pictures, not shapes: the anchors below say where each muscle sits
// on them, as fractions of the image box, so the artwork can be replaced by
// re-tuning fifteen numbers rather than rewriting the view.

struct MuscleBodyPicker: View {
    @Binding var selection: MuscleGroup?

    /// Where each muscle sits on its figure, in fractions of that figure's box
    /// (0,0 top-left → 1,1 bottom-right), and which side its label goes on.
    private struct Anchor {
        let group: MuscleGroup
        let point: CGPoint
        let radius: CGFloat
        let onBack: Bool
    }

    /// Positions on the artwork. `radius` is the highlight blob's size, also as
    /// a fraction of image width, so a broad sheet like the back can be marked
    /// more generously than a small one like the biceps.
    private static let anchors: [Anchor] = [
        // Front figure — labels to its left.
        .init(group: .frontDelts, point: CGPoint(x: 0.285, y: 0.200), radius: 0.070, onBack: false),
        .init(group: .chest,      point: CGPoint(x: 0.410, y: 0.240), radius: 0.100, onBack: false),
        .init(group: .sideDelts,  point: CGPoint(x: 0.235, y: 0.215), radius: 0.060, onBack: false),
        .init(group: .biceps,     point: CGPoint(x: 0.230, y: 0.290), radius: 0.060, onBack: false),
        .init(group: .forearms,   point: CGPoint(x: 0.155, y: 0.390), radius: 0.070, onBack: false),
        .init(group: .absCore,    point: CGPoint(x: 0.500, y: 0.370), radius: 0.085, onBack: false),
        .init(group: .quads,      point: CGPoint(x: 0.395, y: 0.560), radius: 0.090, onBack: false),

        // Back figure — labels to its right.
        .init(group: .traps,      point: CGPoint(x: 0.500, y: 0.185), radius: 0.080, onBack: true),
        .init(group: .rearDelts,  point: CGPoint(x: 0.735, y: 0.215), radius: 0.065, onBack: true),
        .init(group: .back,       point: CGPoint(x: 0.500, y: 0.285), radius: 0.100, onBack: true),
        .init(group: .triceps,    point: CGPoint(x: 0.775, y: 0.295), radius: 0.060, onBack: true),
        .init(group: .lowerBack,  point: CGPoint(x: 0.500, y: 0.380), radius: 0.075, onBack: true),
        .init(group: .glutes,     point: CGPoint(x: 0.500, y: 0.455), radius: 0.100, onBack: true),
        .init(group: .hamstrings, point: CGPoint(x: 0.400, y: 0.570), radius: 0.085, onBack: true),
        .init(group: .calves,     point: CGPoint(x: 0.400, y: 0.720), radius: 0.070, onBack: true),
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

    /// Width ÷ height of the two artwork files. Needed because the anchors are
    /// fractions of the *image*, and an aspect-fitted image almost never fills
    /// its frame — position against the frame instead and every marker drifts
    /// (which put "chest" on the forehead the first time).
    private static let frontAspect: CGFloat = 919.0 / 1656.0
    private static let backAspect: CGFloat = 818.0 / 1636.0

    /// An anchor's position inside the drawn image.
    private static func place(_ p: CGPoint, in art: CGRect) -> CGPoint {
        CGPoint(x: art.minX + p.x * art.width, y: art.minY + p.y * art.height)
    }

    /// The rectangle the image actually occupies inside `size`, mirroring what
    /// `scaledToFit` does.
    private static func drawnRect(in size: CGSize, aspect: CGFloat) -> CGRect {
        let height = min(size.height, size.width / aspect)
        let width = height * aspect
        return CGRect(x: (size.width - width) / 2,
                      y: (size.height - height) / 2,
                      width: width, height: height)
    }

    private func figure(_ anchors: [Anchor], isBack: Bool, labelsOnLeft: Bool) -> some View {
        GeometryReader { geo in
            let size = geo.size
            let aspect = isBack ? Self.backAspect : Self.frontAspect
            let art = Self.drawnRect(in: size, aspect: aspect)
            ZStack {
                Image(isBack ? "body-back" : "body-front")
                    .resizable()
                    .scaledToFit()
                    .frame(width: size.width, height: size.height)

                // Highlight sits over the artwork, under the markers: a soft
                // blob rather than the muscle's outline, because the drawing is
                // a picture here and its shapes are not addressable.
                if let anchor = anchors.first(where: { $0.group == selection }) {
                    Circle()
                        .fill(Color.blue.opacity(0.30))
                        .frame(width: anchor.radius * 2 * art.width,
                               height: anchor.radius * 2 * art.width)
                        .blur(radius: 6)
                        .position(Self.place(anchor.point, in: art))
                        .allowsHitTesting(false)
                }

                // Connector from the label's edge to the muscle.
                ForEach(Array(anchors.enumerated()), id: \.offset) { index, anchor in
                    let target = Self.place(anchor.point, in: art)
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
        // Narrow on purpose: whatever the labels take, the two figures divide
        // between them, and the artwork is width-limited here — every point
        // given back to the columns makes both bodies smaller.
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
