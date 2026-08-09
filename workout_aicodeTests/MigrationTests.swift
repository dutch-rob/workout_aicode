import Testing
import Foundation
import SwiftData
@testable import workout_aicode

// Does a database written by the shipped app still open, with all its data, on
// the current version?
//
// Reopening is always done at the newest schema, because that is what the app
// declares. Pinning these to an older version once the plan grew past it made
// CoreData throw and took the whole test process down with it.
//
// This is the one failure mode with no recovery: a user updates and their
// training history is gone. Adding ExerciseDef fields broke staged migration
// once already (V2 and V3 became indistinguishable), and that showed up as a
// launch crash — so the check is a real store on disk, written through the old
// schema and reopened through the migration plan, not a mock.

private func temporaryStoreURL() -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("migration-\(UUID().uuidString).sqlite")
}

private func removeStore(at url: URL) {
    let folder = url.deletingLastPathComponent()
    let stem = url.deletingPathExtension().lastPathComponent
    let contents = (try? FileManager.default.contentsOfDirectory(at: folder,
                                                                 includingPropertiesForKeys: nil)) ?? []
    for f in contents where f.lastPathComponent.hasPrefix(stem) {
        try? FileManager.default.removeItem(at: f)
    }
}

@Test func storeWrittenByVersion1_2SurvivesTheUpgrade() throws {
    let url = temporaryStoreURL()
    defer { removeStore(at: url) }

    let exerciseId = UUID()
    let workoutId = UUID()
    let logDate = Date(timeIntervalSince1970: 1_700_000_000)

    // ── Write a store exactly as the shipped version would ────────────────
    do {
        let container = try ModelContainer(
            for: Schema(versionedSchema: WorkoutLogSchemaV2.self),
            configurations: ModelConfiguration(url: url, cloudKitDatabase: .none)
        )
        let context = ModelContext(container)
        context.insert(WorkoutLogSchemaV1.ExerciseDef(
            id: exerciseId, name: "Lat pulldown", numberOfSeries: 3,
            lowestWeight: 20, highestWeight: 120, weightIncrement: 5))
        context.insert(WorkoutDef(id: workoutId, name: "Upper body",
                                  exerciseOrder: [exerciseId], sortIndex: 0))
        context.insert(WorkoutLogSchemaV2.WorkoutLog(
            date: logDate, workoutId: workoutId, exerciseId: exerciseId,
            weights: [50, 55], reps: [12, 10]))
        try context.save()
    }

    // ── Reopen through the migration plan, as the updated app does ────────
    let container = try ModelContainer(
        for: Schema(versionedSchema: WorkoutLogSchemaV5.self),
        migrationPlan: WorkoutMigrationPlan.self,
        configurations: ModelConfiguration(url: url, cloudKitDatabase: .none)
    )
    let context = ModelContext(container)

    let exercises = try context.fetch(FetchDescriptor<ExerciseDef>())
    let workouts = try context.fetch(FetchDescriptor<WorkoutDef>())
    let logs = try context.fetch(FetchDescriptor<WorkoutLog>())

    #expect(exercises.count == 1)
    #expect(workouts.count == 1)
    #expect(logs.count == 1)

    let exercise = try #require(exercises.first)
    #expect(exercise.id == exerciseId)
    #expect(exercise.name == "Lat pulldown")
    #expect(exercise.numberOfSeries == 3)
    #expect(exercise.lowestWeight == 20)
    #expect(exercise.highestWeight == 120)
    #expect(exercise.weightIncrement == 5)

    // The new columns must read as "unset" rather than crashing on a NULL —
    // the trap that the movementType comment in the recovery path warns about.
    #expect(exercise.primaryMuscle == nil)
    #expect(exercise.secondaryMuscles.isEmpty)
    #expect(exercise.libraryKey == nil)

    let log = try #require(logs.first)
    #expect(log.weights == [50, 55])
    #expect(log.reps == [12, 10])
    #expect(log.date == logDate)
    #expect(log.exerciseId == exerciseId)

    let workout = try #require(workouts.first)
    #expect(workout.name == "Upper body")
    #expect(workout.exerciseOrder == [exerciseId])
}

@Test func migratedExerciseCanBeGivenMuscleGroups() throws {
    let url = temporaryStoreURL()
    defer { removeStore(at: url) }

    let exerciseId = UUID()
    do {
        let container = try ModelContainer(
            for: Schema(versionedSchema: WorkoutLogSchemaV2.self),
            configurations: ModelConfiguration(url: url, cloudKitDatabase: .none)
        )
        let context = ModelContext(container)
        context.insert(WorkoutLogSchemaV1.ExerciseDef(id: exerciseId, name: "Squat"))
        try context.save()
    }

    let container = try ModelContainer(
        for: Schema(versionedSchema: WorkoutLogSchemaV5.self),
        migrationPlan: WorkoutMigrationPlan.self,
        configurations: ModelConfiguration(url: url, cloudKitDatabase: .none)
    )
    let context = ModelContext(container)
    let exercise = try #require(try context.fetch(FetchDescriptor<ExerciseDef>()).first)

    exercise.primaryMuscle = .quads
    exercise.secondaryMuscles = [.glutes, .hamstrings]
    try context.save()

    let reread = try #require(try ModelContext(container)
        .fetch(FetchDescriptor<ExerciseDef>()).first)
    #expect(reread.primaryMuscle == .quads)
    #expect(reread.secondaryMuscles == [.glutes, .hamstrings])
}

