import Foundation

// MARK: - Heart rate zones
//
// A byte-identical copy of this file lives in the Watch App target
// ("workout_aicode Watch App/HeartRateZones.swift"), like WatchSync.swift and
// BuildStamp.swift. Keep them the same.
//
// THIS IS A STAND-IN, and the seam is the point of it.
//
// From OS 27 HealthKit hands over the real thing:
// `HKHealthStore.preferredWorkoutZoneConfiguration(for:)` returns the very
// configuration the Apple Workout app is using — automatic or custom,
// whichever is active in Settings — and `HKWorkoutZoneGroup` carries the
// time-in-zone for a finished workout, so none of the arithmetic below is
// needed there. That SDK is beta and not installed, so this computes zones the
// way Apple documents its automatic ones, from heart rate reserve.
//
// Expect the numbers to be close but not identical to what the Watch shows:
// Apple uses a *measured* maximum from your history, which no API exposes, and
// anyone can override the boundaries by hand. Nothing here should ever claim to
// BE the Workout app's zones — see `ZoneSource`.

/// Where a set of zone boundaries came from, so the interface can be honest
/// about it rather than implying more precision than it has.
enum ZoneSource: String {
    /// Worked out here from resting and maximum heart rate.
    case estimated
    /// Read from HealthKit — the same zones the Workout app uses. Not reachable
    /// until the app is built against the OS 27 SDK; the case exists so the
    /// call sites are already written for it.
    case healthKit
}

struct HeartRateZones: Equatable {
    /// The four thresholds between the five zones, in beats per minute: the top
    /// of zone 1, of zone 2, of zone 3 and of zone 4.
    ///
    /// Four, not five, and that is the whole shape of it. Zone 1 has no floor —
    /// it is everything below the zone 2 threshold, which is why the Workout
    /// app describes it as "under 90" rather than as a range. An earlier
    /// version here gave zone 1 a bottom too and invented a "below zone 1"
    /// underneath it, so a resting heart rate at the start of a ride lit
    /// nothing at all and the band sat empty while the number ticked along.
    let boundaries: [Int]
    let restingHeartRate: Int
    let maximumHeartRate: Int
    let source: ZoneSource

    static let zoneCount = 5

    /// Where the four thresholds fall as fractions of heart rate reserve.
    /// Everything under the first is zone 1; everything over the last is zone 5.
    static let reserveFractions: [Double] = [0.5, 0.6, 0.7, 0.8]

    /// Rough maximum for someone of this age, the textbook 220 − age.
    ///
    /// Only a starting point: real maxima vary by a good ten beats either way,
    /// which is exactly why Apple prefers a measured one. Used when a birth
    /// date is available; otherwise `defaultMaximum`.
    static func estimatedMaximum(forAge age: Int) -> Int {
        max(100, min(220, 220 - age))
    }

    /// For when there is no birth date to work from — roughly a forty-year-old.
    static let defaultMaximum = 180
    /// For when there is no resting rate on record.
    static let defaultResting = 60

    init(restingHeartRate: Int = defaultResting,
         maximumHeartRate: Int = defaultMaximum,
         source: ZoneSource = .estimated) {
        // A maximum at or below resting would put every boundary on top of the
        // next and make "which zone" meaningless, so it is nudged apart rather
        // than trusted. Bad inputs here come from an empty Health database, not
        // from anything the user did wrong.
        let resting = max(30, min(restingHeartRate, 120))
        let maximum = max(resting + 30, min(maximumHeartRate, 230))
        let reserve = Double(maximum - resting)
        self.restingHeartRate = resting
        self.maximumHeartRate = maximum
        self.source = source
        self.boundaries = Self.reserveFractions.map {
            Int((Double(resting) + reserve * $0).rounded())
        }
    }

