import SwiftUI
import Combine
import UIKit
import UserNotifications

// MARK: - Rest timer
//
// Counts the rest between sets, and between exercises. Off unless the user
// turns it on in settings; with it off, nothing in this file runs and the app
// behaves exactly as it did before.
//
// The design constraint that shapes everything here: the user must be free to
// put the phone in a pocket, or read something else, while resting. So the
// countdown is NOT what measures the time — an absolute end date is. Two
// things are hung off that one date:
//
//   • a foreground tick, which only redraws the countdown screen;
//   • a local notification scheduled at the end date, which is the only thing
//     that can reach the user when the app is backgrounded or the screen off.
//
// Nothing is sent to the Apple Watch. iOS already forwards this notification to
// the wrist while the phone is locked, so a second, watch-scheduled one would
// only buzz twice. It would also be the less reliable of the two: the message
// carrying it can only be queued when the watch app is unreachable, and a
// queued backlog delivered on reconnect would fire a notification per stale
// rest, minutes or hours after the workout.
//
// Because the notification fires regardless, it is also the finish signal in
// the foreground: the delegate suppresses the banner and plays the haptic
// instead. The tick usually gets there a fraction earlier and finishes first;
// whichever wins, `finish` is idempotent.

enum RestTimerKey {
    /// Master switch. Off for everyone until they turn it on.
    static let enabled = "restTimerEnabled"
    /// What a newly created exercise starts with.
    static let defaultSeconds = "restTimerDefaultSeconds"
}

enum RestTimerDefaults {
    /// The rest a new exercise gets, and what the first-run question starts on.
    /// Long enough for a working set of a compound lift, short enough not to
    /// feel like a punishment on an isolation movement.
    static let seconds = 90

    /// Selectable rests: 0:15 to 5:00 in quarter minutes.
    static let choices: [Int] = Array(stride(from: 15, through: 300, by: 15))

    /// "1:30", "0:45", "5:00".
    static func label(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: RestTimerKey.enabled)
    }

    /// The rest a new exercise is created with — the user's answer to the
    /// first-run question, or the built-in default if they never gave one.
    static var newExerciseSeconds: Int {
        UserDefaults.standard.object(forKey: RestTimerKey.defaultSeconds) as? Int ?? seconds
    }

    /// Ask iOS for permission to post the end-of-rest notification. Only ever
    /// called when the user turns the timer on, so the prompt arrives attached
    /// to a thing they just asked for.
    static func requestNotificationPermission() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
}

// MARK: - The timer itself

@MainActor
final class RestTimer: ObservableObject {

    static let shared = RestTimer()
    private init() {}

    private static let notificationId = "restTimerFinished"

    /// When the current rest ends. Nil when nothing is running — the single
    /// source of truth, deliberately a date rather than a countdown so that
    /// backgrounding, locking, or being killed cannot make it drift.
    @Published private(set) var endsAt: Date?
    /// Whether the countdown screen is up. Separate from `endsAt` because of
    /// the settle delay below.
    @Published private(set) var isShowing = false
    /// Name of the exercise just finished, shown on the countdown screen.
    @Published private(set) var exerciseName = ""
    /// Length of this rest, for the progress ring.
    @Published private(set) var totalSeconds = 0
    /// Bumped by the tick so the countdown redraws.
    @Published private(set) var tick = Date()

    /// Changes every time a rest starts or restarts before the countdown has
    /// appeared. The log screen watches it to acknowledge the touch: without
    /// something happening at that moment, the settle delay reads as the app
    /// having ignored you.
    @Published private(set) var settleToken = UUID()

    var remainingSeconds: Int {
        guard let endsAt else { return 0 }
        return max(0, Int(endsAt.timeIntervalSince(tick).rounded(.up)))
    }

    /// Fraction of the rest still to go, for the ring.
    var remainingFraction: Double {
        guard totalSeconds > 0 else { return 0 }
        return min(1, max(0, Double(remainingSeconds) / Double(totalSeconds)))
    }

