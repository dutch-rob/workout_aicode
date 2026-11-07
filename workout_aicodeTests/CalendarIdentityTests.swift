import Testing
import Foundation
@testable import workout_aicode

// MARK: - Which events belong to which workout
//
// The whole point of putting two ids on an event is that the grouping switch
// can be moved afterwards. These tests are the switch being moved: events
// written under one rule, found again under the other.
//
// Nothing here opens a calendar. `ScheduleTarget` and `WorkoutEventTag` are
// plain values on purpose — see CalendarIdentity.swift — so the decision can
// be checked without EventKit and without a real event in anybody's diary.

@Suite struct CalendarIdentityTests {

    // MARK: The mark on the event

    @Test func bothIdsSurviveTheTripThroughAnEventsURL() {
        let workout = UUID(), group = UUID()
        let written = WorkoutEventTag(workoutId: workout, groupId: group)
        let url = written.url
        #expect(url?.scheme == WorkoutEventTag.scheme)
        #expect(WorkoutEventTag(url: url) == written)
    }

    @Test func anUngroupedEventCarriesNoGroupInItsURL() {
        let workout = UUID()
        let url = WorkoutEventTag(workoutId: workout, groupId: nil).url
        #expect(url?.query == nil)
        #expect(url?.absoluteString == "setsrepswheels://workout/\(workout.uuidString)")
    }

    // Every event written before this change, and every ungrouped one written
    // after it, carries one id and does not say which kind it is. Read as
    // both, so a workout claims it by its workout id and a group by its group
    // id — and since both are UUIDs, neither can claim the other's.
    @Test func anEventWithOneIdIsReadAsEitherKind() {
        let filed = UUID()
        let tag = WorkoutEventTag(url: URL(string: "setsrepswheels://workout/\(filed.uuidString)"))
        #expect(tag?.workoutId == filed)
        #expect(tag?.groupId == filed)
    }

    @Test func nothingButThisAppsOwnEventsIsRecognised() {
        #expect(WorkoutEventTag(url: nil) == nil)
        // A meeting with a link in it, however the link reads.
        #expect(WorkoutEventTag(url: URL(string: "https://example.com/workout/\(UUID().uuidString)")) == nil)
        // The app's scheme but not the app's id — nothing to file it under.
        #expect(WorkoutEventTag(url: URL(string: "setsrepswheels://workout/leg-day")) == nil)
    }

    // MARK: Moving the switch

    private func group(_ id: UUID, _ members: [UUID], workout: UUID) -> ScheduleTarget {
        ScheduleTarget.of(workoutId: workout, workoutName: "Biceps curls",
                          groupId: id, groupName: "Pull",
                          groupMembers: members, grouped: true)
    }

    private func alone(_ workout: UUID) -> ScheduleTarget {
        ScheduleTarget.of(workoutId: workout, workoutName: "Biceps curls",
                          groupId: nil, groupName: nil,
                          groupMembers: [], grouped: false)
    }

    /// Grouping goes ON over two workouts that each already had their own
    /// events. Finishing either one claims both lots, so they collapse into
    /// one "Pull" instead of a third event appearing beside them.
    @Test func switchingGroupingOnCollapsesWhatTheWorkoutsHadSeparately() {
        let pull = UUID(), biceps = UUID(), hammers = UUID()
        let target = group(pull, [biceps, hammers], workout: biceps)
        #expect(target.name == "Pull")
        #expect(target.claims(WorkoutEventTag(workoutId: biceps, groupId: biceps)))
        #expect(target.claims(WorkoutEventTag(workoutId: hammers, groupId: hammers)))
        // And its own, once there is one.
        #expect(target.claims(WorkoutEventTag(workoutId: hammers, groupId: pull)))
    }

    /// Grouping goes OFF. The "Pull" event in the calendar was produced by the
    /// biceps workout, so that workout finds it again and renames it, rather
    /// than leaving it orphaned with a second event beside it. This is the
    /// case a single id could not do at all.
    @Test func switchingGroupingOffKeepsTheEventTheWorkoutProduced() {
        let pull = UUID(), biceps = UUID(), hammers = UUID()
        let written = group(pull, [biceps, hammers], workout: biceps).tag
        let target = alone(biceps)
        #expect(target.claims(written))
        // The other workout in the old group does not take it over. Its own
        // events are its own, and it did not write this one.
        #expect(!alone(hammers).claims(written))
    }

    @Test func oneWorkoutsEventsAreNeverAnothers() {
        let heavy = UUID(), light = UUID()
        #expect(!alone(heavy).claims(WorkoutEventTag(workoutId: light, groupId: light)))
        // Nor one group's another's, even for the same workout id.
        let push = UUID(), pull = UUID(), shared = UUID()
        #expect(!group(push, [UUID()], workout: shared)
            .claims(WorkoutEventTag(workoutId: UUID(), groupId: pull)))
    }

    @Test func anEventThatIsNotThisAppsIsNotClaimedByAnybody() {
        let target = alone(UUID())
        #expect(!target.claims(eventAt: nil))
        #expect(!target.claims(eventAt: URL(string: "https://example.com/")))
    }

    @Test func whatGetsWrittenIsWhatTheTargetSays() {
        let pull = UUID(), biceps = UUID()
        let target = group(pull, [biceps], workout: biceps)
        #expect(target.tag == WorkoutEventTag(workoutId: biceps, groupId: pull))
        // A target always claims what it just wrote; without this, every
        // reschedule would add a second event beside the first.
        #expect(target.claims(target.tag))
        #expect(alone(biceps).claims(alone(biceps).tag))
    }
}
