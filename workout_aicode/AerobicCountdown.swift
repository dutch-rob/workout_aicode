import SwiftUI
import Combine
import UIKit
import UserNotifications
import HealthKit

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

/// What one finished aerobic session came to, kept per exercise on the log
/// screen so the numbers stay put while you look at them and are still there
/// when you press log.
struct AerobicSummary: Equatable {
    let seconds: Int
    let averageHeartRate: Int
    let maximumHeartRate: Int
    /// Five entries when a heart rate was measured, empty when none was.
    let zoneSeconds: [Int]

    var hasHeartRate: Bool { averageHeartRate > 0 }
}

enum AerobicDefaults {
    /// Wheel range, in minutes. One minute at the bottom because the wheel is
    /// also how you log a short interval; two hours at the top is past what
    /// this app is for.
    static let minuteChoices: [Int] = Array(1...120)
    static let defaultMinutes = 20

    static func label(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    // MARK: Remembering the length
    //
    // The wheel opens on whatever was chosen for THIS exercise last time, which
    // is what makes it a one-tap start on the second visit. Deliberately the
    // number that was *chosen*, not the one that was logged: stopping a
    // twenty-minute ride at twelve should not quietly make it a twelve-minute
    // ride for ever after.

    private static func key(_ exerciseId: UUID) -> String {
        "aerobicMinutes-\(exerciseId.uuidString)"
    }

    static func lastMinutes(for exerciseId: UUID) -> Int {
        UserDefaults.standard.object(forKey: key(exerciseId)) as? Int ?? defaultMinutes
    }

    static func rememberMinutes(_ minutes: Int, for exerciseId: UUID) {
        UserDefaults.standard.set(minutes, forKey: key(exerciseId))
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

    // MARK: Heart rate, as reported by the Watch
    //
    // The Watch runs the Apple workout and sends each reading here. The zone
    // comes with it rather than being worked out again: the Watch is the device
    // with permission to read the resting rate and date of birth the boundaries
    // are drawn from, and classifying again here would let the phone and the
    // wrist disagree about the same beat.

    @Published private(set) var currentHeartRate: Int?
    @Published private(set) var currentZone: Int?
    /// Highest seen this session, and the running average of what arrived.
    @Published private(set) var maximumHeartRate = 0
    private var heartRateSum = 0
    private var heartRateCount = 0
    private var tally = ZoneTally(zones: HeartRateZones())

    var averageHeartRate: Int {
        heartRateCount > 0 ? Int((Double(heartRateSum) / Double(heartRateCount)).rounded()) : 0
    }

    /// Time in each zone so far. Empty when no reading ever arrived, which is
    /// the ordinary case without a Watch and must not read as five zeroes —
    /// "no heart rate" and "no time in any zone" are different claims.
    var zoneSeconds: [Int] { heartRateCount > 0 ? tally.seconds : [] }

    /// Why there is no heart rate on screen, when there is not one.
    ///
    /// Read authorisation cannot be queried — HealthKit deliberately refuses to
    /// say whether a read was denied, so that an app cannot infer health facts
    /// from the answer. So this reports what can actually be observed: whether
    /// there is a Watch at all, and whether anything has arrived from it yet.
    enum HeartRateStatus {
        case measuring
        /// A Watch is there and the first reading has not landed. Normal for
        /// the first few seconds of every session.
        case waiting
        /// No Watch app, so there is nothing to measure with.
        case noWatch
        /// A Watch, but nothing has come from it for long enough that waiting
        /// is no longer the likeliest explanation.
        case silent
    }

    /// How long to call it "waiting" before calling it silent.
    private static let patience: TimeInterval = 25

    var heartRateStatus: HeartRateStatus {
        if currentHeartRate != nil { return .measuring }
        if !watchWasPresent { return .noWatch }
        return elapsedSeconds < Int(Self.patience) ? .waiting : .silent
    }

    /// The activity of the running session, so a Watch-less one can be written
    /// to Health when it ends.
    private var activityRaw: String?
    /// Whether a Watch app existed when this session began. Captured at the
    /// start so the message cannot flip about mid-session.
    private var watchWasPresent = false

    /// A reading from the Watch.
    func receiveHeartRate(_ beatsPerMinute: Int, zone: Int?, at date: Date = Date()) {
        guard endsAt != nil else { return }   // nothing running; ignore stragglers
        currentHeartRate = beatsPerMinute
        currentZone = zone
        maximumHeartRate = max(maximumHeartRate, beatsPerMinute)
        heartRateSum += beatsPerMinute
        heartRateCount += 1
        tally.add(zone: zone, at: date)
    }

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

    func start(exercise: String, seconds: Int, activityRaw: String?) {
        guard seconds > 0, !isShowing else { return }
        exerciseName = exercise
        totalSeconds = seconds
        let now = Date()
        startedAt = now
        endsAt = now.addingTimeInterval(Double(seconds))
        tick = now
        finishedSeconds = nil
        isShowing = true
        currentHeartRate = nil
        currentZone = nil
        maximumHeartRate = 0
        heartRateSum = 0
        heartRateCount = 0
        tally = ZoneTally(zones: HeartRateZones())
        watchWasPresent = PhoneSessionManager.shared.hasWatchApp
        self.activityRaw = activityRaw
        UIApplication.shared.isIdleTimerDisabled = true
        // Without this the countdown is silent for anyone who never switched
        // the rest timer on — which includes anybody using this app only for
        // cardio, and anybody without a Watch.
        TimerAlerts.requestPermission()
        scheduleNotification(at: endsAt!)
        // The Watch is what actually measures: it starts a real Apple workout
        // for this activity, which is also what puts the session in Fitness.
        PhoneSessionManager.shared.startAerobicOnWatch(activityRaw: activityRaw,
                                                       exercise: exercise,
                                                       endsAt: endsAt!)
        startTicking()
    }

    #if DEBUG
    /// Screenshot/demo only: a countdown with a heart rate in it, so the band
    /// can be seen without a Watch on a wrist.
    ///
    /// `total` is given rather than derived, so a capture can show a real
    /// twenty-minute ride part-way through. The screenshot script waits for two
    /// identical frames before it shoots, which a running clock never produces,
    /// so it gives up after twenty seconds — and those twenty seconds come off
    /// whatever is left. Start high enough that it still reads well.
    func showDemoCountdown(exercise: String, remaining: Int, bpm: Int, total: Int) {
        exerciseName = exercise
        totalSeconds = total
        startedAt = Date()
        endsAt = Date().addingTimeInterval(Double(remaining))
        tick = Date()
        isShowing = true
        let zones = HeartRateZones()
        currentHeartRate = bpm
        currentZone = zones.zone(for: bpm)
        startTicking()
    }
    #endif

    /// A session the Watch is running. Shown, but not owned: no notification
    /// is scheduled and the Watch is not asked to start anything, because it
    /// already is. The Watch logs it too, so this device records nothing.
    func mirrorFromWatch(exercise: String, endsAt date: Date) {
        guard !isShowing, date > Date() else { return }
        exerciseName = exercise
        totalSeconds = max(1, Int(date.timeIntervalSinceNow.rounded()))
        startedAt = Date()
        endsAt = date
        tick = Date()
        finishedSeconds = nil
        isMirroring = true
        watchWasPresent = true          // the Watch is running it
        isShowing = true
        startTicking()
    }

    /// True while the Watch owns the session and this is only a display.
    @Published private(set) var isMirroring = false

    /// Stopped by hand. Records however long it actually ran.
    func stop() {
        finish(haptic: false)
    }

    /// Stopped on the Watch. Same session, so it ends here too — and without
    /// telling the Watch to stop again, which is where a loop would start.
    func stopFromWatch() {
        guard endsAt != nil else { return }
        finishedSeconds = elapsedSeconds
        clear(tellWatch: false)
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
        // A mirrored session is logged by the Watch, so this device must not
        // also write it — two rows for one bike ride.
        if !isMirroring { finishedSeconds = elapsedSeconds }
        writeToHealthIfNoWatch()
        clear()
        if haptic { RestTimerHaptics.strong() }
    }

    /// With no Watch there is no Apple workout for this session, so the phone
    /// writes a plain one. With a Watch, the Watch's is the record.
    private func writeToHealthIfNoWatch() {
        guard !watchWasPresent, !isMirroring,
              let startedAt, elapsedSeconds > 0 else { return }
        HealthWorkoutLogger.shared.saveAerobicWorkout(
            activityType: WatchAerobicActivity.activityType(for: activityRaw),
            start: startedAt,
            end: startedAt.addingTimeInterval(Double(elapsedSeconds)))
    }

    private func clear(tellWatch: Bool = true) {
        // A mirrored session belongs to the Watch; ending the display here must
        // not end the workout on the wrist.
        if tellWatch, !isMirroring { PhoneSessionManager.shared.endAerobicOnWatch() }
        isMirroring = false
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

// MARK: - What a finished session came to

/// Total time, average heart rate and time in each zone, for the log screen to
/// show before you press log and for the logs screen to show afterwards.
///
/// Time in zone is omitted entirely when no heart rate was measured — without a
/// Watch there is nothing to say, and five zeroes would claim a measurement of
/// nothing rather than the absence of one.
struct AerobicSummaryView: View {
    let summary: AerobicSummary
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 2 : 4) {
            HStack(spacing: 12) {
                Label(AerobicDefaults.label(summary.seconds), systemImage: "clock")
                if summary.hasHeartRate {
                    Label("\(summary.averageHeartRate) bpm avg", systemImage: "heart.fill")
                        .foregroundStyle(.red)
                }
            }
            .font(compact ? .caption : .subheadline)
            .monospacedDigit()

            if summary.zoneSeconds.count == HeartRateZones.zoneCount {
                HStack(spacing: compact ? 6 : 10) {
                    ForEach(0..<HeartRateZones.zoneCount, id: \.self) { index in
                        VStack(spacing: 1) {
                            Text("Z\(index + 1)")
                                .font(.system(size: compact ? 8 : 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Text(AerobicDefaults.label(summary.zoneSeconds[index]))
                                .font(.system(size: compact ? 10 : 12))
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - The countdown screen

/// Current heart rate and which of the five zones it is in.
///
/// Nothing at all when there is no reading: without an Apple Watch on the wrist
/// there never will be one, and five empty zone pips would be furniture
/// promising something the app cannot deliver. A dash while waiting for the
/// first reading, because those few seconds are normal and not a failure.
struct HeartRateBar: View {
    let bpm: Int?
    let zone: Int?
    /// Why there is nothing to show, when there is nothing. Silence used to be
    /// the whole message, which left "my Watch is on my wrist and this is
    /// blank" indistinguishable from "this phone has no Watch".
    var status: AerobicCountdown.HeartRateStatus = .waiting

    var body: some View {
        if let bpm {
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "heart.fill").foregroundStyle(.red)
                    Text("\(bpm)").font(.title2).bold().monospacedDigit()
                    Text("bpm").font(.footnote).foregroundStyle(.secondary)
                }
                // Each zone in its own colour, the one you are in at full
                // strength. It used to paint every lit zone red, so zone 1 —
                // the easy one — arrived looking like the hardest.
                HStack(spacing: 4) {
                    ForEach(1...HeartRateZones.zoneCount, id: \.self) { index in
                        Capsule()
                            .fill(ZoneColour.colour(index)
                                .opacity(index == zone ? 1 : ZoneColour.restingOpacity))
                            .frame(height: index == zone ? 14 : 10)
                            .overlay(alignment: .center) {
                                if index == zone {
                                    Text("\(index)")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                    }
                }
                .frame(maxWidth: 240)
                Text(zone.map { "zone \($0)" } ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(spacing: 2) {
                Label(explanation.headline, systemImage: "heart.slash")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let detail = explanation.detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            }
        }
    }

    /// Says what is true rather than guessing at a cause. HealthKit will not
    /// reveal whether a read was refused, so "no readings are arriving" is the
    /// most this can honestly claim — with the likeliest fix named after it.
    private var explanation: (headline: String, detail: String?) {
        switch status {
        case .measuring, .waiting:
            return ("waiting for your heart rate…", nil)
        case .noWatch:
            return ("no heart rate", "Heart rate and zones need an Apple Watch.")
        case .silent:
            return ("no heart rate",
                    "Nothing is arriving from your Watch. Check that the app is allowed to read heart rate in Settings › Health on the Watch.")
        }
    }
}

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

            HeartRateBar(bpm: session.currentHeartRate, zone: session.currentZone,
                         status: session.heartRateStatus)

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
