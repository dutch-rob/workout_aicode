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
// countdown is NOT what measures the time — an absolute end date is. Three
// things are hung off that one date:
//
//   • a foreground tick, which only redraws the countdown screen;
//   • a local notification scheduled at the end date, which is the only thing
//     that can reach the user when the app is backgrounded or the screen off;
//   • the same end date sent to the Apple Watch, which schedules its own
//     notification from it and so buzzes the wrist whether or not it is awake.
//
// The watch is told ONLY when it is reachable at that moment, and the message
// is never queued for later delivery. A queued backlog drained on reconnect
// would fire one notification per stale rest, long after the workout — which is
// exactly why this path is a live send or nothing at all. Relying on iOS
// forwarding the phone's own notification instead is not enough: that only
// happens while the phone is locked, so it misses the common case of the phone
// being in your hand.
//
// Because the notification fires regardless, it is also the finish signal in
// the foreground: the delegate suppresses the banner and plays the haptic
// instead. The tick usually gets there a fraction earlier and finishes first;
// whichever wins, `finish` is idempotent.

enum RestTimerDefaults {
    // The keys, the choices and "what does a new exercise start with" moved to
    // Shared/NewExerciseDefaults.swift when the Mac learned to create
    // exercises. These forward rather than repeat: two copies of the same rest
    // would eventually be two different rests.

    /// The rest a new exercise gets, and what the first-run question starts on.
    static let seconds = defaultRestSeconds

    /// Selectable rests: 0:15 to 5:00 in quarter minutes.
    static var choices: [Int] { ExerciseDefaults.restChoices }

    /// "1:30", "0:45", "5:00".
    static func label(_ seconds: Int) -> String { ExerciseDefaults.restLabel(seconds) }

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: RestTimerKey.enabled)
    }

    /// The rest a new exercise is created with — the user's answer to the
    /// first-run question, or the built-in default if they never gave one.
    static var newExerciseSeconds: Int { ExerciseDefaults.restSeconds }

    /// Ask iOS for permission to post the end-of-rest notification. Only ever
    /// called when the user turns the timer on, so the prompt arrives attached
    /// to a thing they just asked for.
    static func requestNotificationPermission() {
        TimerAlerts.requestPermission()
    }
}

/// Permission to tell the user a timer has finished.
///
/// Shared by the rest timer and the aerobic countdown. It used to belong to the
/// rest timer alone, which meant an aerobic session run by somebody who had
/// never switched the rest timer on had no way to announce itself: they could
/// pocket the phone for twenty minutes and nothing would say the time was up.
/// Asked when a timer that will need it starts, so the prompt is attached to
/// something the user just did.
enum TimerAlerts {
    static func requestPermission() {
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
    /// Name of the exercise just finished, for the notification.
    @Published private(set) var exerciseName = ""
    /// Length of this rest, which the grey drains across.
    @Published private(set) var totalSeconds = 0
    /// Bumped by the tick so the countdown redraws.
    @Published private(set) var tick = Date()

    var isRunning: Bool { endsAt != nil }

    var remainingSeconds: Int {
        guard let endsAt else { return 0 }
        return max(0, Int(endsAt.timeIntervalSince(tick).rounded(.up)))
    }

    // MARK: - The rest, drawn on the log screen
    //
    // There used to be a separate countdown screen, arriving three seconds
    // after the last wheel touch. In use it was fussy: the screen you needed
    // for the next set was taken away and had to be skipped to get back. So
    // the rest now happens where you are. A grey wash fills the log screen the
    // moment a set ends and drains down across the whole rest; the seconds sit
    // small beside the title; the wheels stay usable underneath throughout.
    //
    // Touching a wheel again restarts the rest, as it did during the old
    // settle window: a wheel moved is a set just finished, and your rest
    // begins from the end of that set, not the one before.

    /// How much of the log screen is grey: 1 when the rest starts, 0 when it
    /// is over.
    var restFill: CGFloat {
        Self.restFill(endsAt: endsAt, now: tick, total: TimeInterval(totalSeconds))
    }

    /// Computed from the clock rather than held as animated state, for the
    /// reason the Watch's settle wash taught: a wheel dragged slowly reports
    /// every value it passes, and restarting an animation on each one leaves
    /// SwiftUI blending a stack of them. A number derived from two dates cannot
    /// pile up, and cannot outlive being cancelled.
    nonisolated static func restFill(endsAt: Date?, now: Date,
                                     total: TimeInterval) -> CGFloat {
        guard let endsAt, total > 0 else { return 0 }
        return max(0, min(1, CGFloat(endsAt.timeIntervalSince(now) / total)))
    }

    private var ticker: Timer?

    // MARK: - Starting

    /// A set was finished, or an exercise was logged. Starts the rest, or
    /// starts it again from the top. Does nothing at all when the feature is
    /// off.
    func setFinished(exercise: String, seconds: Int) {
        guard RestTimerDefaults.isEnabled, seconds > 0 else { return }

        exerciseName = exercise
        totalSeconds = seconds
        let end = Date().addingTimeInterval(Double(seconds))
        endsAt = end
        tick = Date()

        run(until: end)
    }

    /// Carry on with a rest begun on the other device, from where it is now —
    /// the end date travels, so the time the hand-over took is already off.
    /// Also used when the app reopens an interrupted workout mid-rest.
    func resume(endsAt end: Date, total: Int, exercise: String) {
        guard RestTimerDefaults.isEnabled, total > 0, end > Date() else { return }
        exerciseName = exercise
        totalSeconds = total
        endsAt = end
        tick = Date()
        run(until: end)
    }

    private func run(until end: Date) {
        scheduleNotification(at: end)
        PhoneSessionManager.shared.sendRestTimer(endsAt: end, total: totalSeconds,
                                                 exercise: exerciseName)
        startTicking()
        PhoneSessionManager.shared.restChanged()
        // Resting with the phone on the bench should not mean unlocking it
        // again to see how long is left.
        UIApplication.shared.isIdleTimerDisabled = true
    }

    #if DEBUG
    /// Screenshot demo mode only (see DemoMode.swift): put a rest on screen at
    /// a chosen point. Deliberately not `setFinished` — that would schedule a
    /// notification and message the Watch, and a screenshot run should not
    /// buzz anything or leave a pending alert behind.
    func showDemoCountdown(exercise: String, total: Int, remaining: Int) {
        exerciseName = exercise
        totalSeconds = total
        endsAt = Date().addingTimeInterval(Double(remaining))
        tick = Date()
    }
    #endif

    // MARK: - Ending

    /// The user tapped the countdown to end the rest early.
    func skip() {
        guard endsAt != nil else { return }
        PhoneSessionManager.shared.cancelRestTimerOnWatch()
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
        } else {
            // Timers do not fire while backgrounded, so whatever was ticking
            // has stopped.
            startTicking()
        }
    }

