import Testing
import Foundation
import SwiftData
@testable import workout_aicode

// MARK: - Grouping workouts for scheduling
//
// The group is what goes in somebody's calendar, so the rules about when
// grouping applies and what it is called get tests of their own, away from
// any screen and away from EventKit.

@Suite struct WorkoutGroupingTests {

    // MARK: Switching it on

    @MainActor @Test func groupingWillNotTurnOnWithNoGroups() {
        #expect(!WorkoutGrouping.canEnable(groupCount: 0, unassignedWorkouts: 0))
        #expect(WorkoutGrouping.blocker(groupCount: 0, unassignedWorkouts: 0)
                == "Add at least one group.")
    }

    // Half-assigned is the state worth refusing: the calendar would name some
    // workouts by their group and some by themselves, with nothing on screen
    // saying which you were about to get.
    @MainActor @Test func groupingWillNotTurnOnWhileAWorkoutHasNoGroup() {
        #expect(!WorkoutGrouping.canEnable(groupCount: 2, unassignedWorkouts: 1))
        #expect(WorkoutGrouping.blocker(groupCount: 2, unassignedWorkouts: 1)
                == "1 workout still has no group.")
        #expect(WorkoutGrouping.blocker(groupCount: 2, unassignedWorkouts: 3)
                == "3 workouts still have no group.")
    }

    @MainActor @Test func groupingTurnsOnOnceEverythingIsAssigned() {
        #expect(WorkoutGrouping.canEnable(groupCount: 2, unassignedWorkouts: 0))
        #expect(WorkoutGrouping.blocker(groupCount: 2, unassignedWorkouts: 0) == nil)
    }

    // MARK: What the calendar is told

    @MainActor @Test func aGroupedWorkoutIsScheduledUnderItsGroup() {
        let workout = UUID(), group = UUID()
        #expect(WorkoutGrouping.scheduledName(workoutName: "PF A — Gym 1",
                                              groupName: "Push", grouped: true) == "Push")
        #expect(WorkoutGrouping.scheduledId(workoutId: workout, groupId: group,
                                            grouped: true) == group)
    }

    @MainActor @Test func withGroupingOffTheWorkoutIsScheduledAsItself() {
        let workout = UUID(), group = UUID()
        #expect(WorkoutGrouping.scheduledName(workoutName: "PF A — Gym 1",
                                              groupName: "Push", grouped: false)
                == "PF A — Gym 1")
        #expect(WorkoutGrouping.scheduledId(workoutId: workout, groupId: group,
                                            grouped: false) == workout)
    }

    // A group can go missing — deleted on another device while this one was
    // away. Naming the event after the workout beats naming it after nothing.
    @MainActor @Test func aWorkoutWhoseGroupWentMissingFallsBackToItsOwnName() {
        let workout = UUID()
        #expect(WorkoutGrouping.scheduledName(workoutName: "PF A", groupName: nil,
                                              grouped: true) == "PF A")
        #expect(WorkoutGrouping.scheduledName(workoutName: "PF A", groupName: "",
                                              grouped: true) == "PF A")
        #expect(WorkoutGrouping.scheduledId(workoutId: workout, groupId: nil,
                                            grouped: true) == workout)
    }

    // MARK: Naming

    @MainActor @Test func aGroupNameMustBeSomethingAndMustBeNew() {
        #expect(WorkoutGrouping.nameIsFree("Push", among: ["Pull", "Legs"]))
        #expect(!WorkoutGrouping.nameIsFree("", among: []))
        #expect(!WorkoutGrouping.nameIsFree("   ", among: []))
        #expect(!WorkoutGrouping.nameIsFree("Push", among: ["Push"]))
    }

    // "Push " and "push" in one list is a mistake every time, never a
    // distinction somebody meant.
    @MainActor @Test func aGroupNameIsTakenWhateverItsCaseOrSpacing() {
        #expect(!WorkoutGrouping.nameIsFree("push", among: ["Push"]))
        #expect(!WorkoutGrouping.nameIsFree("  Push  ", among: ["Push"]))
        #expect(!WorkoutGrouping.nameIsFree("PUSH", among: ["push"]))
    }

    // MARK: The store

    @MainActor private func store() throws -> ModelContext {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("groups-\(UUID().uuidString).sqlite")
        let container = try ModelContainer(
            for: Schema(versionedSchema: WorkoutLogSchemaV10.self),
            configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
        return ModelContext(container)
    }

    @MainActor @Test func aWorkoutMadeBeforeGroupsExistedHasNone() throws {
        let context = try store()
        let workout = WorkoutDef(name: "PF A")
        context.insert(workout)
        try context.save()
        #expect(workout.groupId == nil)
    }

    @MainActor @Test func aGroupSurvivesTheExportFile() throws {
        let group = WorkoutGroupDef(name: "Push", sortIndex: 0)
        let workout = WorkoutDef(name: "PF A — Gym 1", groupId: group.id)
        let envelope = ExportEnvelope(
            exportVersion: LogTransfer.currentVersion,
            appIdentifier: "robotex.workout-aicode", appVersion: "1.8", build: "14",
            exportedAt: "2026-11-06T09:00:00Z",
            device: .init(model: "iPhone", system: "iOS", version: "26.0"),
            locale: "en_US", timeZone: "America/Los_Angeles",
            counts: .init(workouts: 1, exercises: 0, logs: 0),
            data: .init(workouts: [workout], exercises: [], logs: [],
                        workoutGroups: [group]))
        let data = try JSONEncoder().encode(envelope)
        let read = try LogTransfer.load(data)
        try LogTransfer.validate(read)
        #expect(read.data.workoutGroups?.count == 1)
        #expect(read.data.workoutGroups?.first?.name == "Push")
        #expect(read.data.workouts.first?.groupId == group.id)
    }

    // Every file written before logJSON.5 is in exactly this shape. It is not
    // damaged — it is from before groups existed.
    @MainActor @Test func aFileFromBeforeGroupsReadsBackWithNone() throws {
        let json = """
        {"exportVersion":"logJSON.4","appIdentifier":"robotex.workout-aicode",
         "appVersion":"1.7","build":"13","exportedAt":"2026-10-25T12:00:00Z",
         "device":{"model":"iPhone","system":"iOS","version":"26.0"},
         "locale":"en_US","timeZone":"America/Los_Angeles",
         "counts":{"workouts":1,"exercises":0,"logs":0},
         "data":{"workouts":[{"id":"\(UUID().uuidString)","name":"PF A",
                              "exerciseOrder":[],"sortIndex":0}],
                 "exercises":[],"logs":[]}}
        """
        let read = try LogTransfer.load(Data(json.utf8))
        try LogTransfer.validate(read)
        #expect(read.data.workoutGroups == nil)
        #expect(read.data.workouts.first?.groupId == nil)
    }

    // An import can carry a workout whose group is not in the file — an older
    // export of a grouped store, or one edited by hand. A group that is not
    // there reads as grouped everywhere and resolves to nothing.
    @MainActor @Test func anImportedWorkoutLosesAGroupThatDidNotComeWithIt() throws {
        let context = try store()
        let missing = UUID()
        let workout = WorkoutDef(name: "PF A", groupId: missing)
        let envelope = ExportEnvelope(
            exportVersion: LogTransfer.currentVersion,
            appIdentifier: "robotex.workout-aicode", appVersion: "1.8", build: "14",
            exportedAt: "2026-11-06T09:00:00Z",
            device: .init(model: "iPhone", system: "iOS", version: "26.0"),
            locale: "en_US", timeZone: "America/Los_Angeles",
            counts: .init(workouts: 1, exercises: 0, logs: 0),
            data: .init(workouts: [workout], exercises: [], logs: [], workoutGroups: nil))
        try LogTransfer.replace(with: envelope, in: context)
        let stored = try context.fetch(FetchDescriptor<WorkoutDef>())
        #expect(stored.count == 1)
        #expect(stored.first?.groupId == nil)
    }

    @MainActor @Test func replacingPutsTheFilesGroupsInPlaceOfTheOnesHere() throws {
        let context = try store()
        let old = WorkoutGroupDef(name: "Old", sortIndex: 0)
        context.insert(old)
        context.insert(WorkoutDef(name: "Was here", groupId: old.id))
        try context.save()

        let group = WorkoutGroupDef(name: "Push", sortIndex: 0)
        let workout = WorkoutDef(name: "PF A", groupId: group.id)
        let envelope = ExportEnvelope(
            exportVersion: LogTransfer.currentVersion,
            appIdentifier: "robotex.workout-aicode", appVersion: "1.8", build: "14",
            exportedAt: "2026-11-06T09:00:00Z",
            device: .init(model: "iPhone", system: "iOS", version: "26.0"),
            locale: "en_US", timeZone: "America/Los_Angeles",
            counts: .init(workouts: 1, exercises: 0, logs: 0),
            data: .init(workouts: [workout], exercises: [], logs: [],
                        workoutGroups: [group]))
        try LogTransfer.replace(with: envelope, in: context)

        let groups = try context.fetch(FetchDescriptor<WorkoutGroupDef>())
        #expect(groups.count == 1)
        #expect(groups.first?.name == "Push")
        let stored = try context.fetch(FetchDescriptor<WorkoutDef>())
        #expect(stored.first?.groupId == group.id)
    }
}
