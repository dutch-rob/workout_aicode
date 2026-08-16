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
    /// Whether the countdown screen is up. Separate from `endsAt` because of
    /// the settle delay below.
    @Published private(set) var isShowing = false
    /// Name of the exercise just finished, shown on the countdown screen.
    @Published private(set) var exerciseName = ""
    /// Length of this rest, for the progress ring.
    @Published private(set) var totalSeconds = 0
    /// Bumped by the tick so the countdown redraws.
    @Published private(set) var tick = Date()

    /// When the countdown is due, or nil when nothing is settling. The
    /// acknowledgement is computed from this rather than animated — see
    /// `settleFill`.
    @Published private(set) var coverAt: Date?

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
    /// again.
    ///
    /// The delay only postpones the *cover*, never the rest: your rest began
    /// when the set ended, so the countdown opens already that many seconds
    /// down rather than starting over at the full time.
    private let settleDelay: TimeInterval = 3

    /// How much of the log screen the acknowledgement should cover, 1 at the
    /// moment of the touch and 0 when the countdown is due.
    ///
    /// Computed from the clock rather than held as animated state. A wheel
    /// dragged slowly reports every value it passes, and restarting a
    /// three-second animation on each of them leaves SwiftUI blending a stack
    /// of overlapping animations of one property — which on the Watch, where
    /// the Digital Crown reports far more of them, dragged the grey out to
    /// longer than the rest itself. A number derived from two dates cannot
    /// pile up, and cannot outlive being cancelled either.
    var settleFill: CGFloat {
        Self.settleFill(coverAt: coverAt, now: tick, window: settleDelay)
    }

    /// Pulled out as a pure function so the shape of the drain can be pinned by
    /// a test. The bug it is guarding against was invisible to inspection —
    /// the code read as a three-second linear fade and behaved as a
    /// thirty-second one — so "it looks right" is not evidence here.
    nonisolated static func settleFill(coverAt: Date?, now: Date,
                                       window: TimeInterval) -> CGFloat {
        guard let coverAt, window > 0 else { return 0 }
        return max(0, min(1, CGFloat(coverAt.timeIntervalSince(now) / window)))
    }

    private var ticker: Timer?
    private var tickerIsFast = false
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
        let end = Date().addingTimeInterval(Double(seconds))
        endsAt = end
        tick = Date()

        scheduleNotification(at: end)
        PhoneSessionManager.shared.sendRestTimer(endsAt: end, exercise: exercise)
        postponeCover()
    }

    /// The user is still working rather than resting — swiping to another
    /// exercise, say. Pushes the cover out again without moving the rest
    /// itself, which stays where the finished set put it.
    func stillBusy() {
        guard endsAt != nil, !isShowing else { return }
        postponeCover()
    }

    private func postponeCover() {
        coverAt = Date().addingTimeInterval(settleDelay)
        tick = Date()
        startTicking(fast: true)
        presentWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let endsAt = self.endsAt, endsAt > Date() else { return }
            self.coverAt = nil
            self.isShowing = true
            self.startTicking(fast: false)
            // Resting with the phone on the bench should not mean unlocking it
            // again to see the countdown.
            UIApplication.shared.isIdleTimerDisabled = true
        }
        presentWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + settleDelay, execute: work)
    }

    #if DEBUG
    /// Screenshot demo mode only (see DemoMode.swift): put the countdown on
    /// screen at a chosen time. Deliberately not `setFinished` — that would
    /// schedule a notification and message the Watch, and a screenshot run
    /// should not buzz anything or leave a pending alert behind.
    func showDemoCountdown(exercise: String, total: Int, remaining: Int) {
        exerciseName = exercise
        totalSeconds = total
        endsAt = Date().addingTimeInterval(Double(remaining))
        tick = Date()
        coverAt = nil
        isShowing = true
    }
    #endif

    // MARK: - Ending

    /// The user tapped "skip rest".
    func skip() {
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
            // has stopped. Pick it back up at whichever rate the current state
            // wants — the acknowledgement needs the fast one.
            startTicking(fast: coverAt != nil)
        }
    }

    /// The workout ended (finished or quit) — no rest outlives it.
    func cancel() {
        guard endsAt != nil else { return }
        PhoneSessionManager.shared.cancelRestTimerOnWatch()
        finish(haptic: false)
    }

    private func finish(haptic: Bool) {
        presentWork?.cancel()
        presentWork = nil
        coverAt = nil
        stopTicking()
        cancelNotification()
        endsAt = nil
        isShowing = false
        UIApplication.shared.isIdleTimerDisabled = false
        if haptic { RestTimerHaptics.strong() }
    }

    // MARK: - Ticking (display only)

    /// `fast` only while the acknowledgement is on screen: it is drawn from the
    /// clock, so its smoothness is this interval. A countdown of whole seconds
    /// needs nothing like that rate.
    private func startTicking(fast: Bool) {
        if ticker != nil, tickerIsFast == fast { return }
        stopTicking()
        tickerIsFast = fast
        let t = Timer(timeInterval: fast ? 1.0 / 30 : 0.2, repeats: true) { [weak self] _ in
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

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                // No @State and no animation on purpose — see `settleFill`.
                // Anything the countdown or a quit calls off has to vanish with
                // it, and an animation in flight does not care that the thing
                // it was describing is over.
                // A Canvas, for the reason spelled out in the Watch's copy:
                // an animated frame height is exactly what a picker's own
                // animated transaction latches onto. The phone never showed
                // the symptom, but it has the same wheels and there is no
                // reason for the two to be built differently.
                Canvas { context, size in
                    let filled = size.height * timer.settleFill
                    guard filled > 0 else { return }
                    context.fill(
                        Path(CGRect(x: 0, y: size.height - filled,
                                    width: size.width, height: filled)),
                        with: .color(.secondary.opacity(0.28)))
                }
                .frame(height: height)
                .allowsHitTesting(false)
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
