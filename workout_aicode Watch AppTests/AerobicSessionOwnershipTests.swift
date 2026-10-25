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

// MARK: - Zones that came from Health are used exactly as given
//
// `preferredWorkoutZoneConfiguration(for:)` returns whichever configuration is
// active in Health — the system's automatic zones or boundaries the user set
// by hand. When it answers, the band must show THOSE numbers: recomputing
// anything from heart rate reserve would put the app back to disagreeing with
// the Workout app, which is the whole complaint.

@Suite struct PreferredZoneTests {

    @Test func boundariesFromHealthAreKeptVerbatim() throws {
        let zones = try #require(HeartRateZones(boundaries: [114, 133, 152, 171],
                                                restingHeartRate: 52,
                                                maximumHeartRate: 185,
                                                source: .healthKit))
        #expect(zones.boundaries == [114, 133, 152, 171])
        #expect(zones.source == .healthKit)
        // And they decide the zone, rather than the reserve arithmetic.
        #expect(zones.zone(for: 100) == 1)
        #expect(zones.zone(for: 120) == 2)
        #expect(zones.zone(for: 160) == 4)
        #expect(zones.zone(for: 200) == 5)
    }

    @Test func aConfigurationOfTheWrongShapeIsRefused() {
        // Health could describe some other number of zones. A band drawn for
        // five would then be showing something that is not true, so the
        // estimate is the better answer.
        #expect(HeartRateZones(boundaries: [120, 140, 160],
                               restingHeartRate: 52, maximumHeartRate: 185,
                               source: .healthKit) == nil)
        #expect(HeartRateZones(boundaries: [120, 140, 160, 180, 200],
                               restingHeartRate: 52, maximumHeartRate: 185,
                               source: .healthKit) == nil)
    }

    @Test func boundariesOutOfOrderAreRefused() {
        #expect(HeartRateZones(boundaries: [140, 120, 160, 180],
                               restingHeartRate: 52, maximumHeartRate: 185,
                               source: .healthKit) == nil)
        #expect(HeartRateZones(boundaries: [120, 120, 160, 180],
                               restingHeartRate: 52, maximumHeartRate: 185,
                               source: .healthKit) == nil)
    }

    @Test func theEstimateIsStillThereWhenHealthHasNothing() {
        let zones = HeartRateZones(restingHeartRate: 52, maximumHeartRate: 185)
        #expect(zones.source == .estimated)
        #expect(zones.boundaries.count == HeartRateZones.zoneCount - 1)
        #expect(zones.boundaries == zones.boundaries.sorted())
    }
}
