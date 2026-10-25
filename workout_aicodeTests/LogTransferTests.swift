import Testing
import Foundation
import SwiftData
@testable import workout_aicode

// MARK: - The transfer file
//
// The logs are the one thing in this app that cannot be re-made, and import is
// the only screen that can destroy all of them at once. So the rules get tests
// of their own, away from any screen.

@Suite(.serialized)
struct LogTransferTests {

    @MainActor private func store() throws -> ModelContext {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("transfer-\(UUID().uuidString).sqlite")
        let container = try ModelContainer(
            for: Schema(versionedSchema: WorkoutLogSchemaV9.self),
            configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
        return ModelContext(container)
    }

    @MainActor private func envelope(workouts: [WorkoutDef] = [],
                                     exercises: [ExerciseDef] = [],
                                     logs: [WorkoutLog] = [],
                                     weights: [LogWeights] = [],
                                     version: String = LogTransfer.currentVersion)
    -> ExportEnvelope {
        ExportEnvelope(
            exportVersion: version, appIdentifier: "robotex.workout-aicode",
            appVersion: "1.7", build: "12", exportedAt: "2026-10-25T12:00:00Z",
            device: .init(model: "Mac", system: "macOS", version: "27.0"),
            locale: "en_US", timeZone: "America/Los_Angeles",
            counts: .init(workouts: workouts.count, exercises: exercises.count,
                          logs: logs.count),
            data: .init(workouts: workouts, exercises: exercises, logs: logs,
                        logWeights: weights.isEmpty ? nil : weights))
    }

    // MARK: Validation

    @MainActor @Test func aFileThatIsNotAnExportIsRefused() {
        let wrong = envelope(version: "something-else")
        #expect(throws: LogTransfer.Failure.self) { try LogTransfer.validate(wrong) }
    }

    @MainActor @Test func aFileWhoseCountsDisagreeWithItselfIsRefused() throws {
        let exercise = ExerciseDef(name: "Bench")
        var broken = envelope(exercises: [exercise])
        // Say there are five exercises and ship one: the file is damaged, and
        // importing it would quietly lose four.
        broken = ExportEnvelope(
            exportVersion: broken.exportVersion, appIdentifier: broken.appIdentifier,
            appVersion: broken.appVersion, build: broken.build,
            exportedAt: broken.exportedAt, device: broken.device,
            locale: broken.locale, timeZone: broken.timeZone,
            counts: .init(workouts: 0, exercises: 5, logs: 0), data: broken.data)
        #expect(throws: LogTransfer.Failure.self) { try LogTransfer.validate(broken) }
    }

    @MainActor @Test func aFileWithNoAppInformationIsRefused() {
        let anonymous = ExportEnvelope(
            exportVersion: LogTransfer.currentVersion, appIdentifier: "",
            appVersion: "", build: "", exportedAt: "",
            device: .init(model: "", system: "", version: ""),
            locale: "", timeZone: "",
            counts: .init(workouts: 0, exercises: 0, logs: 0),
            data: .init(workouts: [], exercises: [], logs: []))
        #expect(throws: LogTransfer.Failure.self) { try LogTransfer.validate(anonymous) }
    }

    // MARK: Round trip

    @MainActor @Test func whatIsWrittenCanBeReadBack() throws {
        let exercise = ExerciseDef(name: "Bench press")
        let log = WorkoutLog(workoutId: UUID(), exerciseId: exercise.id,
                             weights: [100], reps: [10])
        let out = envelope(exercises: [exercise], logs: [log])
        let data = try JSONEncoder().encode(out)
        let back = try LogTransfer.load(data)
        try LogTransfer.validate(back)
        #expect(back.data.exercises.count == 1)
        #expect(back.data.logs.count == 1)
        #expect(LogTransfer.preview(back).logs == 1)
    }

    // MARK: Merging

    @MainActor @Test func mergeAddsWhatIsMissingAndKeepsWhatIsThere() throws {
        let context = try store()
        let exercise = ExerciseDef(name: "Bench press")
        let workoutId = UUID()
        let mine = WorkoutLog(date: Date(timeIntervalSince1970: 1_700_000_000),
                              workoutId: workoutId, exerciseId: exercise.id,
                              weights: [100], reps: [10])
        context.insert(exercise)
        context.insert(mine)
        try context.save()

        let theirs = WorkoutLog(date: Date(timeIntervalSince1970: 1_700_100_000),
                                workoutId: workoutId, exerciseId: exercise.id,
                                weights: [105], reps: [8])
        let summary = try LogTransfer.merge(
            envelope(exercises: [ExerciseDef(id: exercise.id, name: "Bench press")],
                     logs: [theirs]), into: context)

        #expect(summary.insertedLogs == 1)
        #expect(summary.insertedExercises == 0)
        #expect((try context.fetch(FetchDescriptor<WorkoutLog>())).count == 2)
    }

    @MainActor @Test func aSetAlreadyHereIsNeverOverwritten() throws {
        let context = try store()
        let exerciseId = UUID()
        let workoutId = UUID()
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        let mine = WorkoutLog(date: when, workoutId: workoutId,
                              exerciseId: exerciseId, weights: [100], reps: [10])
        context.insert(mine)
        try context.save()

        // Same date, same workout, same exercise — one set, logged twice on
        // two devices with different numbers. Mine wins, and the disagreement
        // is reported rather than buried.
        let theirs = WorkoutLog(date: when, workoutId: workoutId,
                                exerciseId: exerciseId, weights: [999], reps: [1])
        let summary = try LogTransfer.merge(envelope(logs: [theirs]), into: context)

        #expect(summary.conflicts == 1)
        #expect(summary.insertedLogs == 0)
        let all = try context.fetch(FetchDescriptor<WorkoutLog>())
        #expect(all.count == 1)
        #expect(all[0].weights == [100])
    }

    @MainActor @Test func mergingTheSameFileTwiceChangesNothingTheSecondTime() throws {
        let context = try store()
        let exercise = ExerciseDef(name: "Bench press")
        let log = WorkoutLog(date: Date(timeIntervalSince1970: 1_700_000_000),
                             workoutId: UUID(), exerciseId: exercise.id,
                             weights: [100], reps: [10])
        let file = envelope(exercises: [exercise], logs: [log])

        let first = try LogTransfer.merge(file, into: context)
        #expect(first.insertedLogs == 1)
        let second = try LogTransfer.merge(file, into: context)
        #expect(second.insertedLogs == 0)
        #expect(second.conflicts == 0)
        #expect((try context.fetch(FetchDescriptor<WorkoutLog>())).count == 1)
    }

    // MARK: Replacing

    @MainActor @Test func replaceLeavesNothingOfWhatWasThere() throws {
        let context = try store()
        let old = ExerciseDef(name: "Old exercise")
        let oldLog = WorkoutLog(workoutId: UUID(), exerciseId: old.id,
                                weights: [50], reps: [5])
        context.insert(old)
        context.insert(oldLog)
        context.insert(LogWeights(logId: oldLog.id, grams: [22680]))
        try context.save()

        let new = ExerciseDef(name: "New exercise")
        try LogTransfer.replace(with: envelope(exercises: [new]), in: context)

        let exercises = try context.fetch(FetchDescriptor<ExerciseDef>())
        #expect(exercises.map(\.name) == ["New exercise"])
        #expect((try context.fetch(FetchDescriptor<WorkoutLog>())).isEmpty)
        // The weights hung off a log that is gone; leaving them would let them
        // attach to an imported log that reused the id.
        #expect((try context.fetch(FetchDescriptor<LogWeights>())).isEmpty)
    }

    @MainActor @Test func aDamagedFileChangesNothing() throws {
        let context = try store()
        let mine = ExerciseDef(name: "Mine")
        context.insert(mine)
        try context.save()

        let broken = ExportEnvelope(
            exportVersion: "nonsense", appIdentifier: "x", appVersion: "1", build: "1",
            exportedAt: "", device: .init(model: "", system: "", version: ""),
            locale: "", timeZone: "", counts: .init(workouts: 0, exercises: 0, logs: 0),
            data: .init(workouts: [], exercises: [], logs: []))
        #expect(throws: LogTransfer.Failure.self) {
            try LogTransfer.replace(with: broken, in: context)
        }
        #expect((try context.fetch(FetchDescriptor<ExerciseDef>())).count == 1)
    }

