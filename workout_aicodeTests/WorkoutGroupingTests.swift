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
        let target = ScheduleTarget.of(workoutId: workout, workoutName: "PF A — Gym 1",
                                       groupId: group, groupName: "Push",
                                       groupMembers: [workout], grouped: true)
        #expect(target.name == "Push")
        #expect(target.groupId == group)
        #expect(target.workoutId == workout)
    }

    @MainActor @Test func withGroupingOffTheWorkoutIsScheduledAsItself() {
        let workout = UUID(), group = UUID()
        #expect(WorkoutGrouping.scheduledName(workoutName: "PF A — Gym 1",
                                              groupName: "Push", grouped: false)
                == "PF A — Gym 1")
        let target = ScheduleTarget.of(workoutId: workout, workoutName: "PF A — Gym 1",
                                       groupId: group, groupName: "Push",
                                       groupMembers: [workout], grouped: false)
        #expect(target.name == "PF A — Gym 1")
        #expect(target.groupId == nil)
        #expect(target.memberIds == [workout])
    }

    // A group can go missing — deleted on another device while this one was
    // away. Naming the event after the workout beats naming it after nothing.
    @MainActor @Test func aWorkoutWhoseGroupWentMissingFallsBackToItsOwnName() {
        let workout = UUID()
        #expect(WorkoutGrouping.scheduledName(workoutName: "PF A", groupName: nil,
                                              grouped: true) == "PF A")
        #expect(WorkoutGrouping.scheduledName(workoutName: "PF A", groupName: "",
                                              grouped: true) == "PF A")
        let target = ScheduleTarget.of(workoutId: workout, workoutName: "PF A",
                                       groupId: nil, groupName: nil,
                                       groupMembers: [], grouped: true)
        #expect(target.groupId == nil)
        #expect(target.memberIds == [workout])
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

    // MARK: Editing the groups
    //
    // The iPhone's set-up sheet and the Mac's settings section both run these,
    // so the rules about what they refuse are tested once here rather than
    // tried out twice by hand on two platforms.

    @MainActor @Test func aGroupCannotBeAddedTwiceUnderTheSameName() throws {
        let context = try store()
        #expect(WorkoutGroupEditing.add(named: "Push", among: [], in: context))
        let groups = try context.fetch(FetchDescriptor<WorkoutGroupDef>())
        #expect(groups.count == 1)
        // Capitals and padding are not a distinction anybody meant.
        #expect(!WorkoutGroupEditing.add(named: " push ", among: groups, in: context))
        #expect(!WorkoutGroupEditing.add(named: "   ", among: groups, in: context))
        #expect(try context.fetch(FetchDescriptor<WorkoutGroupDef>()).count == 1)
    }

    @MainActor @Test func addedGroupsKeepTheOrderTheyWereMadeIn() throws {
        let context = try store()
        var groups: [WorkoutGroupDef] = []
        for name in ["Push", "Pull", "Legs"] {
            WorkoutGroupEditing.add(named: name, among: groups, in: context)
            groups = try context.fetch(FetchDescriptor<WorkoutGroupDef>(
                sortBy: [SortDescriptor(\WorkoutGroupDef.sortIndex)]))
        }
        #expect(groups.map(\.name) == ["Push", "Pull", "Legs"])
        #expect(groups.map(\.sortIndex) == [0, 1, 2])
    }

    // Changing only the capitals is a rename somebody meant, so a group is
    // never compared against its own name.
    @MainActor @Test func aGroupMayBeRenamedToADifferentSpellingOfItself() throws {
        let context = try store()
        let push = WorkoutGroupDef(name: "push", sortIndex: 0)
        let pull = WorkoutGroupDef(name: "Pull", sortIndex: 1)
        context.insert(push); context.insert(pull)
        try context.save()

        #expect(WorkoutGroupEditing.rename(push, to: "Push", among: [push, pull], in: context))
        #expect(push.name == "Push")
        #expect(!WorkoutGroupEditing.rename(push, to: "pull", among: [push, pull], in: context))
        #expect(push.name == "Push")
        #expect(!WorkoutGroupEditing.rename(push, to: "", among: [push, pull], in: context))
        #expect(push.name == "Push")
    }

    // The workouts must not be left holding an id that points at nothing —
    // see LogTransfer, which has to undo exactly this after an import.
    @MainActor @Test func deletingAGroupFreesItsWorkoutsAndClosesTheOrder() throws {
        let context = try store()
        let push = WorkoutGroupDef(name: "Push", sortIndex: 0)
        let pull = WorkoutGroupDef(name: "Pull", sortIndex: 1)
        let legs = WorkoutGroupDef(name: "Legs", sortIndex: 2)
        for group in [push, pull, legs] { context.insert(group) }
        let a = WorkoutDef(name: "PF A", groupId: pull.id)
        let b = WorkoutDef(name: "Gold A", groupId: pull.id)
        let c = WorkoutDef(name: "PF B", groupId: legs.id)
        for workout in [a, b, c] { context.insert(workout) }
        try context.save()

        WorkoutGroupEditing.delete([pull], among: [push, pull, legs],
                                   workouts: [a, b, c], in: context)

        #expect(a.groupId == nil)
        #expect(b.groupId == nil)
        #expect(c.groupId == legs.id)
        let left = try context.fetch(FetchDescriptor<WorkoutGroupDef>(
            sortBy: [SortDescriptor(\WorkoutGroupDef.sortIndex)]))
        #expect(left.map(\.name) == ["Push", "Legs"])
        #expect(left.map(\.sortIndex) == [0, 1])
    }

    // A half-typed new workout must not hold the switch hostage.
    @MainActor @Test func aWorkoutWithNoNameIsNotWaitingForAGroup() {
        let named = WorkoutDef(name: "PF A")
        let blank = WorkoutDef(name: "   ")
        #expect(WorkoutGroupEditing.groupable([named, blank]).map(\.name) == ["PF A"])
        #expect(WorkoutGroupEditing.unassigned(among: [named, blank]) == 1)
    }

    @MainActor @Test func aGroupCountsOnlyTheNamedWorkoutsInIt() {
        let push = WorkoutGroupDef(name: "Push", sortIndex: 0)
        let workouts = [WorkoutDef(name: "PF A", groupId: push.id),
                        WorkoutDef(name: "Gold A", groupId: push.id),
                        WorkoutDef(name: " ", groupId: push.id),
                        WorkoutDef(name: "PF B")]
        #expect(WorkoutGroupEditing.count(in: push, among: workouts) == 2)
        #expect(WorkoutGroupEditing.unassigned(among: workouts) == 1)
    }

    // MARK: What the Watch calls it
    //
    // The wrist asks "next X?" at the end of a workout and the phone writes
    // the event; both have to say the same X. Reported from a real workout:
    // the Watch named the workout while the calendar got the group.

    @MainActor @Test func theWatchAsksAboutTheGroupWhenThereIsOne() {
        let grouped = SyncWorkout(id: "a", name: "Biceps curls",
                                  exerciseOrder: [], groupName: "Pull")
        #expect(grouped.scheduledName == "Pull")
    }

    @MainActor @Test func theWatchFallsBackToTheWorkoutsOwnName() {
        let ungrouped = SyncWorkout(id: "a", name: "Biceps curls", exerciseOrder: [])
        #expect(ungrouped.scheduledName == "Biceps curls")
        // A phone from before groups existed sends nothing, and an empty
        // string is no more of a name than nil is.
        let blank = SyncWorkout(id: "a", name: "Biceps curls",
                                exerciseOrder: [], groupName: "")
        #expect(blank.scheduledName == "Biceps curls")
    }
}
