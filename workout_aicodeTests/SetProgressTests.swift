import Testing
import Foundation
@testable import workout_aicode

// MARK: - Which sets the app believes have been done
//
// These are the five-second rule, written out as the thing it is actually
// about: somebody arriving at an exercise, setting three columns of wheels up,
// and then doing the sets. The two look identical in the touches alone. Only
// the pauses tell them apart, so nearly every test here is about time rather
// than about which wheel was touched.
//
// No view and no clock: `SetProgress` is handed the dates, so a set done
// forty seconds after the last one can be tested in no time at all.

@Suite struct SetProgressTests {

    private let start = Date(timeIntervalSince1970: 1_000_000)
    private func after(_ seconds: TimeInterval) -> Date {
        start.addingTimeInterval(seconds)
    }

    // MARK: Setting the wheels up is not doing the sets

    /// "Any gesture within 5 seconds of entering the exercise."
    @Test func aTouchRightAfterArrivingIsSettingUp() {
        var progress = SetProgress(enteredAt: start)
        progress.touched(0, at: after(1))
        progress.settle(at: after(30))
        #expect(progress.doneColumns == 0)
    }

    /// "A number of gestures at entering the exercise with each pause between
    /// gestures less than 5 seconds." However long that goes on for: a burst
    /// that began as setting up stays setting up, because nothing in the
    /// middle of it is a pause long enough to have been a set.
    @Test func aLongFlurryOfSettingUpStaysSettingUp() {
        var progress = SetProgress(enteredAt: start)
        for second in stride(from: 1.0, through: 61.0, by: 4.0) {
            progress.touched(0, at: after(second))
        }
        progress.settle(at: after(90))
        #expect(progress.doneColumns == 0)
    }

    /// "Changing the weights of more than one column when entering the
    /// exercise does not yet lead to making a column green" — which is the
    /// same rule again, and the case it was written for.
    @Test func settingEveryColumnsWeightAtOnceMarksNothing() {
        var progress = SetProgress(enteredAt: start)
        progress.touched(0, at: after(2))
        progress.touched(1, at: after(5))
        progress.touched(2, at: after(8))
        progress.settle(at: after(40))
        #expect(progress.doneColumns == 0)
    }

    // MARK: Doing the sets

    /// "Changing the weight and/or reps or just clicking a wheel of the first
    /// column more than 5 seconds after entering the exercise."
    @Test func theFirstColumnIsMarkedOnceTheWheelsHaveBeenLeftAlone() {
        var progress = SetProgress(enteredAt: start)
        progress.touched(0, at: after(20))
        progress.settle(at: after(25))
        #expect(progress.doneColumns == 1)
        #expect(progress.isDone(0))
        #expect(!progress.isDone(1))
    }

    /// Setting up, then the first set. The flurry at the start uses nothing
    /// up: the next burst is judged against arriving, and arriving was long
    /// enough ago by then.
    @Test func settingUpFirstDoesNotStopTheFirstSetCounting() {
        var progress = SetProgress(enteredAt: start)
        progress.touched(0, at: after(1))
        progress.touched(1, at: after(3))
        progress.touched(2, at: after(5))
        // The set itself.
        progress.touched(0, at: after(45))
        progress.settle(at: after(50))
        #expect(progress.doneColumns == 1)
    }

    /// "Column A just right of column B that got colored green last, more
    /// than 5 seconds after coloring column B."
    @Test func theColumnsAreMarkedOneAfterAnotherAsTheSetsAreDone() {
        var progress = SetProgress(enteredAt: start)
        progress.touched(0, at: after(20))
        progress.settle(at: after(25))
        progress.touched(1, at: after(90))
        progress.settle(at: after(95))
        progress.touched(2, at: after(160))
        progress.settle(at: after(165))
        #expect(progress.doneColumns == 3)
    }

    // MARK: Only the next one along

    /// A touch on a column further right than the next one does nothing —
    /// a marked third set above an unmarked second would be a claim the app
    /// has no way to make. It does not use the burst up either: the set that
    /// IS next still counts when it is done.
    @Test func reachingPastTheNextColumnDoesNothingAndCostsNothing() {
        var progress = SetProgress(enteredAt: start)
        progress.touched(2, at: after(20))
        progress.settle(at: after(25))
        #expect(progress.doneColumns == 0)
        progress.touched(0, at: after(60))
        progress.settle(at: after(65))
        #expect(progress.doneColumns == 1)
    }

    /// Going back to correct a number in a column that is already marked does
    /// not advance anything. The next column is marked when the next set is
    /// done, not when the last one is tidied up.
    @Test func correctingAColumnThatIsAlreadyMarkedAdvancesNothing() {
        var progress = SetProgress(enteredAt: start)
        progress.touched(0, at: after(20))
        progress.settle(at: after(25))
        progress.touched(0, at: after(60))
        progress.settle(at: after(65))
        #expect(progress.doneColumns == 1)
    }

    /// Nothing marked beyond the last set, without being told how many there
    /// are: the column after the last one is not a column anybody can touch.
    @Test func thereIsNothingAfterTheLastSet() {
        var progress = SetProgress(enteredAt: start, doneColumns: 3)
        progress.touched(2, at: after(20))
        progress.settle(at: after(25))
        #expect(progress.doneColumns == 3)
    }

    // MARK: The wait

