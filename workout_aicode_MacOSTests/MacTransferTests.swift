import Testing
import Foundation
import SwiftData
@testable import workout_aicode_MacOS

// MARK: - What the Mac writes, and the order it keeps things in
//
// Both of these are rules the Mac shares with the phone, and both were
// separate code until they disagreed. The export format was written out in
// three places; the numbering of the workout list in two. Tested from here
// because this is the end that had the copy.

@MainActor
@Suite
struct MacTransferTests {

    private func store() throws -> ModelContext {
        let container = try ModelContainer(
            for: WorkoutDef.self, ExerciseDef.self, WorkoutLog.self,
            AerobicResult.self, AssistedResult.self, LogWeights.self, DraftSession.self,
            WorkoutGroupDef.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    private var mac: ExportEnvelope.DeviceInfo {
        ExportEnvelope.DeviceInfo(model: "Mac", system: "macOS", version: "26.5")
    }

    @Test func anExportSaysWhatFormatItIsInRatherThanALiteral() throws {
        let envelope = LogTransfer.envelope(workouts: [], exercises: [], logs: [],
                                            device: mac)

        #expect(envelope.exportVersion == LogTransfer.currentVersion)
        #expect(envelope.device.system == "macOS")
        #expect(!envelope.exportedAt.isEmpty)
    }

    /// `validate` compares the counts against the data, so an envelope built
    /// anywhere must count what it actually carries.
    @Test func theCountsAgreeWithWhatIsInTheFile() throws {
        let context = try store()
        let chest = ExerciseDef(name: "Chest press")
        let upper = WorkoutDef(name: "Upper body")
        context.insert(chest)
        context.insert(upper)
        let log = WorkoutLog(workoutId: upper.id, exerciseId: chest.id,
                             weights: [40, 45], reps: [12, 10])
        context.insert(log)

        let envelope = LogTransfer.envelope(workouts: [upper], exercises: [chest],
                                            logs: [log], device: mac)

        #expect(envelope.counts.workouts == 1)
        #expect(envelope.counts.exercises == 1)
        #expect(envelope.counts.logs == 1)
        // Would throw if they disagreed.
        try LogTransfer.validate(envelope)
    }

    /// The round trip the two apps actually make: the Mac writes a file and
    /// something reads it back. Encoding is shared so that a file leaving one
    /// app is never refused by the other.
    @Test func aFileTheMacWritesIsAFileTheAppsCanRead() throws {
        let context = try store()
        let row = ExerciseDef(name: "Seated row")
        let pull = WorkoutDef(name: "Pull day")
        context.insert(row)
        context.insert(pull)

        let data = try LogTransfer.encoded(
            LogTransfer.envelope(workouts: [pull], exercises: [row], logs: [],
                                 device: mac))
        let back = try LogTransfer.load(data)

        try LogTransfer.validate(back)
        #expect(back.data.workouts.map(\.name) == ["Pull day"])
        #expect(back.data.exercises.map(\.name) == ["Seated row"])
    }

    @Test func aSpreadsheetSaysWhatUnitItsNumbersAreIn() throws {
        let context = try store()
        let press = ExerciseDef(name: "Chest press")
        let upper = WorkoutDef(name: "Upper body")
        context.insert(press)
        context.insert(upper)
        let log = WorkoutLog(workoutId: upper.id, exerciseId: press.id,
                             weights: [], reps: [12])
        context.insert(log)

        let text = LogTransfer.tsv(logs: [log], workouts: [upper], exercises: [press],
                                   weightsByLog: [log.id: [20_000]], unit: .kilograms)
        let lines = text.split(separator: "\n")

        #expect(lines.first?.contains("unit") == true)
        #expect(lines.count == 2)
        #expect(lines[1].contains("kg"))
        #expect(lines[1].contains("Chest press"))
    }

    /// A name with a tab in it would otherwise split one column into two, and
    /// every column after it would be one to the right.
    @Test func aNameWithATabInItDoesNotBreakTheColumns() throws {
        let context = try store()
        let odd = ExerciseDef(name: "Row\there")
        let day = WorkoutDef(name: "Pull day")
        context.insert(odd)
        context.insert(day)
        let log = WorkoutLog(workoutId: day.id, exerciseId: odd.id,
                             weights: [], reps: [8])
        context.insert(log)

        let text = LogTransfer.tsv(logs: [log], workouts: [day], exercises: [odd],
                                   weightsByLog: [:], unit: .kilograms)
        let row = try #require(text.split(separator: "\n").last)

        #expect(row.contains("\"Row\there\""))
    }
}

// MARK: -

@MainActor
@Suite
struct MacWorkoutOrderTests {

    /// SwiftUI's `toOffset` counts the list as it was BEFORE the dragged rows
    /// were lifted out, which is one more than where they land when dragging
    /// downwards. Getting this wrong puts a row one short of where it was
    /// dropped, and it is the sort of thing that reads as correct.
    @Test func draggingDownLandsWhereItWasDropped() {
        let list = ["a", "b", "c", "d"]

        #expect(WorkoutOrder.moved(list, from: IndexSet(integer: 0), to: 2) == ["b", "a", "c", "d"])
        #expect(WorkoutOrder.moved(list, from: IndexSet(integer: 0), to: 4) == ["b", "c", "d", "a"])
    }

    @Test func draggingUpLandsWhereItWasDropped() {
        let list = ["a", "b", "c", "d"]

        #expect(WorkoutOrder.moved(list, from: IndexSet(integer: 3), to: 0) == ["d", "a", "b", "c"])
        #expect(WorkoutOrder.moved(list, from: IndexSet(integer: 2), to: 1) == ["a", "c", "b", "d"])
    }

    @Test func theNumbersAreThePositionsWithNoGaps() throws {
        let container = try ModelContainer(
            for: WorkoutDef.self, ExerciseDef.self, WorkoutLog.self,
            AerobicResult.self, AssistedResult.self, LogWeights.self, DraftSession.self,
            WorkoutGroupDef.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)

        let workouts = ["Legs", "Upper body", "Pull day"].map { name -> WorkoutDef in
            let workout = WorkoutDef(name: name)
            workout.sortIndex = 99
            context.insert(workout)
            return workout
        }

        let dragged = WorkoutOrder.moved(workouts, from: IndexSet(integer: 2), to: 0)
        WorkoutOrder.renumber(dragged)

        #expect(dragged.map(\.sortIndex) == [0, 1, 2])
        #expect(dragged.map(\.name) == ["Pull day", "Legs", "Upper body"])
    }
}
