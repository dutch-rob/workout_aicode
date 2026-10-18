import SwiftUI

/// The heart rate zone, behind the exercise name.
///
/// There is no room on this screen for a number: the layout notes under
/// `WatchLogExerciseView` are about pixels, and a row of its own would come
/// straight off the wheels. So the row the name already occupies is tinted
/// with the zone's colour, and a line across it says where inside that zone
/// the current rate falls — which is what a number would have told you, in the
/// space that was already there.
///
/// A LEAF on purpose. Heart rate arrives about once a second, and the screen
/// that owns the exercise list must not be rebuilt at that rate: the phone's
/// "list" menu stopped accepting taps when the rest timer rebuilt its parent
/// twenty times a second, and this is the same trap. Observing here means a
/// reading redraws this rectangle and nothing else.
struct WatchZoneRowBackground: View {
    @ObservedObject private var workout = WatchStrengthWorkout.shared

    /// Dark enough to read white text over; bright enough to tell the zones
    /// apart at a glance while holding a bar.
    private let tint: Double = 0.45

    var body: some View {
        GeometryReader { geo in
            if let zone = workout.currentZone {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(ZoneColour.colour(zone).opacity(tint))
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 2)
                        .offset(x: markerX(in: geo.size.width))
                }
            }
        }
    }

    /// Clamped so the line stays inside the row at either end of a zone.
    private func markerX(in width: CGFloat) -> CGFloat {
        let fraction = min(1, max(0, workout.currentZoneFraction))
        return (max(0, width - 2)) * CGFloat(fraction)
    }
}
