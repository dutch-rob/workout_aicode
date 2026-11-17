import Testing
import Foundation
@testable import workout_aicode_Watch_App_

// MARK: - What the Watch's log button writes down
//
// These exist because of a real log. Butterfly, 9 November 2026: three sets
// defined, the third set's reps wheel turned to 18, its weight wheel left
// alone — and the set went down with TWO weights and THREE reps, because the
// Watch sent the buffers as they stood and the buffers only grow as far as a
// wheel that was actually turned.
//
// Every reader of a log takes the two arrays as pairs, so a pair with one half
// missing is a set nobody can read: the grams stored beside the log follow the
// weights, the logs screen colours set i against set i of the session before,
// and the one-rep-max estimate needs both numbers of the same set. Worse, the
// next session's wheels are seeded from the last log, so one slip is carried
// forward until somebody happens to turn the wheel that was skipped.
//
// The phone stopped doing this on 23 October 2026 and the Watch was not
// changed with it, which left the Watch the only device that still could. The
// rule now lives in Shared/LoggedSets and both call it; these hold it still
// from the side that got it wrong.

@Suite
struct WatchLoggedSetsTests {

    // MARK: The log that started it

    /// Butterfly's own numbers: the weight wheel of the third set untouched.
    @Test func theSetThatWentDownAsTwoWeightsAndThreeReps() {
        let weights = [[45, 45]]
        let reps = [[15, 15, 18]]

        let outWeights = LoggedSets.displayed(weights, at: 0, sets: 3, default: 0)
        let outReps = LoggedSets.displayed(reps, at: 0, sets: 3, default: 0)

        #expect(outWeights == [45, 45, 0])
        #expect(outReps == [15, 15, 18])
        #expect(outWeights.count == outReps.count)
    }

    /// The property that matters, whichever wheel was the one left alone.
    ///
    /// Every pair here is a shape the old code could produce, including the
    /// six others like Butterfly in the same export.
    @Test func theTwoMetricsAlwaysComeOutTheSameLength() {
        let cases: [(weights: [Int], reps: [Int])] = [
            ([45, 45], [15, 15, 18]),       // the weight skipped, as Butterfly was
            ([4, 4], [20]),                 // the reps skipped
            ([20], [20, 20]),
            ([], []),                       // nothing touched at all
            ([], [2]),
            ([1, 2, 3, 4, 5], [1]),         // a buffer left over from more sets
        ]
        for (weights, reps) in cases {
            for sets in 1...4 {
                let w = LoggedSets.displayed([weights], at: 0, sets: sets, default: 7)
                let r = LoggedSets.displayed([reps], at: 0, sets: sets, default: 0)
                #expect(w.count == r.count,
                        "\(weights) / \(reps) over \(sets) sets")
                #expect(w.count == sets)
            }
        }
    }

    // MARK: What an untouched wheel writes

    @Test func anUntouchedWheelIsWrittenAsTheNumberItShows() {
        // The weight wheel's default is the bottom of its range, the reps
        // wheel's is nought — which is why the fallback is the caller's.
        #expect(LoggedSets.displayed([[]], at: 0, sets: 3, default: 2268) == [2268, 2268, 2268])
        #expect(LoggedSets.displayed([[]], at: 0, sets: 3, default: 0) == [0, 0, 0])
    }

    @Test func aTurnedWheelKeepsItsOwnNumber() {
        #expect(LoggedSets.displayed([[0, 50]], at: 0, sets: 3, default: 9) == [0, 50, 9])
    }

    // MARK: Shape

    @Test func thereIsAlwaysAtLeastOneSet() {
        #expect(LoggedSets.displayed([[]], at: 0, sets: 0, default: 1) == [1])
        #expect(LoggedSets.displayed([[]], at: 0, sets: -3, default: 1) == [1])
    }

    /// An exercise that used to have five sets and now has three logs three.
    @Test func aBufferLongerThanTheExerciseIsCutBackToIt() {
        #expect(LoggedSets.displayed([[1, 2, 3, 4, 5]], at: 0, sets: 3, default: 0) == [1, 2, 3])
    }

    @Test func eachExerciseReadsItsOwnRow() {
        let buffer = [[1, 1], [2, 2], [3, 3]]
        #expect(LoggedSets.displayed(buffer, at: 1, sets: 2, default: 0) == [2, 2])
    }

    /// The buffers are built when the screen appears and rebuilt when the
    /// phone edits the workout underneath it, so an index can be past the end
    /// for a moment. It writes the wheels' defaults rather than trapping.
    @Test func anIndexPastTheEndIsNotACrash() {
        #expect(LoggedSets.displayed([[1, 2]], at: 9, sets: 2, default: 0) == [0, 0])
        #expect(LoggedSets.displayed([[1, 2]], at: -1, sets: 2, default: 0) == [0, 0])
        #expect(LoggedSets.displayed([], at: 0, sets: 2, default: 0) == [0, 0])
    }

    // MARK: A set with no repetitions is not a set

    @Test func noRepetitionsMeansThereIsNothingToLog() {
        #expect(LoggedSets.hasRepetitions([]) == false)
        #expect(LoggedSets.hasRepetitions([0]) == false)
        #expect(LoggedSets.hasRepetitions([0, 0, 0]) == false)
    }

    @Test func oneRepetitionAnywhereIsASet() {
        #expect(LoggedSets.hasRepetitions([1]) == true)
        #expect(LoggedSets.hasRepetitions([0, 3, 0]) == true)
        #expect(LoggedSets.hasRepetitions([0, 0, 18]) == true)
    }

    /// Nought on the weight wheel is a real answer — an assisted machine
    /// carrying nothing, or an exercise done at body weight — so the question
    /// is never asked of the weights.
    @Test func aSetAtNoWeightIsStillASet() {
        #expect(LoggedSets.hasRepetitions(
            LoggedSets.displayed([[15, 15]], at: 0, sets: 2, default: 0)) == true)
    }
}
