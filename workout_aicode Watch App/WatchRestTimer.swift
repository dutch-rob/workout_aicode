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
// of the crown; now a red bar fills the left edge of the screen the moment a
// set ends and drains away across the rest, with the seconds over the wheels.
// The wheels stay usable throughout, and turning one starts the rest again.
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
    /// The whole length of this rest, which the bar drains across.
    @Published private(set) var totalSeconds = 0

    var isRunning: Bool { endsAt != nil }

    /// How much of the bar is filled: 1 as the rest starts, 0 when it is over.
    /// The arithmetic, and why it is arithmetic rather than animated state,
    /// is in `RestBar` — which the phone's countdown uses as well.
    var restFill: CGFloat {
        RestBar.fill(endsAt: endsAt, now: tick, total: TimeInterval(totalSeconds))
    }

    var remainingSeconds: Int { RestBar.remaining(endsAt: endsAt, now: tick) }

    var label: String { RestBar.label(endsAt: endsAt, now: tick) }

    private var ticker: Timer?
    private var scheduleWork: DispatchWorkItem?
    /// A restart waiting for the wheel to stop moving — see `setFinished`.
    private var restartWork: DispatchWorkItem?

    /// The phone is driving and its rest ends at `date`. `total` is the full
    /// length; a phone from before it was sent leaves it out, and the time
    /// still to go then stands in for it.
    func mirror(endsAt date: Date, total: Int?, exercise: String) {
        let whole = total ?? Int(date.timeIntervalSinceNow.rounded(.up))
        _ = begin(endsAt: date, total: whole, exercise: exercise)
    }

    /// A set was logged, or a wheel moved, here on the Watch. Starts the rest
    /// or starts it again from the top.
    ///
    /// Coalesced, and deliberately NOT done on the spot. The wheels call this
    /// once per value the crown passes through, and again the instant a finger
    /// lets go — which is the exact moment the wheel is about to decelerate
    /// onto a number. Doing the work there meant four published changes, a
    /// redraw of the bar and a notification reschedule on the main thread
    /// while the picker was settling, and the wheel came to rest one click
    /// past where it was let go. Reported from three sets of one real workout,
    /// and only ever while a rest was running — which is when the bar and the
    /// counter are on screen to be redrawn.
    ///
    /// A third of a second later nobody can tell the difference, and the
    /// wheel has stopped by then.
    func setFinished(exercise: String, seconds: Int) {
        guard seconds > 0 else { return }
        restartWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            _ = self.begin(endsAt: Date().addingTimeInterval(Double(seconds)),
                           total: seconds, exercise: exercise)
        }
        restartWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
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
        // Remade rather than left running: a rest of a different length wants
        // a different rate, and `startTicking` keeps whatever is already there.
        stopTicking()
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
        restartWork?.cancel()
        restartWork = nil
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
        restartWork?.cancel()
        restartWork = nil
        scheduleWork?.cancel()
        scheduleWork = nil
        endsAt = nil
        stopTicking()
        // Only reached with the app awake; otherwise the notification does the
        // buzzing, and this would be a second one on top of it.
        WatchRestHaptics.strong(taps: WatchSessionManager.shared.restTaps)
    }

    /// How often the clock is re-read, taken from how fast the bar actually
    /// moves: one tick per point of travel, and no faster.
    ///
    /// This was a flat fifteen times a second. A ninety-second rest drains
    /// about two points a second down a watch screen, so fourteen of every
    /// fifteen of those ticks redrew the bar in the same place — all on the
    /// main thread, some of it inside the few hundred milliseconds a wheel
    /// spends settling onto a number.
    ///
    /// Never slower than twice a second: the counter beside the wheels counts
    /// whole seconds and must not skip one.
    private var tickInterval: TimeInterval {
        guard totalSeconds > 0 else { return 0.5 }
        let screenPoints = 220.0
        return min(0.5, max(1.0 / 15, Double(totalSeconds) / screenPoints))
    }

    /// Runs only while a rest does — this is a watch battery.
    private func startTicking() {
        guard ticker == nil else { return }
        // Captures nothing. A Timer's block is `@Sendable` and this class is
        // `@MainActor`, so capturing `self` — even weakly — is an error under
        // the Swift 6 language mode. Naming the singleton inside the hop to the
        // main actor says the same thing and stays correct there.
        let t = Timer(timeInterval: tickInterval, repeats: true) { _ in
            Task { @MainActor in
                let timer = WatchRestTimer.shared
                guard let endsAt = timer.endsAt else { return }
                timer.tick = Date()
                if endsAt <= timer.tick { timer.finish() }
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
            let delay = Double(index) * spacing
            if delay == 0 {
                device.play(.notification)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    device.play(.notification)
                }
            }
        }
    }

    /// Seconds between taps.
    ///
    /// `.notification` is not an instant — it is a PATTERN about a second
    /// long. Asking for the next one while it is still playing does not
    /// queue it: watchOS drops it. At the 0.6 s this used, five taps were
    /// played and about three were felt, with a gap in the middle where two
    /// landed on top of each other — reported from a real workout, in those
    /// words.
    ///
    /// So the spacing has to outlast the pattern rather than merely separate
    /// it. Five taps is then a long announcement, which is the point of
    /// choosing five: whoever sets it is under a bar and means to be
    /// interrupted.
    private static let spacing = 1.1
}