    /// "The app can only know to color the first column green from 5 seconds
    /// after the last potentially qualifying gesture, and I think it is OK if
    /// the coloring waits for that." It does wait, and asking early — a timer
    /// that fires at the wrong moment, a view that settles twice — cannot talk
    /// it into deciding sooner.
    @Test func nothingIsDecidedUntilTheWheelsHaveBeenQuietLongEnough() {
        var progress = SetProgress(enteredAt: start)
        progress.touched(0, at: after(20))
        // Bound rather than asked inside #expect: the macro cannot call a
        // mutating method on a value it is only borrowing.
        let tooSoon = progress.settle(at: after(21))
        let stillTooSoon = progress.settle(at: after(24.9))
        #expect(!tooSoon)
        #expect(!stillTooSoon)
        #expect(progress.doneColumns == 0)
        let decided = progress.settle(at: after(25))
        #expect(decided)
        #expect(progress.doneColumns == 1)
        // And the decision is not made twice.
        let again = progress.settle(at: after(30))
        #expect(!again)
        #expect(progress.doneColumns == 1)
    }

    @Test func theMomentToDecideIsFiveSecondsAfterTheLastTouch() {
        var progress = SetProgress(enteredAt: start)
        #expect(progress.decidesAt == nil)
        progress.touched(0, at: after(20))
        #expect(progress.decidesAt == after(25))
        // A second touch moves it; the burst is not over until the touching is.
        progress.touched(0, at: after(23))
        #expect(progress.decidesAt == after(28))
        progress.settle(at: after(28))
        #expect(progress.decidesAt == nil)
    }

    /// The next column is five seconds clear of the MARKING, which is itself
    /// five seconds after the last touch — so reaching straight back for the
    /// wheels is still setting up for the next set rather than having done it.
    /// A later touch, once the set really has been done, counts as it should.
    @Test func reachingStraightBackForTheWheelsIsStillSettingUp() {
        var progress = SetProgress(enteredAt: start)
        progress.touched(0, at: after(20))
        progress.settle(at: after(25))          // marked at 25
        progress.touched(1, at: after(27))      // only 2s after that
        progress.settle(at: after(35))
        #expect(progress.doneColumns == 1)
        progress.touched(1, at: after(80))
        progress.settle(at: after(85))
        #expect(progress.doneColumns == 2)
    }

    // MARK: Coming back to an exercise

    /// Swiping away and back is arriving again, so the wheels can be looked
    /// over without a set being marked. What was already marked stays marked —
    /// those sets were done, and leaving the screen did not undo them.
    @Test func comingBackToAnExerciseArmsTheGraceAgainButKeepsWhatIsMarked() {
        var progress = SetProgress(enteredAt: start)
        progress.touched(0, at: after(20))
        progress.settle(at: after(25))
        #expect(progress.doneColumns == 1)

        progress.entered(at: after(600))        // back from another exercise
        progress.touched(1, at: after(601))     // a glance at the numbers
        progress.settle(at: after(610))
        #expect(progress.doneColumns == 1)

        // And the set itself, done after it.
        progress.touched(1, at: after(640))
        progress.settle(at: after(645))
        #expect(progress.doneColumns == 2)
    }

    /// An open burst does not survive the trip. Half a flurry before swiping
    /// away and half after is two visits, not one burst.
    @Test func arrivingDropsAnyTouchLeftHangingFromBefore() {
        var progress = SetProgress(enteredAt: start)
        progress.touched(0, at: after(20))
        progress.entered(at: after(21))
        #expect(progress.decidesAt == nil)
        progress.settle(at: after(60))
        #expect(progress.doneColumns == 0)
    }

    /// LEAVING drops it too, and this is the one that matters: the exercise is
    /// not on screen to be asked while it is away, so the question would
    /// otherwise be put on the way back IN — against a five seconds that has
    /// not been re-armed yet, which is how a swipe between exercises managed
    /// to mark a column.
    @Test func leavingAnExerciseDropsTheTouchLeftHangingToo() {
        var progress = SetProgress(enteredAt: start)
        progress.touched(0, at: after(20))
        progress.left()
        #expect(progress.decidesAt == nil)
        // Coming back and asking, as the screen does.
        progress.settle(at: after(30))
        progress.entered(at: after(30))
        #expect(progress.doneColumns == 0)
    }

    @Test func leavingKeepsWhatIsAlreadyMarked() {
        var progress = SetProgress(enteredAt: start)
        progress.touched(0, at: after(20))
        progress.settle(at: after(25))
        progress.left()
        #expect(progress.doneColumns == 1)
    }

    /// The timer wakes at the moment the quiet runs out, so a decision is made
    /// within milliseconds of being due. Being asked long afterwards means
    /// nobody was there — the app was in a pocket — and what happened five
    /// minutes ago on a screen nobody could see is dropped rather than guessed.
    @Test func aQuestionPutFarTooLateIsNotAnsweredAtAll() {
        var progress = SetProgress(enteredAt: start)
        progress.touched(0, at: after(20))
        let decided = progress.settle(at: after(300))
        #expect(!decided)
        #expect(progress.doneColumns == 0)
        // And it is gone, not left lying around to be decided next time.
        #expect(progress.decidesAt == nil)
    }

    /// But a moment late is only a busy device, and still counts.
    @Test func aQuestionPutAMomentLateIsStillAnswered() {
        var progress = SetProgress(enteredAt: start)
        progress.touched(0, at: after(20))
        let decided = progress.settle(at: after(27))
        #expect(decided)
        #expect(progress.doneColumns == 1)
    }
}
