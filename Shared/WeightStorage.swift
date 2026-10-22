import Foundation
import SwiftData

// MARK: - Reading and writing weights
//
// Every weight in this app is now kept in grams, in fields that sit BESIDE the
// original unit-less ones rather than replacing them (see WorkoutLogSchemaV9).
// Nothing writes the old fields any more; a device still on the old build
// reads its own data unchanged and sees nothing at all for anything newer,
// which is a blank rather than a weight that is wrong by a factor of 2.2.
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
    static let statedUnitKey = "weightsHistoryUnit"

    static var statedUnit: WeightUnit? {
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
        var pending = exercises.filter { $0.lowestWeightGrams == nil }.count

        let logs = (try? context.fetch(FetchDescriptor<WorkoutLog>())) ?? []
        let haveWeights = Set(((try? context.fetch(FetchDescriptor<LogWeights>())) ?? [])
            .map(\.logId))
        // A log with no weights at all is an aerobic one, which never had any.
        pending += logs.filter { !$0.weights.isEmpty && !haveWeights.contains($0.id) }.count
        return pending
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
    /// Idempotent: anything already carrying grams is left alone, so running
    /// twice cannot double-convert. The old fields are not touched.
    @discardableResult
    static func adopt(_ unit: WeightUnit, in context: ModelContext) -> Int {
        var filled = 0

        let exercises = (try? context.fetch(FetchDescriptor<ExerciseDef>())) ?? []
        for exercise in exercises where exercise.lowestWeightGrams == nil {
            exercise.lowestWeightGrams = unit.grams(from: Double(exercise.lowestWeight))
            exercise.highestWeightGrams = unit.grams(from: Double(exercise.highestWeight))
            exercise.weightIncrementGrams = unit.grams(from: Double(exercise.weightIncrement))
            filled += 1
        }

        let logs = (try? context.fetch(FetchDescriptor<WorkoutLog>())) ?? []
        let existing = Set(((try? context.fetch(FetchDescriptor<LogWeights>())) ?? []).map(\.logId))
        for log in logs where !existing.contains(log.id) {
            context.insert(LogWeights(logId: log.id,
                                      grams: log.weights.map { unit.grams(from: Double($0)) }))
            filled += 1
        }

        let assisted = (try? context.fetch(FetchDescriptor<AssistedResult>())) ?? []
        for result in assisted where result.bodyWeightGrams == nil {
            result.bodyWeightGrams = unit.grams(from: result.bodyWeight)
            result.machineSettingsGrams = result.machineSettings.map {
                unit.grams(from: Double($0))
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
        try? context.save()
        return filled
    }
}

// MARK: - What a weight is, wherever it is read

extension ExerciseDef {
    /// The wheel's range in grams, or nil while the history has no unit yet.
    var weightRangeGrams: (lowest: Int, highest: Int, increment: Int)? {
        guard let lowest = lowestWeightGrams,
              let highest = highestWeightGrams,
              let increment = weightIncrementGrams else { return nil }
        return (lowest, max(lowest, highest), max(1, increment))
    }

    /// Writes a range the user chose in their own unit.
    func setWeightRange(lowest: Double, highest: Double, increment: Double,
                        unit: WeightUnit = .current) {
        lowestWeightGrams = unit.grams(from: max(0, lowest))
        highestWeightGrams = unit.grams(from: max(lowest, highest))
        weightIncrementGrams = max(1, unit.grams(from: max(0.25, increment)))
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
        return values.isEmpty ? [range.lowest] : values
    }
}
