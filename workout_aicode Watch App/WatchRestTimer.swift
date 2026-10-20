import SwiftUI
import Combine
import WatchKit
import UserNotifications

// MARK: - Rest timer, watch side
//
// A rest belongs to whichever device is driving the workout, and there is only
// ever one driver. Three ways in:
//
//   • `mirror` — the phone is logging and has told us when its rest ends, so
//     the wrist can buzz for it.
//   • `setFinished` — the Watch itself is logging. It runs the rest and does
//     NOT tell the phone: the wrist is right there, and a phone buzzing in a
//     locker for a set logged on the Watch is noise.
//   • `resume` — a workout handed over from the phone mid-rest. It carries on
//     from where the phone's rest was, not from the top.
//
// Either way it is one absolute end date that everything hangs off.
//
// It runs on the log screen, as on the phone: no screen of its own. The Watch
// used to cover everything with a countdown three seconds after the last turn
// of the crown; now the screen greys the moment a set ends and the grey drains
// across the whole rest, with the seconds beside the exercise name. The
// wheels stay usable underneath, and turning one starts the rest again.
//
// Why a scheduled notification and not only a Timer: during a rest the wrist
// is down and the app is not frontmost, so a running timer in a suspended app
// buzzes nobody. A notification scheduled for the end date still fires.
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
    /// The whole length of this rest, which the grey drains across.
    @Published private(set) var totalSeconds = 0

    var isRunning: Bool { endsAt != nil }

    /// How much of the screen is grey: 1 as the rest starts, 0 when it is over.
    ///
    /// Computed from the clock, deliberately, rather than being a piece of
    /// animated state. The crown reports every value it passes through, so one
    /// spin of the wheel is dozens of "set finished" events; restarting an
    /// animation on each of them once left SwiftUI blending dozens of
    /// overlapping animations of the same property, and the grey crawled down
    /// the screen for far longer than intended. A number derived from two
    /// dates cannot pile up.
    var restFill: CGFloat {
        guard let endsAt, totalSeconds > 0 else { return 0 }
        return max(0, min(1, CGFloat(endsAt.timeIntervalSince(tick) / Double(totalSeconds))))
    }

    var remainingSeconds: Int {
        guard let endsAt else { return 0 }
        return max(0, Int(endsAt.timeIntervalSince(tick).rounded(.up)))
    }

    var label: String {
        String(format: "%d:%02d", remainingSeconds / 60, remainingSeconds % 60)
    }

    private var ticker: Timer?
    private var scheduleWork: DispatchWorkItem?

    /// The phone is driving and its rest ends at `date`. `total` is the full
    /// length; a phone from before it was sent leaves it out, and the time
    /// still to go then stands in for it.
    func mirror(endsAt date: Date, total: Int?, exercise: String) {
        let whole = total ?? Int(date.timeIntervalSinceNow.rounded(.up))
        _ = begin(endsAt: date, total: whole, exercise: exercise)
    }

    /// A set was logged, or a wheel moved, here on the Watch. Starts the rest
    /// or starts it again from the top.
    func setFinished(exercise: String, seconds: Int) {
        guard seconds > 0 else { return }
        _ = begin(endsAt: Date().addingTimeInterval(Double(seconds)),
                  total: seconds, exercise: exercise)
    }

    /// A rest handed over from the phone, carried on from where it is.
    func resume(endsAt date: Date, total: Int, exercise: String) {
        _ = begin(endsAt: date, total: total, exercise: exercise)
    }

    private func begin(endsAt date: Date, total: Int, exercise: String) -> Bool {
        let ahead = date.timeIntervalSinceNow
        guard ahead > 0, ahead <= Self.longestPlausibleRest, total > 0 else { return false }
        endsAt = date
        totalSeconds = total
        exerciseName = exercise
        tick = Date()
        scheduleNotificationSoon()
        startTicking()
        return true
    }

    #if DEBUG
    /// Screenshot demo mode only (see DemoMode.swift). Not `setFinished`: that
    /// would schedule a notification, and a screenshot run should not leave a
    /// pending alert on the watch.
    func showDemoCountdown(exercise: String, remaining: Int, total: Int = 90) {
        exerciseName = exercise
        totalSeconds = total
        endsAt = Date().addingTimeInterval(Double(remaining))
        tick = Date()
    }
    #endif

    /// The user tapped the countdown to end the rest. Also calls off the
    /// phone's rest, which is harmless when the phone has none.
    func skip() {
        WatchSessionManager.shared.cancelRestTimerOnPhone()
        cancel()
    }

    /// The phone's rest was skipped, the workout ended, or the phone took the
    /// workout over. Local only: tells nobody.
    func cancel() {
        scheduleWork?.cancel()
        scheduleWork = nil
        endsAt = nil
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
        scheduleWork?.cancel()
        scheduleWork = nil
        endsAt = nil
        stopTicking()
        // Only reached with the app awake; otherwise the notification does the
        // buzzing, and this would be a second one on top of it.
        WatchRestHaptics.strong(taps: WatchSessionManager.shared.restTaps)
    }

    /// Fifteen times a second while a rest runs: the grey is drawn from the
    /// clock, so this is its smoothness, and a watch screen is small enough
    /// that fifteen steps read as continuous. Stops with the rest — this is a
    /// watch battery.
    private func startTicking() {
        guard ticker == nil else { return }
        let t = Timer(timeInterval: 1.0 / 15, repeats: true) { [weak self] _ in
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

    /// Debounced, because the crown redefines the end of the rest dozens of
    /// times a second while it is turning, and asking the notification centre
    /// to reschedule at that rate is both pointless and slow.
    private func scheduleNotificationSoon() {
        scheduleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let endsAt = self.endsAt else { return }
            self.scheduleNotification(at: endsAt)
        }
        scheduleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
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
    /// people already read as "look at me". How MANY of them is the only dial
    /// there is — watchOS gives no way to make a tap harder — and in a gym,
    /// under a bar, one is easy to miss. The count is the user's, set on the
    /// phone; two is what it was before there was a choice.
    static func strong(taps: Int = WatchPreferences.defaultRestTaps) {
        let device = WKInterfaceDevice.current()
        let count = WatchPreferences.clampTaps(taps)
        for index in 0..<count {
            // Far enough apart to be felt as separate taps rather than one
            // long buzz, close enough to read as one announcement.
            let delay = Double(index) * 0.6
            if delay == 0 {
                device.play(.notification)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    device.play(.notification)
                }
            }
        }
    }
}

