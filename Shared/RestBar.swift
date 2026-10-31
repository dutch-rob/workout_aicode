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
}