@Test func secondaryMuscleListIsCappedAtFour() {
    let e = ExerciseDef(name: "Everything")
    e.secondaryMuscles = [.chest, .back, .traps, .biceps, .triceps, .calves]
    #expect(e.secondaryMuscles.count == MuscleGroup.maximumSecondary)
}

@Test func exerciseSurvivesAnExportRoundTrip() throws {
    let original = ExerciseDef(name: "Bench press", numberOfSeries: 4,
                               lowestWeight: 20, highestWeight: 140, weightIncrement: 2,
                               primaryMuscle: .chest,
                               secondaryMuscles: [.frontDelts, .triceps],
                               libraryKey: "bench-press")
    let data = try JSONEncoder().encode(original)
    let restored = try JSONDecoder().decode(ExerciseDef.self, from: data)

    #expect(restored.name == "Bench press")
    #expect(restored.primaryMuscle == .chest)
    #expect(restored.secondaryMuscles == [.frontDelts, .triceps])
    #expect(restored.libraryKey == "bench-press")
}

@Test func exportsFromOlderVersionsStillImport() throws {
    // An export written before muscle groups existed: no primaryMuscle,
    // no secondaryMuscles, no libraryKey.
    let json = """
    {"id":"\(UUID().uuidString)","name":"Old exercise","numberOfSeries":3,
     "lowestWeight":0,"highestWeight":200,"weightIncrement":5,"movementType":"none"}
    """
    let restored = try JSONDecoder().decode(ExerciseDef.self, from: Data(json.utf8))
    #expect(restored.name == "Old exercise")
    #expect(restored.primaryMuscle == nil)
    #expect(restored.secondaryMuscles.isEmpty)
}

@Test func unknownMuscleGroupIsIgnoredRatherThanFailingTheImport() throws {
    // A group name from some future version must not make the whole file
    // unreadable — one unknown attribute should cost one attribute.
    let json = """
    {"id":"\(UUID().uuidString)","name":"Future exercise","numberOfSeries":3,
     "lowestWeight":0,"highestWeight":200,"weightIncrement":5,
     "primaryMuscle":"antigravity","secondaryMuscles":["chest","levitation"]}
    """
    let restored = try JSONDecoder().decode(ExerciseDef.self, from: Data(json.utf8))
    #expect(restored.name == "Future exercise")
    #expect(restored.primaryMuscle == nil)
    #expect(restored.secondaryMuscles == [.chest])
}

@Test func favouriteFlagSurvivesTheUpgradeAndDefaultsToOff() throws {
    // The store is written at V2 (no muscle groups, no favourite flag) and
    // reopened through both later stages, as a user updating from the shipped
    // version does.
    let url = temporaryStoreURL()
    defer { removeStore(at: url) }

    let exerciseId = UUID()
    do {
        let container = try ModelContainer(
            for: Schema(versionedSchema: WorkoutLogSchemaV2.self),
            configurations: ModelConfiguration(url: url, cloudKitDatabase: .none)
        )
        let context = ModelContext(container)
        context.insert(WorkoutLogSchemaV1.ExerciseDef(id: exerciseId, name: "Deadlift"))
        try context.save()
    }

    let container = try ModelContainer(
        for: Schema(versionedSchema: WorkoutLogSchemaV5.self),
        migrationPlan: WorkoutMigrationPlan.self,
        configurations: ModelConfiguration(url: url, cloudKitDatabase: .none)
    )
    let context = ModelContext(container)
    let exercise = try #require(try context.fetch(FetchDescriptor<ExerciseDef>()).first)
    #expect(exercise.name == "Deadlift")
    #expect(exercise.isFavourite == false)

    exercise.isFavourite = true
    try context.save()
    let reread = try #require(try ModelContext(container)
        .fetch(FetchDescriptor<ExerciseDef>()).first)
    #expect(reread.isFavourite)
}

@Test func newExerciseUsesTheChosenDefaults() {
    let d = UserDefaults.standard
    d.set(4, forKey: ExerciseDefaultsKey.sets)
    d.set(10, forKey: ExerciseDefaultsKey.lowest)
    d.set(80, forKey: ExerciseDefaultsKey.highest)
    d.set(2, forKey: ExerciseDefaultsKey.increment)
    defer {
        for key in [ExerciseDefaultsKey.sets, ExerciseDefaultsKey.lowest,
                    ExerciseDefaultsKey.highest, ExerciseDefaultsKey.increment] {
            d.removeObject(forKey: key)
        }
    }
    let e = ExerciseDefaults.makeExercise(name: "Curl")
    #expect(e.numberOfSeries == 4)
    #expect(e.lowestWeight == 10)
    #expect(e.highestWeight == 80)
    #expect(e.weightIncrement == 2)
}

