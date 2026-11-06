import Foundation

// MARK: - Workouts that mean the same session
//
// Somebody who trains at two gyms ends up with two "push" workouts, because
// the machines are not the same. They are one session done two ways, and
// scheduling is the place that cares: the calendar should say "Push", because
// which gym it will be is not known until the day.
//
// So workouts can be put in groups, and when grouping is on it is the GROUP
// that gets scheduled. Everything else — logging, statistics, the order on the
// start screen — is unchanged and does not know groups exist.
//
// The rules are here, on plain values, so they can be held still by tests
// rather than tried out on a real calendar. See `WorkoutSchedule` for the
// arithmetic of when, and `WorkoutCalendar` for the part that writes.

nonisolated enum WorkoutGrouping {

    /// Whether the user has switched grouping on.
    static let enabledKey = "scheduleByWorkoutGroup"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    // MARK: Switching it on

    /// Whether grouping may be switched on yet.
    ///
    /// It may not, until every workout is in a group. A half-assigned state
    /// would mean the calendar sometimes says the group and sometimes the
    /// workout, with nothing on screen to say which you are going to get —
    /// and the whole point of the setting is knowing what will be written.
    ///
    /// This is why the switch opens a sheet instead of simply turning on.
    static func canEnable(groupCount: Int, unassignedWorkouts: Int) -> Bool {
        groupCount > 0 && unassignedWorkouts == 0
    }

    /// What still has to be done before the switch will take, as a sentence
    /// for the sheet. Nil when nothing does.
    static func blocker(groupCount: Int, unassignedWorkouts: Int) -> String? {
        if groupCount == 0 {
            return "Add at least one group."
        }
        if unassignedWorkouts > 0 {
            return unassignedWorkouts == 1
                ? "1 workout still has no group."
                : "\(unassignedWorkouts) workouts still have no group."
        }
        return nil
    }

    // MARK: What gets scheduled

    /// The name that goes in the calendar.
    ///
    /// The group when there is one, and the workout otherwise. "Otherwise"
    /// covers more than grouping being off: a workout can lose its group if
    /// the group is deleted on another device while this one was away, and a
    /// calendar entry named after the workout is a far better answer there
    /// than one named after nothing.
    static func scheduledName(workoutName: String, groupName: String?,
                              grouped: Bool) -> String {
        guard grouped, let groupName, !groupName.isEmpty else { return workoutName }
        return groupName
    }

    /// The id the calendar entry is filed under — the group's when the group
    /// is what was scheduled, so that looking up "what is this event for"
    /// gives the same answer as the name does.
    static func scheduledId(workoutId: UUID, groupId: UUID?, grouped: Bool) -> UUID {
        guard grouped, let groupId else { return workoutId }
        return groupId
    }

    // MARK: Naming

    /// Whether a group name may be used: not blank, and not already taken.
    ///
    /// Case- and space-insensitive, because "Push " and "push" in the same
    /// list are a mistake every time, not a distinction anybody meant.
    static func nameIsFree(_ name: String, among existing: [String]) -> Bool {
        let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wanted.isEmpty else { return false }
        return !existing.contains {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(wanted) == .orderedSame
        }
    }
}
