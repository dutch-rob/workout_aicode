import Foundation
import SwiftData

// MARK: - Reading and writing weights
//
// Every weight in this app is now kept in grams, in fields that sit BESIDE the
// original unit-less ones rather than replacing them (see WorkoutLogSchemaV9).
// BOTH are written. The grams are what this build reads; the unit-less numbers
// beside them are for the devices that cannot — the Mac app until its own App
// Store entry updates, a Watch until it next charges, a phone rolled back to
// the shipping version. They are converted by counting steps of the exercise's
// own wheel, in the unit the user stated for their history, so they are the
// numbers that build would have stored itself.
//
// There is one moment of doubt in all this: the numbers somebody logged before
// today. The app cannot know what they meant. So it asks, once, and until it
// has an answer every gram field stays empty and the weights are not shown.

@MainActor
enum WeightHistory {

    /// What the user said their existing numbers were in. Nil until they say.
    ///
    /// Kept apart from the display unit: that one they may change whenever
    /// they like, and changing it must never re-interpret a history that has
    /// already been given a meaning.
    nonisolated static let statedUnitKey = "weightsHistoryUnit"

    /// Not isolated: it reads one string out of UserDefaults, and the models
    /// themselves have to ask — `setWeightRange` writes the unit-less fields
    /// in this unit, and a model is not on the main actor.
    nonisolated static var statedUnit: WeightUnit? {
        UserDefaults.standard.string(forKey: statedUnitKey).flatMap(WeightUnit.init(rawValue:))
    }

    /// Written by the first version of this and no longer read. A device that
    /// has it set was told the question was settled when it was not, which is
    /// precisely the bug — so the new key is a different one, and everybody
    /// gets asked once more.
    static let answeredKey = "weightsHaveAUnit"

    static var isAnswered: Bool { statedUnit != nil }

    /// How much is still waiting for a unit: exercises whose wheel has no
    /// range in grams, and logs whose weights are still only the old
    /// unit-less numbers.
    ///
    /// Asked EVERY time rather than recorded once. The first version of this
    /// settled the question at launch — and a store that is empty at launch is
    /// not the same thing as a user with nothing: on a fresh install the
    /// records arrive from iCloud a moment later, and on a Watch sync they
    /// arrive later still. Everything that landed after that instant kept no
    /// grams at all, which is why wheels came up empty and sets logged as
    /// zero. Nothing about this is a one-off event, so nothing about it is
    /// recorded as one.
    static func pendingCount(in context: ModelContext) -> Int {
        let exercises = (try? context.fetch(FetchDescriptor<ExerciseDef>())) ?? []
        var pending = exercises.filter { $0.weightRangeGrams == nil }.count

        let logs = (try? context.fetch(FetchDescriptor<WorkoutLog>())) ?? []
        let gramsByLog = LogWeightsIndex.byLogId(
            (try? context.fetch(FetchDescriptor<LogWeights>())) ?? [])
        pending += logs.filter { needsConverting($0, grams: gramsByLog[$0.id]) }.count

        let assisted = (try? context.fetch(FetchDescriptor<AssistedResult>())) ?? []
        pending += assisted.filter { needsConverting($0) }.count
        return pending
    }

    /// Whether a log still has to be given a unit.
    ///
    /// Two cases, and the second is the one that was missed. Either there are
    /// no grams beside it at all — the ordinary case, a log from before any of
    /// this existed — or there IS a row and it says nothing, while the old
    /// field beside it says a weight was lifted.
    ///
    /// That second case came from a real phone. The units work ran on it,
    /// wrote zeros, and was rolled back; rolling back the code does not roll
    /// back iCloud, so the zeroed rows stayed in the account and synced down
    /// again afterwards. Everything logged after the rollback had no such row
    /// and converted correctly, which is why the user saw one date onwards
    /// come out right and everything older read zero.
    ///
    /// Asking whether the row EXISTS is therefore not the question. It is the
    /// same mistake `weightRangeGrams` was fixed for, and its comment says it
    /// in one line: zero matters as much as nil.
    private static func needsConverting(_ log: WorkoutLog, grams: [Int]?) -> Bool {
        // A log with no weights at all is an aerobic one, which never had any.
        guard let grams else { return !log.weights.isEmpty }
        guard grams.allSatisfy({ $0 == 0 }) else { return false }
        // Only where there is something to recover. A set genuinely logged at
        // nothing is zero in both fields, and rewriting it would invent a
        // weight the user never lifted.
        return log.weights.contains { $0 != 0 }
    }

