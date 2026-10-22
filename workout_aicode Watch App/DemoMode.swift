#if DEBUG
import Foundation

// MARK: - DemoMode (App Store screenshots, watchOS)
//
// Mirrors the iPhone's DemoMode so `tools/make-screenshots.sh` can capture the
// Watch screens without needing a paired phone to sync data first:
//
//   -SRWDemo               seed sample workouts directly into WatchSessionManager
//   -SRWScreen <name>      open a screen: log | paused
//
// DEBUG-only, so none of this can ship.

enum DemoMode {

    static var isEnabled: Bool { CommandLine.arguments.contains("-SRWDemo") }

    // Kept in step with the iPhone's DemoMode, so the two rest-timer captures
    // show the same rest.
    static let restExercise = "Lats pull down"
    static let restTotal = 90
    static let restRemaining = 68

    static var screen: String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "-SRWScreen"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    /// Id of the demo workout the screenshot script opens.
    static let workoutId = "demo-upper"

    static var exercises: [SyncExercise] {
        [
            demoExercise(id: "d1", name: "Lats pull down"),
            demoExercise(id: "d2", name: "Chest press"),
            demoExercise(id: "d3", name: "Seated row"),
            // One aerobic exercise, so the cardio screen can be photographed
            // and its layout checked without a real phone driving the Watch.
            SyncExercise(id: "d4", name: "Indoor cycle", numberOfSeries: 1,
                         lowestWeight: 0, highestWeight: 0, weightIncrement: 1,
                         kindRaw: SyncDefaults.aerobicKind,
                         aerobicActivityRaw: "indoorCycle"),
        ]
    }

    static var workouts: [SyncWorkout] {
        [
            SyncWorkout(id: workoutId, name: "Upper body", exerciseOrder: ["d1", "d2", "d3", "d4"]),
            SyncWorkout(id: "demo-legs", name: "Leg day", exerciseOrder: []),
        ]
    }

    /// Demo numbers are read as being in the unit the demo is read in: a
    /// screenshot is about what the app looks like, and 50 is 50 on the wheel
    /// whichever unit it is.
    private static func grams(_ values: [Int]) -> [Int] {
        values.map { WeightUnit.regionDefault.grams(from: Double($0)) }
    }

    private static func demoExercise(id: String, name: String) -> SyncExercise {
        let unit = WeightUnit.regionDefault
        return SyncExercise(id: id, name: name, numberOfSeries: 2,
                            lowestWeight: 20, highestWeight: 120, weightIncrement: 5,
                            lowestGrams: unit.grams(from: 20),
                            highestGrams: unit.grams(from: 120),
                            incrementGrams: unit.grams(from: 5))
    }

    static var lastEntries: [String: SyncLastEntry] {
        [
            "\(workoutId)|d1": SyncLastEntry(weights: grams([50, 55]), reps: [12, 10]),
            "\(workoutId)|d2": SyncLastEntry(weights: grams([40, 45]), reps: [12, 10]),
            "\(workoutId)|d3": SyncLastEntry(weights: grams([45, 50]), reps: [12, 9]),
        ]
    }
}
#endif
