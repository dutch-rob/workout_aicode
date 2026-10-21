import Foundation

/// Where the app gets your body weight.
///
/// Only needed by machines that take weight OFF you — an assisted chin-up or
/// dip — where what you lifted is your body weight minus what the machine was
/// carrying. See `ExerciseDef.subtractsFromBodyWeight`.
enum BodyWeightSource: String, CaseIterable, Identifiable {
    case health, manual

    var id: String { rawValue }

    var label: String {
        switch self {
        case .health: return "From Apple Health"
        case .manual: return "Set here"
        }
    }
}

enum BodyWeight {
    static let sourceKey = "bodyWeightSource"
    static let manualKey = "bodyWeightManualKg"
    /// The last reading taken from Health.
    ///
    /// Kept so that logging a set never waits on HealthKit, and so that a set
    /// can still be logged in a basement with no recent weigh-in. It is also
    /// what travels to the Watch, which has no body weight of its own.
    static let healthCacheKey = "bodyWeightHealthKg"

    /// Only ever used when nothing else is known. It is deliberately a round
    /// number rather than an average of anybody: a wrong body weight shows up
    /// immediately in the logged weight, which is the point at which the user
    /// goes and sets it.
    static let fallbackKg: Double = 75

    static var source: BodyWeightSource {
        BodyWeightSource(rawValue: UserDefaults.standard.string(forKey: sourceKey) ?? "")
            ?? .health
    }

    static var manualKg: Double {
        let stored = UserDefaults.standard.double(forKey: manualKey)
        return stored > 0 ? stored : fallbackKg
    }

    static var healthKg: Double? {
        let stored = UserDefaults.standard.double(forKey: healthCacheKey)
        return stored > 0 ? stored : nil
    }

    /// What the app believes you weigh, in kilograms.
    ///
    /// Health when that is the choice and a reading has arrived; otherwise the
    /// typed-in value. Never zero: a set logged against a body weight of zero
    /// would read as a weight lifted of minus the machine setting.
    static var currentKg: Double {
        switch source {
        case .health: return healthKg ?? manualKg
        case .manual: return manualKg
        }
    }

    /// What was actually lifted on an assisted machine: your weight, less what
    /// the machine carried. Never negative — a machine set higher than the
    /// user's body weight means they are being lifted, not lifting, and zero
    /// is the honest floor.
    static func liftedKg(bodyWeight: Double, machineSetting: Int) -> Int {
        max(0, Int((bodyWeight - Double(machineSetting)).rounded()))
    }
}
