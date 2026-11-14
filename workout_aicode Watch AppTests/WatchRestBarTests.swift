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
// what these cover — both what the bar says and, now, where it is drawn.

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
}
