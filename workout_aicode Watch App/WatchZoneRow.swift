import SwiftUI

/// The heart rate zones, behind the exercise name.
///
/// The same band as the aerobic screen's — all five zones, the one you are in
/// widened and lit — but as a BACKGROUND rather than a row of its own. The
/// layout notes under `WatchLogExerciseView` are about pixels: a band of its
/// own would cost about 33pt, and that comes straight off the wheels.
///
/// So no heart icon and no "ZONE 3" here. The exercise name is already in this
/// row and needs the space; the colour says which zone, and the marker says
/// where in it. The inactive zones are dimmer than the aerobic screen's for
/// the same reason — white text has to stay readable over them.
///
/// A LEAF on purpose. Heart rate arrives about once a second, and the screen
/// that owns the exercise list must not be rebuilt at that rate: the phone's
/// "list" menu stopped accepting taps when the rest timer rebuilt its parent
/// twenty times a second, and this is the same trap.
struct WatchZoneRowBackground: View {
    @ObservedObject private var workout = WatchStrengthWorkout.shared

    @ObservedObject private var session = WatchSessionManager.shared

    private let spacing: CGFloat = 2
    /// Every zone at the same strength. Dimming the ones you are not in made
    /// them all but invisible on the wrist — this row is small, and a colour
    /// at a fifth strength behind text is not a colour. The zone you are in is
    /// picked out by WIDTH instead, which survives being small.
    ///
    /// How strong is the user's, set on the phone against a preview: it
    /// depends on the wrist, the light, and the person reading it.
    private var tint: Double { session.zoneTint }
    /// The marker pokes up out of the bar into the text's row. Small enough
    /// not to fight the exercise name, big enough to find at a glance.
    private let markerWidth: CGFloat = 9
    private let markerHeight: CGFloat = 5.5

    var body: some View {
        GeometryReader { geo in
            if let zone = workout.currentZone {
                ZStack(alignment: .bottomLeading) {
                    HStack(spacing: spacing) {
                        ForEach(1...HeartRateZones.zoneCount, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(ZoneColour.colour(index).opacity(tint))
                                .frame(width: width(for: index, zone: zone,
                                                    in: geo.size.width))
                        }
                    }
                    ZoneMarker()
                        .fill(Color.white)
                        .frame(width: markerWidth, height: markerHeight)
                        .offset(x: markerX(in: geo.size.width, zone: zone))
                }
            }
        }
    }

    /// Halve the zones you are not in, and give what that frees to the one you
    /// are — capped at half the row, so the band stays a band rather than one
    /// block with slivers beside it. With five zones the cap is what binds:
    /// the one you are in takes half the width and the other four share the
    /// rest, an eighth each.
    private func activeWidth(in usable: CGFloat) -> CGFloat {
        let count = CGFloat(HeartRateZones.zoneCount)
        let equal = usable / count
        let freed = (equal / 2) * (count - 1)
        return min(usable / 2, equal + freed)
    }

    private func width(for index: Int, zone: Int, in total: CGFloat) -> CGFloat {
        let gaps = spacing * CGFloat(HeartRateZones.zoneCount - 1)
        let usable = max(0, total - gaps)
        let active = activeWidth(in: usable)
        if index == zone { return active }
        return max(0, usable - active) / CGFloat(HeartRateZones.zoneCount - 1)
    }

    /// Along the block you are in, clamped so it stays inside it at either end.
    private func markerX(in total: CGFloat, zone: Int) -> CGFloat {
        let gaps = spacing * CGFloat(HeartRateZones.zoneCount - 1)
        let usable = max(0, total - gaps)
        let active = activeWidth(in: usable)
        let other = max(0, usable - active) / CGFloat(HeartRateZones.zoneCount - 1)
        let start = (other + spacing) * CGFloat(zone - 1)
        let fraction = min(1, max(0, workout.currentZoneFraction))
        return start + max(0, active - markerWidth) * CGFloat(fraction)
    }
}

/// Points up, from the bottom edge of the row — the aerobic band's marker,
/// which points up at the band from below.
private nonisolated struct ZoneMarker: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
