import Foundation

// MARK: - The numbers a new exercise starts with
//
// Sets, weight range, increment and rest are the same for most of a person's
// exercises and depend on their gym: a rack of dumbbells going up in 2 kg
// steps, or a machine stack in 5s. Asking once beats correcting every exercise.
//
// This lives in Shared because the Mac is now the likeliest place to *make* an
// exercise — a keyboard beats a wheel for typing numbers — and a Mac that
// created every exercise with the built-in 0…200 in 5s would undo the answer
// the user gave on their phone.
//
// These are read from UserDefaults, which is per-device: the Mac has its own
// answer and the phone has its own. That is a real limitation and the Mac's
// settings screen says so rather than implying the two are one setting.

enum ExerciseDefaultsKey {
    static let sets = "defaultNumberOfSets"
    static let lowest = "defaultLowestWeight"
    static let highest = "defaultHighestWeight"
    static let increment = "defaultWeightIncrement"
    /// Set once the question has been asked, so it is never asked again.
    static let asked = "exerciseDefaultsAsked"
}

enum RestTimerKey {
    /// Master switch. Off for everyone until they turn it on. The Mac never
    /// reads it — nothing there rests between sets — but the key is defined
    /// here with its sibling so the two cannot drift apart.
    static let enabled = "restTimerEnabled"
    /// What a newly created exercise starts with.
    static let defaultSeconds = "restTimerDefaultSeconds"
}

enum ExerciseDefaults {
    /// What the app used before this was configurable, and what the question
    /// itself starts from.
    static let sets = 3
    static let lowest = 0
    static let highest = 200
    static let increment = 5

    static var current: (sets: Int, lowest: Int, highest: Int, increment: Int) {
        let d = UserDefaults.standard
        return (d.object(forKey: ExerciseDefaultsKey.sets) as? Int ?? sets,
                d.object(forKey: ExerciseDefaultsKey.lowest) as? Int ?? lowest,
                d.object(forKey: ExerciseDefaultsKey.highest) as? Int ?? highest,
                d.object(forKey: ExerciseDefaultsKey.increment) as? Int ?? increment)
    }

    // MARK: Rest

    /// Selectable rests: 0:15 to 5:00 in quarter minutes.
    static let restChoices: [Int] = Array(stride(from: 15, through: 300, by: 15))

    /// "1:30", "0:45", "5:00".
    static func restLabel(_ seconds: Int) -> String { minutesSeconds(seconds) }

    /// Whether the rest timer is switched on.
    ///
    /// Takes the store it reads, defaulting to the user's. That is for the
    /// test: UserDefaults.standard belongs to the whole device, so a test that
    /// asserts on it can be broken by somebody switching the rest timer on in
    /// the simulator by hand — which happened twice while this was being
    /// built. Given its own store, the test cannot be poisoned and cannot
    /// poison anything else.
    static func restTimerIsOn(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: RestTimerKey.enabled)
    }

    /// The rest a new exercise is created with — the user's answer to the
    /// first-run question, or the built-in default if they never gave one.
    static var restSeconds: Int {
        UserDefaults.standard.object(forKey: RestTimerKey.defaultSeconds) as? Int
            ?? defaultRestSeconds
    }

    // MARK: Making one

    /// A new exercise, with whatever the user chose.
    static func makeExercise(name: String = "",
                             primary: MuscleGroup? = nil,
                             secondary: [MuscleGroup] = [],
                             libraryKey: String? = nil) -> ExerciseDef {
        let d = current
        return ExerciseDef(name: name,
                           numberOfSeries: d.sets,
                           lowestWeight: d.lowest,
                           highestWeight: d.highest,
                           weightIncrement: d.increment,
                           primaryMuscle: primary,
                           secondaryMuscles: secondary,
                           libraryKey: libraryKey,
                           restSeconds: restSeconds)
    }

    /// Only for someone who has not been asked yet. An existing user updating
    /// the app already has exercises set up the way they want, and a popup
    /// offering to change "the defaults" would read as a threat to them.
    static func shouldAsk(existingExercises: Int) -> Bool {
        !UserDefaults.standard.bool(forKey: ExerciseDefaultsKey.asked)
            && existingExercises == 0
    }

    static func markAsked() {
        UserDefaults.standard.set(true, forKey: ExerciseDefaultsKey.asked)
    }
}
