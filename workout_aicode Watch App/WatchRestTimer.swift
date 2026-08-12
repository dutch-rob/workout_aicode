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

    /// When the cover is due, or nil when nothing is settling. The
    /// acknowledgement is computed from this and `tick` rather than animated,
    /// which is what makes it survive the Digital Crown — see below.
    @Published private(set) var coverAt: Date?

    /// Same reasoning as the phone's: a set is logged over several separate
    /// turns of the crown, and covering the screen after the first would take
    /// the wheel away mid-edit. Postpones only the cover, never the rest.
    private let settleDelay: TimeInterval = 3

    /// How much of the screen the acknowledgement should cover, 1 at the
    /// moment of the turn and 0 when the cover is due.
    ///
    /// Computed from the clock, deliberately, rather than being a piece of
    /// animated state. The crown reports every value it passes through, so one
    /// spin of the wheel is dozens of "set finished" events; restarting a
    /// three-second animation on each of them left SwiftUI blending dozens of
    /// overlapping animations of the same property, and the grey crawled down
    /// the screen for far longer than the rest itself. A number derived from
    /// two dates cannot pile up: however many events arrive, the answer is
    /// always "this far, right now".
    var settleFill: CGFloat {
        guard let coverAt, settleDelay > 0 else { return 0 }
        return max(0, min(1, CGFloat(coverAt.timeIntervalSince(tick) / settleDelay)))
    }

    var remainingSeconds: Int {
        guard let endsAt else { return 0 }
        return max(0, Int(endsAt.timeIntervalSince(tick).rounded(.up)))
    }

    var label: String {
        String(format: "%d:%02d", remainingSeconds / 60, remainingSeconds % 60)
    }

    private var ticker: Timer?
    private var tickerIsFast = false
    private var presentWork: DispatchWorkItem?
    private var scheduleWork: DispatchWorkItem?

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
        scheduleNotificationSoon()
        startTicking(fast: coverAt != nil)
        return true
    }

    private func showCover() {
        presentWork?.cancel()
        presentWork = nil
        coverAt = nil
        isShowing = true
        startTicking(fast: false)
    }

    private func postponeCover() {
        coverAt = Date().addingTimeInterval(settleDelay)
        tick = Date()
        startTicking(fast: true)
        presentWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let endsAt = self.endsAt, endsAt > Date() else { return }
            self.showCover()
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
        scheduleWork?.cancel()
        scheduleWork = nil
        endsAt = nil
        coverAt = nil
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
        scheduleWork?.cancel()
        scheduleWork = nil
        endsAt = nil
        coverAt = nil
        isShowing = false
        stopTicking()
        // Only reached with the app awake; otherwise the notification does the
        // buzzing, and this would be a second one on top of it.
        WatchRestHaptics.strong()
    }

    /// `fast` only while the acknowledgement is on screen: it is drawn from the
    /// clock, so its smoothness is this interval. The rest of the time a
    /// countdown of whole seconds needs nothing like that rate, and this is a
    /// watch battery.
    private func startTicking(fast: Bool) {
        if ticker != nil, tickerIsFast == fast { return }
        stopTicking()
        tickerIsFast = fast
        let t = Timer(timeInterval: fast ? 1.0 / 15 : 0.5, repeats: true) { [weak self] _ in
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
    /// people already read as "look at me", repeated so it is not mistaken for
    /// an incoming message.
    static func strong() {
        let device = WKInterfaceDevice.current()
        device.play(.notification)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { device.play(.notification) }
    }
}

// MARK: - Settle acknowledgement

/// The Watch's half of the phone's draining grey: the screen greys the instant
/// a rest starts here and the grey recedes across the settle window, so how
/// much is left is how much time is left to correct a wheel before the
/// countdown covers it.
///
/// Only for rests started ON the Watch. A rest mirrored from the phone shows
/// its countdown at once — the phone has already served the settle delay, and
/// greying the watch for three seconds after the fact would be theatre.
///
/// White rather than grey: the watch UI is on black, where a grey wash is
/// almost invisible and a light one reads as exactly the same gesture.
struct WatchRestSettleAcknowledgement: ViewModifier {
    @ObservedObject private var timer = WatchRestTimer.shared

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                // Measured against the screen rather than the laid-out content:
                // the buttons sit in their own safe-area strip, and a grey that
                // stopped short of them looked like a rendering fault rather
                // than a deliberate wash over the screen.
                //
                // No @State and no animation here on purpose — see settleFill.
                // Quitting mid-drain used to leave the grey sliding down over
                // the workout list, because an animation in flight does not
                // care that the thing it was describing has been called off.
                //
                // Drawn into a Canvas rather than being a Rectangle with an
                // animated height, and that is the whole point of it.
                //
                // A `.frame(height:)` is animatable, so SwiftUI will happily
                // interpolate it — and the crown changes the picker's
                // selection inside an animated transaction, which SwiftUI
                // applies to everything else changed during that update. The
                // grey slid up from nothing before it began draining. Asking
                // for the animation to be dropped (`.transaction`) did not
                // hold. A Canvas has no animatable geometry in the first
                // place: the closure runs, the rectangle is where it is.
                Canvas { context, size in
                    let height = size.height * timer.settleFill
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
