import Testing
import Foundation
@testable import workout_aicode_Watch_App_

// MARK: - A finished cardio session belongs to ONE exercise
//
// From a real workout: it began with the elliptical, which ran fine, and the
// next exercise — the indoor cycle, also cardio — came up with no start
// button, so it could not be logged at all.
//
// `hasRun(index)` took an index and ignored it, asking instead whether ANY
// session had finished. One session therefore counted as every cardio
// exercise having been done. The second half of the same bug is quieter and
// worse: logging that second exercise would have recorded the elliptical's
// duration and heart rate under the indoor cycle's name.

@Suite(.serialized)
@MainActor
struct AerobicSessionOwnershipTests {

    private func summary(seconds: Int) -> WatchAerobicWorkout.Summary {
        WatchAerobicWorkout.Summary(durationSeconds: seconds,
                                    averageHeartRate: 120,
                                    maximumHeartRate: 150,
                                    zoneSeconds: [])
    }

    @Test func aFinishedSessionCountsOnlyForItsOwnExercise() {
        let aerobic = WatchAerobicWorkout.shared
        aerobic.rememberForTesting(summary(seconds: 1200), exercise: "Elliptical")

        #expect(aerobic.hasFinishedSession(for: "Elliptical"))
        // The one that had no start button.
        #expect(!aerobic.hasFinishedSession(for: "Indoor cycle"))
    }

    @Test func anotherExerciseCannotTakeItsNumbers() {
        let aerobic = WatchAerobicWorkout.shared
        aerobic.rememberForTesting(summary(seconds: 1200), exercise: "Elliptical")

        #expect(aerobic.takeLastSummary(for: "Indoor cycle") == nil)
        // And taking it for the wrong one must not have consumed it.
        let mine = aerobic.takeLastSummary(for: "Elliptical")
        #expect(mine?.durationSeconds == 1200)
        // Taken once.
        #expect(aerobic.takeLastSummary(for: "Elliptical") == nil)
        #expect(!aerobic.hasFinishedSession(for: "Elliptical"))
    }
}
