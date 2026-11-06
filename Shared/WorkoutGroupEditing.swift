import Foundation
import SwiftData

// MARK: - Making, renaming and removing workout groups
//
// The mutations behind the group screens, in one place because there are two
// of them: the iPhone's set-up sheet (`WorkoutGroupSetupView`) and the Mac's
// settings section (`MacWorkoutGroups`). The same store, the same rules, and
// no second copy to forget to fix.
//
// Validation lives next door in `WorkoutGrouping` on plain values, so what
// counts as a usable name can be held still by tests. What is here is the part
// that needs a context, and every function refuses rather than saves a state
// the rules do not allow.

enum WorkoutGroupEditing {

    /// Adds a group named `name`, placed last. Returns false, changing
    /// nothing, when the name is blank or already taken.
    @discardableResult
    static func add(named name: String, among groups: [WorkoutGroupDef],
                    in context: ModelContext) -> Bool {
        let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard WorkoutGrouping.nameIsFree(wanted, among: groups.map(\.name)) else { return false }
        context.insert(WorkoutGroupDef(name: wanted, sortIndex: groups.count))
        StoreSave.save(context, doing: "adding a workout group")
        return true
    }

    /// Renames `group`. Returns false, changing nothing, when the new name is
    /// blank or belongs to one of the others — a group keeping its own name is
    /// allowed, so a rename that changes only capitals goes through.
    @discardableResult
    static func rename(_ group: WorkoutGroupDef, to name: String,
                       among groups: [WorkoutGroupDef],
                       in context: ModelContext) -> Bool {
        let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let others = groups.filter { $0.id != group.id }.map(\.name)
        guard WorkoutGrouping.nameIsFree(wanted, among: others) else { return false }
        group.name = wanted
        StoreSave.save(context, doing: "renaming a workout group")
        return true
    }

    /// Removes `doomed`, and renumbers what is left so the order has no holes.
    ///
    /// The workouts in a removed group go back to having none rather than
    /// keeping an id that points at nothing — see `LogTransfer`, which has to
    /// undo exactly this when an import brings a dangling id in.
    static func delete(_ doomed: [WorkoutGroupDef], among groups: [WorkoutGroupDef],
                       workouts: [WorkoutDef], in context: ModelContext) {
        guard !doomed.isEmpty else { return }
        let goingIds = Set(doomed.map(\.id))
        for workout in workouts where workout.groupId.map(goingIds.contains) == true {
            workout.groupId = nil
        }
        for group in doomed { context.delete(group) }
        for (index, group) in groups.filter({ !goingIds.contains($0.id) }).enumerated()
        where group.sortIndex != index {
            group.sortIndex = index
        }
        StoreSave.save(context, doing: "deleting a workout group")
    }

    /// Puts `workout` in `groupId`, or in none when it is nil.
    static func assign(_ workout: WorkoutDef, to groupId: UUID?,
                       in context: ModelContext) {
        workout.groupId = groupId
        StoreSave.save(context, doing: "grouping a workout")
    }

    // MARK: Reading

    /// The workouts a group screen should show: the named ones.
    ///
    /// A blank row is a workout somebody started adding and has not finished,
    /// and demanding a group for it would block the switch on a workout that
    /// does not exist yet.
    static func groupable(_ workouts: [WorkoutDef]) -> [WorkoutDef] {
        workouts.filter {
            !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// How many of `workouts` are in `group`.
    static func count(in group: WorkoutGroupDef, among workouts: [WorkoutDef]) -> Int {
        groupable(workouts).filter { $0.groupId == group.id }.count
    }

    /// How many of `workouts` are in no group at all.
    static func unassigned(among workouts: [WorkoutDef]) -> Int {
        groupable(workouts).filter { $0.groupId == nil }.count
    }
}