    /// The same question for an assisted set's body weight and machine
    /// setting, which were zeroed by the same versions.
    private static func needsConverting(_ result: AssistedResult) -> Bool {
        guard let bodyWeightGrams = result.bodyWeightGrams else { return true }
        if bodyWeightGrams == 0, result.bodyWeight > 0 { return true }
        let settings = result.machineSettingsGrams ?? []
        return settings.allSatisfy { $0 == 0 }
            && result.machineSettings.contains { $0 != 0 }
    }

    /// One old weight, in grams.
    ///
    /// Converted THE WAY ITS WHEEL IS, by counting steps, rather than on its
    /// own. Rounding does not distribute: 130 lb on its own is 58,967g, while
    /// the wheel's twenty-sixth step is 26 × 2,268 = 58,968g. Converting each
    /// number independently therefore left 48 of one real user's 138 logs
    /// holding a weight that was not on its own exercise's wheel — a gram out,
    /// invisible on screen, and wrong in every comparison made afterwards.
    ///
    /// A weight that is NOT a step of its exercise — logged before the range
    /// was changed, say — keeps its own conversion rather than being moved
    /// onto a grid it never belonged to.
    static func grams(fromLegacy weight: Int, of exercise: ExerciseDef?,
                      in unit: WeightUnit) -> Int {
        guard let exercise else { return unit.grams(from: Double(weight)) }
        let low = exercise.lowestWeight
        let step = max(1, exercise.weightIncrement)
        let offset = weight - low
        guard weight >= low, offset % step == 0 else {
            return unit.grams(from: Double(weight))
        }
        // The two ends are numbers the user typed, and the wheel carries both
        // exactly — including a top that is not a whole number of steps from
        // the bottom, which is why `WeightWheel.values` appends it. Counting
        // steps to reach it lands a gram or two away, off the wheel.
        if let range = exercise.weightRangeGrams,
           exercise.legacyRangeIsTheSameWheel(in: unit) {
            if weight == exercise.lowestWeight { return range.lowest }
            if weight == exercise.highestWeight { return range.highest }
            return range.lowest + (offset / step) * range.increment
        }
        return unit.grams(from: Double(low)) + (offset / step) * unit.grams(from: Double(step))
    }

    /// Weights in grams written back as the plain unit-less numbers an older
    /// build reads — the old Mac app, a phone rolled back to the App Store
    /// version, a Watch that has not updated.
    ///
    /// Written on every new log, which is what the comment at the top of this
    /// file once said would NOT happen. Leaving them blank was the safer
    /// choice while the numbers could only be converted one at a time and
    /// might therefore be wrong by a factor of 2.2; counting steps of the
    /// exercise's own wheel in the unit the user stated for their history
    /// makes them right, and a right number beats a blank on a device that
    /// has no other way to show the set at all.
    static func legacyNumbers(for grams: [Int], of exercise: ExerciseDef?,
                              in unit: WeightUnit) -> [Int] {
        guard let exercise else {
            return grams.map { Int(unit.display(grams: $0).rounded()) }
        }
        return grams.map { exercise.legacyWeight(fromGrams: $0, in: unit) }
    }

    /// Fills in anything that arrived since the question was answered.
    ///
    /// Call it whenever the data may have changed. Once the user has stated a
    /// unit, that answer is about their HISTORY, not about this moment, so it
    /// applies just as well to a record that syncs in tomorrow.
    @discardableResult
    static func catchUp(in context: ModelContext) -> Int {
        guard let unit = statedUnit, pendingCount(in: context) > 0 else { return 0 }
        return adopt(unit, in: context)
    }

    /// Whether to put the question to the user: there is something without a
    /// unit, and they have not said what it should be.
    static func shouldAsk(in context: ModelContext) -> Bool {
        statedUnit == nil && pendingCount(in: context) > 0
    }

