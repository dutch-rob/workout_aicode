import Foundation

// MARK: - Which calendar events belong to which workout
//
// An event the app writes carries BOTH ids it could be filed under:
//
//     setsrepswheels://workout/<workout id>?group=<group id>
//
// The workout id is the one that produced the event — whichever of a group's
// workouts was actually finished that day. The group id is there when
// grouping was on, and absent when it was not.
//
// Both, rather than only the one that was scheduled, because the setting can
// be switched. With a single id, turning grouping off orphaned everything
// written while it was on: the app would look for a workout's id, find an
// event filed under the group instead, match nothing, write a second event,
// and leave the first in the calendar for ever. Nothing would ever claim it
// again, so nothing would ever move it or take it out. The user is left with
// two workouts on the same day and no way to tell the app about it.
//
// Nothing here touches EventKit, so what the app decides an event is for can
// be held still by tests rather than tried out on a real calendar. See
// `WorkoutCalendar` for the part that reads and writes, `WorkoutGrouping` for
// what an event is named, and `WorkoutSchedule` for when it goes.

/// The ids on one event, as the app wrote them.
nonisolated struct WorkoutEventTag: Equatable {

    /// The URL scheme that marks an event as this app's.
    static let scheme = "setsrepswheels"
    /// The query item that carries the group.
    static let groupKey = "group"

    var workoutId: UUID?
    var groupId: UUID?

    init(workoutId: UUID?, groupId: UUID?) {
        self.workoutId = workoutId
        self.groupId = groupId
    }

    /// Reads the ids off an event's URL, or nil for an event that is not this
    /// app's — one the user made by hand, or another app's.
    ///
    /// A URL with no `group` is read as BOTH ids at once: the app wrote one id
    /// and did not say which kind it was. Every event written before this
    /// change is like that, and so is every ungrouped event written after it.
    /// Reading it as both is what makes those two cases the same case — a
    /// workout claims it by its workout id, a group claims it by its group id,
    /// and since the two namespaces are UUIDs, neither claims the other's.
    init?(url: URL?) {
        guard let url, url.scheme == Self.scheme,
              let filed = UUID(uuidString: url.lastPathComponent) else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        let group = items?.first { $0.name == Self.groupKey }?.value
        if let group, let groupId = UUID(uuidString: group) {
            self.init(workoutId: filed, groupId: groupId)
        } else {
            self.init(workoutId: filed, groupId: filed)
        }
    }

    /// What goes on the event. Nil only for a tag with no workout, which the
    /// app never writes.
    var url: URL? {
        guard let workoutId else { return nil }
        var parts = URLComponents()
        parts.scheme = Self.scheme
        parts.host = "workout"
        parts.path = "/\(workoutId.uuidString)"
        if let groupId, groupId != workoutId {
            parts.queryItems = [URLQueryItem(name: Self.groupKey, value: groupId.uuidString)]
        }
        return parts.url
    }
}

/// What one reschedule is for: the name to write, and every id whose events it
/// is entitled to move or take out.
nonisolated struct ScheduleTarget: Equatable {

    /// What the calendar entry is called — the group's name when grouping is
    /// on, the workout's otherwise. `WorkoutGrouping.scheduledName`'s answer.
    let name: String
    /// The workout that was finished.
    let workoutId: UUID
    /// The group it is filed under, or nil when grouping is off or the group
    /// has gone missing.
    let groupId: UUID?
    /// Every workout whose events this target claims: just the one when
    /// ungrouped, the whole group when grouped.
    let memberIds: Set<UUID>

    /// The ids to write on a new event.
    var tag: WorkoutEventTag { WorkoutEventTag(workoutId: workoutId, groupId: groupId) }

    /// Whether an event with these ids is this target's to deal with.
    ///
    /// GROUPED: the group's own id matches, and so does any of its workouts' —
    /// which is what collapses the separate events of "Biceps" and "Hammer
    /// curls" into one "Pull" the first time either is finished after the
    /// switch goes on.
    ///
    /// UNGROUPED: only the exact workout. A "Pull" event written while grouped
    /// stays attached to whichever workout produced it, is found again, and
    /// gets retitled on the next reschedule instead of being left behind.
    /// Somebody alternating a heavy day and a light one still has both in the
    /// calendar, and finishing the heavy one has no business touching the
    /// light one.
    func claims(_ tag: WorkoutEventTag) -> Bool {
        if let groupId, let theirs = tag.groupId, theirs == groupId { return true }
        if let theirs = tag.workoutId, memberIds.contains(theirs) { return true }
        return false
    }

    /// The same question asked of an event's URL. False for anything that is
    /// not this app's.
    func claims(eventAt url: URL?) -> Bool {
        guard let tag = WorkoutEventTag(url: url) else { return false }
        return claims(tag)
    }

    /// What finishing one workout schedules.
    ///
    /// `groupMembers` is every workout in the group, including this one; it is
    /// only consulted when grouping is on, so passing the lot costs nothing
    /// when it is off.
    static func of(workoutId: UUID, workoutName: String,
                   groupId: UUID?, groupName: String?,
                   groupMembers: [UUID], grouped: Bool) -> ScheduleTarget {
        let group = grouped ? groupId : nil
        var members: Set<UUID> = [workoutId]
        if group != nil { members.formUnion(groupMembers) }
        return ScheduleTarget(
            name: WorkoutGrouping.scheduledName(workoutName: workoutName,
                                                groupName: groupName, grouped: grouped),
            workoutId: workoutId, groupId: group, memberIds: members)
    }
}
