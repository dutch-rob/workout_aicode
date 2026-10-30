import Foundation

// MARK: - Following an edit made while the workout is open
//
// Both log screens keep what they are showing in plain arrays, one entry per
// exercise, in the workout's order: `weights[2]` is the third exercise's
// wheels. That is the right shape for a screen whose whole job is "the third
// one of these", and it is only ever wrong in one way — when the order itself
// changes underneath it.
//
// Which can happen at any moment, on either device. Edit a workout on the
// phone and the new definitions are pushed straight to the Watch, mid-session.
// Edit it on the Mac, or delete an exercise from the library, and iCloud
// brings it to the phone the same way. Taking the first exercise out slid
// every array up by one: the first remaining exercise opened on nothing, the
// second on the first's weights, the third on the second's. Reported from a
// real workout on the Watch, and it stayed wrong until the app was force-quit,
// because the arrays were built once when the screen opened. The phone's log
// screen has the same shape and was open to the same thing.
//
// The answer is not to key everything by id — a screen that pages through
// exercises wants positions — but to re-index when the order moves. Which is
// all this is, and it is here rather than inside the views so that it can be
// tested, and so that both ends follow the same rules: index arithmetic that
// nobody can see is exactly the kind that goes quietly wrong.
//
// Generic over the id because the two ends name exercises differently: the
// Watch is handed Strings over the wire, the phone has the UUIDs themselves.
//
// Ids are taken to appear at most once in an order, which is what both build:
// a workout is a set of exercises, not a list that can repeat.

enum ExerciseOrderChange {

    /// `old`, re-indexed onto `newOrder`.
    ///
    /// An exercise still in the workout brings its value with it wherever it
    /// has moved to — including a wheel turned but not yet logged. One that
    /// has just been added gets a fresh value. One that has gone takes its
    /// value with it.
    static func carry<Value, ID: Hashable>(_ old: [Value],
                                           from oldOrder: [ID],
                                           to newOrder: [ID],
                                           fresh: (ID) -> Value) -> [Value] {
        newOrder.map { id in
            guard let was = oldOrder.firstIndex(of: id), old.indices.contains(was) else {
                return fresh(id)
            }
            return old[was]
        }
    }

    /// The same for a set of positions, such as which exercises are logged.
    /// What was logged stays logged; an exercise that has gone stops counting.
    static func carry<ID: Hashable>(_ old: Set<Int>,
                                    from oldOrder: [ID],
                                    to newOrder: [ID]) -> Set<Int> {
        let ids = Set(old.compactMap { oldOrder.indices.contains($0) ? oldOrder[$0] : nil })
        return Set(newOrder.indices.filter { ids.contains(newOrder[$0]) })
    }

    /// Where the exercise on screen has ended up.
    ///
    /// If it is the one that was just removed there is nothing to follow, so
    /// the nearest position still there takes its place — which is the next
    /// exercise along, or the last one when the end of the list went.
    static func position<ID: Hashable>(of showing: Int,
                                       from oldOrder: [ID],
                                       to newOrder: [ID]) -> Int {
        if oldOrder.indices.contains(showing),
           let now = newOrder.firstIndex(of: oldOrder[showing]) {
            return now
        }
        return min(showing, max(0, newOrder.count - 1))
    }
}