    /// The user has said which unit their history was in. Fill in the grams
    /// everywhere, and remember the unit as their preference.
    ///
    /// Idempotent: anything already carrying a real weight is left alone, so
    /// running twice cannot double-convert — and `catchUp` runs on every
    /// launch, every foreground and every record that arrives, so it has to
    /// survive running a hundred times. The old fields are not touched.
    @discardableResult
    static func adopt(_ unit: WeightUnit, in context: ModelContext) -> Int {
        var filled = 0

        let exercises = (try? context.fetch(FetchDescriptor<ExerciseDef>())) ?? []
        // `weightRangeGrams == nil` rather than "has no grams": an exercise
        // whose grams were zeroed is repaired from the numbers beside them.
        for exercise in exercises where exercise.weightRangeGrams == nil {
            exercise.lowestWeightGrams = unit.grams(from: Double(exercise.lowestWeight))
            exercise.highestWeightGrams = unit.grams(from: Double(exercise.highestWeight))
            exercise.weightIncrementGrams = unit.grams(from: Double(exercise.weightIncrement))
            filled += 1
        }

        let byId = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let logs = (try? context.fetch(FetchDescriptor<WorkoutLog>())) ?? []
        let rows = Dictionary(
            ((try? context.fetch(FetchDescriptor<LogWeights>())) ?? [])
                .filter { !$0.isDeleted }
                .map { ($0.logId, $0) },
            uniquingKeysWith: { first, _ in first })
        for log in logs {
            let row = rows[log.id]
            guard needsConverting(log, grams: row?.grams) else { continue }
            let exercise = byId[log.exerciseId]
            let converted = log.weights.map { grams(fromLegacy: $0, of: exercise, in: unit) }
            // Overwritten where a zeroed row is already sitting there, rather
            // than inserted beside it: two rows for one log would be worse
            // than the zero.
            if let row { row.grams = converted }
            else { context.insert(LogWeights(logId: log.id, grams: converted)) }
            filled += 1
        }

        let logExercise = Dictionary(logs.map { ($0.id, $0.exerciseId) },
                                     uniquingKeysWith: { first, _ in first })
        let assisted = (try? context.fetch(FetchDescriptor<AssistedResult>())) ?? []
        for result in assisted where needsConverting(result) {
            result.bodyWeightGrams = unit.grams(from: result.bodyWeight)
            result.machineSettingsGrams = result.machineSettings.map {
                grams(fromLegacy: $0, of: byId[logExercise[result.logId] ?? UUID()], in: unit)
            }
            filled += 1
        }

        // The answer about the history, which never changes again...
        UserDefaults.standard.set(unit.rawValue, forKey: statedUnitKey)
        // ...and the unit to show things in, which the user may change at will.
        // Only set the first time, or switching to kilograms and then syncing
        // an old record would read that record as kilograms.
        if UserDefaults.standard.string(forKey: WeightUnit.key) == nil {
            UserDefaults.standard.set(unit.rawValue, forKey: WeightUnit.key)
        }
        StoreSave.save(context)
        return filled
    }
}

// MARK: - What a weight is, wherever it is read

extension ExerciseDef {
    /// The wheel's range in grams, or nil while the history has no unit yet.
    /// Nil when this exercise has no usable range — unset, or ZEROED.
    ///
    /// Zero matters as much as nil here. An edit field showing a placeholder 0
    /// for an unset value writes that 0 back the moment the form commits, and
    /// a stored 0/0/0 is not "no range yet" to anything that only checks for
    /// nil: it is a wheel with one value on it, which logs every set at zero.
    /// That is exactly what happened, so a range has to be POSITIVE to count,
    /// not merely present. The old unit-less numbers are untouched beside it,
    /// so an exercise in this state can always be rebuilt from them.
    var weightRangeGrams: (lowest: Int, highest: Int, increment: Int)? {
        guard let lowest = lowestWeightGrams,
              let highest = highestWeightGrams,
              let increment = weightIncrementGrams,
              increment > 0, highest > 0, highest >= lowest else { return nil }
        return (lowest, highest, increment)
    }

    /// A weight in grams written back as the plain unit-less number an older
    /// build expects.
    ///
    /// By STEPS of this exercise's own wheel wherever it has both ranges, so a
    /// weight that travels out to an older device and back is the same weight
    /// and not a rounding away from it. The unit only comes into it for an
    /// exercise defined on this build, which has no unit-less range to count.
    func legacyWeight(fromGrams grams: Int, in unit: WeightUnit) -> Int {
        guard let range = weightRangeGrams, weightIncrement > 0,
              grams >= range.lowest, legacyRangeIsTheSameWheel(in: unit) else {
            return Int(unit.display(grams: grams).rounded())
        }
        // Both ends exactly, for the reason given in `grams(fromLegacy:)`.
        if grams == range.lowest { return lowestWeight }
        if grams == range.highest { return highestWeight }
        let steps = Int((Double(grams - range.lowest) / Double(range.increment)).rounded())
        return lowestWeight + steps * weightIncrement
    }

    /// Whether the range in grams is simply the unit-less one converted, which
    /// is the usual case, rather than one the user re-typed in another unit.
    ///
    /// It decides how a number from a device that has only the unit-less range
    /// may be read. Where the two describe the same wheel, counting steps puts
    /// the number exactly back on it. Where they do not, the number means a
    /// WEIGHT and not a position, and converting it is the only honest reading:
    /// a wheel re-typed from 0–200 lb to 0–90 kg has a twenty-sixth step of
    /// 65 kg, while the 130 lb that came off the old one is 59.
    func legacyRangeIsTheSameWheel(in unit: WeightUnit) -> Bool {
        guard let range = weightRangeGrams, weightIncrement > 0 else { return false }
        // Each end converts and rounds on its own, so "the same" is within a
        // gram or two, not to the gram.
        let tolerance = 2
        return abs(range.lowest - unit.grams(from: Double(lowestWeight))) <= tolerance
            && abs(range.increment - unit.grams(from: Double(weightIncrement))) <= tolerance
    }

