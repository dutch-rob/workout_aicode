import SwiftUI

/// A heart with "AE" in it, for picking out the aerobic exercises.
///
/// A heart rather than another capsule on purpose: every other button beside
/// the body names a muscle, and this one does not — it is a different kind of
/// thing, and looking different is the quickest way to say so.
struct HeartShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var path = Path()
        // Two lobes meeting in a dip at the top, drawn down to a point at the
        // bottom. Proportions chosen to sit square-ish rather than tall, so the
        // "AE" inside has room.
        path.move(to: CGPoint(x: w * 0.5, y: h))
        path.addCurve(to: CGPoint(x: 0, y: h * 0.33),
                      control1: CGPoint(x: w * 0.16, y: h * 0.78),
                      control2: CGPoint(x: 0, y: h * 0.58))
        path.addArc(center: CGPoint(x: w * 0.25, y: h * 0.33),
                    radius: w * 0.25,
                    startAngle: .degrees(180), endAngle: .degrees(0),
                    clockwise: false)
        path.addArc(center: CGPoint(x: w * 0.75, y: h * 0.33),
                    radius: w * 0.25,
                    startAngle: .degrees(180), endAngle: .degrees(0),
                    clockwise: false)
        path.addCurve(to: CGPoint(x: w * 0.5, y: h),
                      control1: CGPoint(x: w, y: h * 0.58),
                      control2: CGPoint(x: w * 0.84, y: h * 0.78))
        path.closeSubpath()
        return path
    }
}

/// The "AE" button that picks out aerobic exercises.
///
/// It behaves like a muscle-group button — selecting it clears any muscle
/// filter and vice versa, since an exercise is one kind or the other and both
/// at once could only ever show an empty list — but it is not one, and it is
/// drawn as a heart so nobody has to be told that.
struct AerobicFilterButton: View {
    @Binding var isOn: Bool
    var size: CGFloat = 42

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            ZStack {
                HeartShape()
                    .fill(isOn ? Color.red : Color.red.opacity(0.35))
                Text("AE")
                    .font(.system(size: size * 0.3, weight: .heavy))
                    .foregroundStyle(.white)
                    // Sits on the body of the heart rather than in the dip
                    // between the lobes, where it would be half off the shape.
                    .offset(y: size * 0.06)
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Aerobic exercises")
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}
