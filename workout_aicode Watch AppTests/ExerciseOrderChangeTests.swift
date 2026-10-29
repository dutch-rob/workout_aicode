import Testing
import Foundation
@testable import workout_aicode_Watch_App_

// MARK: - The phone edits a workout that is being logged on the Watch
//
// From a real workout: the first exercise was taken out on the phone just
// after the workout began. The Watch then showed the first remaining exercise
// with nothing on its wheels, the second with the first's weights, and the
// third with the second's — and went on doing so until the app was force-
// quit, at which point everything lined up again.
//
// Nothing was wrong with the data. The screen's arrays are by position and
// the order had moved under them.

@Suite
struct ExerciseOrderChangeTests {

    private let before = ["a", "b", "c", "d"]

    /// "0" stands for an exercise never logged before, which is what the
    /// first remaining one was showing.
    private func fresh(_ id: String) -> String { "fresh-\(id)" }

    @Test func removingTheFirstExerciseDoesNotSlideTheRestUp() {
        let wheels = ["wa", "wb", "wc", "wd"]
        let after = ["b", "c", "d"]

        let carried = ExerciseOrderChange.carry(wheels, from: before, to: after, fresh: fresh)

        // What went wrong in the gym was ["wa", "wb", "wc"].
        #expect(carried == ["wb", "wc", "wd"])
    }

    @Test func anExerciseAddedMidWorkoutOpensOnItsOwnNumbers() {
        let wheels = ["wa", "wb"]
        let after = ["a", "new", "b"]

        let carried = ExerciseOrderChange.carry(wheels, from: ["a", "b"], to: after, fresh: fresh)

        #expect(carried == ["wa", "fresh-new", "wb"])
    }

    @Test func reorderingCarriesTheWheelsAlong() {
        let wheels = ["wa", "wb", "wc", "wd"]
        let after = ["d", "a", "c", "b"]

        let carried = ExerciseOrderChange.carry(wheels, from: before, to: after, fresh: fresh)

        #expect(carried == ["wd", "wa", "wc", "wb"])
    }

    /// A half-built screen must not be made worse by this: shorter arrays
    /// fall back to a fresh value rather than reading off the end.
    @Test func aShortArrayIsFilledInRatherThanRunOff() {
        let carried = ExerciseOrderChange.carry(["wa"], from: before, to: before, fresh: fresh)

        #expect(carried == ["wa", "fresh-b", "fresh-c", "fresh-d"])
    }

    @Test func whatWasLoggedStaysLogged() {
        // a and c are done; a is then removed on the phone.
        let logged = ExerciseOrderChange.carry(Set([0, 2]), from: before, to: ["b", "c", "d"])

        // c is now second. Nothing else counts as done.
        #expect(logged == Set([1]))
    }

    @Test func theExerciseInFrontOfYouStaysInFrontOfYou() {
        // Showing c, which the phone moves to the front.
        #expect(ExerciseOrderChange.position(of: 2, from: before,
                                             to: ["c", "a", "b", "d"]) == 0)
        // Showing b, and a is removed: b moves up one, and so does the screen.
        #expect(ExerciseOrderChange.position(of: 1, from: before,
                                             to: ["b", "c", "d"]) == 0)
    }

    @Test func removingTheExerciseOnScreenLandsOnTheNextOne() {
        // Showing b, and b is what goes: c has taken its place.
        #expect(ExerciseOrderChange.position(of: 1, from: before,
                                             to: ["a", "c", "d"]) == 1)
        // Showing d, the last one, and d is what goes.
        #expect(ExerciseOrderChange.position(of: 3, from: before,
                                             to: ["a", "b", "c"]) == 2)
        // Everything is taken out.
        #expect(ExerciseOrderChange.position(of: 3, from: before, to: []) == 0)
    }
}
