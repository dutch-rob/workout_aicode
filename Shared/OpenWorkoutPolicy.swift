import Foundation

// MARK: - When is a workout over?
//
// Two questions with one answer, which is why they live together.
//
// The app cannot be told the workout ended if the user never says so: they put
// the phone in a pocket, finish the session, drive home. And iOS will not keep
// a suspended app alive to notice — there is no background mode for "this
// person is at the gym", and asking for one under a false pretext is how apps
// get rejected. So the phone writes down when the workout started and when
// something was last logged, and works the rest out afterwards:
//
//   • more than an hour since the last set → the workout is over, and it ended
//     at that last set, not now. A forgotten workout must not be recorded as
//     seven hours of strength training.
//   • less than an hour → it is still going, so reopening the app should carry
//     on from where it was rather than starting again.
//
// The same hour decides both, and that is deliberate: a session the app is
// willing to resume is exactly a session it has not yet declared finished.

enum OpenWorkoutPolicy {

    /// How long a workout may sit with nothing logged before it counts as over.
    ///
    /// An hour is long enough for a slow set of heavy singles with a chat in
    /// between, and short enough that the workout is closed before it can be
    /// confused with the next one.
    static let idleLimit: TimeInterval = 3600

    /// When a workout left un-ended should be recorded as having finished, or
    /// nil while it is still running.
    ///
    /// The end is the last logged set, never `now`: the user stopped training
    /// when they stopped logging, and the hour it took anyone to notice is not
    /// part of the workout.
    static func endDate(startedAt: Date, lastActivityAt: Date, now: Date) -> Date? {
        guard now.timeIntervalSince(lastActivityAt) > idleLimit else { return nil }
        return closingDate(startedAt: startedAt, lastActivityAt: lastActivityAt)
    }

    /// The end to record for a workout being closed now, whatever the reason —
    /// idle, or superseded by a new one. Nil when nothing was ever logged, so
    /// an empty workout is not written at all.
    static func closingDate(startedAt: Date, lastActivityAt: Date) -> Date? {
        lastActivityAt > startedAt ? lastActivityAt : nil
    }

    /// Whether an interrupted session should be picked up where it was left.
    ///
    /// The app being killed while it sat in a pocket is the ordinary case, not
    /// a failure: iOS reclaims suspended apps, and the user comes back to find
    /// the workout gone. Anything still inside the idle limit is the same
    /// workout and should be continued.
    static func isResumable(lastActivityAt: Date, now: Date) -> Bool {
        let elapsed = now.timeIntervalSince(lastActivityAt)
        // A future date means the clock moved, or the record came from another
        // device that is ahead. Neither is a reason to throw the session away.
        return elapsed <= idleLimit
    }
}
