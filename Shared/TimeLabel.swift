import Foundation

// MARK: - Minutes and seconds
//
// "1:30", "0:45", "24:00". One function, because there were three: the rest
// timer's, the aerobic countdown's, and the exercise defaults'. All three the
// same format string, none of them reachable from the Mac, which was about to
// make it four.

/// Seconds as m:ss. Minutes are not wrapped into hours — a two-hour session
/// reads as "120:00", which is what someone timing a workout means.
func minutesSeconds(_ seconds: Int) -> String {
    String(format: "%d:%02d", seconds / 60, seconds % 60)
}
