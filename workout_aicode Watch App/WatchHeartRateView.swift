import SwiftUI

// MARK: - The heart rate screen, while an aerobic session runs
//
// This screen exists because the Watch had nothing to show during one. The
// phone would start the workout, the Watch would sit on "Active on iPhone"
// offering to take a session over, and the only sign anything was happening was
// that the watch had stopped responding to the workout it was actually running.
//
// Laid out after the Apple Workout app's own band, which is what people already
// know how to read: five blocks, the one you are in lit and taller, a marker
// under it showing roughly where inside that zone you are, and the number
// underneath. Time in zone and average are deliberately absent — they are
// interesting afterwards, not while pedalling.

/// The five zone colours, low to high. Blue for easy through to red for the
/// top, the ordering people expect from every heart rate band they have seen.
enum ZoneColour {
    static let all: [Color] = [
        Color(red: 0.16, green: 0.55, blue: 0.95),   // 1 — blue
        Color(red: 0.16, green: 0.68, blue: 0.60),   // 2 — teal
        Color(red: 0.72, green: 0.72, blue: 0.14),   // 3 — yellow-green
        Color(red: 0.85, green: 0.45, blue: 0.12),   // 4 — orange
        Color(red: 0.80, green: 0.15, blue: 0.28),   // 5 — red
    ]

    static func colour(_ zone: Int) -> Color {
        guard zone >= 1, zone <= all.count else { return .secondary }
        return all[zone - 1]
    }
}

struct WatchHeartRateBand: View {
    /// 1...5, or nil when the rate is below zone 1 or nothing has arrived.
    let zone: Int?
    /// Where inside the lit zone the marker sits, 0...1.
    let fraction: Double

    private let activeHeight: CGFloat = 26
    private let restingHeight: CGFloat = 18

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 3) {
                ForEach(1...HeartRateZones.zoneCount, id: \.self) { index in
                    block(index)
                }
            }
            marker
        }
    }

    private func block(_ index: Int) -> some View {
        let isActive = index == zone
        return RoundedRectangle(cornerRadius: 4)
            .fill(ZoneColour.colour(index).opacity(isActive ? 1 : 0.32))
            .frame(height: isActive ? activeHeight : restingHeight)
            // The lit zone takes twice the width of the others, which is what
            // makes it findable at a glance on a moving wrist.
            .frame(maxWidth: .infinity)
            .layoutPriority(isActive ? 2 : 1)
            .overlay {
                if isActive {
                    HStack(spacing: 2) {
                        Image(systemName: "heart.fill").font(.system(size: 8))
                        Text("ZONE \(index)").font(.system(size: 9, weight: .heavy))
                    }
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                }
            }
    }

    /// A small pointer under the lit block. Nothing at all when there is no
    /// zone: an arrow with nowhere to point would be worse than no arrow.
    @ViewBuilder private var marker: some View {
        if let zone {
            GeometryReader { geo in
                Triangle()
                    .fill(Color.white)
                    .frame(width: 8, height: 5)
                    .offset(x: markerX(in: geo.size.width, zone: zone))
            }
            .frame(height: 5)
        } else {
            Color.clear.frame(height: 5)
        }
    }

    /// The lit block is double width, so the band is (count + 1) slots wide and
    /// the lit one occupies two of them.
    private func markerX(in width: CGFloat, zone: Int) -> CGFloat {
        let slots = CGFloat(HeartRateZones.zoneCount + 1)
        let slot = width / slots
        let start = slot * CGFloat(zone - 1)
        return start + slot * 2 * CGFloat(min(1, max(0, fraction))) - 4
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// What the Watch shows while the phone is counting down an aerobic exercise.
struct WatchHeartRateView: View {
    @ObservedObject private var workout = WatchAerobicWorkout.shared

    var body: some View {
        VStack(spacing: 6) {
            if !workout.exerciseName.isEmpty {
                Text(workout.exerciseName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            WatchHeartRateBand(zone: workout.currentZone,
                               fraction: workout.currentZoneFraction)

            if let bpm = workout.currentHeartRate {
                HStack(spacing: 4) {
                    Text("\(bpm)")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.red)
                        .font(.system(size: 18))
                }
            } else {
                // The first reading takes a few seconds every time. Saying so
                // beats a zero, which would read as a measurement.
                Text("waiting for your heart rate…")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
    }
}
