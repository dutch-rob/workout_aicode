import Foundation
import CoreGraphics

// MARK: - How much of the rest is left
//
// The arithmetic behind the draining bar, on both the phone and the Watch, as
// three functions of two dates. It is here rather than in either timer for
// two reasons.
//
// It was written twice, once on each side, and the Watch's copy had no tests
// at all — while the phone's had six, which is the wrong way round for the
// screen whose bar had to be redrawn because its first and last seconds were
// being lost in the corners.
//
// And it must stay a computation rather than becoming state. The crown reports
// every value it passes through, so one spin of the wheel is dozens of "set
// finished" events; animating a stored fill on each of them left SwiftUI
// blending dozens of overlapping animations of the same property, and the bar
// crawled down the screen long after the rest was over. A number derived from
// two dates cannot pile up, and cannot outlive being cancelled.

// Arithmetic on two dates, called from the Watch's timer as well as the
// phone's and from neither one's main actor in particular.
nonisolated enum RestBar {

    /// 1 as the rest starts, 0 when it is over, and never outside that.
    ///
    /// Clamped at both ends on purpose: `now` can be past `endsAt` for the
    /// moment between the rest ending and something noticing, and it can be
    /// before the start if the clock moves or a rest arrives from a device
    /// that is ahead.
    static func fill(endsAt: Date?, now: Date, total: TimeInterval) -> CGFloat {
        guard let endsAt, total > 0 else { return 0 }
        return max(0, min(1, CGFloat(endsAt.timeIntervalSince(now) / total)))
    }

    /// Seconds still to go, rounded UP: a rest with a tenth of a second left
    /// reads as "1", because it has not finished, and "0" is reserved for a
    /// rest that is over.
    static func remaining(endsAt: Date?, now: Date) -> Int {
        guard let endsAt else { return 0 }
        return max(0, Int(endsAt.timeIntervalSince(now).rounded(.up)))
    }

    /// What the counter beside the exercise name says.
    static func label(endsAt: Date?, now: Date) -> String {
        minutesSeconds(remaining(endsAt: endsAt, now: now))
    }

    // MARK: Where the bar is

    /// The rectangle to draw, in a strip `height` tall, inset equally at both
    /// ends. Nil when there is nothing to draw.
    ///
    /// The Watch's bar does not run the whole height of its screen: the top of
    /// it sat under the heart rate zone band, where additive red over blue made
    /// the first seconds of a rest a smudge in the one corner a glance has to
    /// read. So it starts below the band and stops as far short of the bottom
    /// as it starts short of the top — symmetrical, because a bar that reaches
    /// one end and not the other reads as part-drained when it is full.
    ///
    /// Here rather than in the Canvas that draws it because a closure inside a
    /// view modifier is the one place arithmetic cannot be checked, and the
    /// last bar whose ends were wrong was wrong on a wrist in a gym.
    static func bar(in height: CGFloat, inset: CGFloat,
                    width: CGFloat, fill: CGFloat) -> CGRect? {
        let track = height - inset * 2
        guard track > 0, width > 0 else { return nil }
        let drawn = track * max(0, min(1, fill))
        guard drawn > 0 else { return nil }
        return CGRect(x: 0, y: height - inset - drawn, width: width, height: drawn)
    }

    // MARK: The half that moves

    /// The bar is split lengthwise, and the two halves drain at different
    /// rates: the left one across the whole rest, the right one over and over.
    ///
    /// A ninety-second rest drains about two points a second down a watch
    /// screen. That is honest and it is unreadable — a glance cannot tell a
    /// bar that is draining from one that has stopped, and the question a
    /// glance is asking is "is this thing still running?". The right half
    /// sweeps the full height every `fastCycle` seconds instead, so there is
    /// always something visibly moving, while the left half keeps saying how
    /// much of the rest is actually left. Reported from a real workout: the
    /// bar was too slow to read.
    ///
    /// The sweep is timed from the END of the rest rather than its start, so
    /// the fast half reaches the bottom exactly as the rest runs out instead
    /// of being cut off part way down.

    /// How long the fast half takes to sweep from top to bottom once.
    ///
    /// Fifteen seconds is about thirteen points a second, which reads as
    /// motion at a glance, and is slow enough that the clock still only has to
    /// be read about three times a second — see `tickInterval`. Shorter sweeps
    /// look better and cost a watch battery proportionally more.
    static let fastCycle: TimeInterval = 15

    /// Where the fast half stands: 1 at the top of a sweep, 0 at the bottom.
    ///
    /// Derived from the two dates like everything else here, and for the same
    /// reason — see the note at the top of the file. A stored phase advanced by
    /// a timer would drift, would have to be reset on every one of the dozens
    /// of "set finished" events one spin of the crown produces, and would
    /// outlive the rest being cancelled.
    static func fastFill(endsAt: Date?, now: Date) -> CGFloat {
        guard let endsAt else { return 0 }
        let toGo = endsAt.timeIntervalSince(now)
        guard toGo > 0 else { return 0 }
        let sweeps = toGo / fastCycle
        // The fractional part of "how many sweeps are left". As time passes it
        // falls to 0, jumps to just under 1, and falls again — which is a bar
        // draining and starting over.
        return CGFloat(sweeps - sweeps.rounded(.down))
    }

    /// The two rectangles to draw, side by side within the bar's own width:
    /// the slow half on the left, the fast one on the right.
    static func halves(in height: CGFloat, inset: CGFloat, width: CGFloat,
                       fill: CGFloat,
                       fastFill: CGFloat) -> (slow: CGRect?, fast: CGRect?) {
        let half = width / 2
        let slow = bar(in: height, inset: inset, width: half, fill: fill)
        // `bar` always draws at the left edge, so the fast half is the same
        // rectangle moved over by its own width.
        let fast = bar(in: height, inset: inset, width: half, fill: fastFill)
            .map { CGRect(x: half, y: $0.minY, width: $0.width, height: $0.height) }
        return (slow, fast)
    }

    // MARK: How often the clock is read

    /// How tall the bar's track is, near enough to decide how often to read the
    /// clock. The watch screens this app runs on are 170 to 230 points tall;
    /// the top of the range is the one to take, since being wrong this way
    /// reads the clock slightly too often rather than visibly too little.
    static let screenPoints: CGFloat = 220

    /// The furthest anything on the bar may move between two readings of the
    /// clock.
    ///
    /// It was one point — a tick for every point of travel, which is as smooth
    /// as the screen can show and more than anybody looks at. Five points is
    /// about 2% of the bar's height, invisible on a drain and indistinguishable
    /// from smooth on the fast half, and it is what makes the fast half
    /// affordable at all.
    static let stepPoints: CGFloat = 5

    /// How many readings of the clock one full sweep of the bar is worth.
    static var stepsPerSweep: Double { Double(screenPoints / stepPoints) }

    /// How often to re-read the clock during a rest of `total` seconds.
    ///
    /// Taken from whatever on screen moves fastest, and no faster than that.
    /// Three things have a say:
    ///
    ///   • the counter beside the wheels, which counts whole seconds and must
    ///     not skip one — so never slower than twice a second;
    ///   • the fast half, which sweeps the screen every `fastCycle` seconds;
    ///   • the slow half, which drains across the whole rest, and for any rest
    ///     longer than one sweep has nothing to add to the above.
    ///
    /// This replaced a flat fifteen times a second, and then one tick per
    /// point of travel. It is all on the main thread, some of it inside the few
    /// hundred milliseconds a wheel spends settling onto a number, which is
    /// where a wheel was coming to rest one click past where it was let go.
    static func tickInterval(total: TimeInterval) -> TimeInterval {
        var wanted = 0.5
        if total > 0 { wanted = min(wanted, total / stepsPerSweep) }
        wanted = min(wanted, fastCycle / stepsPerSweep)
        // A floor, so a rest of a second or two cannot spin the main thread.
        return max(1.0 / 15, wanted)
    }
}
