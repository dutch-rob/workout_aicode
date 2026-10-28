import Testing
import Foundation
@testable import workout_aicode

// MARK: - Copying a workout, and joining two of them
//
// The lists and the names only. Nothing here inserts into a store: the
// operation IS the arithmetic on exercise ids, and both the phone and the Mac
// call the same four functions to get it.

@Suite struct WorkoutCompositionTests {

    private func workout(_ name: String, _ order: [UUID], sortIndex: Int = 0) -> WorkoutDef {
        WorkoutDef(name: name, exerciseOrder: order, sortIndex: sortIndex)
    }

    @Test func aCopyNamesTheSameExercises() {
        let press = UUID(), row = UUID(), curl = UUID()
        let original = workout("Upper body", [press, row, curl])
        let copy = WorkoutComposition.copy(of: original, named: "Upper body copy",
                                           among: [original])

        // The same exercises, in the same order, and the SAME ids: a copy that
        // pointed at copied exercises would start the history again.
        #expect(copy.exerciseOrder == [press, row, curl])
        #expect(copy.name == "Upper body copy")
        #expect(copy.id != original.id)
        #expect(original.exerciseOrder == [press, row, curl])
    }

    @Test func aCopyGoesOnTheEnd() {
        let a = workout("A", [], sortIndex: 0)
        let b = workout("B", [], sortIndex: 7)
        #expect(WorkoutComposition.copy(of: a, named: "A copy", among: [a, b]).sortIndex == 8)
        #expect(WorkoutComposition.nextSortIndex(among: []) == 0)
    }

    @Test func copyNamesDoNotCollide() {
        let leg = workout("Leg day", [])
        #expect(WorkoutComposition.copyName(for: leg, among: [leg]) == "Leg day copy")

        let firstCopy = workout("Leg day copy", [])
        #expect(WorkoutComposition.copyName(for: leg, among: [leg, firstCopy])
                == "Leg day copy 2")

        let secondCopy = workout("Leg day copy 2", [])
        #expect(WorkoutComposition.copyName(for: leg, among: [leg, firstCopy, secondCopy])
                == "Leg day copy 3")
    }

    @Test func anUnnamedWorkoutStillGetsAUsableCopyName() {
        let blank = workout("", [])
        #expect(WorkoutComposition.copyName(for: blank, among: [blank]) == "Workout copy")
    }

    @Test func mergingPutsTheFirstsExercisesThenTheSeconds() {
        let press = UUID(), row = UUID(), squat = UUID(), calf = UUID()
        let upper = workout("Upper body", [press, row])
        let legs = workout("Leg day", [squat, calf])
        let joined = WorkoutComposition.merge(upper, legs, named: "Everything",
                                              among: [upper, legs])
        #expect(joined.exerciseOrder == [press, row, squat, calf])
        // Neither original is touched: merging makes a third workout.
        #expect(upper.exerciseOrder == [press, row])
        #expect(legs.exerciseOrder == [squat, calf])
    }

    @Test func anExerciseInBothAppearsOnce() {
        let warmUp = UUID(), press = UUID(), squat = UUID()
        let a = workout("A", [warmUp, press])
        let b = workout("B", [warmUp, squat])
        let joined = WorkoutComposition.merge(a, b, named: "A + B", among: [a, b])
        // Where it first falls, not where it last does — a second identical
        // row is two sets of one lift to log and two identical rows to read.
        #expect(joined.exerciseOrder == [warmUp, press, squat])
    }

    @Test func mergingAWorkoutWithItselfChangesNothingAboutIt() {
        let press = UUID(), row = UUID()
        let a = workout("A", [press, row])
        let joined = WorkoutComposition.merge(a, a, named: "A + A", among: [a])
        #expect(joined.exerciseOrder == [press, row])
    }

    @Test func mergedNamesSayWhatWentIn() {
        let upper = workout("Upper body", [])
        let legs = workout("Leg day", [])
        #expect(WorkoutComposition.mergedName(upper, legs, among: [upper, legs])
                == "Upper body + Leg day")

        let taken = workout("Upper body + Leg day", [])
        #expect(WorkoutComposition.mergedName(upper, legs, among: [upper, legs, taken])
                == "Upper body + Leg day 2")
    }

    @Test func anEmptyWorkoutMergesWithoutComplaint() {
        let press = UUID()
        let empty = workout("Empty", [])
        let real = workout("Real", [press])
        #expect(WorkoutComposition.merge(empty, real, named: "x", among: []).exerciseOrder
                == [press])
        #expect(WorkoutComposition.merge(real, empty, named: "x", among: []).exerciseOrder
                == [press])
    }
}
