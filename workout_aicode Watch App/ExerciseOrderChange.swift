import Foundation

// MARK: - Following an edit made on the phone
//
// The Watch's log screen keeps what it is showing in plain arrays, one entry
// per exercise, in the workout's order: `weights[2]` is the third exercise's
// wheels. That is the right shape for a screen whose whole job is "the third
// one of these", and it is only ever wrong in one way — when the order itself
// changes underneath it.
//
// Which the phone can do at any moment. Edit a workout there and the new
// definitions are pushed straight across, mid-session. Taking the first
// exercise out slid every array up by one: the first remaining exercise
// opened on nothing, the second on the first's weights, the third on the
// second's. Reported from a real workout, and it stayed wrong until the app
// was force-quit, because the arrays were built once when the screen opened.
//
// The answer is not to key everything by id — a screen that pages through
// exercises wants positions — but to re-index when the order moves. Which is
// all this is, and it is here rather than inside the view so that it can be
// tested: index arithmetic that nobody can see is exactly the kind that goes
// quietly wrong.
//
// Ids are taken to appear at most once in an order, which is what the phone
// builds: a workout is a set of exercises there, not a list that can repeat.

enum ExerciseOrderChange {

    /// `old`, re-indexed onto `newOrder`.
    ///
    /// An exercise still in the workout brings its value with it wherever it
    /// has moved to — including a wheel turned but not yet logged. One that
    /// has just been added gets a fresh value. One that has gone takes its
    /// value with it.
    static func carry<Value>(_ old: [Value],
                             from oldOrder: [String],
                             to newOrder: [String],
                             fresh: (String) -> Value) -> [Value] {
        newOrder.map { id in
            guard let was = oldOrder.firstIndex(of: id), old.indices.contains(was) else {
                return fresh(id)
            }
            return old[was]
        }
    }

    /// The same for a set of positions, such as which exercises are logged.
    /// What was logged stays logged; an exercise that has gone stops counting.
    static func carry(_ old: Set<Int>,
                      from oldOrder: [String],
                      to newOrder: [String]) -> Set<Int> {
        let ids = Set(old.compactMap { oldOrder.indices.contains($0) ? oldOrder[$0] : nil })
        return Set(newOrder.indices.filter { ids.contains(newOrder[$0]) })
    }

    /// Where the exercise on screen has ended up.
    ///
    /// If it is the one that was just removed there is nothing to follow, so
    /// the nearest position still there takes its place — which is the next
    /// exercise along, or the last one when the end of the list went.
    static func position(of showing: Int,
                         from oldOrder: [String],
                         to newOrder: [String]) -> Int {
        if oldOrder.indices.contains(showing),
           let now = newOrder.firstIndex(of: oldOrder[showing]) {
            return now
        }
        return min(showing, max(0, newOrder.count - 1))
    }
}
