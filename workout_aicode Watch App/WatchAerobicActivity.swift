import HealthKit

// MARK: - Which Apple workout to start
//
// A byte-identical copy of this file lives in the Watch App target
// ("workout_aicode Watch App/WatchAerobicActivity.swift"). It is duplicated
// rather than left on the Watch alone so the phone's tests can hold it against
// AerobicActivity.allCases: twenty-nine hand-written cases is exactly the sort
// of list where one gets forgotten, and a forgotten one does not fail — it
// quietly starts a workout called "Other".
//
// The phone stores an activity as a plain string (see AerobicActivity in
// Models.swift) so the database does not depend on HealthKit's numbering. This
// is where that string becomes a workout configuration.
//
// "Indoor" is not an activity type of its own — it is the location type set
// alongside an ordinary one, which is why every case here is indoor and the
// names read as the Apple Workout app's do. Getting this right is what makes a
// finished session show up in Fitness as the thing the user actually did
// rather than as a generic "Other".

enum WatchAerobicActivity {

    static func configuration(for raw: String?) -> HKWorkoutConfiguration {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activityType(for: raw)
        configuration.locationType = .indoor
        return configuration
    }

    /// Unknown or missing falls back to `.other`, which is what HealthKit is
    /// for. A newer phone naming an activity this build has never heard of
    /// should still produce a workout, just an unlabelled one.
    static func activityType(for raw: String?) -> HKWorkoutActivityType {
        switch raw {
        case "indoorWalk":         return .walking
        case "indoorRun":          return .running
        case "indoorCycle":        return .cycling
        case "elliptical":         return .elliptical
        case "rower":              return .rowing
        case "stairStepper":       return .stepTraining
        case "stairs":             return .stairs
        case "handCycling":        return .handCycling
        case "wheelchairWalkPace": return .wheelchairWalkPace
        case "wheelchairRunPace":  return .wheelchairRunPace
        case "hiit":               return .highIntensityIntervalTraining
        case "crossTraining":      return .crossTraining
        case "functionalStrength": return .functionalStrengthTraining
        case "coreTraining":       return .coreTraining
        case "jumpRope":           return .jumpRope
        case "mixedCardio":        return .mixedCardio
        case "kickboxing":         return .kickboxing
        case "dance":              return .cardioDance
        case "socialDance":        return .socialDance
        case "yoga":               return .yoga
        case "pilates":            return .pilates
        case "barre":              return .barre
        case "taiChi":             return .taiChi
        case "mindAndBody":        return .mindAndBody
        case "flexibility":        return .flexibility
        case "cooldown":           return .cooldown
        case "poolSwim":           return .swimming
        case "waterFitness":       return .waterFitness
        case "fitnessGaming":      return .fitnessGaming
        default:                   return .other
        }
    }
}
