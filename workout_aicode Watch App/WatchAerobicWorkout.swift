import Foundation
import Combine
import HealthKit

// MARK: - The aerobic workout, on the Watch
//
// An HKWorkoutSession is not optional decoration here: it is the only way
// watchOS samples heart rate often enough to be worth showing, and the only
// way this app keeps running once the wrist drops. Without it HealthKit
// delivers a handful of background samples a minute late, which is no use for
// "what is my heart rate right now".
//
// HealthKit does the measuring, not us. HKLiveWorkoutDataSource collects the
// default quantities for the workout's configuration — heart rate, active
// energy, distance where it applies — and the finished session is written to
// Health as a real workout, so it appears in Fitness and closes rings like any
// other. That is worth more than anything this app could compute for itself.
//
// Time in zone IS ours, and only until OS 27 — see HeartRateZones.

@MainActor
final class WatchAerobicWorkout: NSObject, ObservableObject {

    static let shared = WatchAerobicWorkout()
    private override init() { super.init() }

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    /// Most recent heart rate, or nil before the first reading arrives — which
    /// is a normal few seconds at the start of every session, not a fault.
    @Published private(set) var currentHeartRate: Int?
    @Published private(set) var averageHeartRate: Int = 0
    @Published private(set) var maximumHeartRate: Int = 0
    @Published private(set) var isRunning = false
    /// Which zone the current rate falls in, 1...5. Nil only before the first
    /// reading arrives — every actual heart rate is in a zone.
    @Published private(set) var currentZone: Int?
    /// Where inside that zone, 0...1, for the marker under the band.
    @Published private(set) var currentZoneFraction: Double = 0
    /// The exercise this session belongs to, for the screen to name.
    @Published private(set) var exerciseName = ""
    /// When the phone's countdown finishes, so the Watch can show the same one.
    /// Nil when the Watch has not been told — the session still runs, there is
    /// simply no number to count down.
    @Published private(set) var endsAt: Date?
    @Published private(set) var tick = Date()

    var remainingSeconds: Int? {
        guard let endsAt else { return nil }
        return max(0, Int(endsAt.timeIntervalSince(tick).rounded(.up)))
    }

