import SwiftUI
import Combine
import WatchKit
import UserNotifications

// MARK: - Rest timer, watch side
//
// The Watch never decides anything about the rest: the phone owns the timer and
// sends one thing, the moment it ends. Everything here hangs off that date.
//
// The reason it is a date and not a countdown, and the reason a local
// notification is scheduled rather than a `Timer` relied on: the watch app is
// almost certainly not frontmost during a rest — the wrist is down, the screen
// is off. A scheduled notification still buzzes; a running timer in a suspended
// app does not.
//
// The countdown view is only for the case where the user happens to be looking
// at the watch, and is honestly secondary.

@MainActor
final class WatchRestTimer: ObservableObject {

    static let shared = WatchRestTimer()
    private init() {}

    private static let notificationId = "restTimerFinished"

    @Published private(set) var endsAt: Date?
    @Published private(set) var exerciseName = ""
    @Published private(set) var tick = Date()

    var isRunning: Bool { endsAt.map { $0 > Date() } ?? false }

    var remainingSeconds: Int {
        guard let endsAt else { return 0 }
        return max(0, Int(endsAt.timeIntervalSince(tick).rounded(.up)))
    }

    var label: String {
        String(format: "%d:%02d", remainingSeconds / 60, remainingSeconds % 60)
    }

    private var ticker: Timer?

    /// The phone started a rest ending at `date`.
    func start(endsAt date: Date, exercise: String) {
        guard date > Date() else { return }
        endsAt = date
        exerciseName = exercise
        tick = Date()
        scheduleNotification(at: date)
        startTicking()
    }

    /// The phone's rest was skipped or the workout ended.
    func cancel() {
        endsAt = nil
        stopTicking()
        cancelNotification()
    }

    /// Ask once, when the watch first hears about a rest. A refusal is not
    /// fatal — the countdown still works while the app is on screen.
    func requestNotificationPermission() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func finish() {
        endsAt = nil
        stopTicking()
        // Only reached with the app awake; otherwise the notification is what
        // does the buzzing.
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
    /// people already read as "look at me", repeated so it cannot be mistaken
    /// for an incoming message.
    static func strong() {
        let device = WKInterfaceDevice.current()
        device.play(.notification)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { device.play(.notification) }
    }
}

// MARK: - Countdown

/// Shown over the watch's log screen while the phone is resting.
struct WatchRestCountdownView: View {
    @ObservedObject private var timer = WatchRestTimer.shared

    var body: some View {
        VStack(spacing: 6) {
            Text("rest").font(.headline)
            Text(timer.label)
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
            if !timer.exerciseName.isEmpty {
                Text(timer.exerciseName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.9))
    }
}
