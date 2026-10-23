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
//   -SRWSide <name>        which tab the open Duo's left pane shows:
//                          logs | graphs | progress | transfer
//
// DEBUG-only, so none of this can ship. The in-memory store matters: screenshots
// never touch (or risk) the real data on the device they run on.

enum DemoMode {

    static var isEnabled: Bool { CommandLine.arguments.contains("-SRWDemo") }

    /// A screenshot run has its own seeded history, so the question about what
    /// the old numbers meant does not apply to it.
    static func settleWeightUnit() {
        guard isEnabled else { return }
        // The seeded history is in whatever unit the demo is read in, so it
        // needs no question — and says so the way everything else does, by
        // stating the unit rather than by setting a "do not ask" flag.
        UserDefaults.standard.set(WeightUnit.regionDefault.rawValue,
                                  forKey: WeightHistory.statedUnitKey)
    }

    // The rest-timer capture. Fixed numbers so the iPhone and the Watch shots
    // show the same rest, and a remaining time that leaves the ring obviously
    // part-way round rather than nearly full or nearly empty.
    static let restExercise = "Lats pull down"
    /// The aerobic exercise the demo seeds, for the cardio captures.
    static let aerobicExercise = "Exercise bike"
    static let restTotal = 90
    static let restRemaining = 68

    /// Value passed after `-SRWScreen`, if any.
    static var screen: String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "-SRWScreen"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    /// Value passed after `-SRWSide`, if any: which tab the left-hand pane of
    /// the open Duo shows. Only read when that pane exists.
    static var side: String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "-SRWSide"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    /// An in-memory container holding a realistic-looking training history.
    static func makeContainer() -> ModelContainer {
        // cloudKitDatabase: .none explicitly. Without it the app's CloudKit
        // entitlement lets mirroring attach itself to this throwaway store;
        // in a simulator with no iCloud account that fails
        // ("Unable to initialize without an iCloud account"), the store is
        // pulled out from under the seeding, and the app dies on the save with
        // "No eligible connection available". A screenshot run has nothing to
        // sync and must never try.
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        // swiftlint:disable:next force_try
        let container = try! ModelContainer(
            for: WorkoutDef.self, ExerciseDef.self, WorkoutLog.self, AerobicResult.self,
                 DraftSession.self, AssistedResult.self, LogWeights.self,
            configurations: config
        )
        settleWeightUnit()
        seed(into: container.mainContext)
        markFirstExerciseAssisted(in: container.mainContext)
        addExerciseWithoutHistory(in: container.mainContext)
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
        addAerobic(to: lower, into: ctx)
        try? ctx.save()
    }

    /// Twelve sessions each, roughly weekly. Counted in days ago, so the list
    /// runs DESCENDING: oldest session first, most recent last. addHistory
    /// makes the later entries the heavier ones, and reversing this would
    /// quietly turn every exercise into a decline.
    private static let upperDays: [Int] = (0..<12).map { 79 - $0 * 7 }
    private static let lowerDays: [Int] = (0..<12).map { 75 - $0 * 7 }

    @discardableResult
    /// One aerobic exercise, on the end of leg day. Without it every demo
    /// screen shows a library and a log with no cardio in them, and the AE
    /// filter photographs as an empty list.
    private static func addAerobic(to workout: WorkoutDef, into ctx: ModelContext) {
        let bike = ExerciseDef(name: "Exercise bike",
                               kind: .aerobic, aerobicActivity: .indoorCycle)
        ctx.insert(bike)
        workout.exerciseOrder.append(bike.id)

        // A couple of past sessions, so "last time" has something to say.
        for (daysAgo, seconds) in [(3, 18 * 60), (10, 20 * 60)] {
            let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
            let log = WorkoutLog(date: date, workoutId: workout.id,
                                 exerciseId: bike.id, weights: [], reps: [])
            ctx.insert(log)
            ctx.insert(AerobicResult(logId: log.id, durationSeconds: seconds,
                                     averageHeartRate: 138, maximumHeartRate: 157,
                                     zoneSeconds: [60, 240, 600, 180, 0]))
        }
    }

    /// DEBUG only: puts data into the REAL store that looks like it came from
    /// before weights had a unit — legacy numbers, no grams — and the zeroed
    /// variant a committed edit field produced. For walking the recovery path
    /// the way a user meets it, rather than asserting about it in a test.
    ///
    ///     -SRWLegacySeed         exercises with no grams at all
    ///     -SRWLegacySeed zeroed  exercises whose grams were written as 0
    ///     -SRWPoison             plus a set logged while it was broken:
    ///                            zero weight, zero reps, newest of its
    ///                            exercise, which is what every wheel then
    ///                            opens on
    static func seedLegacyData(into ctx: ModelContext) {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "-SRWLegacySeed") else { return }
        let zeroed = i + 1 < args.count && args[i + 1] == "zeroed"
        guard ((try? ctx.fetchCount(FetchDescriptor<ExerciseDef>())) ?? 0) == 0 else { return }

