import SwiftUI
import Combine
import UIKit
import UserNotifications

// MARK: - The aerobic countdown
//
// One wheel picks how long, and this counts it down. Deliberately built the
// same way as the rest timer: an absolute end date is the truth, a tick only
// redraws, and a local notification is what reaches the user once the phone is
// in a pocket or face-down on a treadmill. See RestTimer for why none of that
// is animated.
//
// What it records is what you ACTUALLY did, not what you set out to do —
// stopping at twelve minutes of a twenty-minute run logs twelve. A planned
// number would be a wish rather than a measurement, and the statistics have to
// be about the second one.

enum AerobicDefaults {
    /// Wheel range, in minutes. One minute at the bottom because the wheel is
    /// also how you log a short interval; two hours at the top is past what
    /// this app is for.
    static let minuteChoices: [Int] = Array(1...120)
    static let defaultMinutes = 20

    static func label(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

@MainActor
final class AerobicCountdown: ObservableObject {

    static let shared = AerobicCountdown()
    private init() {}

    private static let notificationId = "aerobicFinished"

    /// When the countdown is due to finish. Nil when nothing is running.
    @Published private(set) var endsAt: Date?
    @Published private(set) var isShowing = false
    @Published private(set) var exerciseName = ""
    /// The full length that was chosen, for the ring.
    @Published private(set) var totalSeconds = 0
    @Published private(set) var tick = Date()

    /// Set when a session ends, for the log screen to pick up. Seconds actually
    /// spent, whether it ran out or was stopped early.
    @Published var finishedSeconds: Int?

    private var startedAt: Date?
    private var ticker: Timer?

    var remainingSeconds: Int {
        guard let endsAt else { return 0 }
        return max(0, Int(endsAt.timeIntervalSince(tick).rounded(.up)))
    }

    var elapsedSeconds: Int {
        guard let startedAt else { return 0 }
        return max(0, Int(tick.timeIntervalSince(startedAt).rounded()))
    }

    var remainingFraction: CGFloat {
        guard totalSeconds > 0 else { return 0 }
        return min(1, max(0, CGFloat(remainingSeconds) / CGFloat(totalSeconds)))
    }

    // MARK: - Running

    func start(exercise: String, seconds: Int) {
        guard seconds > 0, !isShowing else { return }
        exerciseName = exercise
        totalSeconds = seconds
        let now = Date()
        startedAt = now
        endsAt = now.addingTimeInterval(Double(seconds))
        tick = now
        finishedSeconds = nil
        isShowing = true
        UIApplication.shared.isIdleTimerDisabled = true
        scheduleNotification(at: endsAt!)
        startTicking()
    }

    /// Stopped by hand. Records however long it actually ran.
    func stop() {
        finish(haptic: false)
    }

    /// Ran out on its own.
    private func complete() {
        finish(haptic: true)
    }

    /// The workout ended underneath it — nothing to record.
    func cancel() {
        guard endsAt != nil else { return }
        clear()
    }

    private func finish(haptic: Bool) {
        guard endsAt != nil else { return }
        finishedSeconds = elapsedSeconds
        clear()
        if haptic { RestTimerHaptics.strong() }
    }

    private func clear() {
        ticker?.invalidate()
        ticker = nil
        endsAt = nil
        startedAt = nil
        isShowing = false
        UIApplication.shared.isIdleTimerDisabled = false
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationId])
        center.removeDeliveredNotifications(withIdentifiers: [Self.notificationId])
    }

    /// Coming back to the app. One that ran out while away is simply over, and
    /// its length is what it was set to — the clock kept it, not the screen.
    func onForeground() {
        guard let endsAt else { return }
        if endsAt <= Date() {
            tick = endsAt
            finish(haptic: false)
        } else {
            startTicking()
        }
    }

    private func startTicking() {
        ticker?.invalidate()
        let t = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let endsAt = self.endsAt else { return }
                self.tick = Date()
                if endsAt <= self.tick { self.complete() }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func scheduleNotification(at date: Date) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationId])
        let content = UNMutableNotificationContent()
        content.title = "Done"
        content.body = exerciseName.isEmpty ? "Your session is over."
                                            : "\(exerciseName) is over."
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        center.add(UNNotificationRequest(
            identifier: Self.notificationId,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(
                timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)))
    }
}

// MARK: - The countdown screen

struct AerobicCountdownView: View {
    @ObservedObject private var session = AerobicCountdown.shared

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Text(session.exerciseName.isEmpty ? "session" : session.exerciseName)
                .font(.largeTitle).bold()
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            ZStack {
                Circle().stroke(Color.secondary.opacity(0.25), lineWidth: 14)
                Circle()
                    .trim(from: 0, to: session.remainingFraction)
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(AerobicDefaults.label(session.remainingSeconds))
                    .font(.system(size: 60, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            .frame(width: 240, height: 240)

            Text("You can leave the app — it will buzz when the time is up.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            Button {
                session.stop()
            } label: {
                Text("stop")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}
