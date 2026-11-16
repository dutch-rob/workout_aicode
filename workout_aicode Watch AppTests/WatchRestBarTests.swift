import Testing
import Foundation
import CoreGraphics
@testable import workout_aicode_Watch_App_

// MARK: - The bar that drains down the side of the watch face
//
// The bar is the rest, and nothing else on the screen says how long is left
// while you are looking at the wheels. It is drawn from two dates on every
// tick rather than animated, and it is the only piece of the Watch's rest a
// test can hold still.
//
// It has been redrawn twice after real workouts, both times at its ENDS: first
// because the rounded corners ate its first and last seconds, then because the
// top of it was adding red to the blue of the heart rate zone band, in the one
// corner a glance has to read to know the rest has started. So the ends are
// what these cover — both what the bar says and where it is drawn.
//
// A third report, from a workout on 15 November 2026: the bar was too slow to
// tell from a stopped one. It is now split lengthwise, with the right half
// sweeping the whole height every fifteen seconds, so the last tests here are
// about that half and about the one thing it put at risk — how often the clock
// is read, which is a watch battery and the main thread the wheels settle on.

@Suite
struct WatchRestBarTests {

    private let start = Date(timeIntervalSince1970: 1_000_000)
    private let total: TimeInterval = 90

    private var endsAt: Date { start.addingTimeInterval(total) }

    @Test func theBarIsFullAtTheStartAndEmptyAtTheEnd() {
        #expect(RestBar.fill(endsAt: endsAt, now: start, total: total) == 1)
        #expect(RestBar.fill(endsAt: endsAt, now: endsAt, total: total) == 0)
    }

    @Test func halfwayThroughTheBarIsHalfFull() {
        let halfway = start.addingTimeInterval(total / 2)

        #expect(RestBar.fill(endsAt: endsAt, now: halfway, total: total) == 0.5)
    }

    /// A rest can be looked at after it is over — the screen stays up — and
    /// one can arrive from a phone whose clock is ahead.
    @Test func theBarDoesNotRunOffEitherEnd() {
        let after = endsAt.addingTimeInterval(600)
        let before = start.addingTimeInterval(-600)

        #expect(RestBar.fill(endsAt: endsAt, now: after, total: total) == 0)
        #expect(RestBar.fill(endsAt: endsAt, now: before, total: total) == 1)
    }

    @Test func noRestMeansNoBar() {
        #expect(RestBar.fill(endsAt: nil, now: start, total: total) == 0)
        // A rest of no length is not a rest, and dividing by it is worse.
        #expect(RestBar.fill(endsAt: endsAt, now: start, total: 0) == 0)
    }

    /// Rounded up, so a rest with anything at all left on it still shows a
    /// second. Zero is reserved for a rest that is over.
    @Test func aRestWithATenthOfASecondLeftStillSaysOne() {
        let nearlyDone = endsAt.addingTimeInterval(-0.1)

        #expect(RestBar.remaining(endsAt: endsAt, now: nearlyDone) == 1)
        #expect(RestBar.remaining(endsAt: endsAt, now: endsAt) == 0)
        #expect(RestBar.remaining(endsAt: endsAt, now: endsAt.addingTimeInterval(5)) == 0)
        #expect(RestBar.remaining(endsAt: nil, now: start) == 0)
    }

    @Test func theCounterReadsAsMinutesAndSeconds() {
        #expect(RestBar.label(endsAt: endsAt, now: start) == "1:30")
        #expect(RestBar.label(endsAt: endsAt, now: start.addingTimeInterval(45)) == "0:45")
        #expect(RestBar.label(endsAt: endsAt, now: endsAt) == "0:00")
        // Single digits are padded; the minutes are not.
        #expect(RestBar.label(endsAt: start.addingTimeInterval(9), now: start) == "0:09")
    }

    /// The bar is as wide as the screen's own margin plus the row-label
    /// column, so it runs under "weight" and "reps" and stops short of the
    /// wheels. Narrower than that and the corners ate its ends; wider and it
    /// would sit on top of the numbers being read.
    @Test func theBarCoversTheLabelColumnAndNoMore() {
        #expect(WatchRestDrain.barWidth == 20)
    }