    /// Which zone a heart rate falls in: always 1...5.
    ///
    /// Never optional. Every heart rate is in a zone — a slow one is in zone 1,
    /// which is what zone 1 is for.
    func zone(for beatsPerMinute: Int) -> Int {
        var zone = 1
        for boundary in boundaries where beatsPerMinute >= boundary { zone += 1 }
        return zone
    }

    /// Where within its zone a heart rate sits, 0 at the bottom and 1 at the
    /// top — what the marker under the band points at.
    ///
    /// The outer two zones are open-ended, so each is given the width of its
    /// neighbour: a marker pinned to one edge for every rate outside the middle
    /// would say less than nothing. Zone 1 is measured from the resting rate,
    /// which is the lowest it is going to get in practice.
    func fraction(forBeatsPerMinute bpm: Int, inZone zone: Int) -> Double {
        guard let range = range(forZone: zone) else { return 0 }
        let lower = range.lower ?? restingHeartRate
        let upper = range.upper ?? (lower + typicalZoneWidth)
        let width = max(1, upper - lower + 1)
        return min(1, max(0, Double(bpm - lower) / Double(width)))
    }

    /// How wide a middle zone is, used to give the open-ended ones a size.
    private var typicalZoneWidth: Int {
        guard boundaries.count >= 2 else { return 20 }
        return max(1, boundaries[1] - boundaries[0])
    }

    /// The range shown for a zone. Zone 1 has no lower bound and zone 5 no
    /// upper one — there is always a little less, and always a little more.
    func range(forZone zone: Int) -> (lower: Int?, upper: Int?)? {
        guard zone >= 1, zone <= Self.zoneCount else { return nil }
        let lower = zone == 1 ? nil : boundaries[zone - 2]
        let upper = zone == Self.zoneCount ? nil : boundaries[zone - 1] - 1
        return (lower, upper)
    }
}

// MARK: - Adding up the time

/// Accumulates seconds per zone from a stream of heart-rate readings.
///
/// Each reading is credited with the time since the one before it, which is
/// what makes the totals independent of how often the Watch happens to sample —
/// counting readings instead would make a dense stretch look longer than a
/// sparse one of the same duration.
struct ZoneTally {
    let zones: HeartRateZones
    /// Seconds in each of the five zones, lowest first. There is nowhere else
    /// for time to go: every heart rate is in a zone, and a slow one is in
    /// zone 1.
    private(set) var seconds = [Int](repeating: 0, count: HeartRateZones.zoneCount)
    private var last: (date: Date, zone: Int?)?


    init(zones: HeartRateZones) {
        self.zones = zones
    }

    /// A reading is credited to the zone it was IN for the interval leading up
    /// to it, so a jump between zones does not backdate the new one over time
    /// spent in the old.
    mutating func add(beatsPerMinute: Int, at date: Date) {
        add(zone: zones.zone(for: beatsPerMinute), at: date)
    }

    /// The same, for a zone worked out elsewhere.
    ///
    /// The phone takes this route: the Watch sends the zone alongside the beat
    /// count, because the Watch is the one with permission to read the resting
    /// rate and date of birth the boundaries are drawn from. Classifying again
    /// on the phone from default boundaries would quietly disagree with the
    /// wrist about which zone the same beat was in.
    mutating func add(zone: Int?, at date: Date) {
        defer { last = (date, zone) }
        guard let previous = last else { return }
        let elapsed = Int(date.timeIntervalSince(previous.date).rounded())
        // A gap this long means the watch stopped reporting — the wrist was
        // down, or the app was asleep. Guessing what happened in between would
        // be inventing data.
        guard elapsed > 0, elapsed <= 60 else { return }
        // An unknown zone can only mean a reading that never arrived, so there
        // is nothing to credit it to.
        guard let zone = previous.zone,
              zone >= 1, zone <= HeartRateZones.zoneCount else { return }
        seconds[zone - 1] += elapsed
    }

    var totalCountedSeconds: Int { seconds.reduce(0, +) }
}