    /// Writes a range the user chose in their own unit.
    ///
    /// The unit-less fields are written too, in the unit the user stated for
    /// their history. Without that an exercise defined on this build keeps the
    /// factory 0–200 by 5 in those fields, and that — not the range the user
    /// typed — is what an older Watch is sent and what the Mac app shows.
    ///
    /// Whole numbers in the stated unit, so they are lossy where the real
    /// range is not: 2.5 kg of increment goes down as 6 lb for a user whose
    /// history is in pounds. They are a fallback and never the source of
    /// truth, and `legacyRangeIsTheSameWheel` notices the difference and stops
    /// anything counting ticks against them.
    func setWeightRange(lowest: Double, highest: Double, increment: Double,
                        unit: WeightUnit = .current) {
        lowestWeightGrams = unit.grams(from: max(0, lowest))
        highestWeightGrams = unit.grams(from: max(lowest, highest))
        weightIncrementGrams = max(1, unit.grams(from: max(0.25, increment)))

        syncLegacyRange(fallbackUnit: unit)
    }

    /// Writes the unit-less fields from the range in grams, so the two
    /// describe the same wheel for anything that can only read the unit-less
    /// ones — the Mac app, a Watch that has not updated, the snapshot the
    /// iCloud toggle copies between stores.
    ///
    /// Call it after ANY change to the gram range. The edit screen writes the
    /// three gram fields one at a time rather than through `setWeightRange`,
    /// and without this an exercise edited there kept whatever unit-less range
    /// it had before — found by reading the store after a real edit, not by
    /// reading the code.
    func syncLegacyRange(fallbackUnit: WeightUnit = .current) {
        // Only from a range that exists. Writing zeros over the unit-less
        // fields while the history has no unit yet would destroy the only
        // numbers `WeightHistory.adopt` has to work from.
        guard let range = weightRangeGrams else { return }
        let unit = WeightHistory.statedUnit ?? fallbackUnit
        lowestWeight = max(0, Int(unit.display(grams: range.lowest).rounded()))
        highestWeight = max(lowestWeight, Int(unit.display(grams: range.highest).rounded()))
        weightIncrement = max(1, Int(unit.display(grams: range.increment).rounded()))
    }
}

/// A log's weights live beside it, so a screen that shows many logs reads them
/// all once and looks them up here rather than fetching per row.
enum LogWeightsIndex {
    static func byLogId(_ all: [LogWeights]) -> [UUID: [Int]] {
        Dictionary(all.filter { !$0.isDeleted }.map { ($0.logId, $0.grams) },
                   uniquingKeysWith: { first, _ in first })
    }
}

/// The wheel's values, in grams, from an exercise's range.
///
/// Built in grams rather than in the display unit so that what is stored is
/// exactly what the wheel offered — converting back from a displayed 130½
/// would land a gram or two away and make every set look like a new weight.
enum WeightWheel {
    /// The wheel value nearest a stored weight.
    ///
    /// A weight that came off this wheel is already one of its values. One
    /// that did not — an exercise whose increment was changed since, a set
    /// logged on a different machine, seeded demo data — has to be put on the
    /// nearest step, or the Picker finds no tag matching its selection and
    /// silently shows the first value instead. That reads as the app having
    /// forgotten what you lifted last time.
    static func snap(_ grams: Int, for exercise: ExerciseDef) -> Int {
        let values = Self.values(for: exercise)
        guard let nearest = values.min(by: {
            abs($0 - grams) < abs($1 - grams)
        }) else { return grams }
        return nearest
    }

    static func values(for exercise: ExerciseDef) -> [Int] {
        guard let range = exercise.weightRangeGrams else { return [] }
        var values: [Int] = []
        var grams = range.lowest
        while grams <= range.highest, values.count < 2000 {
            values.append(grams)
            grams += range.increment
        }
        // The top of the range is a number the user chose, so it belongs on
        // the wheel. Each end converts to grams on its own and rounds on its
        // own, so the steps can stop a gram or two short of the maximum —
        // 20 to 120 by 5 pounds ended at 115, with 120 nowhere to be found.
        if let last = values.last, last < range.highest,
           range.highest - last < range.increment {
            values.append(range.highest)
        }
        return values.isEmpty ? [range.lowest] : values
    }
}
