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

enum MacDemoData {
    static var isEnabled: Bool { CommandLine.arguments.contains("-SRWDemo") }

    /// Plausible rather than impressive: a routine somebody might actually
    /// run, with numbers that move a little, because a chart of a perfect
    /// line looks like test data and reads as one.
    @MainActor
    static func seed(into context: ModelContext) {
        let unit = WeightUnit.current

        func exercise(_ name: String, _ muscle: MuscleGroup?,
                      low: Double, high: Double, step: Double,
                      sets: Int = 3) -> ExerciseDef {
            let made = ExerciseDef(name: name, numberOfSeries: sets,
                                   primaryMuscle: muscle)
            made.setWeightRange(lowest: low, highest: high, increment: step, unit: unit)
            context.insert(made)
            return made
        }

        let bench = exercise("Machine bench press", .chest, low: 20, high: 200, step: 5)
        let pulldown = exercise("Lat pulldown", .back, low: 20, high: 200, step: 5)
        let press = exercise("Machine shoulder press", .frontDelts, low: 10, high: 120, step: 5)
        let legPress = exercise("Leg press", .quads, low: 40, high: 400, step: 10)
        let curl = exercise("Biceps curl machine", .biceps, low: 10, high: 100, step: 5)
        let row = exercise("Seated row", .back, low: 20, high: 200, step: 5)
        let extensions = exercise("Triceps extensions", .triceps, low: 10, high: 120, step: 5)
        let abs = exercise("Abs crunch machine", .absCore, low: 10, high: 120, step: 5)

        let upper = WorkoutDef(name: "Upper body")
        upper.exerciseOrder = [bench.id, pulldown.id, press.id, row.id, extensions.id]
        let lower = WorkoutDef(name: "Lower body")
        lower.exerciseOrder = [legPress.id, curl.id, abs.id]
        context.insert(upper)
        context.insert(lower)

        // Eight weeks, twice a week, alternating — enough for the trend lines
        // on the graphs screen to have something to say.
        let calendar = Calendar.current
        var day = calendar.date(byAdding: .day, value: -56, to: Date()) ?? Date()
        var session = 0

        while day < Date() {
            let isUpper = session % 2 == 0
            let workout = isUpper ? upper : lower
            let plan: [(ExerciseDef, Double, [Int])] = isUpper
                ? [(bench, 50, [12, 10]), (pulldown, 45, [12, 10]),
                   (press, 25, [12, 10]), (row, 40, [15, 12]),
                   (extensions, 20, [15, 12])]
                : [(legPress, 120, [15, 12]), (curl, 25, [12, 10]),
                   (abs, 30, [20, 20])]

            let at = calendar.date(bySettingHour: 17, minute: 15, second: 0, of: day) ?? day
            for (index, entry) in plan.enumerated() {
                let (definition, base, reps) = entry
                // A little progress across the weeks, and not in lockstep.
                let gained = Double(session / 2) * (isUpper ? 1.25 : 2.5)
                let weight = base + gained
                let log = WorkoutLog(date: calendar.date(byAdding: .minute,
                                                         value: index * 6, to: at) ?? at,
                                     workoutId: workout.id,
                                     exerciseId: definition.id,
                                     weights: [Int(weight), Int(weight)],
                                     reps: reps)
                context.insert(log)
                context.insert(LogWeights(logId: log.id,
                                          grams: [unit.grams(from: weight),
                                                  unit.grams(from: weight)]))
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
