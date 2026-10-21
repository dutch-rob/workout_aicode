import Foundation
import HealthKit

/// Your body weight, read from Apple Health.
///
/// Read-only and on demand: the most recent body mass sample, whoever wrote it
/// — a scale, the Health app, another fitness app. It is cached in
/// `BodyWeight.healthCacheKey` so that logging a set never waits on HealthKit
/// and still works when Health has nothing to say.
///
/// Nothing is ever WRITTEN here. The app does not record your weight.
enum HealthBodyWeight {

    private static let store = HKHealthStore()

    private static var bodyMass: HKQuantityType? {
        HKQuantityType.quantityType(forIdentifier: .bodyMass)
    }

    /// Asked for only when the user chooses to take their weight from Health —
    /// never at launch, for the same reason the workout permission is not.
    static func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable(), let bodyMass else { return }
        try? await store.requestAuthorization(toShare: [], read: [bodyMass])
    }

    /// The most recent reading, in kilograms, or nil when there is none or
    /// Health will not say. HealthKit does not report a refused read, so this
    /// cannot tell "no permission" from "never weighed yourself" — and does
    /// not pretend to.
    static func latestKilograms() async -> Double? {
        guard HKHealthStore.isHealthDataAvailable(), let bodyMass else { return nil }
        return await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(sampleType: bodyMass, predicate: nil,
                                      limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                let kg = (samples?.first as? HKQuantitySample)?
                    .quantity.doubleValue(for: .gramUnit(with: .kilo))
                continuation.resume(returning: kg)
            }
            store.execute(query)
        }
    }

    /// Take a reading and keep it. Called when the setting is switched on and
    /// when the app comes to the foreground, so the number used at the machine
    /// is the one from this morning's scale rather than last month's.
    @discardableResult
    static func refresh() async -> Double? {
        guard BodyWeight.source == .health else { return nil }
        guard let kg = await latestKilograms(), kg > 0 else { return nil }
        UserDefaults.standard.set(kg, forKey: BodyWeight.healthCacheKey)
        return kg
    }
}
