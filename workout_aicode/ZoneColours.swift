import SwiftUI

// MARK: - Zone colours
//
// A byte-identical copy of this file lives in the Watch App target
// ("workout_aicode Watch App/ZoneColours.swift"). Shared because the two ends
// disagreed once already: the Watch drew zone 1 blue while the phone drew every
// lit zone red, so the same heart rate was a different colour depending on
// which device you looked at.

/// Blue for easy through to red for the top — the ordering people already know
/// from every heart rate band they have seen, including the Workout app's.
enum ZoneColour {
    static let all: [Color] = [
        Color(red: 0.16, green: 0.55, blue: 0.95),   // 1 — blue
        Color(red: 0.16, green: 0.68, blue: 0.60),   // 2 — teal
        Color(red: 0.72, green: 0.72, blue: 0.14),   // 3 — yellow-green
        Color(red: 0.85, green: 0.45, blue: 0.12),   // 4 — orange
        Color(red: 0.80, green: 0.15, blue: 0.28),   // 5 — red
    ]

    static func colour(_ zone: Int) -> Color {
        guard zone >= 1, zone <= all.count else { return .secondary }
        return all[zone - 1]
    }

    /// How much of its colour a zone shows when it is not the one you are in.
    /// Dim enough to recede, strong enough that the band still reads as a band.
    static let restingOpacity: Double = 0.4
}