// MARK: - The rest on screen

/// The rest as a bar up the left edge of the screen, full at the start and
/// drained away by the end.
///
/// It used to be a wash of white at 22% over the WHOLE screen, including the
/// wheels, and then a 5pt white sliver in the margin beside them. It is now
/// wide enough to run under the "weight" and "reps" labels, for three reasons:
///
///   • The wheels. Every tick of the rest redraws this, and a full-screen
///     overlay has to be composited back over the pickers each time —
///     including during the few hundred milliseconds a wheel spends settling
///     onto a number, which is exactly when a wheel was coming to rest one
///     click past where it was let go. A bar of `barWidth` points touches
///     under a tenth of the screen and none of the wheels.
///   • The corners. The screen is a rounded rectangle, so the left edge is
///     cut away at either end: a 5pt bar first appeared about 20pt down from
///     the top and was gone about 20pt short of the bottom, which is the
///     first and last few seconds of every rest. The bar looked part-drained
///     the moment it started and empty before it was — reported from a real
///     workout. This width clears the curve within about 5pt of either end.
///   • It can be read. At 22% over black a wash is faint by design, because
///     a stronger one would sit on top of the numbers. The row labels are the
///     one column with no numbers in it, so the bar can be as strong as it
///     likes there.
///
/// Why drawn over everything, and why additive: a bar UNDER the content would
/// disappear at exactly the two places the ends of it fall — behind the zone
/// band at the top and behind the buttons at the bottom. So it goes on top,
/// and `.plusLighter` adds it to what is already there rather than hiding it:
/// black becomes the bar's red, and anything already white STAYS white. The
/// row labels therefore read straight through the bar, which is why they are
/// plain white rather than `.secondary` — see `WatchLogExerciseView.rowLabel`.
///
/// It does NOT run the full height of the screen, and that is the one thing
/// about it that was reported from a real workout rather than reasoned out.
/// Additive over the heart rate zone band makes red plus blue, which at the
/// top corner is where the bar's first seconds are: the one place a glance
/// has to answer "did it start?" was the one place the answer was a smudge.
/// So the bar begins at the BOTTOM of the top row, under the band, and stops
/// as far short of the bottom as it starts short of the top. Symmetrical
/// because an asymmetric bar reads as part-drained when it is full.
struct WatchRestDrain: ViewModifier {
    @ObservedObject private var timer = WatchRestTimer.shared

    /// Where the log screen's first row ends, reported by the screen itself.
    ///
    /// Measured rather than written down: the row is one line of `.caption`
    /// over the clock's strip, so its height is the watch's size and the
    /// user's text size, neither of which this file can know. Nil until the
    /// first report — and kept once it arrives, since an exercise with no
    /// band (an aerobic one) should not make the bar jump to full height.
    @State private var topRowBottom: CGFloat?

