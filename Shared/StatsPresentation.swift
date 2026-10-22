import SwiftUI
import SwiftData

// MARK: - Turning stored logs into statistics
//
// StatsEngine is pure arithmetic over plain values. This is the thin layer
// between it and the database: it reads the user's options, flattens SwiftData
// rows into the engine's inputs, and formats what comes back.
//
// It lives in Shared because the phone and the Mac must never disagree about
// what a trend is. Two copies of "which formula, over how many sessions" is two
// answers to the same question, on the same data, in the same account.

enum StatsSettingsKey {
    static let formula   = "oneRMFormula"
    static let window    = "trendWindow"
    static let smoothing = "graphSmoothing"
}

/// Reads the user's options and turns stored logs into `ExerciseStats`.
/// Kept in one place so the graphs screen and the progress screen can never
/// disagree about what the numbers are.
struct StatsInputs {
    let formula: OneRMFormula
    let window: Int
    let smoothing: Int

    init(formulaRaw: String, window: Int, smoothing: Int) {
        self.formula = OneRMFormula(rawValue: formulaRaw) ?? .epley
        self.window = max(ExerciseStats.minimumSessions, window)
        self.smoothing = smoothing
    }

    /// `weightsByLog` is the grams for each log — see `LogWeightsIndex`.
    ///
    /// Everything downstream of here is therefore in grams: the estimates, the
    /// trends per week, the best-ever numbers. They are converted to the
    /// user's unit where they are written on screen, and nowhere else. A log
    /// with no grams yet — one from before weights had a unit, not yet filled
    /// in — is left out rather than read as if it were kilograms.
    func analyze(logs: [WorkoutLog], exercises: [ExerciseDef],
                 weightsByLog: [UUID: [Int]]) -> [ExerciseStats] {
        let names = Dictionary(exercises.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        let inputs = logs.compactMap { log -> StatsEngine.LogInput? in
            guard let grams = weightsByLog[log.id], !grams.isEmpty else { return nil }
            return StatsEngine.LogInput(id: log.id, exerciseId: log.exerciseId, date: log.date,
                                        weights: grams, reps: log.reps)
        }
        return StatsEngine.analyze(logs: inputs, names: names,
                                   formula: formula, window: window, smoothing: smoothing)
    }

    /// Exercises that are still short of the 8 sessions needed, with how many
    /// they have — so the UI can say which graphs are still coming.
    func pending(logs: [WorkoutLog], exercises: [ExerciseDef]) -> [(name: String, count: Int)] {
        let counts = Dictionary(grouping: logs, by: \.exerciseId).mapValues(\.count)
        return exercises
            .compactMap { exercise in
                let n = counts[exercise.id] ?? 0
                guard n > 0, n < ExerciseStats.minimumSessions else { return nil }
                return (name: exercise.name, count: n)
            }
            .sorted { $0.count > $1.count }
    }
}

/// A computed weight — a one-rep-max estimate, a best — as the user reads it.
///
/// Everything the statistics produce is in grams, because everything they are
/// computed from is. Trends are percentages and need none of this; absolute
/// numbers do.
func displayWeight(_ grams: Double, in unit: WeightUnit = .current) -> Double {
    unit.display(grams: Int(grams.rounded()))
}

/// Formats a trend as a percentage per week, the scale people plan in.
func formatTrend(_ perWeek: Double?) -> String {
    guard let perWeek else { return "—" }
    return String(format: "%+.1f%%/week", perWeek * 100)
}

func trendColor(_ perWeek: Double?) -> Color {
    guard let perWeek else { return .secondary }
    if perWeek > 0.002 { return .green }
    if perWeek < -0.002 { return .red }
    return .primary
}

// MARK: - Reading one logged row against the one before it

/// The green/red in a log list: did this set go up or down since last time?
///
/// Shared because it is a claim about the user's training, not a decoration. A
/// Mac that coloured the same two rows differently from the phone would be
/// telling one of two contradictory stories about the same workout.
enum LogComparison {

    /// The most recent earlier log of the same exercise.
    ///
    /// `logs` must be sorted newest first, which is how both screens query it.
    static func previous(for exerciseId: UUID, before date: Date,
                         in logs: [WorkoutLog]) -> WorkoutLog? {
        logs.first { $0.date < date && $0.exerciseId == exerciseId }
    }

    /// How much a weight may differ before the difference is worth colouring:
    /// half the exercise's own increment.
    ///
    /// On an ordinary machine this changes nothing — weights move by whole
    /// increments, so any real change clears half of one. It exists for the
    /// assisted machines, where the weight logged is BODY WEIGHT minus the
    /// setting: step on the scale a kilo heavier and every set of an assisted
    /// chin-up turns green, though nothing about the training changed. Half an
    /// increment is the line between "you did something different" and "you
    /// had breakfast".
    static func tolerance(forIncrement increment: Int) -> Double {
        Double(max(1, increment)) / 2
    }

    /// More weight is progress, less is not. No previous entry is neither.
    ///
    /// `increment` is the exercise's weight increment; a difference of half of
    /// it or less is left uncoloured. Passing nothing keeps the old exact
    /// comparison, which is what a caller without the exercise to hand gets.
    static func weightColour(current: Int, previous: Int?,
                             increment: Int? = nil) -> Color {
        guard let previous else { return .primary }
        let margin = increment.map(tolerance(forIncrement:)) ?? 0
        let difference = Double(current - previous)
        if difference > margin { return .green }
        if difference < -margin { return .red }
        return .primary
    }

    /// Reps only count as progress if the weight did not drop to buy them —
    /// two more reps at ten kilos less is not a better set, and colouring it
    /// green would be flattery rather than information.
    ///
    /// The same margin applies to that weight comparison: a kilo of body
    /// weight must not take the colour off an extra repetition.
    static func repsColour(current: Int, previous: Int?,
                           currentWeight: Int, previousWeight: Int?,
                           increment: Int? = nil) -> Color {
        guard let previous else { return .primary }
        let margin = increment.map(tolerance(forIncrement:)) ?? 0
        let prevWeight = previousWeight ?? currentWeight
        let weightDifference = Double(currentWeight - prevWeight)
        if current > previous && weightDifference >= -margin { return .green }
        if current < previous && weightDifference <= margin { return .red }
        return .primary
    }
}

// MARK: - Grouping logs into workout sessions

/// Consecutive logs belong to the same session when they are from the same
/// workout and close together in time. An hour's gap starts a new one: people
/// do the same workout twice in a week, and running the two together would
/// read as one impossibly long session.
enum LogSessions {
    static let maximumGap: TimeInterval = 3600

    struct Session: Identifiable {
        let id: String
        let workoutId: UUID
        let workoutName: String
        let date: Date
        let logs: [WorkoutLog]
    }

    /// `logs` newest first, as queried; sessions come back in the same order.
    static func group(_ logs: [WorkoutLog], workoutNames: [UUID: String]) -> [Session] {
        var sessions: [Session] = []
        var current: [WorkoutLog] = []

        func flush() {
            guard let first = current.first else { return }
            sessions.append(Session(id: "s-\(first.id.uuidString)",
                                    workoutId: first.workoutId,
                                    workoutName: workoutNames[first.workoutId] ?? "Workout",
                                    date: first.date,
                                    logs: current))
            current = []
        }

        for log in logs {
            if let last = current.last,
               last.date.timeIntervalSince(log.date) < maximumGap,
               last.workoutId == log.workoutId {
                current.append(log)
            } else {
                flush()
                current = [log]
            }
        }
        flush()
        return sessions
    }
}