    /// A set finishes with several separate touches — the weight wheel, then
    /// the reps wheel — and covering the screen after the first one would take
    /// the second wheel away mid-edit. So the countdown waits this long after
    /// the last touch before appearing, and each further touch pushes it out
    /// again. The delay is part of the rest, so the countdown still starts at
    /// exactly the configured time.
    private let settleDelay: TimeInterval = 3

    /// The settle window, for the log screen's acknowledgement to run over.
    var settleDuration: TimeInterval { settleDelay }

    private var ticker: Timer?
    private var presentWork: DispatchWorkItem?

    // MARK: - Starting

    /// A set was finished, or an exercise was logged. Starts (or restarts) the
    /// rest. Does nothing at all when the feature is off.
    ///
    /// Once the countdown screen is up, further activity is ignored: the user
    /// is resting, not logging, and anything reaching here would be a stray
    /// gesture rather than the end of another set.
    func setFinished(exercise: String, seconds: Int) {
        guard RestTimerDefaults.isEnabled, seconds > 0, !isShowing else { return }

        exerciseName = exercise
        totalSeconds = seconds
        let end = Date().addingTimeInterval(settleDelay + Double(seconds))
        endsAt = end
        tick = Date()
        settleToken = UUID()

        scheduleNotification(at: end)
        startTicking()

        presentWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.endsAt != nil else { return }
            self.isShowing = true
            // Resting with the phone on the bench should not mean unlocking it
            // again to see the countdown.
            UIApplication.shared.isIdleTimerDisabled = true
        }
        presentWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + settleDelay, execute: work)
    }

    // MARK: - Ending

    /// The user tapped "skip rest".
    func skip() {
        finish(haptic: false)
    }

    /// The rest ran out with the app on screen.
    private func complete() {
        finish(haptic: true)
    }

    /// Called by the notification delegate when the alert would have been shown
    /// while the app is in the foreground — the banner is suppressed and this
    /// happens instead. A no-op if the tick already finished the rest.
    func notificationFired() {
        guard endsAt != nil else { return }
        complete()
    }

    /// Returning to the app. A rest that ran out while we were away is simply
    /// over — the user already got the notification, and buzzing again now
    /// would be reporting news from several minutes ago.
    func onForeground() {
        guard let endsAt else { return }
        if endsAt <= Date() {
            finish(haptic: false)
        } else if isShowing {
            startTicking()
        }
    }

    /// The workout ended (finished or quit) — no rest outlives it.
    func cancel() {
        guard endsAt != nil else { return }
        finish(haptic: false)
    }

    private func finish(haptic: Bool) {
        presentWork?.cancel()
        presentWork = nil
        stopTicking()
        cancelNotification()
        endsAt = nil
        isShowing = false
        UIApplication.shared.isIdleTimerDisabled = false
        if haptic { RestTimerHaptics.strong() }
    }

    // MARK: - Ticking (display only)

    private func startTicking() {
        stopTicking()
        let t = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let endsAt = self.endsAt else { return }
                self.tick = Date()
                if endsAt <= self.tick { self.complete() }
            }
        }
        // .common so the countdown keeps running while a scroll view is being
        // dragged.
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func stopTicking() {
        ticker?.invalidate()
        ticker = nil
    }

    // MARK: - Local notification

    private func scheduleNotification(at date: Date) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationId])

        let content = UNMutableNotificationContent()
        content.title = "Rest over"
        content.body = exerciseName.isEmpty
            ? "Time for your next set."
            : "Time for your next set of \(exerciseName)."
        content.sound = .default
        // A rest timer is exactly what this level is for: useless if a Focus
        // holds it back. Ignored (treated as .active) without the Time
        // Sensitive Notifications entitlement, which costs nothing here.
        content.interruptionLevel = .timeSensitive

        let request = UNNotificationRequest(
            identifier: Self.notificationId,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(
                timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)
        )
        center.add(request)
    }

    private func cancelNotification() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationId])
        center.removeDeliveredNotifications(withIdentifiers: [Self.notificationId])
    }
}

