#if DEBUG
import Foundation
import SwiftData

// MARK: - DemoMode (App Store screenshots)
//
// Drives the app from launch arguments so `tools/make-screenshots.sh` can reach
// each screen with believable sample data:
//
//   -SRWDemo               seed an IN-MEMORY store with sample workouts + history
//   -SRWScreen <name>      open a screen: log | logs | info | settings
//
// DEBUG-only, so none of this can ship. The in-memory store matters: screenshots
// never touch (or risk) the real data on the device they run on.

enum DemoMode {

    static var isEnabled: Bool { CommandLine.arguments.contains("-SRWDemo") }

    /// Value passed after `-SRWScreen`, if any.
    static var screen: String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "-SRWScreen"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    /// An in-memory container holding a realistic-looking training history.
    static func makeContainer() -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        // swiftlint:disable:next force_try
        let container = try! ModelContainer(
            for: WorkoutDef.self, ExerciseDef.self, WorkoutLog.self,
            configurations: config
        )
        seed(into: container.mainContext)
        return container
    }

    // MARK: - Sample data

    /// name, sets, lowest, highest, increment, weights, reps, primary muscle,
    /// library key (nil for an exercise the "user" invented)
    private typealias Row = (String, Int, Int, Int, Int, [Int], [Int], MuscleGroup, String?)

    private static let upperBody: [Row] = [
        ("Lats pull down",     3, 20, 120, 5, [50, 55, 55], [12, 10, 8], .back,       "lat-pulldown"),
        ("Chest press",        3, 20, 120, 5, [40, 45, 45], [12, 10, 8], .chest,      "incline-press"),
        ("Seated row",         3, 20, 120, 5, [45, 50, 50], [12, 10, 9], .back,       "seated-row"),
        ("Shoulder press",     3, 10,  80, 5, [30, 35, 35], [10,  9, 8], .frontDelts, "overhead-press"),
        ("Biceps curl",        3, 10,  60, 5, [25, 30, 30], [12, 10, 8], .biceps,     "biceps-curl"),
        ("Triceps pushdown",   3, 10,  60, 5, [30, 30, 35], [12, 10, 8], .triceps,    "triceps-pushdown"),
        ("Abs crunch machine", 2, 10,  80, 5, [40, 45],     [15, 12],    .absCore,    nil),
    ]

    private static let lowerBody: [Row] = [
        ("Leg press",     3, 40, 250, 10, [120, 140, 140], [12, 10, 8],  .quads,      "leg-press"),
        ("Leg extension", 3, 20, 120,  5, [ 45,  50,  50], [12, 10, 8],  .quads,      "leg-extension"),
        ("Leg curl",      3, 20, 120,  5, [ 40,  45,  45], [12, 10, 8],  .hamstrings, "leg-curl"),
        ("Calf raise",    3, 20, 150,  5, [ 70,  80,  80], [15, 12, 12], .calves,     "calf-raise"),
    ]

    private static func seed(into ctx: ModelContext) {
        let upper = build("Upper body", upperBody, sortIndex: 0, into: ctx)
        let lower = build("Leg day", lowerBody, sortIndex: 1, into: ctx)
        // Enough history for the statistics to exist: the graphs and progress
        // tabs need an exercise logged in at least
        // ExerciseStats.minimumSessions workouts before they show anything, so
        // three sessions each (which was plenty for the logs screen) would have
        // photographed two empty screens. The two workouts alternate across the
        // weeks, as a real routine would.
        addHistory(for: upper, upperBody, daysAgo: upperDays, hour: 18, into: ctx)
        addHistory(for: lower, lowerBody, daysAgo: lowerDays, hour: 9, into: ctx)
        try? ctx.save()
    }

    /// Twelve sessions each, roughly weekly. Counted in days ago, so the list
    /// runs DESCENDING: oldest session first, most recent last. addHistory
    /// makes the later entries the heavier ones, and reversing this would
    /// quietly turn every exercise into a decline.
    private static let upperDays: [Int] = (0..<12).map { 79 - $0 * 7 }
    private static let lowerDays: [Int] = (0..<12).map { 75 - $0 * 7 }

    @discardableResult
    private static func build(_ name: String, _ rows: [Row],
                              sortIndex: Int, into ctx: ModelContext) -> WorkoutDef {
        var ids: [UUID] = []
        for r in rows {
            let ex = ExerciseDef(name: r.0, numberOfSeries: r.1,
                                 lowestWeight: r.2, highestWeight: r.3, weightIncrement: r.4,
                                 primaryMuscle: r.7,
                                 secondaryMuscles: r.8.flatMap { ExerciseLibrary.entry(key: $0)?.secondary } ?? [],
                                 libraryKey: r.8)
            ctx.insert(ex)
            ids.append(ex.id)
        }
        let workout = WorkoutDef(name: name, exerciseOrder: ids, sortIndex: sortIndex)
        ctx.insert(workout)
        return workout
    }

    /// Past sessions, generally lighter the further back they go, so the most
    /// recent entries show the green "went up" colouring. `hour` puts each
    /// workout at a plausible time of day rather than whenever the screenshots
    /// happen to run.
    ///
    /// Each exercise progresses at its own rate — one of them slightly
    /// downwards — so the graphs have visibly different slopes and the progress
    /// ranking has something to order. A small repeating wobble in the
    /// repetitions keeps the strength metric off a perfectly straight line,
    /// which a real log never is.
    private static func addHistory(for workout: WorkoutDef, _ rows: [Row],
                                   daysAgo: [Int], hour: Int, into ctx: ModelContext) {
        let cal = Calendar.current
        // Increments gained per session, cycled across the exercises. Kept
        // small: at one weight increment every several sessions these come out
        // near 1%/week, which is what steady progress actually looks like.
        // The last one declines, so the demo shows a losing exercise (and the
        // red styling) alongside the gaining ones.
        let rates: [Double] = [0.15, 0.10, 0.13, 0.06, 0.08, 0.03, -0.12]
        let wobble = [0, 1, -1, 0, 1, -1, 1, 0]

        for (session, days) in daysAgo.enumerated() {
            let stepsBack = Double((daysAgo.count - 1) - session)
            guard let dayStart = cal.date(byAdding: .day, value: -days, to: Date()),
                  let start = cal.date(bySettingHour: hour, minute: 5, second: 0, of: dayStart)
            else { continue }
            for (i, r) in rows.enumerated() {
                let rate = rates[i % rates.count]
                let drop = Int((stepsBack * rate).rounded()) * r.4
                let weights = r.5.map { min(r.3, max(r.2, $0 - drop)) }
                let nudge = wobble[(session + i) % wobble.count]
                let reps = r.6.enumerated().map { idx, rep in
                    max(1, idx == 0 ? rep + nudge : rep)
                }
                let date = start.addingTimeInterval(Double(i) * 240)
                ctx.insert(WorkoutLog(date: date,
                                      workoutId: workout.id,
                                      exerciseId: workout.exerciseOrder[i],
                                      weights: weights,
                                      reps: reps))
            }
        }
    }
}
#endif
