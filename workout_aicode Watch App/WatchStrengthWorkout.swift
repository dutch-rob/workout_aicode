import Foundation
import Combine
import HealthKit

// MARK: - Health access and zones, shared by both sessions
//
// One copy on purpose. The aerobic countdown and the strength workout both
// need permission and both need to know where the zone boundaries fall, and
// two copies of that would eventually be two different answers to "which zone
// am I in". (HeartRateZones.swift itself cannot hold this: it is one of the
// files kept byte-identical with the phone, which has no business asking
// HealthKit from the Watch's store.)

enum WatchHealthAccess {

    static func requestAuthorization(_ store: HKHealthStore) async {
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

    /// The wearer's own zones: their resting rate, and a maximum estimated
    /// from their age. Falls back to the defaults when Health will not say.
    static func zones(from store: HKHealthStore) async -> HeartRateZones {
        var resting = HeartRateZones.defaultResting
        var maximum = HeartRateZones.defaultMaximum

        if let type = HKQuantityType.quantityType(forIdentifier: .restingHeartRate),
           let value = await mostRecentQuantity(type, from: store) {
            resting = Int(value.doubleValue(for: HKUnit.count().unitDivided(by: .minute())).rounded())
        }
        if let birth = try? store.dateOfBirthComponents(),
           let date = Calendar.current.date(from: birth),
           let age = Calendar.current.dateComponents([.year], from: date, to: Date()).year {
            maximum = HeartRateZones.estimatedMaximum(forAge: age)
        }
        // The user's OWN zones first, which is the only way the band can agree
        // with the Workout app: Health returns whichever configuration is
        // active there, the system's automatic ones or boundaries the user set
        // by hand. Everything below this point is the fallback.
        if let preferred = await preferredZones(from: store,
                                                resting: resting, maximum: maximum) {
            return preferred
        }
        // Next best: the four numbers the user copied out of Health by hand on
        // the phone. Tedious to enter and exactly right, which is the better
        // half of that bargain on a Watch too old for watchOS 27.
        let typed = WatchPreferences.zoneBoundaries
        if !typed.isEmpty,
           let manual = HeartRateZones(boundaries: typed,
                                       restingHeartRate: resting,
                                       maximumHeartRate: maximum,
                                       source: .manual) {
            return manual
        }
        return HeartRateZones(restingHeartRate: resting, maximumHeartRate: maximum)
    }

    /// Apple's own zone boundaries, when this OS and this Health database have
    /// them.
    ///
    /// `zones` comes back as the five bands themselves. What this type keeps
    /// is the four thresholds BETWEEN them, which are the minimums of zones
    /// two upwards — zone one has no minimum and the top zone has no maximum,
    /// which is why the thresholds are read from the bottom edges rather than
    /// the top ones.
    static func preferredZones(from store: HKHealthStore,
                               resting: Int, maximum: Int) async -> HeartRateZones? {
        guard #available(watchOS 27.0, iOS 27.0, *),
              let heartRate = HKQuantityType.quantityType(forIdentifier: .heartRate)
        else { return nil }
        guard let configuration =
                try? await store.preferredWorkoutZoneConfiguration(for: heartRate)
        else { return nil }

        let unit = HKUnit.count().unitDivided(by: .minute())
        let thresholds = configuration.zones
            .sorted { $0.index < $1.index }
            .dropFirst()                       // zone 1 has no bottom edge
            .compactMap { $0.minimum?.doubleValue(for: unit) }
            .map { Int($0.rounded()) }

        return HeartRateZones(boundaries: thresholds,
                              restingHeartRate: resting,
                              maximumHeartRate: maximum,
                              source: .healthKit)
    }

    static func mostRecentQuantity(_ type: HKQuantityType,
                                   from store: HKHealthStore) async -> HKQuantity? {
        await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(sampleType: type, predicate: nil,
                                      limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                continuation.resume(returning: (samples?.first as? HKQuantitySample)?.quantity)
            }
            store.execute(query)
        }
    }
}

// MARK: - The whole workout as an Apple workout
//
// Only in `WatchWorkoutMode.appleWorkout`. The weights session runs for as
// long as the workout does, which is what gives heart rate during the sets,
// keeps the app on the wrist, and puts the workout in Fitness.
//
// watchOS runs ONE workout session at a time, and an aerobic exercise in the
// middle of a workout wants its own — of its own activity type, so it lands in
// Fitness as the cardio it was. So the strength session stands aside for it:
// the part done so far is saved, the countdown runs as its own workout, and a
// fresh strength session starts after. A workout with cardio in the middle
// arrives in Health as strength, then cardio, then strength, which is what
// actually happened.

@MainActor
final class WatchStrengthWorkout: NSObject, ObservableObject {

    static let shared = WatchStrengthWorkout()
    private override init() { super.init() }

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var zones = HeartRateZones()

    /// A session is being built right now — see `start`.
    private var starting = false

