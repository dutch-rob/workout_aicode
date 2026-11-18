import Testing
import Foundation
import SwiftData
@testable import workout_aicode

// MARK: - The one-row editor's read and write
//
// `LogRowDraft` is what the Mac's "correct this row" panel and the phone's
// sheet both hold while they are open, and the one piece of those two screens
// that is shared. The screens look nothing alike and are each platform's own;
// what must never differ is this — what is read off a log and what writing it
// back does to the weights beside it, to the assisted machine's own number and
// to the trailing empty sets.
//
// Tested against a real store rather than trusted, for the reason the log
// editor's own tests give: the log is the one thing in this app that cannot be
// re-made.

@Suite(.serialized)
struct LogRowDraftTests {

    @MainActor private func store() throws -> ModelContext {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rowdraft-\(UUID().uuidString).sqlite")
        let container = try ModelContainer(
            for: Schema(versionedSchema: WorkoutLogSchemaV9.self),
            configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
        return ModelContext(container)
    }

    private let when = Date(timeIntervalSince1970: 1_000_000)

    // MARK: What comes back is what went in

    @MainActor @Test func readingAndWritingBackChangesNothing() throws {
        let context = try store()
        let unit = WeightUnit.current
        let grams = [unit.grams(from: 40), unit.grams(from: 45), unit.grams(from: 45)]
        let log = WorkoutLog(date: when, workoutId: UUID(), exerciseId: UUID(),
                             weights: [], reps: [11, 10, 8])
        context.insert(log)
        context.insert(LogWeights(logId: log.id, grams: grams))
        try context.save()

        var draft = LogRowDraft.read(log, in: context)
        #expect(draft.grams == grams)
        #expect(draft.reps == [11, 10, 8])

        draft.write(to: log, isAerobic: false, in: context)
        try context.save()

        #expect(LogEditing.grams(for: log, in: context) == grams)
        #expect(log.reps == [11, 10, 8])
    }

    // MARK: A corrected number lands, and only that number

    @MainActor @Test func correctingOneSetLeavesTheOthersAlone() throws {
        let context = try store()
        let unit = WeightUnit.current
        let log = WorkoutLog(date: when, workoutId: UUID(), exerciseId: UUID(),
                             weights: [], reps: [11, 10, 8])
        context.insert(log)
        context.insert(LogWeights(logId: log.id,
                                  grams: [unit.grams(from: 40), unit.grams(from: 45),
                                          unit.grams(from: 45)]))
        try context.save()

        var draft = LogRowDraft.read(log, in: context)
        draft.setRepetitions(7, at: 2)
        draft.setWeight(50, at: 1, in: unit)
        draft.write(to: log, isAerobic: false, in: context)
        try context.save()

        #expect(log.reps == [11, 10, 7])
        #expect(LogEditing.grams(for: log, in: context)
                == [unit.grams(from: 40), unit.grams(from: 50), unit.grams(from: 45)])
    }

    // MARK: Weights and reps that disagree in count
    //
    // Seven logs in the user's own export are like this — a reps wheel turned
    // and a weight wheel left alone, before LoggedSets stopped it happening.
    // The screen that exists to put that right cannot be a screen that shows
    // only half of it, so the short side is filled with noughts and both come
    // back the same length.

    @MainActor @Test func aRowWithMoreRepsThanWeightsOpensWithEverySet() throws {
        let context = try store()
        let unit = WeightUnit.current
        let log = WorkoutLog(date: when, workoutId: UUID(), exerciseId: UUID(),
                             weights: [], reps: [12, 10, 18])
        context.insert(log)
        context.insert(LogWeights(logId: log.id,
                                  grams: [unit.grams(from: 30), unit.grams(from: 35)]))
        try context.save()

        let draft = LogRowDraft.read(log, in: context)
        #expect(draft.reps.count == 3)
        #expect(draft.grams.count == 3)
        #expect(draft.grams[2] == 0)
    }

    // MARK: A set added and left empty is not a set

    @MainActor @Test func anEmptySetAtTheEndIsDroppedOnSave() throws {
        let context = try store()
        let unit = WeightUnit.current
        let log = WorkoutLog(date: when, workoutId: UUID(), exerciseId: UUID(),
                             weights: [], reps: [11, 10])
        context.insert(log)
        context.insert(LogWeights(logId: log.id,
                                  grams: [unit.grams(from: 40), unit.grams(from: 45)]))
        try context.save()

        var draft = LogRowDraft.read(log, in: context)
        draft.addSet()
        // "One more set" opens at the previous set's weight, so emptying it
        // means saying nought to both — which is what somebody who changed
        // their mind would leave behind.
        draft.setWeight(0, at: 2, in: unit)
        draft.setRepetitions(0, at: 2)
        draft.write(to: log, isAerobic: false, in: context)
        try context.save()

        #expect(log.reps == [11, 10])
        #expect(LogEditing.grams(for: log, in: context).count == 2)
    }

    // MARK: An assisted set's machine number follows the weight

    @MainActor @Test func correctingAnAssistedWeightMovesTheMachineSetting() throws {
        let context = try store()
        let unit = WeightUnit.current
        let log = WorkoutLog(date: when, workoutId: UUID(), exerciseId: UUID(),
                             weights: [], reps: [8])
        context.insert(log)
        context.insert(LogWeights(logId: log.id, grams: [unit.grams(from: 52)]))
        context.insert(AssistedResult(logId: log.id, bodyWeight: 0, machineSettings: [],
                                      bodyWeightGrams: unit.grams(from: 82),
                                      machineSettingsGrams: [unit.grams(from: 30)]))
        try context.save()

        var draft = LogRowDraft.read(log, in: context)
        draft.setWeight(55, at: 0, in: unit)
        draft.write(to: log, isAerobic: false, in: context)
        try context.save()

        let result = try #require(LogEditing.assistedResults(forLog: log.id, in: context).first)
        // 82 carried, 55 lifted: the machine was taking 27.
        #expect(result.machineSettingsGrams?.first == unit.grams(from: 82) - unit.grams(from: 55))
    }

    // MARK: A ride's sets are not typed over

    @MainActor @Test func anAerobicRowKeepsItsSetsUntouched() throws {
        let context = try store()
        let log = WorkoutLog(date: when, workoutId: UUID(), exerciseId: UUID(),
                             weights: [], reps: [])
        context.insert(log)
        try context.save()

        var draft = LogRowDraft.read(log, in: context)
        let movedTo = when.addingTimeInterval(3600)
        draft.date = movedTo
        draft.grams = [99_000]
        draft.reps = [99]
        draft.write(to: log, isAerobic: true, in: context)
        try context.save()

        // The date and the workout it belongs to are the editor's to change;
        // what the Watch measured is not.
        #expect(log.date == movedTo)
        #expect(log.reps.isEmpty)
        #expect(LogEditing.grams(for: log, in: context).isEmpty)
    }
}