    // MARK: Where it is drawn

    private let screen: CGFloat = 220
    private let inset: CGFloat = 30
    private let width: CGFloat = WatchRestDrain.barWidth

    @Test func aFullBarStartsUnderTheBandAndStopsAsFarShortOfTheBottom() {
        let full = RestBar.bar(in: screen, inset: inset, width: width, fill: 1)
        #expect(full?.minY == inset)
        #expect(full?.maxY == screen - inset)
        // Symmetrical, which is the whole point: a bar that reached one end
        // and not the other read as part-drained the moment it started.
        #expect(full?.minY == screen - (full?.maxY ?? 0))
    }

    @Test func theBarDrainsWithinItsOwnTrackNotTheWholeScreen() {
        let half = RestBar.bar(in: screen, inset: inset, width: width, fill: 0.5)
        #expect(half?.height == (screen - inset * 2) / 2)
        // It drains downwards: the bottom stays put and the top comes down.
        #expect(half?.maxY == screen - inset)
    }

    @Test func nothingIsDrawnWhenThereIsNothingLeft() {
        #expect(RestBar.bar(in: screen, inset: inset, width: width, fill: 0) == nil)
    }

    // An inset bigger than half the strip has no track left between its ends.
    // Reachable on a small watch with large text, where one row of the layout
    // can be a good share of the screen, and the answer is to draw nothing
    // rather than an upside-down rectangle.
    @Test func anImpossibleInsetDrawsNothingRatherThanSomethingWrong() {
        #expect(RestBar.bar(in: screen, inset: screen / 2, width: width, fill: 1) == nil)
        #expect(RestBar.bar(in: screen, inset: screen, width: width, fill: 1) == nil)
        #expect(RestBar.bar(in: screen, inset: inset, width: 0, fill: 1) == nil)
    }

    // No report from the log screen yet, or a screen that has no such row:
    // the bar is the full height it always was.
    @Test func withNoInsetTheBarIsTheWholeStripAsItWas() {
        let full = RestBar.bar(in: screen, inset: 0, width: width, fill: 1)
        #expect(full == CGRect(x: 0, y: 0, width: width, height: screen))
    }

    // MARK: - The half that sweeps

    // The fast half is timed from the END of the rest, so that it reaches the
    // bottom exactly as the rest runs out rather than being cut off part way
    // down. Which means a whole number of sweeps from the end is the bottom.
    @Test func theFastHalfIsAtTheBottomAWholeNumberOfSweepsFromTheEnd() {
        #expect(RestBar.fastFill(endsAt: endsAt, now: endsAt) == 0)
        for sweeps in 1...3 {
            let when = endsAt.addingTimeInterval(-RestBar.fastCycle * Double(sweeps))
            #expect(RestBar.fastFill(endsAt: endsAt, now: when) == 0)
        }
    }

    @Test func theFastHalfDrainsAcrossOneSweepAndStartsAgain() {
        // A quarter of the way into a sweep, three quarters of it is left.
        let quarterIn = endsAt.addingTimeInterval(-RestBar.fastCycle * 1.75)
        #expect(abs(RestBar.fastFill(endsAt: endsAt, now: quarterIn) - 0.75) < 0.0001)
        // Halfway, half of it.
        let halfIn = endsAt.addingTimeInterval(-RestBar.fastCycle * 1.5)
        #expect(abs(RestBar.fastFill(endsAt: endsAt, now: halfIn) - 0.5) < 0.0001)
        // A moment after the bottom it is back at the top rather than stuck
        // there — the "starts again" half of the whole idea.
        let justAfterBottom = endsAt.addingTimeInterval(-RestBar.fastCycle * 2 + 0.01)
        #expect(RestBar.fastFill(endsAt: endsAt, now: justAfterBottom) > 0.99)
    }

    // The same clamping the slow half gets: nothing to draw once the rest is
    // over, or before it starts, or when there is no rest at all.
    @Test func theFastHalfIsEmptyWhenThereIsNoRestLeft() {
        #expect(RestBar.fastFill(endsAt: nil, now: start) == 0)
        #expect(RestBar.fastFill(endsAt: endsAt, now: endsAt.addingTimeInterval(5)) == 0)
    }

