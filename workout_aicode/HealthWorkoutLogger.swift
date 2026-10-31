import Foundation
import HealthKit

// MARK: - HealthWorkoutLogger
//
// Saves completed workouts to Apple Health as Traditional Strength Training
// sessions. Only ever WRITES (never reads). Gated by the user's "Save workouts
// to Apple Health" setting; the caller is responsible for checking that flag.
//
// A byte-identical copy lives in the Watch App target so the device that
// finishes a workout can log it, with or without a paired Watch.

final class HealthWorkoutLogger {

    static let shared = HealthWorkoutLogger()
    private let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Ask permission to write workouts. Safe to call repeatedly; the system
    /// only prompts the first time.
    func requestAuthorization(_ completion: ((Bool) -> Void)? = nil) {
        guard isAvailable else { completion?(false); return }
        // Awaited rather than nested: HealthKit answers on a queue of its
        // own, so the caller's completion had to be carried back to the main
        // queue from inside its handler, and a closure the caller handed in is
        // not something Swift will let cross a thread.
        //
        // `ok` meant that the ASK went through, not that permission was given
        // — HealthKit never says that for a type only being written — so a
        // throw is the same false it always was.
        Task { @MainActor in
            let asked = (try? await store.requestAuthorization(
                toShare: [HKObjectType.workoutType()], read: [])) != nil
            completion?(asked)
        }
    }

    /// Save a strength-training workout spanning [start, end]. No-op for an
    /// invalid/empty range or when Health is unavailable.
    /// An aerobic session that no Watch recorded.
    ///
    /// Normally the Watch writes these, as a real workout of the chosen
    /// activity with heart rate in it. Without a Watch nothing was written at
    /// all, so a Watch-less user's ride existed in this app and nowhere else —
    /// not in Fitness, which iPhone has had on its own since iOS 16, and not
    /// towards the Move ring. This is the plain version of the same thing:
    /// the right activity and the right duration, with nothing measured.
    ///
    /// Only called when there is no Watch app. With one, the Watch's own
    /// workout is the record and a second one from here would be a duplicate.
    func saveAerobicWorkout(activityType: HKWorkoutActivityType,
                            start: Date, end: Date) {
        guard isAvailable, end > start else { return }
        let config = HKWorkoutConfiguration()
        config.activityType = activityType
        config.locationType = .indoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        builder.beginCollection(withStart: start) { ok, _ in
            guard ok else { return }
            builder.endCollection(withEnd: end) { ok, _ in
                guard ok else { return }
                builder.finishWorkout { _, _ in }
            }
        }
    }

    func saveStrengthWorkout(start: Date, end: Date) {
        guard isAvailable, end > start else { return }
        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining
        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        builder.beginCollection(withStart: start) { ok, _ in
            guard ok else { return }
            builder.endCollection(withEnd: end) { ok, _ in
                guard ok else { return }
                builder.finishWorkout { _, _ in }
            }
        }
    }
}
