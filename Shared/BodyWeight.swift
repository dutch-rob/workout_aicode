import Foundation

/// Where the app gets your body weight.
///
/// Only needed by machines that take weight OFF you — an assisted chin-up or
/// dip — where what you lifted is your body weight minus what the machine was
/// carrying. See `ExerciseDef.subtractsFromBodyWeight`.
///
/// **In whatever unit your weights are in.** This app has never had a unit:
/// the wheels hold numbers, and whether they mean kilograms or pounds is
/// between the user and their gym. A body weight in kilograms against a
/// machine set in pounds produces nonsense — the first version of this read
/// Health in kilograms and did exactly that, and the subtraction went
/// negative, which showed up as a logged weight of zero.
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
    static let manualKey = "bodyWeightManual"
    /// The last reading taken from Health, in the user's own Health unit.
    ///
    /// Kept so that logging a set never waits on HealthKit, and so that a set
    /// can still be logged in a basement with no recent weigh-in.
    static let healthCacheKey = "bodyWeightHealth"

    static var source: BodyWeightSource {
        BodyWeightSource(rawValue: UserDefaults.standard.string(forKey: sourceKey) ?? "")
            ?? .health
    }

    /// Zero when it has never been set. There is deliberately no default: a
    /// made-up body weight is worse than none, because it produces a plausible
    /// wrong number instead of an obvious missing one.
    static var manual: Double {
        max(0, UserDefaults.standard.double(forKey: manualKey))
    }

    static var health: Double? {
        let stored = UserDefaults.standard.double(forKey: healthCacheKey)
        return stored > 0 ? stored : nil
    }

    /// What the app believes you weigh, or 0 when it does not know.
    static var current: Double {
        switch source {
        case .health: return health ?? manual
        case .manual: return manual
        }
    }

    static var isKnown: Bool { current > 0 }

    /// Whether a body weight is known AND bigger than what the machine is set
    /// to carry. A machine carrying more than the user weighs means one of the
    /// two numbers is in the wrong unit, or the body weight was never set —
    /// either way the subtraction is meaningless and must not be logged as if
    /// it were a set lifted at zero.
    static func canCompute(machineSetting: Int) -> Bool {
        isKnown && current > Double(machineSetting)
    }

    /// What was actually lifted on an assisted machine: your weight, less what
    /// the machine carried. Never negative.
    static func lifted(bodyWeight: Double, machineSetting: Int) -> Int {
        max(0, Int((bodyWeight - Double(machineSetting)).rounded()))
    }
}
