#if DEBUG
import Foundation

// MARK: - DemoMode (App Store screenshots, watchOS)
//
// Mirrors the iPhone's DemoMode so `tools/make-screenshots.sh` can capture the
// Watch screens without needing a paired phone to sync data first:
//
//   -SRWDemo               seed sample workouts directly into WatchSessionManager
//   -SRWScreen <name>      open a screen: log | tworows | paused | rest | restzone
//   -SRWRest <seconds>     how much of the demo rest is left (default 68 of 90)
//
// DEBUG-only, so none of this can ship.

enum DemoMode {

    static var isEnabled: Bool { CommandLine.arguments.contains("-SRWDemo") }

    // Kept in step with the iPhone's DemoMode, so the two rest-timer captures
    // show the same rest.
    static let restExercise = "Lats pull down"
    static let restTotal = 90
    /// How much of the rest is left, overridable with `-SRWRest 88`.
    ///
    /// Overridable because the ENDS are what needed looking at: the bar got
    /// wider after a real workout where its first and last seconds were lost
    /// in the screen's rounded corners, and a fixed 68 of 90 shows neither
    /// end. 68 is what the App Store captures use.
    static var restRemaining: Int {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "-SRWRest"), i + 1 < args.count,
           let seconds = Int(args[i + 1]) {
            return seconds
        }
        return 68
    }

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

    /// Both numbers, as a real phone sends them: the grams the wheels open on,
    /// and the plain ones beside them. Putting grams in `weights` made the
    /// Watch read them as pounds and convert them a second time.
    static var lastEntries: [String: SyncLastEntry] {
        [
            "\(workoutId)|d1": SyncLastEntry(weights: [50, 55], reps: [12, 10],
                                             weightsGrams: grams([50, 55])),
            "\(workoutId)|d2": SyncLastEntry(weights: [40, 45], reps: [12, 10],
                                             weightsGrams: grams([40, 45])),
            "\(workoutId)|d3": SyncLastEntry(weights: [45, 50], reps: [12, 9],
                                             weightsGrams: grams([45, 50])),
        ]
    }
}
#endif
