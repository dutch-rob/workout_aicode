import Testing
import Foundation
@testable import workout_aicode_Watch_App_

// MARK: - The bar that drains down the side of the watch face
//
// The bar is the rest, and nothing else on the screen says how long is left
// while you are looking at the wheels. It is drawn from two dates on every
// tick rather than animated, and it is the only piece of the Watch's rest a
// test can hold still.
//
// It was redrawn once already, after a real workout where its first and last
// seconds were lost in the screen's rounded corners. These cover what it says,
// not where it is drawn: the ends are exactly the part that had to be right.

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
}
