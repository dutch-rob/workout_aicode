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

    /// name, sets, lowest, highest, increment, weights, reps
    private typealias Row = (String, Int, Int, Int, Int, [Int], [Int])

    private static let upperBody: [Row] = [
        ("Lats pull down",     3, 20, 120, 5, [50, 55, 55], [12, 10, 8]),
        ("Chest press",        3, 20, 120, 5, [40, 45, 45], [12, 10, 8]),
        ("Seated row",         3, 20, 120, 5, [45, 50, 50], [12, 10, 9]),
        ("Shoulder press",     3, 10,  80, 5, [30, 35, 35], [10,  9, 8]),
        ("Biceps curl",        3, 10,  60, 5, [25, 30, 30], [12, 10, 8]),
        ("Triceps pushdown",   3, 10,  60, 5, [30, 30, 35], [12, 10, 8]),
        ("Abs crunch machine", 2, 10,  80, 5, [40, 45],     [15, 12]),
    ]

    private static let lowerBody: [Row] = [
        ("Leg press",     3, 40, 250, 10, [120, 140, 140], [12, 10, 8]),
        ("Leg extension", 3, 20, 120,  5, [ 45,  50,  50], [12, 10, 8]),
        ("Leg curl",      3, 20, 120,  5, [ 40,  45,  45], [12, 10, 8]),
        ("Calf raise",    3, 20, 150,  5, [ 70,  80,  80], [15, 12, 12]),
    ]

    private static func seed(into ctx: ModelContext) {
        let upper = build("Upper body", upperBody, sortIndex: 0, into: ctx)
        let lower = build("Leg day", lowerBody, sortIndex: 1, into: ctx)
        // History so the logs screen has up/down colouring to show. The two
        // workouts alternate across days, as a real routine would.
        addHistory(for: upper, upperBody, daysAgo: [11, 6, 2], hour: 18, into: ctx)
        addHistory(for: lower, lowerBody, daysAgo: [9, 4, 1], hour: 9, into: ctx)
        try? ctx.save()
    }

    @discardableResult
    private static func build(_ name: String, _ rows: [Row],
                              sortIndex: Int, into ctx: ModelContext) -> WorkoutDef {
        var ids: [UUID] = []
        for r in rows {
            let ex = ExerciseDef(name: r.0, numberOfSeries: r.1,
                                 lowestWeight: r.2, highestWeight: r.3, weightIncrement: r.4)
            ctx.insert(ex)
            ids.append(ex.id)
        }
        let workout = WorkoutDef(name: name, exerciseOrder: ids, sortIndex: sortIndex)
        ctx.insert(workout)
        return workout
    }

    /// Past sessions, each slightly lighter than the next, so the most recent
    /// entries show the green "went up" colouring. `hour` puts each workout at a
    /// plausible time of day rather than whenever the screenshots happen to run.
    private static func addHistory(for workout: WorkoutDef, _ rows: [Row],
                                   daysAgo: [Int], hour: Int, into ctx: ModelContext) {
        let cal = Calendar.current
        for (session, days) in daysAgo.enumerated() {
            let drop = (daysAgo.count - 1) - session   // older sessions are lighter
            guard let dayStart = cal.date(byAdding: .day, value: -days, to: Date()),
                  let start = cal.date(bySettingHour: hour, minute: 5, second: 0, of: dayStart)
            else { continue }
            for (i, r) in rows.enumerated() {
                let weights = r.5.map { max(r.2, $0 - drop * r.4) }
                let date = start.addingTimeInterval(Double(i) * 240)
                ctx.insert(WorkoutLog(date: date,
                                      workoutId: workout.id,
                                      exerciseId: workout.exerciseOrder[i],
                                      weights: weights,
                                      reps: r.6))
            }
        }
    }
}
#endif
