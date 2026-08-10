import SwiftUI
import Combine
import WatchKit
import UserNotifications

// MARK: - Rest timer, watch side
//
// A rest belongs to whichever device is driving the workout, and there is only
// ever one driver. Two ways in:
//
//   • `mirror` — the phone is logging and has told us when its rest ends. The
//     countdown appears at once; the phone has already had its settle delay.
//   • `setFinished` — the Watch itself is logging. It runs the rest, with the
//     same settle delay as the phone so the wheels are not snatched away, and
//     does NOT tell the phone: the wrist is right there, and a phone buzzing
//     in a locker for a set logged on the Watch is noise.
//
// Either way it is one absolute end date that everything hangs off.
//
// Why a scheduled notification and not a Timer: during a rest the wrist is
// down and the watch app is not frontmost, so a running timer in a suspended
// app buzzes nobody. A notification scheduled for the end date still fires.
// The countdown view is secondary — it is only for the case where the user
// happens to be looking at the watch.
//
// Why this cannot pile up: the phone only sends while the Watch is reachable
// and never queues the message, each new rest replaces the pending
// notification, and anything already past (or implausibly far out) is thrown
// away below rather than scheduled.

@MainActor
final class WatchRestTimer: ObservableObject {

    static let shared = WatchRestTimer()
    private init() {}

    private static let notificationId = "restTimerFinished"

    /// Longest rest worth believing. A message this stale or this far out is a
    /// straggler, not a rest anyone is waiting on.
    private static let longestPlausibleRest: TimeInterval = 15 * 60

    @Published private(set) var endsAt: Date?
    @Published private(set) var exerciseName = ""
    @Published private(set) var tick = Date()
    /// Whether the countdown is covering the screen. Not the same as having a
    /// rest: a Watch-driven rest waits out the settle delay first.
    @Published private(set) var isShowing = false

    /// Same reasoning as the phone's: a set is logged over several separate
    /// turns of the crown, and covering the screen after the first would take
    /// the wheel away mid-edit. Postpones only the cover, never the rest.
    private let settleDelay: TimeInterval = 3

    var remainingSeconds: Int {
        guard let endsAt else { return 0 }
        return max(0, Int(endsAt.timeIntervalSince(tick).rounded(.up)))
    }

    var label: String {
        String(format: "%d:%02d", remainingSeconds / 60, remainingSeconds % 60)
    }

    private var ticker: Timer?
    private var presentWork: DispatchWorkItem?

    /// The phone is driving and its rest ends at `date`.
    func mirror(endsAt date: Date, exercise: String) {
        guard begin(endsAt: date, exercise: exercise) else { return }
        showCover()
    }

    /// A set was logged here on the Watch.
    func setFinished(exercise: String, seconds: Int) {
        guard seconds > 0, !isShowing else { return }
        guard begin(endsAt: Date().addingTimeInterval(Double(seconds)),
                    exercise: exercise) else { return }
        postponeCover()
    }

    /// The user is still working rather than resting — swiping to another
    /// exercise. Puts the cover off without moving the rest.
    func stillBusy() {
        guard endsAt != nil, !isShowing else { return }
        postponeCover()
    }

    private func begin(endsAt date: Date, exercise: String) -> Bool {
        let ahead = date.timeIntervalSinceNow
        guard ahead > 0, ahead <= Self.longestPlausibleRest else { return false }
        endsAt = date
        exerciseName = exercise
        tick = Date()
        scheduleNotification(at: date)
        startTicking()
        return true
    }

    private func showCover() {
        presentWork?.cancel()
        presentWork = nil
        isShowing = true
    }

    private func postponeCover() {
        presentWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let endsAt = self.endsAt, endsAt > Date() else { return }
            self.isShowing = true
        }
        presentWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + settleDelay, execute: work)
    }

    /// The user tapped "skip" here. Also calls off the phone's rest, which is
    /// harmless when the phone has none.
    func skip() {
        WatchSessionManager.shared.cancelRestTimerOnPhone()
        cancel()
    }

    /// The phone's rest was skipped, or the workout ended.
    func cancel() {
        presentWork?.cancel()
        presentWork = nil
        endsAt = nil
        isShowing = false
        stopTicking()
        cancelNotification()
    }

    /// Asked once, when the watch first hears about a rest. A refusal is not
    /// fatal — the countdown still works while the app is on screen.
    func requestNotificationPermission() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func finish() {
        presentWork?.cancel()
        presentWork = nil
        endsAt = nil
        isShowing = false
        stopTicking()
        // Only reached with the app awake; otherwise the notification does the
        // buzzing, and this would be a second one on top of it.
        WatchRestHaptics.strong()
    }

    private func startTicking() {
        stopTicking()
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let endsAt = self.endsAt else { return }
                self.tick = Date()
                if endsAt <= self.tick { self.finish() }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func stopTicking() {
        ticker?.invalidate()
        ticker = nil
    }

    private func scheduleNotification(at date: Date) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationId])

        let content = UNMutableNotificationContent()
        content.title = "Rest over"
        content.body = exerciseName.isEmpty
            ? "Time for your next set."
            : "Time for your next set of \(exerciseName)."
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        center.add(UNNotificationRequest(
            identifier: Self.notificationId,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(
                timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)))
    }

    private func cancelNotification() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationId])
        center.removeDeliveredNotifications(withIdentifiers: [Self.notificationId])
    }
}

enum WatchRestHaptics {
    /// `.notification` is the strongest of the standard patterns and the one
    /// people already read as "look at me", repeated so it is not mistaken for
    /// an incoming message.
    static func strong() {
        let device = WKInterfaceDevice.current()
        device.play(.notification)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { device.play(.notification) }
    }
}

// MARK: - Countdown

/// Shown over the watch's own screens while the phone is resting.
struct WatchRestCountdownView: View {
    @ObservedObject private var timer = WatchRestTimer.shared

    var body: some View {
        VStack(spacing: 2) {
            Text("rest").font(.caption)
            Text(timer.label)
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
            if !timer.exerciseName.isEmpty {
                Text(timer.exerciseName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            // Without this the Watch is held hostage for the whole rest: the
            // cover sits over the log screen, and the wheels are behind it.
            Button("skip") { timer.skip() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.top, 4)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.9))
    }
}
