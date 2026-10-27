#if DEBUG
import Foundation
import SwiftData

// MARK: - Sample data for screenshots
//
// A screenshot run gets its OWN in-memory store, seeded here. Two reasons,
// and the second is the important one.
//
// An App Store screenshot of "No workouts yet" says nothing about the app —
// which is what the first Mac capture showed, because this Mac's iCloud store
// was empty.
//
// And nothing from a real account should end up in a picture that goes to
// Apple. Reaching for the live store would mean somebody's real training, and
// their workout names, in a public listing.

// The screenshot script passes "-SRWDemo 1" and this runs. The value is
// never read, and it still has to be there: see the long note in
// tools/make-mac-screenshots.sh. A bare "-SRWDemo" makes NSUserDefaults
// swallow the next flag as its value and strand that flag's value as a bare
// word, which AppKit reads as a file to open — and an app launched to open a
// file gets no window at all. The app then runs and seeds in silence with
// nothing on screen, which is exactly how this sample data got blamed, and
// switched off, for a fault that had nothing to do with it.
enum MacDemoData {
    static var isEnabled: Bool { CommandLine.arguments.contains("-SRWDemo") }

    /// The SAME routine the iPhone and Watch screenshots use — see
    /// DemoMode.upperBody and .lowerBody on the phone.
    ///
    /// They sit in one App Store listing, and a Mac showing "Lower body" with
    /// a machine bench press beside an iPhone showing "Leg day" with a chest
    /// press reads as two different apps photographed badly. Matching them is
    /// the whole point: the same person's training, seen on two screens.
    private typealias Row = (name: String, sets: Int, low: Double, high: Double,
                             step: Double, weight: Double, reps: [Int],
                             muscle: MuscleGroup?)

    private static let upperBody: [Row] = [
        ("Lats pull down",     3, 20, 120, 5, 50, [12, 10, 8], .back),
        ("Chest press",        3, 20, 120, 5, 40, [12, 10, 8], .chest),
        ("Seated row",         3, 20, 120, 5, 45, [12, 10, 9], .back),
        ("Shoulder press",     3, 10,  80, 5, 30, [10,  9, 8], .frontDelts),
        ("Biceps curl",        3, 10,  60, 5, 25, [12, 10, 8], .biceps),
        ("Triceps pushdown",   3, 10,  60, 5, 30, [12, 10, 8], .triceps),
        ("Abs crunch machine", 2, 10,  80, 5, 40, [15, 12],    .absCore),
    ]

    private static let legDay: [Row] = [
        ("Leg press",     3, 40, 250, 10, 120, [12, 10, 8],  .quads),
        ("Leg extension", 3, 20, 120,  5,  45, [12, 10, 8],  .quads),
        ("Leg curl",      3, 20, 120,  5,  40, [12, 10, 8],  .hamstrings),
        ("Calf raise",    3, 20, 150,  5,  70, [15, 12, 12], .calves),
    ]

    /// A repeatable 0..<100 from two numbers, so the wobble below is the
    /// same every run: two screenshot runs must make the same pictures, and
    /// a random one would quietly change the graphs between them.
    private static func wobble(_ a: Int, _ b: Int) -> Int {
        var x = UInt64(bitPattern: Int64(a &* 73856093 ^ b &* 19349663 &+ 83492791))
        x ^= x >> 33
        x = x &* 0xff51afd7ed558ccd
        x ^= x >> 29
        return Int(x % 100)
    }

    @MainActor
    static func seed(into context: ModelContext) {
        let unit = WeightUnit.current

        func define(_ rows: [Row]) -> [(ExerciseDef, Row)] {
            rows.map { row in
                let made = ExerciseDef(name: row.name, numberOfSeries: row.sets,
                                       primaryMuscle: row.muscle)
                made.setWeightRange(lowest: row.low, highest: row.high,
                                    increment: row.step, unit: unit)
                context.insert(made)
                return (made, row)
            }
        }

        let upper = define(upperBody)
        let lower = define(legDay)


        let upperWorkout = WorkoutDef(name: "Upper body",
                                      exerciseOrder: upper.map(\.0.id), sortIndex: 0)
        let legWorkout = WorkoutDef(name: "Leg day",
                                    exerciseOrder: lower.map(\.0.id), sortIndex: 1)
        context.insert(upperWorkout)
        context.insert(legWorkout)


        // Eight weeks, alternating, every third day — enough history for the
        // trend lines to have something to say and for the logs screen to
        // need its filter.
        let calendar = Calendar.current
        var day = calendar.date(byAdding: .day, value: -56, to: Date()) ?? Date()
        var session = 0

        while day < Date() {
            let isUpper = session % 2 == 0
            let workout = isUpper ? upperWorkout : legWorkout
            let plan = isUpper ? upper : lower
            let at = calendar.date(bySettingHour: 17, minute: 15, second: 0, of: day) ?? day
            // A little progress across the weeks, in steps of the wheel, so
            // every weight shown is one the machine actually has.
            let steps = Double(session / 4)

            for (index, pair) in plan.enumerated() {
                let (definition, row) = pair
                // Held and backed-off weeks, and reps that move about. Adding
                // the same step every fourth session drew nine flawless
                // straight lines on the graphs screen, which looks like a
                // formula rather than like training. Still only ever lands on
                // a weight the machine has.
                let held = wobble(session, index) < 22 ? 1.0 : 0.0
                let weight = row.weight + max(0, steps - held) * row.step
                let reps = row.reps.enumerated().map { set, count in
                    max(6, count + wobble(session &* 31 &+ set, index) % 3 - 1)
                }
                let grams = Array(repeating: unit.grams(from: weight), count: reps.count)
                let log = WorkoutLog(date: calendar.date(byAdding: .minute,
                                                         value: index * 6, to: at) ?? at,
                                     workoutId: workout.id,
                                     exerciseId: definition.id,
                                     weights: Array(repeating: Int(weight),
                                                    count: reps.count),
                                     reps: reps)
                context.insert(log)
                context.insert(LogWeights(logId: log.id, grams: grams))
            }
            day = calendar.date(byAdding: .day, value: 3, to: day) ?? Date.distantFuture
            session += 1
        }

        // The question about what old weights meant must not appear over a
        // screenshot: this data was written in the unit being read.
        UserDefaults.standard.set(unit.rawValue, forKey: WeightHistory.statedUnitKey)
        try? context.save()

    }
}
#endif