    /// The Watch has taken the workout over, rest included. Ends the rest here
    /// without telling the Watch: a cancel sent now would land just after the
    /// Watch had picked the rest up, and end it there as well.
    func handOver() {
        guard endsAt != nil else { return }
        finish(haptic: false)
    }

    /// The workout ended (finished or quit) — no rest outlives it.
    func cancel() {
        guard endsAt != nil else { return }
        PhoneSessionManager.shared.cancelRestTimerOnWatch()
        finish(haptic: false)
    }

    private func finish(haptic: Bool) {
        stopTicking()
        cancelNotification()
        endsAt = nil
        PhoneSessionManager.shared.restChanged()
        UIApplication.shared.isIdleTimerDisabled = false
        if haptic { RestTimerHaptics.strong() }
    }

    // MARK: - Ticking (display only)

    /// Twenty times a second. The grey is drawn from the clock, so this is its
    /// smoothness: a two-minute rest over a phone-height screen moves a few
    /// points a second, and twenty steps of that read as continuous.
    private func startTicking() {
        guard ticker == nil else { return }
        let t = Timer(timeInterval: 1.0 / 20, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let endsAt = self.endsAt else { return }
                self.tick = Date()
                if endsAt <= self.tick { self.complete() }
            }
        }
        // .common so the countdown keeps running while a wheel is being
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

// MARK: - The rest on the log screen

/// Greys the log screen the instant a rest starts, then drains that grey
/// downwards over the whole rest. How much grey is left is how much rest is
/// left, readable at a glance from across a bench.
///
/// Lives here, and as a modifier rather than inline, because the log screen's
/// modifier chain is long enough that adding more defeated the type-checker.
struct RestDrain: ViewModifier {
    /// Height to drain across — the log screen's own, not the window's.
    let height: CGFloat

    @ObservedObject private var timer = RestTimer.shared

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                // No @State and no animation on purpose — see `restFill`.
                // A Canvas because an animated frame height is exactly what a
                // picker's own animated transaction latches onto.
                Canvas { context, size in
                    let filled = size.height * timer.restFill
                    guard filled > 0 else { return }
                    context.fill(
                        Path(CGRect(x: 0, y: size.height - filled,
                                    width: size.width, height: filled)),
                        with: .color(.secondary.opacity(0.28)))
                }
                .frame(height: height)
                // The wheels stay usable through the whole rest.
                .allowsHitTesting(false)
            }
    }
}

/// The seconds left, small, beside "log exercise". Tapping it ends the rest —
/// the one control the old countdown screen had, kept where it is findable.
struct RestCounter: View {
    @ObservedObject private var timer = RestTimer.shared

    var body: some View {
        if timer.isRunning {
            Button {
                timer.skip()
            } label: {
                HStack(spacing: 3) {
                    Text(RestTimerDefaults.label(timer.remainingSeconds))
                        .monospacedDigit()
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Rest, \(timer.remainingSeconds) seconds left. Tap to end the rest.")
        }
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