    @Test func theFastHalfIsNeverOutsideTheBar() {
        // Walked a second at a time across a rest and a bit beyond it, since
        // a phase that strayed outside 0...1 would draw past the bar's ends.
        for second in 0...120 {
            let fill = RestBar.fastFill(endsAt: endsAt,
                                        now: start.addingTimeInterval(Double(second)))
            #expect(fill >= 0 && fill < 1)
        }
    }

    // MARK: - The two halves side by side

    @Test func theSlowHalfIsOnTheLeftAndTheFastOneOnTheRight() {
        let halves = RestBar.halves(in: screen, inset: inset, width: width,
                                    fill: 1, fastFill: 1)
        #expect(halves.slow?.minX == 0)
        #expect(halves.fast?.minX == width / 2)
        #expect(halves.slow?.width == width / 2)
        #expect(halves.fast?.width == width / 2)
        // Together they are the bar that was there before the split.
        #expect(halves.slow?.union(halves.fast!)
                == RestBar.bar(in: screen, inset: inset, width: width, fill: 1))
    }

    // Each half is drained by its own number, and the two are nothing to do
    // with each other: late in a rest the fast half can be near the top while
    // the slow one is nearly gone, which is the point of it.
    @Test func eachHalfIsDrainedByItsOwnNumber() {
        let halves = RestBar.halves(in: screen, inset: inset, width: width,
                                    fill: 0.1, fastFill: 0.9)
        let track = screen - inset * 2
        #expect(abs((halves.slow?.height ?? 0) - track * 0.1) < 0.0001)
        #expect(abs((halves.fast?.height ?? 0) - track * 0.9) < 0.0001)
        // Both sit on the same bottom edge.
        #expect(halves.slow?.maxY == halves.fast?.maxY)
    }

    @Test func anEmptyHalfIsNotDrawnAtAll() {
        let halves = RestBar.halves(in: screen, inset: inset, width: width,
                                    fill: 0, fastFill: 0.5)
        #expect(halves.slow == nil)
        #expect(halves.fast != nil)
    }

    // MARK: - How often the clock is read
    //
    // This is a watch battery, and it is also the main thread the wheels
    // settle on: a wheel once came to rest one click past where it was let go
    // because the bar was being redrawn fifteen times a second underneath it.
    // So the rate is part of the behaviour, not a detail.

    @Test func theClockIsReadNoFasterThanTheBarActuallyMoves() {
        // An ordinary rest. The fast half sweeps every `fastCycle` seconds, so
        // it, and not the ninety-second drain, sets the rate.
        let ordinary = RestBar.tickInterval(total: 90)
        #expect(abs(ordinary - RestBar.fastCycle / RestBar.stepsPerSweep) < 0.0001)
        // Which is about three times a second, not fifteen.
        #expect(ordinary > 1.0 / 4)
        #expect(ordinary < 1.0 / 2.5)
    }

    @Test func aLongRestIsReadNoMoreOftenThanAShortOne() {
        // The fast half is the same speed whatever the rest's length, so the
        // rate stops depending on it. It used to: a thirty-second rest was
        // read seven times a second and a three-minute one twice.
        #expect(RestBar.tickInterval(total: 60) == RestBar.tickInterval(total: 300))
    }

    @Test func theCounterNeverSkipsASecond() {
        // Whole seconds beside the wheels, so twice a second is the slowest
        // the clock may ever be read — including for a rest so long that
        // nothing on the bar would need it.
        for total in [15.0, 90.0, 600.0, 36_000.0] {
            #expect(RestBar.tickInterval(total: total) <= 0.5)
        }
        #expect(RestBar.tickInterval(total: 0) <= 0.5)
    }

    @Test func aVeryShortRestCannotSpinTheMainThread() {
        // A one-second rest would want the clock read every 20 ms; the floor
        // says fifteen times a second and no more.
        #expect(RestBar.tickInterval(total: 1) >= 1.0 / 15)
        #expect(RestBar.tickInterval(total: 0.001) >= 1.0 / 15)
    }
}
