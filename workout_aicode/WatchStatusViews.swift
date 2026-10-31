// What the phone shows instead of the log screen when the Watch has the
// workout: paused for a hand-over, or running it as an Apple workout. Both are
// put up by ContentView, which decides between them.

import SwiftUI

// MARK: - Handover Paused overlay
//
// Shown over the log screen when the workout has been taken over on the other
// device. Tapping "Continue here" pulls the session back to this device.
struct HandoverPausedView: View {
    let otherDeviceName: String
    let onContinue: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "arrow.left.arrow.right.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)
                Text("Workout active on \(otherDeviceName)")
                    .font(.title3).bold()
                    .multilineTextAlignment(.center)
                Text("You're logging this workout on your \(otherDeviceName). Continue it here to move it back.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button(action: onContinue) {
                    Text("Continue here")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Not now", action: onDismiss)
                    .buttonStyle(.bordered)
            }
            .padding(32)
        }
    }
}
/// What the log screen becomes while the Watch is running the workout as an
/// Apple workout: a statement, and the way back.
///
/// There is no "Continue here". HealthKit will not move a running session to
/// another device, and ending it early to hand over would put half a workout
/// in Fitness and lose the heart rate for the rest — so the choice the
/// hand-over screen offers does not exist here. Saying so plainly beats a
/// button that cannot work.
struct WatchWorkoutActiveView: View {
    let onReturn: () -> Void

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "applewatch.radiowaves.left.and.right")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)
                Text("Workout active on your Apple Watch")
                    .font(.title3).bold()
                    .multilineTextAlignment(.center)
                Text("It is running as an Apple workout, so it stays on your wrist until you finish it there. Your logs, graphs and progress are still here to look at.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button(action: onReturn) {
                    Text("Return to start screen")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(32)
        }
    }
}
