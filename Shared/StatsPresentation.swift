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
    ///
    /// `nonisolated` because it is arithmetic on an Int and nothing more, and
    /// because it is passed by name to `map` below — a function VALUE, which
    /// carries no actor with it, so an isolated one cannot be handed over.
    nonisolated static func tolerance(forIncrement increment: Int) -> Double {
        Double(max(1, increment)) / 2
    }

    /// More weight is progress only if the reps did not drop to buy it. No
    /// previous entry is neither.
    ///
    /// THE SAME RULE AS `repsColour`, READ THE OTHER WAY ROUND, and it did not
    /// used to be. Weight was coloured on the weight alone, so a set of
    /// butterfly done at more weight for fewer reps than the week before came
    /// up green on the weight and uncoloured on the reps — the screen
    /// announcing an improvement that the two numbers together do not support.
    /// Found in a real log, 9 to 16 November 2026.
    ///
    /// Green means the number in question went up and the other one did not go
    /// down; red means it went down and the other one did not go up. Anything
    /// else — a trade, either way round — is left uncoloured, because which
    /// side of it came out ahead is not this screen's to decide.
    ///
    /// `increment` is the exercise's weight increment; a difference of half of
    /// it or less is left uncoloured. Passing nothing keeps the old exact
    /// comparison, which is what a caller without the exercise to hand gets.
    /// It applies to the weight only: reps are counted, not measured, and one
    /// of them is always worth something.
    static func weightColour(current: Int, previous: Int?,
                             currentReps: Int, previousReps: Int?,
                             increment: Int? = nil) -> Color {
        guard let previous else { return .primary }
        let margin = increment.map(tolerance(forIncrement:)) ?? 0
        let difference = Double(current - previous)
        // A missing counterpart reads as unchanged, which is the same thing
        // `repsColour` does with a missing weight: it is the reading that lets
        // the number in question speak for itself.
        let prevReps = previousReps ?? currentReps
        if difference > margin && currentReps >= prevReps { return .green }
        if difference < -margin && currentReps <= prevReps { return .red }
        return .primary
    }

    /// Reps only count as progress if the weight did not drop to buy them —
    /// two more reps at ten kilos less is not a better set, and colouring it
    /// green would be flattery rather than information. `weightColour` is this
    /// same rule the other way round; the two must stay each other's mirror.
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

    /// How a log list is ordered. By date it is the session or the last time
    /// the exercise was done; by name it is the workout's or the exercise's.
    enum Order: String, CaseIterable, Identifiable {
        case newestFirst, oldestFirst, nameAZ, nameZA
        var id: String { rawValue }

        var isByDate: Bool { self == .newestFirst || self == .oldestFirst }

        /// The order a heading moves to when it is clicked: clicking the one
        /// already in use reverses it, clicking the other starts at its own
        /// natural end — newest first for a date, A to Z for a name.
        func clickingDate() -> Order { self == .newestFirst ? .oldestFirst : .newestFirst }
        func clickingName() -> Order { self == .nameAZ ? .nameZA : .nameAZ }
    }

    static func ordered(_ sessions: [Session], by order: Order) -> [Session] {
        switch order {
        case .newestFirst: return sessions.sorted { $0.date > $1.date }
        case .oldestFirst: return sessions.sorted { $0.date < $1.date }
        case .nameAZ: return sessions.sorted { compare($0.workoutName, $1.workoutName, ascending: true) }
        case .nameZA: return sessions.sorted { compare($0.workoutName, $1.workoutName, ascending: false) }
        }
    }

    static func ordered(_ histories: [ExerciseHistory], by order: Order) -> [ExerciseHistory] {
        switch order {
        case .newestFirst: return histories.sorted { $0.lastLogged > $1.lastLogged }
        case .oldestFirst: return histories.sorted { $0.lastLogged < $1.lastLogged }
        case .nameAZ: return histories.sorted { compare($0.name, $1.name, ascending: true) }
        case .nameZA: return histories.sorted { compare($0.name, $1.name, ascending: false) }
        }
    }

    /// Names compared the way a person reads them, so "abs" and "Abs" sort
    /// together and "Exercise 10" comes after "Exercise 9".
    private static func compare(_ a: String, _ b: String, ascending: Bool) -> Bool {
        let result = a.localizedStandardCompare(b)
        guard result != .orderedSame else { return false }
        return ascending ? result == .orderedAscending : result == .orderedDescending
    }

    /// Narrows a log list by typed text and by date.
    ///
    /// The text matches the way somebody typing half a name expects it to: the
    /// ROWS are reduced to the exercises whose names contain it, not merely
    /// the sessions that happen to hold one. Filtering sessions while still
    /// listing every exercise inside them is what the Mac used to do, and it
    /// read as the field doing nothing at all — type "assisted chin up", and
    /// if that exercise is in most sessions, almost nothing disappears and
    /// every session still shows its whole contents.
    ///
    /// A WORKOUT name is the exception and keeps its session whole. Asking for
    /// "PF B" is asking for that workout, and answering with a workout
    /// stripped of its exercises would be a strange reading of the question.
    ///
    /// Dates are inclusive and by the day, not the instant: `to` of the 17th
    /// means everything up to the end of the 17th, because that is what
    /// picking a date on a calendar means.
    static func matching(_ sessions: [Session], text: String = "",
                         exerciseNames: [UUID: String] = [:],
                         from: Date? = nil, to: Date? = nil,
                         calendar: Calendar = .current) -> [Session] {
        let needle = text.trimmingCharacters(in: .whitespaces).lowercased()
        let start = from.map { calendar.startOfDay(for: $0) }
        let end = to.flatMap {
            calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: $0))
        }

        return sessions.compactMap { session in
            if let start, session.date < start { return nil }
            if let end, session.date >= end { return nil }
            guard !needle.isEmpty else { return session }

            if Self.name(session.workoutName, matches: needle) { return session }

            let kept = session.logs.filter {
                Self.name(exerciseNames[$0.exerciseId] ?? "", matches: needle)
            }
            guard !kept.isEmpty else { return nil }
            return Session(id: session.id, workoutId: session.workoutId,
                           workoutName: session.workoutName,
                           date: session.date, logs: kept)
        }
    }

    /// One exercise and every time it was logged, newest first.
    ///
    /// The other way of reading a log. Grouping by session answers "what did I
    /// do that day"; this answers "when do I do this, and what was it last
    /// time", which is the question somebody has while standing in front of a
    /// machine wondering whether to add five pounds.
    struct ExerciseHistory: Identifiable {
        let id: String
        let exerciseId: UUID
        let name: String
        /// Newest first, like everything else in this app's log reading.
        let entries: [Entry]

        struct Entry: Identifiable {
            let id: String
            let log: WorkoutLog
            let workoutName: String
            var date: Date { log.date }
        }

        var mostRecent: Entry? { entries.first }
        var lastLogged: Date { entries.first?.date ?? .distantPast }
    }

    /// Turns sessions inside out: the same logs, gathered by exercise.
    ///
    /// Takes already-filtered sessions, so the exercise list narrows with the
    /// same typing and the same dates as the session list — one filter, two
    /// ways of looking at what it left.
    static func byExercise(_ sessions: [Session],
                           exerciseNames: [UUID: String]) -> [ExerciseHistory] {
        var entries: [UUID: [ExerciseHistory.Entry]] = [:]
        for session in sessions {
            for log in session.logs {
                entries[log.exerciseId, default: []].append(
                    ExerciseHistory.Entry(id: log.id.uuidString, log: log,
                                          workoutName: session.workoutName))
            }
        }
        return entries.map { exerciseId, list in
            ExerciseHistory(id: exerciseId.uuidString,
                            exerciseId: exerciseId,
                            name: exerciseNames[exerciseId] ?? "",
                            entries: list.sorted { $0.date > $1.date })
        }
        .sorted { $0.lastLogged > $1.lastLogged }
    }

    /// Whether a name answers to what was typed.
    ///
    /// By WORDS, not by raw substring, and a real exercise list is the reason:
    /// "Machine bench press" contains the letters of "chin" — ma-CHIN-e — so a
    /// plain `contains` answers a search for the chin-up with the bench press.
    /// Found by a test that expected two sessions and got three, which is a
    /// better way to find it than from a user wondering why their filter is
    /// full of nonsense.
    ///
    /// So a single word matches where some word in the name STARTS with it:
    /// "chin" finds "Assisted chin up" and not the bench press, "press" finds
    /// both the leg press and the bench press. Anything with a space in it is
    /// matched against the whole name instead, since by then the typing is
    /// specific enough to mean what it says — and typing a full name, which is
    /// what somebody does first, has to work.
    static func name(_ name: String, matches needle: String) -> Bool {
        guard !needle.isEmpty else { return true }
        let haystack = name.lowercased()
        if needle.contains(" ") { return haystack.contains(needle) }
        return haystack
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .contains { $0.hasPrefix(needle) }
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