// MARK: - The rest on screen

/// Greys the screen the instant a rest starts and drains the grey down across
/// the whole rest, as the phone does.
///
/// White rather than grey: the watch UI is on black, where a grey wash is
/// almost invisible and a light one reads as exactly the same gesture.
struct WatchRestDrain: ViewModifier {
    @ObservedObject private var timer = WatchRestTimer.shared

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                // Measured against the screen rather than the laid-out content:
                // the buttons sit in their own safe-area strip, and a grey that
                // stopped short of them looked like a rendering fault.
                //
                // A Canvas, not a Rectangle with an animated height, and that
                // is the whole point of it: the crown changes the picker's
                // selection inside an animated transaction, which SwiftUI
                // applied to the grey's height too, so it slid up from nothing
                // before it began draining. A Canvas has no animatable
                // geometry: the closure runs, the rectangle is where it is.
                Canvas { context, size in
                    let height = size.height * timer.restFill
                    guard height > 0 else { return }
                    context.fill(
                        Path(CGRect(x: 0, y: size.height - height,
                                    width: size.width, height: height)),
                        with: .color(.white.opacity(0.22)))
                }
                .allowsHitTesting(false)
                .ignoresSafeArea()
            }
    }
}

/// The seconds left, small, beside the exercise name. Tapping it ends the rest
/// — the one control the old countdown screen had.
struct WatchRestCounter: View {
    @ObservedObject private var timer = WatchRestTimer.shared

    var body: some View {
        if timer.isRunning {
            Button {
                timer.skip()
            } label: {
                HStack(spacing: 2) {
                    Text(timer.label).monospacedDigit()
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .font(.caption2.weight(.semibold))
            }
            .buttonStyle(.plain)
            .fixedSize()
        }
    }
}