    // MARK: The spreadsheet

    @MainActor @Test func theSpreadsheetSaysWhichUnitItIsIn() throws {
        let exercise = ExerciseDef(name: "Bench press")
        let workout = WorkoutDef(name: "PF A")
        let log = WorkoutLog(workoutId: workout.id, exerciseId: exercise.id,
                             weights: [], reps: [10, 8])
        let grams = [WeightUnit.pounds.grams(from: 130), WeightUnit.pounds.grams(from: 130)]

        let text = LogTransfer.tsv(logs: [log], workouts: [workout], exercises: [exercise],
                                   weightsByLog: [log.id: grams], unit: .pounds)
        let lines = text.split(separator: "\n")
        #expect(lines[0].contains("unit"))
        #expect(lines.count == 3)          // header plus two sets
        #expect(lines[1].contains("130"))
        #expect(lines[1].contains("lb"))
        #expect(lines[1].contains("Bench press"))

        // The same weights read in kilograms, because the file says which.
        let metric = LogTransfer.tsv(logs: [log], workouts: [workout], exercises: [exercise],
                                     weightsByLog: [log.id: grams], unit: .kilograms)
        #expect(metric.split(separator: "\n")[1].contains("kg"))
        #expect(metric.split(separator: "\n")[1].contains("59"))
    }
}
