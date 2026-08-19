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

struct WatchHeartRateBand: View {
    /// 1...5, or nil when nothing has arrived yet.
    let zone: Int?
    /// Where inside the lit zone the marker sits, 0...1.
    let fraction: Double

    private let activeHeight: CGFloat = 26
    private let restingHeight: CGFloat = 18

    private let spacing: CGFloat = 3

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 2) {
                HStack(spacing: spacing) {
                    ForEach(1...HeartRateZones.zoneCount, id: \.self) { index in
                        block(index).frame(width: width(for: index, in: geo.size.width))
                    }
                }
                marker(totalWidth: geo.size.width)
            }
        }
        .frame(height: activeHeight + 7)
    }

    /// Widths worked out rather than left to layout priority.
    ///
    /// The lit zone is double width, and the first attempt said so with
    /// `.layoutPriority(2)` and `maxWidth: .infinity`. That gave it the whole
    /// row and collapsed the other four to nothing, so the band was a single
    /// coloured bar with no band around it.
    private func width(for index: Int, in total: CGFloat) -> CGFloat {
        let gaps = spacing * CGFloat(HeartRateZones.zoneCount - 1)
        let usable = max(0, total - gaps)
        // Six shares: two for the lit zone, one for each of the others.
        let unit = usable / CGFloat(HeartRateZones.zoneCount + 1)
        return index == zone ? unit * 2 : unit
    }

    private func block(_ index: Int) -> some View {
        let isActive = index == zone
        return RoundedRectangle(cornerRadius: 4)
            .fill(ZoneColour.colour(index)
                .opacity(isActive ? 1 : ZoneColour.restingOpacity))
            .frame(height: isActive ? activeHeight : restingHeight)
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
    @ViewBuilder private func marker(totalWidth: CGFloat) -> some View {
        if let zone {
            HStack(spacing: 0) {
                Triangle()
                    .fill(Color.white)
                    .frame(width: 8, height: 5)
                    .offset(x: markerX(in: totalWidth, zone: zone))
                Spacer(minLength: 0)
            }
        } else {
            Color.clear.frame(height: 5)
        }
    }

    /// Along the lit block, which starts after all the narrower ones to its left.
    private func markerX(in total: CGFloat, zone: Int) -> CGFloat {
        let gaps = spacing * CGFloat(HeartRateZones.zoneCount - 1)
        let unit = max(0, total - gaps) / CGFloat(HeartRateZones.zoneCount + 1)
        let start = (unit + spacing) * CGFloat(zone - 1)
        return start + unit * 2 * CGFloat(min(1, max(0, fraction))) - 4
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
            // The same countdown the phone is showing. Absent rather than zero
            // when the Watch was never told the finishing time — the session is
            // still running, there is simply no number for it.
            if let remaining = workout.remainingLabel {
                Text(remaining)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
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
                // The first reading takes a few seconds every time, so waiting
                // is said first. Once it has been a while, silence is more
                // likely to be a refused permission than a slow sensor, and
                // saying so beats leaving the screen blank — HealthKit will not
                // reveal whether a read was denied, so this names the likeliest
                // fix rather than claiming to know.
                VStack(spacing: 2) {
                    Text(workout.hasWaitedLongForHeartRate
                         ? "no heart rate" : "waiting for your heart rate…")
                        .font(.caption2)
                    if workout.hasWaitedLongForHeartRate {
                        Text("Allow heart rate in Settings › Health")
                            .font(.system(size: 10))
                    }
                }
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            }

            Button("stop") {
                Task { await workout.stopFromWatch() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
    }
}