    var remainingLabel: String? {
        guard let seconds = remainingSeconds else { return nil }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// Details that could not travel in a workout configuration, arriving
    /// either live or in the application context the phone left for us.
    func describe(exercise: String, endsAt date: Date?) {
        if !exercise.isEmpty { exerciseName = exercise }
        if let date, date > Date() { endsAt = date }
    }

    private var zones = HeartRateZones()
    private var tally = ZoneTally(zones: HeartRateZones())

    /// What a finished session measured, for the log.
    struct Summary {
        let durationSeconds: Int
        let averageHeartRate: Int
        let maximumHeartRate: Int
        /// Five entries, lowest zone first. Empty when no heart rate arrived.
        let zoneSeconds: [Int]
    }

    // MARK: - Permission

    /// Asked when an aerobic session is about to start, so the prompt arrives
    /// attached to the thing that needs it.
    ///
    /// Read-only apart from the workout itself. A refusal is survivable: the
    /// countdown still runs, and the session is still written to Health — there
    /// is simply no heart rate to show.
    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let toShare: Set = [HKObjectType.workoutType()]
        var toRead: Set<HKObjectType> = [HKObjectType.workoutType()]
        if let heartRate = HKQuantityType.quantityType(forIdentifier: .heartRate) {
            toRead.insert(heartRate)
        }
        if let resting = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) {
            toRead.insert(resting)
        }
        toRead.insert(HKCharacteristicType(.dateOfBirth))
        try? await store.requestAuthorization(toShare: toShare, read: toRead)
    }

    // MARK: - Running

    func start(activityRaw: String?, exercise: String = "") async {
        await start(configuration: WatchAerobicActivity.configuration(for: activityRaw),
                    exercise: exercise)
    }

    /// The phone launched us with this configuration — see WatchAppDelegate.
    func start(configuration: HKWorkoutConfiguration, exercise: String = "") async {
        guard !isRunning, HKHealthStore.isHealthDataAvailable() else { return }
        if !exercise.isEmpty { exerciseName = exercise }
        await requestAuthorization()

        zones = await currentZones()
        tally = ZoneTally(zones: zones)
        currentHeartRate = nil
        currentZone = nil
        averageHeartRate = 0
        maximumHeartRate = 0

        do {
            let session = try HKWorkoutSession(healthStore: store,
                                               configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            // This is the line that makes HealthKit do the collecting.
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store,
                                                         workoutConfiguration: configuration)
            session.delegate = self
            builder.delegate = self

            let started = Date()
            session.startActivity(with: started)
            try await builder.beginCollection(at: started)

            self.session = session
            self.builder = builder
            isRunning = true
            startTicking()
        } catch {
            // A session that will not start is not worth a scene of its own:
            // the countdown carries on and simply has no heart rate in it.
            self.session = nil
            self.builder = nil
            isRunning = false
        }
    }

    /// Ends the session, writes the workout to Health, and reports what it
    /// measured. Returns nil when nothing was running.
    func finish() async -> Summary? {
        guard let session, let builder else { return nil }
        let ended = Date()
        session.end()
        try? await builder.endCollection(at: ended)
        // The workout is saved even when no heart rate ever arrived — the
        // session happened, and Fitness should show it.
        _ = try? await builder.finishWorkout()

        let duration = Int(builder.elapsedTime.rounded())
        let summary = Summary(
            durationSeconds: max(0, duration),
            averageHeartRate: averageHeartRate,
            maximumHeartRate: maximumHeartRate,
            zoneSeconds: tally.totalCountedSeconds > 0 ? tally.seconds : [])

        self.session = nil
        self.builder = nil
        isRunning = false
        currentHeartRate = nil
        currentZone = nil
        endsAt = nil
        stopTicking()
        lastSummary = summary
        return summary
    }

    /// Started here on the Watch rather than by the phone. Runs the same
    /// session, sets its own countdown, and tells the phone so that an open
    /// phone shows the exercise too.
    func startHere(activityRaw: String?, exercise: String, seconds: Int) async {
        guard !isRunning else { return }
        let end = Date().addingTimeInterval(Double(seconds))
        describe(exercise: exercise, endsAt: end)
        await start(activityRaw: activityRaw, exercise: exercise)
        guard isRunning else { return }
        WatchSessionManager.shared.reportAerobicStarted(exercise: exercise, endsAt: end)
    }

    /// What the last finished session measured, for the log message that
    /// follows it. Taken once and cleared, so a second exercise logged without
    /// running one cannot inherit the first one's numbers.
    private var lastSummary: Summary?

    /// True once a session has finished and not yet been logged.
    var hasFinishedSession: Bool { lastSummary != nil }

    func takeLastSummary() -> Summary? {
        defer { lastSummary = nil }
        return lastSummary
    }

    /// Ends the session here and tells the phone, so stopping on either device
    /// stops both. The phone does not send an end back, or the two would keep
    /// ending each other.
    func stopFromWatch() async {
        guard isRunning else { return }
        _ = await finish()
        WatchSessionManager.shared.reportAerobicStopped()
    }

    private var ticker: Timer?

    private func startTicking() {
        stopTicking()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick = Date() }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func stopTicking() {
        ticker?.invalidate()
        ticker = nil
    }

    // MARK: - Zones

    /// The user's own resting rate and age where Health has them, falling back
    /// to defaults rather than refusing to show zones at all.
    private func currentZones() async -> HeartRateZones {
        var resting = HeartRateZones.defaultResting
        var maximum = HeartRateZones.defaultMaximum

        if let type = HKQuantityType.quantityType(forIdentifier: .restingHeartRate),
           let value = await mostRecentQuantity(type) {
            resting = Int(value.doubleValue(for: HKUnit.count().unitDivided(by: .minute())).rounded())
        }
        if let birth = try? store.dateOfBirthComponents(),
           let date = Calendar.current.date(from: birth),
           let age = Calendar.current.dateComponents([.year], from: date, to: Date()).year {
            maximum = HeartRateZones.estimatedMaximum(forAge: age)
        }
        return HeartRateZones(restingHeartRate: resting, maximumHeartRate: maximum)
    }

    private func mostRecentQuantity(_ type: HKQuantityType) async -> HKQuantity? {
        await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(sampleType: type, predicate: nil,
                                      limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                continuation.resume(returning: (samples?.first as? HKQuantitySample)?.quantity)
            }
            store.execute(query)
        }
    }

    fileprivate func absorb(_ statistics: HKStatistics?, at date: Date) {
        guard let statistics,
              statistics.quantityType == HKQuantityType.quantityType(forIdentifier: .heartRate)
        else { return }
        let unit = HKUnit.count().unitDivided(by: .minute())

        if let latest = statistics.mostRecentQuantity()?.doubleValue(for: unit) {
            let bpm = Int(latest.rounded())
            let zone = zones.zone(for: bpm)
            currentHeartRate = bpm
            currentZone = zone
            currentZoneFraction = zones.fraction(forBeatsPerMinute: bpm, inZone: zone)
            tally.add(beatsPerMinute: bpm,
                      at: statistics.mostRecentQuantityDateInterval()?.end ?? date)
            // Straight on to the phone, which is where the countdown the user
            // is looking at usually lives.
            WatchSessionManager.shared.sendHeartRate(bpm, zone: zone)
        }
        if let average = statistics.averageQuantity()?.doubleValue(for: unit) {
            averageHeartRate = Int(average.rounded())
        }
        if let maximum = statistics.maximumQuantity()?.doubleValue(for: unit) {
            maximumHeartRate = Int(maximum.rounded())
        }
    }
}

// MARK: - HealthKit delegates

extension WatchAerobicWorkout: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState,
                                    date: Date) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didFailWithError error: Error) {
        Task { @MainActor in
            // Nothing to announce: the countdown is the thing the user is
            // watching, and it keeps its own time regardless.
            self.isRunning = false
        }
    }
}

extension WatchAerobicWorkout: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                                    didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let now = Date()
        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType else { continue }
            let statistics = workoutBuilder.statistics(for: quantityType)
            Task { @MainActor in self.absorb(statistics, at: now) }
        }
    }
}
