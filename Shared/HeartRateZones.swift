import Foundation

// MARK: - Heart rate zones
//
// In Shared/, so both ends compile the same boundaries: a zone the phone drew
// differently from the Watch would be the same heart rate telling two stories.
//
// THIS IS A STAND-IN, and the seam is the point of it.
//
// From OS 27 HealthKit hands over the real thing, and the app asks for it:
// `HKHealthStore.preferredWorkoutZoneConfiguration(for:)` returns the very
// configuration the Workout app is using — the system's automatic zones, or
// the boundaries the user set by hand in Health, whichever is active. When
// that answers, these zones ARE Apple's and `source` says `.healthKit`.
//
// Two fallbacks, in order. The user's OWN boundaries, typed on the phone, if
// they gave any — which is the only way to agree with the wrist on a Watch
// that cannot run OS 27. Then the arithmetic below, which follows Apple's
// documented automatic zones from heart rate reserve and will not agree
// exactly with a Watch whose maximum was measured from the user's own
// history — which is exactly why reading the real one matters.
//
// The OS 27 requirement is not academic: it needs a Series 9 or later, so a
// Series 6 stays on 26.x for good and never gets the first route at all.
//
// (A note here once claimed this API did not exist, on the strength of a
// search through HealthKit's Objective-C headers. It is declared in the Swift
// interface, which that search never looked at. Grep the .swiftinterface too.)
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
    /// Read from HealthKit — the same zones the Workout app uses. Needs
    /// watchOS 27, and so a Series 9 or later.
    case healthKit
    /// Typed in by the user, on the phone, and sent to the Watch. For the
    /// Watch that cannot have `healthKit`: copying the four numbers out of
    /// Health by hand is tedious but exact, which beats an estimate that is
    /// neither.
    case manual

    /// How to name these on screen, where the whole point is to be honest
    /// about which of the three is in play.
    var label: String {
        switch self {
        case .estimated: return "estimated zones"
        case .healthKit: return "Apple zones"
        case .manual:    return "your zones"
        }
    }
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

    /// Boundaries taken verbatim, for zones that came from Health rather than
    /// being worked out here.
    ///
    /// Nothing is recomputed: these are the numbers the Workout app is using,
    /// and the whole point is that the band agrees with the wrist. Resting and
    /// maximum are carried only so the rest of the type has something to
    /// report; they take no part in deciding a zone.
    init?(boundaries: [Int], restingHeartRate: Int, maximumHeartRate: Int,
          source: ZoneSource) {
        // Five zones, so four thresholds. Health could in principle describe
        // some other number, and a band drawn for five would then be a lie —
        // better to fall back to the estimate than to show the wrong shape.
        guard boundaries.count == Self.zoneCount - 1,
              boundaries == boundaries.sorted(),
              Set(boundaries).count == boundaries.count else { return nil }
        self.boundaries = boundaries
        self.restingHeartRate = restingHeartRate
        self.maximumHeartRate = maximumHeartRate
        self.source = source
    }

    /// The boundaries and where they came from, small enough to sit under the
    /// band: "Apple zones · 91·115·139·164".
    ///
    /// On screen because there was no way to tell the two apart. A ride
    /// showed zone 4 at 128 bpm for someone whose own zone 3 runs 115–138,
    /// and nothing in the app said whether it was reading Apple's boundaries
    /// and getting them wrong, or quietly using its own. The numbers it is
    /// actually using answer that in one glance.
    var summary: String {
        source.label + " · " + boundaries.map(String.init).joined(separator: "·")
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
