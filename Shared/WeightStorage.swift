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

    /// Set once the user has said what their existing numbers meant — or
    /// immediately, for somebody with nothing to convert.
    static let answeredKey = "weightsHaveAUnit"

    static var isAnswered: Bool {
        UserDefaults.standard.bool(forKey: answeredKey)
    }

    /// Nothing logged and nothing defined: there is no history to interpret,
    /// so there is nothing to ask about. The unit follows the region and the
    /// user can change it in Settings like any other preference.
    static func isNewUser(in context: ModelContext) -> Bool {
        let exercises = (try? context.fetchCount(FetchDescriptor<ExerciseDef>())) ?? 0
        let logs = (try? context.fetchCount(FetchDescriptor<WorkoutLog>())) ?? 0
        return exercises == 0 && logs == 0
    }

    /// Answers the question for someone who never had to be asked.
    static func settleForNewUser(in context: ModelContext) {
        guard !isAnswered, isNewUser(in: context) else { return }
        UserDefaults.standard.set(true, forKey: answeredKey)
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

        UserDefaults.standard.set(unit.rawValue, forKey: WeightUnit.key)
        UserDefaults.standard.set(true, forKey: answeredKey)
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
