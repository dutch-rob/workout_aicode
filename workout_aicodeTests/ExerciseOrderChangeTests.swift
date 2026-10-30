import Testing
import Foundation
@testable import workout_aicode

// MARK: - The workout is edited while the phone is logging it
//
// The Watch's version of this was reported from a real workout and is tested
// in the Watch target against the ids it is sent over the wire, which are
// Strings. The phone holds the UUIDs themselves, and reaches the same screen
// by different routes: the Mac reorders a workout and iCloud brings it over,
// or an exercise is deleted from the library, which drops it out of the log
// screen's list without the workout itself being touched.
//
// Same arithmetic, so what is worth testing here is the phone's own shapes:
// UUID ids, and the two buffers only this screen has — what an aerobic
// session came to, and how long it actually ran.

@Suite
struct PhoneExerciseOrderChangeTests {

    private let squat = UUID()
    private let bench = UUID()
    private let row = UUID()
    private let bike = UUID()

    private var before: [UUID] { [squat, bench, row, bike] }

    /// An exercise nobody has done before opens on empty wheels.
    private func fresh(_ id: UUID) -> [Int] { [] }

    @Test func deletingAnExerciseFromTheLibraryDoesNotSlideTheRestUp() {
        // Grams, as the phone holds them.
        let wheels = [[60_000], [40_000], [45_000], []]

        // Squat is deleted in the library, so it drops out of exerciseIds
        // although the workout still names it.
        let carried = ExerciseOrderChange.carry(wheels, from: before,
                                                to: [bench, row, bike], fresh: fresh)

        #expect(carried == [[40_000], [45_000], []])
    }

    @Test func theMacReorderingAWorkoutCarriesTheWheelsAlong() {
        let wheels = [[60_000], [40_000], [45_000], []]

        let carried = ExerciseOrderChange.carry(wheels, from: before,
                                                to: [bike, row, squat, bench], fresh: fresh)

        #expect(carried == [[], [45_000], [60_000], [40_000]])
    }

    /// Reps and weights are two arrays that must move together, or a set is
    /// logged with one exercise's weight and another's repetitions.
    @Test func repsAndWeightsStayWithTheSameExercise() {
        let order = [squat, bench, row]
        let weights = [[60_000], [40_000], [45_000]]
        let reps = [[8], [12], [10]]
        let after = [row, squat]

        let carriedWeights = ExerciseOrderChange.carry(weights, from: order, to: after,
                                                       fresh: fresh)
        let carriedReps = ExerciseOrderChange.carry(reps, from: order, to: after) { _ in [Int]() }

        #expect(carriedWeights == [[45_000], [60_000]])
        #expect(carriedReps == [[10], [8]])
    }

    /// An aerobic session belongs to the exercise it was run for. Carrying
    /// the summaries by position would hand a finished ride to whatever
    /// exercise happened to land in that slot.
    @Test func aFinishedRideStaysWithTheExerciseItWasRidden() {
        let order = [squat, bike, bench]
        let seconds = [0, 1_080, 0]
        let after = [bike, bench]

        let carried = ExerciseOrderChange.carry(seconds, from: order, to: after) { _ in 0 }

        #expect(carried == [1_080, 0])
    }

    /// Optionals carry like anything else — `summaries` is `[AerobicSummary?]`
    /// and the generic must not need it to be non-nil.
    @Test func anEmptySlotIsCarriedAsAnEmptySlot() {
        let order = [squat, bike]
        let done: [String?] = [nil, "18:00"]

        let carried = ExerciseOrderChange.carry(done, from: order,
                                                to: [bike, squat]) { _ in nil }

        #expect(carried == ["18:00", nil])
    }

    @Test func whatWasLoggedStaysLogged() {
        // Squat and row are done; squat is then deleted.
        let logged = ExerciseOrderChange.carry(Set([0, 2]), from: before,
                                               to: [bench, row, bike])

        // Row is now second, and nothing else counts as done.
        #expect(logged == Set([1]))
    }

    @Test func theExerciseInFrontOfYouStaysInFrontOfYou() {
        // Showing the row, which the Mac moves to the front.
        #expect(ExerciseOrderChange.position(of: 2, from: before,
                                             to: [row, squat, bench, bike]) == 0)
        // Showing the bench, and the squat goes: both move up one.
        #expect(ExerciseOrderChange.position(of: 1, from: before,
                                             to: [bench, row, bike]) == 0)
    }

    @Test func removingTheExerciseOnScreenLandsOnTheNextOne() {
        // Showing the bench, and the bench is what goes.
        #expect(ExerciseOrderChange.position(of: 1, from: before,
                                             to: [squat, row, bike]) == 1)
        // Showing the bike, last in the list, and the bike is what goes.
        #expect(ExerciseOrderChange.position(of: 3, from: before,
                                             to: [squat, bench, row]) == 2)
        // The workout is emptied while it is open.
        #expect(ExerciseOrderChange.position(of: 3, from: before, to: []) == 0)
    }

    /// The screen can be part-built when this runs — `adopt` fills the
    /// buffers from a snapshot that may be shorter than the workout.
    @Test func aShortBufferIsFilledInRatherThanRunOff() {
        let carried = ExerciseOrderChange.carry([[60_000]], from: before, to: before,
                                                fresh: fresh)

        #expect(carried == [[60_000], [], [], []])
    }
}
