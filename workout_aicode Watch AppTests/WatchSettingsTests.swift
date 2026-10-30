import Testing
import Foundation
@testable import workout_aicode_Watch_App_

// MARK: - Settings that arrive from the phone
//
// The Watch has no settings screen worth the name: everything below is typed
// on the phone and sent across. What it does have is the job of not believing
// any of it — a payload comes from whatever build happens to be on the other
// device, including one older or newer than this one, and a value that makes
// no sense must turn into a sensible one rather than into a wrong screen.
//
// The heart rate boundaries are the sharp end of that. Four numbers typed by
// hand, and a band drawn from a half-valid set would be a confident lie about
// which zone someone is training in.

@Suite
struct WatchPreferenceClampTests {

    @Test func therowsSettingIsOneOrTwoAndNothingElse() {
        #expect(WatchPreferences.clampRows(1) == 1)
        #expect(WatchPreferences.clampRows(2) == 2)
        // Anything else is one row: the layout only has the two.
        #expect(WatchPreferences.clampRows(0) == 1)
        #expect(WatchPreferences.clampRows(3) == 1)
        #expect(WatchPreferences.clampRows(-7) == 1)
    }

    @Test func theZoneTintNeverGoesSoFaintThatTheBandDisappears() {
        #expect(WatchPreferences.clampTint(0.5) == 0.5)
        #expect(WatchPreferences.clampTint(1) == 1)
        #expect(WatchPreferences.clampTint(9) == 1)
        #expect(WatchPreferences.clampTint(0) == WatchPreferences.minimumZoneTint)
        #expect(WatchPreferences.clampTint(-1) == WatchPreferences.minimumZoneTint)
    }

    @Test func theTapsAtTheEndOfARestAreAtLeastOne() {
        #expect(WatchPreferences.clampTaps(1) == 1)
        #expect(WatchPreferences.clampTaps(0) == 1)
        #expect(WatchPreferences.clampTaps(99) == WatchPreferences.maximumRestTaps)
    }
}

@Suite
struct WatchZoneBoundaryTests {

    private let good = [91, 115, 139, 164]

    @Test func fourRisingNumbersAreKept() {
        #expect(WatchPreferences.validBoundaries(good) == good)
        #expect(WatchPreferences.parseBoundaries("91,115,139,164") == good)
        #expect(WatchPreferences.parseBoundaries(" 91 , 115,139 , 164 ") == good)
        #expect(WatchPreferences.boundariesText(good) == "91,115,139,164")
    }

    /// Nothing half-valid ever comes out: a band drawn from three thresholds,
    /// or from four that are not in order, is worse than no band at all.
    @Test func anythingElseIsNoBoundariesRatherThanSomeOfThem() {
        #expect(WatchPreferences.validBoundaries([91, 115, 139]).isEmpty)
        #expect(WatchPreferences.validBoundaries([91, 115, 139, 164, 180]).isEmpty)
        #expect(WatchPreferences.validBoundaries([115, 91, 139, 164]).isEmpty)
        #expect(WatchPreferences.validBoundaries([91, 91, 139, 164]).isEmpty)
        #expect(WatchPreferences.validBoundaries([]).isEmpty)
        // Heart rates a person could not have.
        #expect(WatchPreferences.validBoundaries([5, 115, 139, 164]).isEmpty)
        #expect(WatchPreferences.validBoundaries([91, 115, 139, 900]).isEmpty)
    }

    @Test func textThatIsNotFourNumbersComesBackEmpty() {
        #expect(WatchPreferences.parseBoundaries("").isEmpty)
        #expect(WatchPreferences.parseBoundaries("one,two,three,four").isEmpty)
        #expect(WatchPreferences.parseBoundaries("91,115,139").isEmpty)
        #expect(WatchPreferences.boundariesText([91, 115]).isEmpty)
    }

    /// The same shape `HeartRateZones` insists on, so the settings screen can
    /// promise what the band will actually do.
    @Test func whatTheSettingsAcceptIsWhatTheBandCanDraw() {
        #expect(HeartRateZones(boundaries: good, restingHeartRate: 55,
                               maximumHeartRate: 185, source: .manual) != nil)
        #expect(HeartRateZones(boundaries: [115, 91, 139, 164], restingHeartRate: 55,
                               maximumHeartRate: 185, source: .manual) == nil)
        #expect(HeartRateZones(boundaries: [91, 115, 139], restingHeartRate: 55,
                               maximumHeartRate: 185, source: .manual) == nil)
    }
}

@Suite
struct WatchZoneReadingTests {

    private var zones: HeartRateZones {
        HeartRateZones(boundaries: [91, 115, 139, 164], restingHeartRate: 55,
                       maximumHeartRate: 185, source: .manual)!
    }

    /// Every heart rate is in a zone. A slow one is in zone 1, which is what
    /// zone 1 is for — there is no "below the band".
    @Test func everyHeartRateLandsInAZone() {
        #expect(zones.zone(for: 40) == 1)
        #expect(zones.zone(for: 90) == 1)
        #expect(zones.zone(for: 91) == 2)
        #expect(zones.zone(for: 114) == 2)
        #expect(zones.zone(for: 115) == 3)
        #expect(zones.zone(for: 139) == 4)
        #expect(zones.zone(for: 164) == 5)
        #expect(zones.zone(for: 220) == 5)
    }

    /// The marker under the band. The outer zones are open-ended and are
    /// given the width of their neighbour, so a marker pinned to one edge for
    /// every rate outside the middle would say less than nothing.
    @Test func theMarkerSitsSomewhereInsideItsZone() {
        for bpm in [40, 70, 95, 120, 150, 170, 210] {
            let zone = zones.zone(for: bpm)
            let fraction = zones.fraction(forBeatsPerMinute: bpm, inZone: zone)
            #expect(fraction >= 0 && fraction <= 1, "\(bpm) bpm put the marker at \(fraction)")
        }
    }

    @Test func theMarkerRisesThroughAZoneRatherThanJumping() {
        let low = zones.fraction(forBeatsPerMinute: 116, inZone: 3)
        let high = zones.fraction(forBeatsPerMinute: 138, inZone: 3)

        #expect(low < high)
    }

    /// Shown under the band because there was no way to tell Apple's own
    /// boundaries from the app's estimate, and a ride that showed zone 4 at
    /// 128 bpm could have been either.
    @Test func theBandSaysWhoseBoundariesItIsDrawing() {
        #expect(zones.summary.contains("91·115·139·164"))
        #expect(zones.summary.hasPrefix(ZoneSource.manual.label))
    }
}
