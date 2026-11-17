import Foundation

// MARK: - What the "log" button actually writes down
//
// A set's weight and its repetitions are two wheels, and the buffer behind them
// only gets an entry for a wheel somebody has actually turned: the number on an
// untouched wheel comes from its binding's getter and is never stored. Sending
// those buffers as they stand therefore writes however many sets were FIDDLED
// WITH rather than however many the exercise has — and because the weight wheel
// and the reps wheel of one set are independent, it can write a different
// number of each.
//
// That is not a tidiness point. Everything downstream reads the two arrays as
// PAIRS. `LogWeights` is built from the weights, so the grams match the weights
// and never the reps. The logs screen colours set i of this session against set
// i of the last one and has to guess when one side of the pair is missing. The
// statistics pair a weight with its reps to estimate a one-rep max.
//
// FOUND IN A REAL LOG. Butterfly, 9 November 2026: the third set's reps wheel
// was turned to 18 and its weight wheel was left alone, so the set went down
// with two weights and three reps — and then seeded the next session's wheels,
// which is how one slip travels. Seven logs in that export are like it.
//
// The phone was given this rule on 23 October 2026 and stopped doing it. The
// Watch was not, which left it the only device that still could. So the rule
// lives here and both of them call it: one answer to "what does the log button
// write", rather than one answer per device that drift apart in exactly the way
// these two did.
//
// It takes a COUNT rather than an exercise because the devices do not share an
// exercise type — `ExerciseDef` on the phone and the Mac, `SyncExercise` on the
// Watch — and how many sets it has is the only thing this needs from either.

nonisolated enum LoggedSets {

    /// One value per set, for every set the exercise has: what the wheels are
    /// SHOWING, which is not the same as what is in the buffer.
    ///
    /// `fallback` is what an untouched wheel reads, and belongs to the caller
    /// because it differs by metric — the bottom of the weight range for a
    /// weight, nought for a repetition.
    ///
    /// Always at least one set, and never more than the exercise defines: a
    /// buffer longer than that is a leftover from when the exercise had more
    /// sets, and logging it would record sets the exercise no longer has.
    static func displayed(_ buffer: [[Int]], at index: Int,
                          sets: Int, default fallback: Int) -> [Int] {
        let count = max(1, sets)
        let row = buffer.indices.contains(index) ? buffer[index] : []
        return (0..<count).map { series in
            series < row.count ? row[series] : fallback
        }
    }

    /// Whether there is a set here at all.
    ///
    /// Nought repetitions is not a set, and a row of them is what "log" on a
    /// screen nobody had touched used to write — which then became what the
    /// wheels opened on next time, for this exercise and for the next device
    /// that synced it.
    ///
    /// Asked of the repetitions only, never of the weight: nought on the
    /// wheel is a real answer on an assisted machine, and exercises done at
    /// body weight exist.
    static func hasRepetitions(_ reps: [Int]) -> Bool {
        reps.contains { $0 > 0 }
    }
}
