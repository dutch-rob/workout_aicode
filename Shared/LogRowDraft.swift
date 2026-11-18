import Foundation
import SwiftData

// MARK: - One logged row, being corrected
//
// What the single-row editor holds while it is open: a copy of one log's
// numbers, read when the screen appears and written back on Save. The log
// itself is not touched in between, which is the whole point — there is no
// snapshot to take, no draft mode to switch on and nothing to ask on the way
// out, because closing the screen leaves the log exactly as it was.
//
// This lives in Shared because the Mac and the phone both offer that screen
// and the two LOOK nothing alike: a 430pt panel with a Grid of pickers on one,
// a Form inside a NavigationStack with a decimal keypad on the other. What
// they must not differ on is the part below — what is read off a log, and what
// writing it back does to the weights beside it, to the assisted machine's own
// number and to the trailing empty sets. A second copy of that on the phone is
// exactly the kind of thing that drifts: see LoggedSets for the last time one
// device had a rule the other did not.
//
// WEIGHTS ARE GRAMS here, as everywhere stored. `weight(_:in:)` and
// `setWeight(_:at:in:)` are the only places the user's unit comes into it, so
// a field can bind straight to them.

struct LogRowDraft {
    var date: Date
    var workoutId: UUID
    var exerciseId: UUID
    /// GRAMS, one per set.
    var grams: [Int]
    var reps: [Int]

    /// Before anything is read. The editor's `@State` needs a value to start
    /// at; `load` replaces it the moment the screen appears.
    static var empty: LogRowDraft {
        LogRowDraft(date: Date(), workoutId: UUID(), exerciseId: UUID(),
                    grams: [], reps: [])
    }

    /// Everything the editor shows, read off the log.
    ///
    /// The two arrays are made the same length, filling with nought whichever
    /// is short: logs exist whose weights and reps disagree in count — seven
    /// of them in the user's own export — and the screen that is there to fix
    /// that cannot be a screen that hides half of it.
    static func read(_ log: WorkoutLog, in context: ModelContext) -> LogRowDraft {
        let stored = LogEditing.grams(for: log, in: context)
        let count = max(stored.count, log.reps.count)
        return LogRowDraft(
            date: log.date,
            workoutId: log.workoutId,
            exerciseId: log.exerciseId,
            grams: (0..<count).map { $0 < stored.count ? stored[$0] : 0 },
            reps: (0..<count).map { $0 < log.reps.count ? log.reps[$0] : 0 })
    }

    /// Writes it back, through `LogEditing` and nothing else.
    ///
    /// `isAerobic` is asked rather than worked out here: a ride has no sets,
    /// and which logs are rides is an `AerobicResult` query that belongs to
    /// the screen. Its sets are left alone entirely — what the Watch measured
    /// is not something to be typed over.
    func write(to log: WorkoutLog, isAerobic: Bool, in context: ModelContext) {
        log.date = date
        log.workoutId = workoutId
        log.exerciseId = exerciseId

        guard !isAerobic else { return }

        LogEditing.extend(log, toSets: grams.count, in: context)
        for i in grams.indices {
            LogEditing.setGrams(grams[i], at: i, for: log, in: context)
            // On an assisted machine the weight here is what was lifted; the
            // machine's own number has to follow it.
            LogEditing.realignAssisted(log: log, set: i, in: context)
            log.reps[i] = i < reps.count ? reps[i] : 0
        }
        // A set with nothing in it at the end of a row is a column the big
        // table would go on offering for ever.
        LogEditing.trimEmptyTrailingSets(log, in: context)
    }

    /// For the set that went unlogged. It opens at the previous set's weight,
    /// which is what the next set usually is, and at no reps, which is the one
    /// number the user has to supply.
    mutating func addSet() {
        grams.append(grams.last ?? 0)
        reps.append(0)
    }

    // MARK: In the user's unit

    func weight(_ i: Int, in unit: WeightUnit) -> Double {
        unit.display(grams: i < grams.count ? grams[i] : 0)
    }

    mutating func setWeight(_ value: Double, at i: Int, in unit: WeightUnit) {
        guard grams.indices.contains(i) else { return }
        grams[i] = unit.grams(from: max(0, value))
    }

    func repetitions(_ i: Int) -> Int {
        i < reps.count ? reps[i] : 0
    }

    mutating func setRepetitions(_ value: Int, at i: Int) {
        guard reps.indices.contains(i) else { return }
        reps[i] = max(0, value)
    }
}
