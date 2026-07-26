import Foundation

// MARK: - Strength statistics
//
// Pure computation: no SwiftUI, no SwiftData. Everything here takes plain
// values and returns plain values, so it can be unit-tested, reused by a future
// regression model, and run off the main actor without touching model objects.
//
// The chain, for one exercise:
//   sets (weight, reps)  →  1RM per set  →  m1RM (best of the session)
//                        →  sessions over time  →  linear fit  →  trend
//
// "m1RM" (the best estimated one-rep max among a session's sets) is the
// strength metric the graphs and the progress ranking are built on.

// MARK: - 1RM formulas

/// How an estimated one-rep max is derived from a set of `reps` at `weight`.
/// The user picks one in settings; it changes every number in this file, so a
/// value is always carried explicitly rather than read from defaults down here.
enum OneRMFormula: String, Codable, CaseIterable, Identifiable {
    case epley
    case brzycki
    case lombardi

    var id: String { rawValue }

    var label: String {
        switch self {
        case .epley:    return "Epley"
        case .brzycki:  return "Brzycki"
        case .lombardi: return "Lombardi"
        }
    }

    var formulaText: String {
        switch self {
        case .epley:    return "w × (1 + r/30)"
        case .brzycki:  return "w / (1.0278 − 0.0278 × r)"
        case .lombardi: return "w × r^0.1"
        }
    }

    /// Estimated one-rep max, or nil when the set carries no information
    /// (no reps, or no weight — a bodyweight set has no load to extrapolate).
    ///
    /// Two guards matter:
    ///   • r == 1 is returned as w by every formula. Epley would otherwise say
    ///     w × 1.033 for a set that IS a one-rep max, overstating it by 3%.
    ///   • Brzycki's denominator reaches zero at r ≈ 37 and goes negative above
    ///     it, which would produce a huge or negative "max" from a long light
    ///     set. Above the usable range it is not evaluated.
    func estimate(weight: Double, reps: Int) -> Double? {
        guard reps >= 1, weight > 0 else { return nil }
        if reps == 1 { return weight }
        let r = Double(reps)
        switch self {
        case .epley:
            return weight * (1 + r / 30)
        case .brzycki:
            let denominator = 1.0278 - 0.0278 * r
            guard denominator > 0.05 else { return nil }   // r ≲ 35
            return weight / denominator
        case .lombardi:
            return weight * pow(r, 0.1)
        }
    }
}

// MARK: - One set, one session

/// A single logged set and what it implies about strength.
struct SetStat: Hashable {
    let weight: Int
    let reps: Int
    /// Estimated 1RM for this set alone; nil when the set is uninformative.
    let oneRM: Double?
    /// True when this set is at or near the session's best effort — see
    /// `ExerciseSession.hardSetCount` for the rule.
    let isHard: Bool
}

/// One occurrence of one exercise inside one workout: all its sets, plus the
/// derived strength metric for that day.
struct ExerciseSession: Identifiable, Hashable {
    let id: UUID
    let date: Date
    let sets: [SetStat]
    /// Best estimated 1RM among the sets — the strength metric that is tracked.
    let m1RM: Double
    /// How many sets counted as hard. Not shown as a headline number, but kept
    /// because it is the natural volume-of-hard-work covariate for the
    /// regression work planned later.
    var hardSetCount: Int { sets.filter(\.isHard).count }

    /// Build a session from raw logged weights/reps.
    ///
    /// A set is *hard* when it is the best set of the session, or when four
    /// more reps at the same weight would have matched that best set — i.e. it
    /// was taken close enough to the limit to count as real work. Sets further
    /// away than that are warm-ups or back-offs and are not counted.
    ///
    /// Returns nil when no set in the log yields a usable 1RM, so callers never
    /// have to reason about an "empty" session.
    init?(id: UUID, date: Date, weights: [Int], reps: [Int], formula: OneRMFormula) {
        let pairs = zip(weights, reps).map { ($0, $1) }
        let estimates = pairs.map { formula.estimate(weight: Double($0.0), reps: $0.1) }
        guard let best = estimates.compactMap({ $0 }).max() else { return nil }

        // Floating-point slack: a set that ties the best must not fail the
        // comparison because of rounding in the formula.
        let epsilon = best * 1e-9
        self.sets = zip(pairs, estimates).map { pair, estimate in
            let isBest = estimate.map { $0 >= best - epsilon } ?? false
            let reachesBest = formula
                .estimate(weight: Double(pair.0), reps: pair.1 + 4)
                .map { $0 >= best - epsilon } ?? false
            return SetStat(weight: pair.0, reps: pair.1,
                           oneRM: estimate, isHard: isBest || reachesBest)
        }
        self.id = id
        self.date = date
        self.m1RM = best
    }
}

// MARK: - Linear fit

/// Ordinary least squares of `y` on time, with time measured in days from the
/// first point so the slope reads as "units per day" rather than "per second".
struct LinearFit: Hashable {
    let slopePerDay: Double
    let intercept: Double
    /// Time origin the intercept is relative to.
    let origin: Date

    func value(at date: Date) -> Double {
        intercept + slopePerDay * date.timeIntervalSince(origin) / 86_400
    }