// MARK: - Haptics

enum RestTimerHaptics {
    /// Three heavy knocks. One tap is easy to miss through a jacket or with a
    /// bar in your hands; a burst is not.
    static func strong() {
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.prepare()
        for i in 0..<3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.18) {
                generator.impactOccurred(intensity: 1.0)
            }
        }
    }
}

// MARK: - Notification delegate

/// Without a delegate, iOS shows nothing at all for a notification that arrives
/// while the app is in front — which is exactly when the rest ends most often.
/// This suppresses the banner and turns it into the haptic instead.
final class RestTimerNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = RestTimerNotificationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler:
                                @escaping (UNNotificationPresentationOptions) -> Void) {
        Task { @MainActor in RestTimer.shared.notificationFired() }
        completionHandler([])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        // Tapped the notification: the app comes forward into the log screen,
        // and the rest is over.
        Task { @MainActor in RestTimer.shared.onForeground() }
        completionHandler()
    }
}

// MARK: - Settle acknowledgement

/// Greys the log screen the instant a rest starts, then drains that grey away
/// over the settle window.
///
/// The settle delay exists so that setting the weight does not snatch the reps
/// wheel away, but three silent seconds after a touch read as the app having
/// missed it — the one thing a timer must never do. So the acknowledgement is
/// immediate, and it recedes rather than merely fading: how much grey is left
/// is how much time is left to correct a wheel before the countdown covers it.
///
/// Lives here, and as a modifier rather than inline, because the log screen's
/// modifier chain is long enough that adding four more defeated the
/// type-checker outright.
struct RestSettleAcknowledgement: ViewModifier {
    /// Height to drain across — the log screen's own, not the window's.
    let height: CGFloat

    @ObservedObject private var timer = RestTimer.shared
    @State private var fill: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.28))
                    .frame(height: height * fill)
                    .allowsHitTesting(false)
            }
            .onChange(of: timer.settleToken) { _, _ in
                fill = 1
                // A hop, so filling back up is a change of its own rather than
                // being coalesced into the animated drain and never drawn.
                DispatchQueue.main.async {
                    withAnimation(.linear(duration: timer.settleDuration)) { fill = 0 }
                }
            }
            // The countdown taking over, or the rest being called off, both end
            // the acknowledgement early.
            .onChange(of: timer.isShowing) { _, showing in
                if showing { fill = 0 }
            }
            .onChange(of: timer.endsAt) { _, end in
                if end == nil {
                    withAnimation(.easeOut(duration: 0.2)) { fill = 0 }
                }
            }
    }
}

// MARK: - Countdown screen

struct RestCountdownView: View {
    @ObservedObject private var timer = RestTimer.shared

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Text("rest")
                .font(.largeTitle).bold()
            if !timer.exerciseName.isEmpty {
                Text("after \(timer.exerciseName)")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 14)
                Circle()
                    .trim(from: 0, to: timer.remainingFraction)
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(RestTimerDefaults.label(timer.remainingSeconds))
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            .frame(width: 240, height: 240)
            .padding(.vertical, 8)

            Text("You can leave the app — it will buzz when the rest is over.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            Button {
                timer.skip()
            } label: {
                Text("skip rest")
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

// MARK: - Per-exercise / default picker

/// The one place a rest length is chosen, used by the first-run question, by
/// settings, and by the exercise editor — so the options can never drift apart.
struct RestSecondsPicker: View {
    let title: String
    @Binding var seconds: Int

    var body: some View {
        Picker(selection: $seconds) {
            ForEach(RestTimerDefaults.choices, id: \.self) { s in
                Text(RestTimerDefaults.label(s)).tag(s)
            }
        } label: {
            Text(title)
        }
    }
}