@Test func defaultsAreNotAskedOfSomeoneWhoAlreadyHasExercises() {
    UserDefaults.standard.removeObject(forKey: ExerciseDefaultsKey.asked)
    #expect(ExerciseDefaults.shouldAsk(existingExercises: 0))
    #expect(!ExerciseDefaults.shouldAsk(existingExercises: 7))
}

// MARK: - The rest timer column

@Test func restSecondsArrivesWithADefaultAndThenPersists() throws {
    // Written at V2 — the shipped shape before muscle groups, favourites or the
    // rest timer — and reopened at the current version, walking the whole chain
    // V2 → V3 → V4 → V5. That is the migration a long-untouched install makes.
    //
    // Writing the store at V4 instead would be a closer match to the most
    // recent release, but a store opened without a migration plan records no
    // version identifier: the real plan then matches it by shape to its
    // earliest candidate, and a "V4" store written that way came back as V2
    // with its later columns stripped. Handing the writing container its own
    // plan fixes the identification and breaks something else — two migration
    // plans over the same model classes in one process abort inside CoreData.
    // So the store is written the way every other test here writes one.
    let url = temporaryStoreURL()
    defer { removeStore(at: url) }

    let exerciseId = UUID()
    do {
        let container = try ModelContainer(
            for: Schema(versionedSchema: WorkoutLogSchemaV2.self),
            configurations: ModelConfiguration(url: url, cloudKitDatabase: .none)
        )
        let context = ModelContext(container)
        let old = WorkoutLogSchemaV1.ExerciseDef(id: exerciseId, name: "Overhead press")
        old.numberOfSeries = 4
        context.insert(old)
        try context.save()
    }

    let container = try ModelContainer(
        for: Schema(versionedSchema: WorkoutLogSchemaV5.self),
        migrationPlan: WorkoutMigrationPlan.self,
        configurations: ModelConfiguration(url: url, cloudKitDatabase: .none)
    )
    let context = ModelContext(container)
    let exercise = try #require(try context.fetch(FetchDescriptor<ExerciseDef>()).first)

    #expect(exercise.name == "Overhead press")
    #expect(exercise.numberOfSeries == 4)
    // An exercise that predates the timer must not arrive with a zero rest.
    // Zero means "no rest", and the timer would never run for that exercise —
    // a silent, per-exercise version of the feature not working.
    #expect(exercise.restSeconds == RestTimerDefaults.seconds)

    exercise.restSeconds = 120
    try context.save()
    let reread = try #require(try ModelContext(container)
        .fetch(FetchDescriptor<ExerciseDef>()).first)
    #expect(reread.restSeconds == 120)
}

@Test func restSecondsSurvivesAnExportRoundTrip() throws {
    let original = ExerciseDef(name: "Front squat", restSeconds: 180)
    let restored = try JSONDecoder().decode(
        ExerciseDef.self, from: try JSONEncoder().encode(original))
    #expect(restored.restSeconds == 180)
}

@Test func exportsFromBeforeTheRestTimerStillImport() throws {
    let json = """
    {"id":"\(UUID().uuidString)","name":"Old exercise","numberOfSeries":3,
     "lowestWeight":0,"highestWeight":200,"weightIncrement":5}
    """
    let restored = try JSONDecoder().decode(ExerciseDef.self, from: Data(json.utf8))
    #expect(restored.restSeconds == RestTimerDefaults.seconds)
}

// MARK: - Rest lengths offered

@Test func restChoicesRunFromFifteenSecondsToFiveMinutes() {
    #expect(RestTimerDefaults.choices.first == 15)
    #expect(RestTimerDefaults.choices.last == 300)
    #expect(RestTimerDefaults.choices.count == 20)
    // The default must be one of the options, or the picker would show blank.
    #expect(RestTimerDefaults.choices.contains(RestTimerDefaults.seconds))
}

@Test func restIsLabelledAsMinutesAndSeconds() {
    #expect(RestTimerDefaults.label(90) == "1:30")
    #expect(RestTimerDefaults.label(45) == "0:45")
    #expect(RestTimerDefaults.label(300) == "5:00")
}

@Test func aNewExerciseGetsTheChosenRest() {
    let d = UserDefaults.standard
    d.set(120, forKey: RestTimerKey.defaultSeconds)
    defer { d.removeObject(forKey: RestTimerKey.defaultSeconds) }
    #expect(ExerciseDefaults.makeExercise(name: "Dip").restSeconds == 120)
}

@Test func theRestTimerIsOffUntilItIsTurnedOn() {
    UserDefaults.standard.removeObject(forKey: RestTimerKey.enabled)
    #expect(!RestTimerDefaults.isEnabled)
}
