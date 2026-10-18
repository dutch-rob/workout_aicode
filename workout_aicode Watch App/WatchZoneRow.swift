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

    private let spacing: CGFloat = 2
    private let litOpacity: Double = 0.5
    private let restingOpacity: Double = 0.18
    /// Marker size, kept small: it shares the row with the descenders of the
    /// exercise name.
    private let markerWidth: CGFloat = 7
    private let markerHeight: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            if let zone = workout.currentZone {
                ZStack(alignment: .bottomLeading) {
                    HStack(spacing: spacing) {
                        ForEach(1...HeartRateZones.zoneCount, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(ZoneColour.colour(index)
                                    .opacity(index == zone ? litOpacity : restingOpacity))
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

    /// Six shares: two for the zone you are in, one for each of the others —
    /// the aerobic band's proportions, so the two screens read the same way.
    private func width(for index: Int, zone: Int, in total: CGFloat) -> CGFloat {
        let gaps = spacing * CGFloat(HeartRateZones.zoneCount - 1)
        let unit = max(0, total - gaps) / CGFloat(HeartRateZones.zoneCount + 1)
        return index == zone ? unit * 2 : unit
    }

    /// Along the lit block, clamped so it stays inside it at either end.
    private func markerX(in total: CGFloat, zone: Int) -> CGFloat {
        let gaps = spacing * CGFloat(HeartRateZones.zoneCount - 1)
        let unit = max(0, total - gaps) / CGFloat(HeartRateZones.zoneCount + 1)
        let start = (unit + spacing) * CGFloat(zone - 1)
        let fraction = min(1, max(0, workout.currentZoneFraction))
        let along = (unit * 2 - markerWidth) * CGFloat(fraction)
        return start + along
    }
}

/// Points up, from the bottom edge of the row — the aerobic band's marker,
/// which points up at the band from below.
private struct ZoneMarker: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