    @Published private(set) var isRunning = false
    /// 1...5, nil until the first reading arrives — a normal few seconds.
    @Published private(set) var currentZone: Int?
    /// Where inside that zone, 0...1, for the line across the row.
    @Published private(set) var currentZoneFraction: Double = 0

    /// When the WORKOUT began, which is not when this session did: one started
    /// on the phone and carried on at the machine is back-dated so Health gets
    /// the whole thing. Only the heart rate is missing for the earlier part,
    /// and that is unavoidable — nothing was on the wrist to measure it.
    private var workoutStartedAt: Date?
    /// Set while an aerobic exercise has the session, so the strength one knows
    /// to pick up again afterwards rather than treating the gap as the end.
    private var standingAside = false

    private var configuration: HKWorkoutConfiguration {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        return configuration
    }

    // MARK: Running

    /// `workoutStartedAt` is the start of the WORKOUT, not of this session.
    func start(workoutStartedAt start: Date) async {
        // `starting`, because everything between here and `isRunning` being
        // set is an `await` and this is now asked for from more than one place
        // — see `WatchLogExerciseView.startAppleWorkoutIfChosen`. Without it
        // two asks a moment apart would each build a session.
        //
        // `standingAside`, because the way back from an aerobic exercise is
        // `resumeAfterAerobic`, which starts from NOW on purpose. Coming back
        // through here instead would back-date a new session over the cardio
        // minutes that were just written.
        guard !isRunning, !starting, !standingAside,
              !WatchAerobicWorkout.shared.isRunning else { return }
        starting = true
        defer { starting = false }
        await WatchHealthAccess.requestAuthorization(store)
        zones = await WatchHealthAccess.zones(from: store)
        workoutStartedAt = start
        await begin(at: min(start, Date()))
    }

    /// Ends the workout and writes it to Health.
    func finish() async {
        standingAside = false
        workoutStartedAt = nil
        await end()
    }

    /// An aerobic exercise is about to run and needs the session for itself.
    /// What has been done so far is saved as the workout it was.
    func suspendForAerobic() async {
        guard isRunning else { return }
        standingAside = true
        await end()
    }

    /// The countdown is over. A new strength session from here — the earlier
    /// part is already in Health, and double-counting the cardio minutes by
    /// back-dating over them would be worse than two entries.
    func resumeAfterAerobic() async {
        guard standingAside, workoutStartedAt != nil else { return }
        standingAside = false
        guard !WatchAerobicWorkout.shared.isRunning else { return }
        await begin(at: Date())
    }

    private func begin(at start: Date) async {
        do {
            let session = try HKWorkoutSession(healthStore: store,
                                               configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store,
                                                         workoutConfiguration: configuration)
            session.delegate = self
            builder.delegate = self

            session.startActivity(with: start)
            try await builder.beginCollection(at: start)

            self.session = session
            self.builder = builder
            isRunning = true
        } catch {
            // A session that will not start must not take the workout with it:
            // the user carries on logging, with no heart rate and nothing in
            // Fitness. Logging the sets is the thing this app is for.
            self.session = nil
            self.builder = nil
            isRunning = false
        }
    }

    private func end() async {
        guard let session, let builder else { return }
        let ended = Date()
        session.end()
        try? await builder.endCollection(at: ended)
        // Saved even when no heart rate ever arrived: the workout happened.
        _ = try? await builder.finishWorkout()

        self.session = nil
        self.builder = nil
        isRunning = false
        currentZone = nil
        currentZoneFraction = 0
    }

    #if DEBUG
    /// Screenshot/demo only: a zone and a position in it, so the row can be
    /// looked at without a wrist. The simulator has no heart rate.
    func showDemoZone(bpm: Int) {
        let zones = HeartRateZones()
        let zone = zones.zone(for: bpm)
        currentZone = zone
        currentZoneFraction = zones.fraction(forBeatsPerMinute: bpm, inZone: zone)
    }
    #endif

    fileprivate func absorb(_ statistics: HKStatistics?) {
        guard let statistics,
              statistics.quantityType == HKQuantityType.quantityType(forIdentifier: .heartRate),
              let latest = statistics.mostRecentQuantity()?
                  .doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        else { return }
        let bpm = Int(latest.rounded())
        let zone = zones.zone(for: bpm)
        currentZone = zone
        currentZoneFraction = zones.fraction(forBeatsPerMinute: bpm, inZone: zone)
    }
}

// MARK: - HealthKit delegates

extension WatchStrengthWorkout: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState,
                                    date: Date) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didFailWithError error: Error) {
        Task { @MainActor in
            self.session = nil
            self.builder = nil
            self.isRunning = false
            self.currentZone = nil
        }
    }
}

extension WatchStrengthWorkout: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                                    didCollectDataOf collectedTypes: Set<HKSampleType>) {
        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType else { continue }
            let statistics = workoutBuilder.statistics(for: quantityType)
            Task { @MainActor in self.absorb(statistics) }
        }
    }
}