    /// nil when the points are too few, or all on one day — a vertical spread
    /// of dates with no horizontal spread has no defined slope.
    init?(points: [(date: Date, value: Double)]) {
        guard points.count >= 2, let origin = points.map(\.date).min() else { return nil }
        let xs = points.map { $0.date.timeIntervalSince(origin) / 86_400 }
        let ys = points.map(\.value)
        let n = Double(points.count)
        let meanX = xs.reduce(0, +) / n
        let meanY = ys.reduce(0, +) / n
        let varianceX = xs.reduce(0) { $0 + ($1 - meanX) * ($1 - meanX) }
        guard varianceX > 0 else { return nil }
        let covariance = zip(xs, ys).reduce(0) { $0 + ($1.0 - meanX) * ($1.1 - meanY) }
        self.slopePerDay = covariance / varianceX
        self.intercept = meanY - (covariance / varianceX) * meanX
        self.origin = origin
    }
}

// MARK: - Per-exercise statistics

/// Everything the graphs and the progress list need for one exercise.
struct ExerciseStats: Identifiable {
    let id: UUID                 // exercise id
    let name: String
    /// Sessions used for the statistics: the most recent `window`, oldest first.
    let sessions: [ExerciseSession]
    /// Total sessions on record, which may exceed `sessions.count`.
    let totalSessions: Int
    let fit: LinearFit?
    /// Slope divided by the mean strength metric: relative change per day.
    /// nil when there is no fit or the mean is zero.
    let trendPerDay: Double?

    /// The same trend expressed per week, which is the scale people actually
    /// think in. Presented as a percentage by the UI.
    var trendPerWeek: Double? { trendPerDay.map { $0 * 7 } }

    /// Points to draw: either the raw metric or a centred moving average.
    let plotPoints: [(date: Date, value: Double)]

    /// Minimum sessions before any statistics are shown.
    static let minimumSessions = 8
}

// MARK: - Engine

enum StatsEngine {

    /// Default user options.
    static let defaultWindow = 16          // sessions used for the regression
    static let defaultSmoothing = 3        // moving-average width (odd)
    static let smoothingChoices = [1, 3, 5, 7, 9]

    /// A logged row, flattened away from SwiftData so this stays testable.
    struct LogInput {
        let id: UUID
        let exerciseId: UUID
        let date: Date
        let weights: [Int]
        let reps: [Int]

        init(id: UUID, exerciseId: UUID, date: Date, weights: [Int], reps: [Int]) {
            self.id = id
            self.exerciseId = exerciseId
            self.date = date
            self.weights = weights
            self.reps = reps
        }
    }

    /// Statistics for every exercise that has enough history, ordered from
    /// lowest (worst) to highest (best) trend — the order the progress list
    /// wants, so the exercises needing attention come first.
    ///
    /// Exercises without a computable trend sort last: "no trend yet" is not a
    /// bad trend, and putting them at the top would bury the real findings.
    static func analyze(logs: [LogInput],
                        names: [UUID: String],
                        formula: OneRMFormula,
                        window: Int,
                        smoothing: Int) -> [ExerciseStats] {

        let grouped = Dictionary(grouping: logs, by: \.exerciseId)

        let stats: [ExerciseStats] = grouped.compactMap { exerciseId, rows in
            let sessions = rows
                .sorted { $0.date < $1.date }
                .compactMap {
                    ExerciseSession(id: $0.id, date: $0.date,
                                    weights: $0.weights, reps: $0.reps,
                                    formula: formula)
                }
            guard sessions.count >= ExerciseStats.minimumSessions else { return nil }

            let recent = Array(sessions.suffix(max(ExerciseStats.minimumSessions, window)))
            let raw = recent.map { (date: $0.date, value: $0.m1RM) }
            let fit = LinearFit(points: raw)
            let mean = raw.map(\.value).reduce(0, +) / Double(raw.count)
            let trend = (fit != nil && mean > 0) ? fit!.slopePerDay / mean : nil

            return ExerciseStats(
                id: exerciseId,
                name: names[exerciseId] ?? "(deleted exercise)",
                sessions: recent,
                totalSessions: sessions.count,
                fit: fit,
                trendPerDay: trend,
                plotPoints: movingAverage(raw, width: smoothing)
            )
        }

        return stats.sorted { a, b in
            switch (a.trendPerDay, b.trendPerDay) {
            case let (x?, y?): return x < y
            case (nil, _?):    return false
            case (_?, nil):    return true
            case (nil, nil):   return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
        }
    }

    /// Centred moving average over `width` points (odd; 1 means no smoothing).
    /// Each output point sits at the *middle date* of the points it averages,
    /// so a smoothed dot is placed at the time it actually describes rather
    /// than at the end of its window.
    ///
    /// With fewer points than the window, the series is returned unsmoothed —
    /// better a truthful sparse graph than an empty one.
    static func movingAverage(_ points: [(date: Date, value: Double)],
                              width: Int) -> [(date: Date, value: Double)] {
        let w = max(1, width % 2 == 0 ? width - 1 : width)
        guard w > 1, points.count >= w else { return points }
        let half = w / 2
        return (half..<(points.count - half)).map { i in
            let slice = points[(i - half)...(i + half)]
            let mean = slice.map(\.value).reduce(0, +) / Double(w)
            return (date: points[i].date, value: mean)
        }
    }
}
