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
        store.requestAuthorization(toShare: [HKObjectType.workoutType()], read: []) { ok, _ in
            DispatchQueue.main.async { completion?(ok) }
        }
    }

    /// Save a strength-training workout spanning [start, end]. No-op for an
    /// invalid/empty range or when Health is unavailable.
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