    /// How wide the bar is: the log screen's own margin plus its row-label
    /// column, so it covers the labels and stops short of the wheels.
    static let barWidth: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .onPreferenceChange(WatchRestBarTop.self) { reported in
                if let reported { topRowBottom = reported }
            }
            .overlay(alignment: .bottom) {
                // Measured against the screen rather than the laid-out content:
                // the buttons sit in their own safe-area strip, and a bar that
                // stopped short of them would read as the rest being over.
                //
                // A Canvas, not a Rectangle with an animated height, and that
                // is the whole point of it: the crown changes the picker's
                // selection inside an animated transaction, which SwiftUI
                // applied to the bar's height too, so it slid up from nothing
                // before it began draining. A Canvas has no animatable
                // geometry: the closure runs, the rectangle is where it is.
                Canvas { [inset = topRowBottom ?? 0] context, size in
                    guard let rect = RestBar.bar(in: size.height, inset: inset,
                                                 width: Self.barWidth,
                                                 fill: timer.restFill) else { return }
                    context.fill(Path(rect), with: .color(.red))
                }
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
                .ignoresSafeArea()
            }
    }
}

/// How far down the screen the rest's bar should begin: the bottom edge of the
/// log screen's first row, which is also the bottom of the heart rate zone band
/// when there is one, since the band is that row's background.
///
/// A preference because the two ends of it are far apart in the view tree — the
/// row is deep inside the log screen, the bar is a modifier on the whole app —
/// and because it travels UP, which is the direction preferences go. The value
/// is static once laid out, so the drain is not rebuilt by this at heart-rate
/// speed; see the warning on `WatchZoneRowBackground` about exactly that.
nonisolated struct WatchRestBarTop: PreferenceKey {
    static let defaultValue: CGFloat? = nil
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        guard let next = nextValue() else { return }
        value = max(value ?? next, next)
    }
}

extension View {
    /// Say that this row is the one the rest's bar starts under.
    func marksRestBarTop() -> some View {
        overlay {
            GeometryReader { geo in
                Color.clear.preference(key: WatchRestBarTop.self,
                                       value: geo.frame(in: .global).maxY)
            }
        }
    }
}

/// The seconds left, small, beside the exercise name. Tapping it ends the rest
/// — the one control the old countdown screen had.
struct WatchRestCounter: View {
    @ObservedObject private var timer = WatchRestTimer.shared

    /// Without the ✕, for where there is no room for it — see
    /// `WatchRestOverlay`. Tapping the number still ends the rest, which is
    /// what the seconds beside "log exercise" do on the phone.
    var compact = false

    var body: some View {
        if timer.isRunning {
            Button {
                timer.skip()
            } label: {
                HStack(spacing: 2) {
                    Text(timer.label).monospacedDigit()
                    if !compact {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption2.weight(.semibold))
            }
            .buttonStyle(.plain)
            .fixedSize()
        }
    }
}

/// The rest's seconds laid over the wheels rather than beside the name.
///
/// With two rows of wheels the name is up on the clock's row, where there is
/// no width to spare: the counter and its ✕ sat on top of the exercise title.
/// Reported from a real workout, with the right answer attached — put the
/// number over the wheels, and leave the wheels working.
///
/// So it is the number alone, in the top corner, away from the middle of a
/// wheel where a tap means "that set is done". Everything around it passes
/// touches straight through: `allowsHitTesting(false)` on the padding means
/// only the few points actually under the digits belong to the counter.
struct WatchRestOverlay: View {
    @ObservedObject private var timer = WatchRestTimer.shared

    var body: some View {
        if timer.isRunning {
            WatchRestCounter(compact: true)
                .padding(.horizontal, 4)
                .background(.black.opacity(0.55), in: Capsule())
                .padding(.trailing, 2)
        }
    }
}