        // A history the shape of a real one: several exercises, a dozen
        // sessions each, weights and repetitions that move. Everything in the
        // ORIGINAL unit-less fields, which is what a store looks like before
        // any of this existed.
        let rows: [(String, Int, Int, Int, [Int], [Int])] = [
            ("Lat pulldown",   3, 20, 120, [50, 55, 55], [12, 10, 8]),
            ("Chest press",    3, 20, 120, [40, 45, 45], [12, 10, 9]),
            ("Seated row",     2, 20, 120, [45, 50],     [12, 9]),
            ("Assisted chin-up", 2, 0, 80, [30, 35],     [8, 6]),
        ]
        var ids: [UUID] = []
        for (name, sets, low, high, weights, reps) in rows {
            let exercise = ExerciseDef(name: name, numberOfSeries: sets)
            exercise.lowestWeight = low
            exercise.highestWeight = high
            exercise.weightIncrement = 5
            exercise.subtractsFromBodyWeight = name.hasPrefix("Assisted")
            if zeroed {
                // What a committed edit field wrote: present, and useless.
                exercise.lowestWeightGrams = 0
                exercise.highestWeightGrams = 0
                exercise.weightIncrementGrams = 0
            }
            ctx.insert(exercise)
            ids.append(exercise.id)

            for session in 0..<12 {
                let date = Date().addingTimeInterval(-Double(session + 1) * 7 * 86_400)
                let drop = session * 5
                ctx.insert(WorkoutLog(date: date, workoutId: UUID(),
                                      exerciseId: exercise.id,
                                      weights: weights.map { max(low, $0 - drop) },
                                      reps: reps))
            }
        }

        if args.contains("-SRWPoison"), let first = ids.first {
            ctx.insert(WorkoutLog(date: Date(), workoutId: UUID(),
                                  exerciseId: first, weights: [], reps: []))
        }

        let workout = WorkoutDef(name: "Upper body", exerciseOrder: ids)
        ctx.insert(workout)
        // The logs belong to it.
        let logs = (try? ctx.fetch(FetchDescriptor<WorkoutLog>())) ?? []
        for log in logs { log.workoutId = workout.id }
        try? ctx.save()
    }

    /// DEBUG only: an exercise with no history at all, first in the workout,
    /// so the log screen opens on wheels that have never been touched. That is
    /// the state that wrote a row of nothing into a real log.
    static func addExerciseWithoutHistory(in ctx: ModelContext) {
        guard CommandLine.arguments.contains("-SRWFreshExercise"),
              let workout = try? ctx.fetch(FetchDescriptor<WorkoutDef>())
                  .sorted(by: { $0.sortIndex < $1.sortIndex }).first else { return }
        let exercise = ExerciseDef(name: "Brand new machine", numberOfSeries: 2,
                                   lowestWeight: 10, highestWeight: 100, weightIncrement: 5,
                                   primaryMuscle: .chest)
        ctx.insert(exercise)
        workout.exerciseOrder.insert(exercise.id, at: 0)
        try? ctx.save()
    }

    /// Screenshot/demo only: makes the first exercise an assisted machine, so
    /// the screens that only appear for one can be looked at without building
    /// a workout by hand. `-SRWDemo -SRWAssisted`.
    static func markFirstExerciseAssisted(in ctx: ModelContext) {
        // The one the demo log screen opens on, not whichever the store hands
        // back first: a fetch has no order, so this marked a different
        // exercise from one run to the next.
        guard CommandLine.arguments.contains("-SRWAssisted"),
              let workout = try? ctx.fetch(FetchDescriptor<WorkoutDef>())
                  .sorted(by: { $0.sortIndex < $1.sortIndex })
                  .first(where: { !$0.exerciseOrder.isEmpty }),
              let firstId = workout.exerciseOrder.first,
              let exercise = try? ctx.fetch(FetchDescriptor<ExerciseDef>())
                  .first(where: { $0.id == firstId }) else { return }
        exercise.subtractsFromBodyWeight = true
        try? ctx.save()
    }

    private static func build(_ name: String, _ rows: [Row],
                              sortIndex: Int, into ctx: ModelContext) -> WorkoutDef {
        var ids: [UUID] = []
        for r in rows {
            let ex = ExerciseDef(name: r.0, numberOfSeries: r.1,
                                 primaryMuscle: r.7,
                                 secondaryMuscles: r.8.flatMap { ExerciseLibrary.entry(key: $0)?.secondary } ?? [],
                                 libraryKey: r.8)
            // Demo numbers are in whatever unit the demo is being read in:
            // the point of a screenshot is what the app looks like, and 50 is
            // 50 on the wheel either way.
            ex.setWeightRange(lowest: Double(r.2), highest: Double(r.3), increment: Double(r.4))
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
                let log = WorkoutLog(date: date,
                                     workoutId: workout.id,
                                     exerciseId: workout.exerciseOrder[i],
                                     weights: [],
                                     reps: reps)
                ctx.insert(log)
                let unit = WeightUnit.current
                ctx.insert(LogWeights(logId: log.id,
                                      grams: weights.map { unit.grams(from: Double($0)) }))
            }
        }
    }
}
#endif
