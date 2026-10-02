import Testing
import Foundation
import SwiftData
import HealthKit
import SwiftUI
@testable import workout_aicode



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


// MARK: - The numbers a new exercise starts with
//
// Serialized, and it has to be. These write UserDefaults.standard, which is one
// object shared by the whole process, and Swift Testing runs tests in parallel
// by default — two of them setting "sets" to different values at the same
// moment gave a failure that looked like a bug in the code under test and was
// nothing of the sort. Any test that writes these keys belongs in here.

@Suite(.serialized)
struct NewExerciseNumberTests {

    /// Put the four number keys back however they were.
    private func withDefaults(sets: Int, lowest: Int, highest: Int, increment: Int,
                              _ body: () -> Void) {
        let d = UserDefaults.standard
        let keys = [ExerciseDefaultsKey.sets, ExerciseDefaultsKey.lowest,
                    ExerciseDefaultsKey.highest, ExerciseDefaultsKey.increment]
        let saved = keys.map { d.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) {
                if let value { d.set(value, forKey: key) } else { d.removeObject(forKey: key) }
            }
        }
        d.set(sets, forKey: ExerciseDefaultsKey.sets)
        d.set(lowest, forKey: ExerciseDefaultsKey.lowest)
        d.set(highest, forKey: ExerciseDefaultsKey.highest)
        d.set(increment, forKey: ExerciseDefaultsKey.increment)
        body()
    }

    @Test func newExerciseUsesTheChosenDefaults() {
        withDefaults(sets: 4, lowest: 10, highest: 80, increment: 2) {
            let e = ExerciseDefaults.makeExercise(name: "Curl")
            #expect(e.numberOfSeries == 4)
            #expect(e.lowestWeight == 10)
            #expect(e.highestWeight == 80)
            #expect(e.weightIncrement == 2)
        }
    }

    @Test func aTakenLibraryExerciseStartsOnTheUsersOwnNumbers() {
        // The catalogue carries defaults of its own — the same 3 / 0…200 / 5
        // the app ships with, which is exactly why building a copy from them
        // looked right and quietly ignored what the user had chosen.
        withDefaults(sets: 5, lowest: 15, highest: 90, increment: 2) {
            let taken = ExerciseLibrary.take(ExerciseLibrary.entry(key: "biceps-curl")!,
                                             existingNames: [])
            #expect(taken.numberOfSeries == 5)
            #expect(taken.lowestWeight == 15)
            #expect(taken.highestWeight == 90)
            #expect(taken.weightIncrement == 2)
        }
    }

    @Test func theRestTimerIsOffUntilItIsTurnedOn() {
        // Its own store, not the device's. This test failed twice during
        // development for a reason that had nothing to do with the code: the
        // rest timer had been switched on by hand in the simulator, and the
        // test clones inherit the device's settings. A test that a person's own
        // use of the app can break is a test people learn to ignore.
        let store = UserDefaults(suiteName: "resttimer-\(UUID().uuidString)")!

        #expect(!ExerciseDefaults.restTimerIsOn(in: store))   // never answered
        store.set(false, forKey: RestTimerKey.enabled)
        #expect(!ExerciseDefaults.restTimerIsOn(in: store))   // answered no
        store.set(true, forKey: RestTimerKey.enabled)
        #expect(ExerciseDefaults.restTimerIsOn(in: store))    // only this is on
    }

    @Test func defaultsAreNotAskedOfSomeoneWhoAlreadyHasExercises() {
        UserDefaults.standard.removeObject(forKey: ExerciseDefaultsKey.asked)
        #expect(ExerciseDefaults.shouldAsk(existingExercises: 0))
        #expect(!ExerciseDefaults.shouldAsk(existingExercises: 7))
    }
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




@Test func anAerobicResultSurvivesAnExportRoundTrip() throws {
    let original = AerobicResult(logId: UUID(), durationSeconds: 1800,
                                 averageHeartRate: 142, maximumHeartRate: 170,
                                 zoneSeconds: [0, 200, 900, 600, 100])
    let restored = try JSONDecoder().decode(
        AerobicResult.self, from: try JSONEncoder().encode(original))
    #expect(restored.durationSeconds == 1800)
    #expect(restored.zoneSeconds == [0, 200, 900, 600, 100])
    #expect(restored.maximumHeartRate == 170)
}

@Test func anAerobicExerciseSurvivesAnExportRoundTrip() throws {
    let original = ExerciseDef(name: "Treadmill", kind: .aerobic, aerobicActivity: .indoorRun)
    let restored = try JSONDecoder().decode(
        ExerciseDef.self, from: try JSONEncoder().encode(original))
    #expect(restored.kind == .aerobic)
    #expect(restored.aerobicActivity == .indoorRun)
}

@Test func anUnknownKindReadsAsStrengthRatherThanFailing() throws {
    // One unrecognised value from a future version should cost one attribute,
    // not the whole exercise — the same rule the muscle groups follow.
    let json = """
    {"id":"\(UUID().uuidString)","name":"Future exercise","numberOfSeries":3,
     "lowestWeight":0,"highestWeight":200,"weightIncrement":5,
     "kind":"telekinesis","aerobicActivity":"levitation"}
    """
    let restored = try JSONDecoder().decode(ExerciseDef.self, from: Data(json.utf8))
    #expect(restored.name == "Future exercise")
    #expect(restored.kind == .strength)
    #expect(restored.aerobicActivity == nil)
}

@Test func aLogIsUnchangedByTheAerobicVersion() throws {
    // WorkoutLog deliberately gained nothing in V6 — the measurements went to
    // their own entity — so an export from any earlier version decodes exactly
    // as it always did.
    let json = """
    {"id":"\(UUID().uuidString)","date":728000000,"workoutId":"\(UUID().uuidString)",
     "exerciseId":"\(UUID().uuidString)","weights":[50],"reps":[10]}
    """
    let restored = try JSONDecoder().decode(WorkoutLog.self, from: Data(json.utf8))
    #expect(restored.weights == [50])
    #expect(restored.reps == [10])
}

// MARK: - Schema and migration
//
// Serialized, and that is load-bearing. Swift Testing runs tests in parallel
// within one process, and SwiftData keeps per-model-class state that is global
// to it — so a container opened from the V2 schema, whose frozen ExerciseDef
// has no `kind` column, races one opened from V6 and the newer columns read
// back as their defaults. It looks exactly like a persistence bug: the value is
// set, the save succeeds, and the row comes back with the default. Every one of
// these tests opens a container, so they take turns.
@Suite(.serialized)
struct SchemaMigrationTests {

    // MARK: Editing logs undoably
    //
    // In this suite rather than one of their own, and that is not tidiness: two
    // serialized suites still run in parallel with EACH OTHER, and these open
    // containers. Put in their own suite they made
    // storeWrittenByVersion1_2SurvivesTheUpgrade fail — the same
    // parallelism-versus-SwiftData race described above, reintroduced by a
    // second @Suite.
    //
    // The log is the one thing in this app that cannot be re-made: a workout
    // can be rebuilt in a minute, but nobody remembers what they lifted in
    // March. The editor takes a copy first and "discard" puts it back, so the
    // putting-back is tested against a real store rather than trusted.


    @MainActor private func logEditStore() throws -> ModelContext {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("logedit-\(UUID().uuidString).sqlite")
        let container = try ModelContainer(
            for: Schema(versionedSchema: WorkoutLogSchemaV7.self),
            configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
        return ModelContext(container)
    }

    @discardableResult
    private func addLog(_ context: ModelContext, weights: [Int], reps: [Int],
                        date: Date = Date(timeIntervalSince1970: 1_000_000)) -> WorkoutLog {
        let log = WorkoutLog(date: date, workoutId: UUID(), exerciseId: UUID(),
                             weights: weights, reps: reps)
        context.insert(log)
        try? context.save()
        return log
    }

    @MainActor @Test func anEditedRowGoesBackToWhatItWas() throws {
        let context = try logEditStore()
        let log = addLog(context, weights: [60, 60], reps: [10, 8])
        let snapshot = try LogEditing.snapshot(in: context)

        log.weights = [80, 80]
        log.reps = [3, 3]
        try context.save()
        #expect(LogEditing.hasChanged(from: snapshot, in: context))

        try LogEditing.restore(snapshot, in: context)
        let after = try #require(try context.fetch(FetchDescriptor<WorkoutLog>()).first)
        #expect(after.weights == [60, 60])
        #expect(after.reps == [10, 8])
        #expect(!LogEditing.hasChanged(from: snapshot, in: context))
    }

    @MainActor @Test func aRowAddedAfterTheCopyIsRemovedAgain() throws {
        let context = try logEditStore()
        addLog(context, weights: [50], reps: [10])
        let snapshot = try LogEditing.snapshot(in: context)

        addLog(context, weights: [999], reps: [1])
        #expect(try context.fetch(FetchDescriptor<WorkoutLog>()).count == 2)

        try LogEditing.restore(snapshot, in: context)
        let after = try context.fetch(FetchDescriptor<WorkoutLog>())
        #expect(after.count == 1)
        #expect(after.first?.weights == [50])
    }

    @MainActor @Test func aRowDeletedAfterTheCopyComesBack() throws {
        // The half people actually worry about.
        let context = try logEditStore()
        let log = addLog(context, weights: [70], reps: [5])
        let snapshot = try LogEditing.snapshot(in: context)

        context.delete(log)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<WorkoutLog>()).isEmpty)

        try LogEditing.restore(snapshot, in: context)
        let after = try context.fetch(FetchDescriptor<WorkoutLog>())
        #expect(after.count == 1)
        #expect(after.first?.weights == [70])
        #expect(after.first?.reps == [5])
    }

    @MainActor @Test func movingARowToAnotherExerciseIsUndone() throws {
        let context = try logEditStore()
        let log = addLog(context, weights: [40], reps: [12])
        let original = log.exerciseId
        let snapshot = try LogEditing.snapshot(in: context)

        log.exerciseId = UUID()
        log.date = Date(timeIntervalSince1970: 2_000_000)
        try context.save()

        try LogEditing.restore(snapshot, in: context)
        let after = try #require(try context.fetch(FetchDescriptor<WorkoutLog>()).first)
        #expect(after.exerciseId == original)
        #expect(Int(after.date.timeIntervalSince1970) == 1_000_000)
    }

    @MainActor @Test func anAerobicMeasurementComesBackWithItsLog() throws {
        // Deleting an aerobic row takes its measurements with it; putting the
        // row back has to put those back too, or the log says a ride happened
        // and can no longer say anything about it.
        let context = try logEditStore()
        let log = addLog(context, weights: [], reps: [])
        context.insert(AerobicResult(logId: log.id, durationSeconds: 1200,
                                     averageHeartRate: 131, maximumHeartRate: 158,
                                     zoneSeconds: [60, 300, 600, 240, 0]))
        try context.save()
        let snapshot = try LogEditing.snapshot(in: context)

        for result in try context.fetch(FetchDescriptor<AerobicResult>()) { context.delete(result) }
        context.delete(log)
        try context.save()

        try LogEditing.restore(snapshot, in: context)
        let result = try #require(try context.fetch(FetchDescriptor<AerobicResult>()).first)
        #expect(result.durationSeconds == 1200)
        #expect(result.averageHeartRate == 131)
        #expect(result.zoneSeconds == [60, 300, 600, 240, 0])
        #expect(try context.fetch(FetchDescriptor<WorkoutLog>()).count == 1)
    }

    @MainActor @Test func nothingTouchedMeansNothingChanged() throws {
        // The Done button leans on this: if it said "changed" for an untouched
        // screen, every visit would end in a dialog nobody needs.
        let context = try logEditStore()
        addLog(context, weights: [60, 60], reps: [10, 8])
        addLog(context, weights: [], reps: [])
        let snapshot = try LogEditing.snapshot(in: context)
        #expect(!LogEditing.hasChanged(from: snapshot, in: context))
    }

    @MainActor @Test func restoringTwiceIsTheSameAsRestoringOnce() throws {
        let context = try logEditStore()
        let log = addLog(context, weights: [60], reps: [10])
        let snapshot = try LogEditing.snapshot(in: context)
        log.weights = [90]
        try context.save()

        try LogEditing.restore(snapshot, in: context)
        try LogEditing.restore(snapshot, in: context)
        let after = try context.fetch(FetchDescriptor<WorkoutLog>())
        #expect(after.count == 1)
        #expect(after.first?.weights == [60])
    }

    @MainActor @Test func emptyTrailingSetsAreTrimmedButRealZeroesAreNot() throws {
        let context = try logEditStore()
        // Reaching set 4 to type in it lengthens the arrays; changing your
        // mind must not leave two sets of nothing behind.
        let log = addLog(context, weights: [60, 60, 0, 0], reps: [10, 8, 0, 0])
        LogEditing.trimEmptyTrailingSets(log)
        #expect(log.weights == [60, 60])
        #expect(log.reps == [10, 8])

        // A bodyweight set is 0 kg for real reps, and is not an empty set.
        let bodyweight = addLog(context, weights: [0, 0], reps: [12, 10])
        LogEditing.trimEmptyTrailingSets(bodyweight)
        #expect(bodyweight.reps == [12, 10])
    }

    @MainActor @Test func reachingAnEmptyColumnKeepsWeightsAndRepsTheSameLength() throws {
        let context = try logEditStore()
        let log = addLog(context, weights: [60], reps: [10])
        LogEditing.extend(log, toSets: 4)
        #expect(log.weights.count == 4)
        #expect(log.reps.count == 4)
        // A weight with no reps beside it is a row every reader has to guess at.
        #expect(log.weights.count == log.reps.count)
    }


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

    @Test func anAerobicSessionWithoutAWatchStillRecordsItsDuration() throws {
        let url = temporaryStoreURL()
        defer { removeStore(at: url) }
        let container = try ModelContainer(
            for: Schema(versionedSchema: WorkoutLogSchemaV6.self),
            configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
        let context = ModelContext(container)

        let bike = ExerciseDef(name: "Exercise bike", kind: .aerobic,
                               aerobicActivity: .indoorCycle)
        context.insert(bike)
        let log = WorkoutLog(workoutId: UUID(), exerciseId: bike.id, weights: [], reps: [])
        context.insert(log)
        // What the log screen writes when nothing ever reported a heart rate.
        context.insert(AerobicResult(logId: log.id, durationSeconds: 1200,
                                     averageHeartRate: 0, maximumHeartRate: 0,
                                     zoneSeconds: []))
        try context.save()

        let result = try #require(try ModelContext(container)
            .fetch(FetchDescriptor<AerobicResult>()).first)
        #expect(result.durationSeconds == 1200)
        // Zero and empty are the "not measured" readings, and must stay
        // distinguishable from a real measurement of nothing.
        #expect(result.averageHeartRate == 0)
        #expect(result.zoneSeconds.isEmpty)
    }


    // MARK: - Draft mode
    //
    // Somewhere to try things out, where leaving asks rather than assumes. The
    // assertions that matter are about what is NOT taken away.

    @Test @MainActor func draftRecordsOnlyWhatWasMadeWhileItWasOn() throws {
        let url = temporaryStoreURL(); defer { removeStore(at: url) }
        let container = try ModelContainer(
            for: Schema(versionedSchema: WorkoutLogSchemaV7.self),
            configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
        let context = ModelContext(container)

        // Made before draft: must never be at risk.
        let existing = ExerciseDef(name: "Bench press", primaryMuscle: .chest)
        context.insert(existing)
        try context.save()

        DraftMode.start(in: context)
        let sketch = ExerciseDef(name: "Sketch", primaryMuscle: .back)
        context.insert(sketch)
        DraftMode.note(exercise: sketch.id, in: context)

        // Editing something that already existed is a real edit, not a draft
        // creation — leaving draft must not undo it.
        existing.name = "Bench press (wide)"
        try context.save()

        DraftMode.discardAll(in: context)

        let left = try context.fetch(FetchDescriptor<ExerciseDef>())
        #expect(left.count == 1)
        #expect(left.first?.name == "Bench press (wide)")
    }

    @Test @MainActor func keepingADraftLeavesEverythingInPlace() throws {
        let url = temporaryStoreURL(); defer { removeStore(at: url) }
        let container = try ModelContainer(
            for: Schema(versionedSchema: WorkoutLogSchemaV7.self),
            configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
        let context = ModelContext(container)

        DraftMode.start(in: context)
        let exercise = ExerciseDef(name: "Keeper", primaryMuscle: .chest)
        context.insert(exercise)
        DraftMode.note(exercise: exercise.id, in: context)
        DraftMode.keepAll(in: context)

        #expect(try context.fetch(FetchDescriptor<ExerciseDef>()).count == 1)
        // And draft is off afterwards, with nothing left marked.
        #expect(!DraftMode.isOn(in: context))
    }

    @Test @MainActor func discardingTakesTheLogAndItsMeasurementsTogether() throws {
        let url = temporaryStoreURL(); defer { removeStore(at: url) }
        let container = try ModelContainer(
            for: Schema(versionedSchema: WorkoutLogSchemaV7.self),
            configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
        let context = ModelContext(container)

        DraftMode.start(in: context)
        let log = WorkoutLog(workoutId: UUID(), exerciseId: UUID(), weights: [], reps: [])
        context.insert(log)
        context.insert(AerobicResult(logId: log.id, durationSeconds: 900))
        DraftMode.note(log: log.id, in: context)
        try context.save()

        DraftMode.discardAll(in: context)
        #expect(try context.fetch(FetchDescriptor<WorkoutLog>()).isEmpty)
        // The measurements belong to the log; leaving them would be an orphan
        // row nothing could ever reach.
        #expect(try context.fetch(FetchDescriptor<AerobicResult>()).isEmpty)
    }

    @Test @MainActor func discardingUnpicksADraftExerciseFromAKeptWorkout() throws {
        // A draft exercise added to a workout that existed before: deleting the
        // exercise must take it out of that workout too, or the workout is left
        // pointing at something that is gone.
        let url = temporaryStoreURL(); defer { removeStore(at: url) }
        let container = try ModelContainer(
            for: Schema(versionedSchema: WorkoutLogSchemaV7.self),
            configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
        let context = ModelContext(container)

        let workout = WorkoutDef(name: "Upper body")
        context.insert(workout)
        try context.save()

        DraftMode.start(in: context)
        let sketch = ExerciseDef(name: "Sketch", primaryMuscle: .back)
        context.insert(sketch)
        DraftMode.note(exercise: sketch.id, in: context)
        workout.exerciseOrder.append(sketch.id)
        try context.save()

        DraftMode.discardAll(in: context)
        let kept = try #require(try context.fetch(FetchDescriptor<WorkoutDef>()).first)
        #expect(kept.name == "Upper body")
        #expect(kept.exerciseOrder.isEmpty)
    }

    @Test @MainActor func draftSurvivesARelaunch() throws {
        // Held in the store, not in memory: coming back to find draft quietly
        // off, with nothing marked any more, is how work gets lost by accident.
        let url = temporaryStoreURL(); defer { removeStore(at: url) }
        let container = try ModelContainer(
            for: Schema(versionedSchema: WorkoutLogSchemaV7.self),
            configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
        DraftMode.start(in: ModelContext(container))
        #expect(DraftMode.isOn(in: ModelContext(container)))
    }

    @Test @MainActor func switchingDraftOnTwiceKeepsOneSession() throws {
        let url = temporaryStoreURL(); defer { removeStore(at: url) }
        let container = try ModelContainer(
            for: Schema(versionedSchema: WorkoutLogSchemaV7.self),
            configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
        let context = ModelContext(container)
        let first = DraftMode.start(in: context)
        let second = DraftMode.start(in: context)
        #expect(first.id == second.id)
        #expect(try context.fetch(FetchDescriptor<DraftSession>()).count == 1)
    }

    @Test @MainActor func nothingIsRecordedWhileDraftIsOff() throws {
        let url = temporaryStoreURL(); defer { removeStore(at: url) }
        let container = try ModelContainer(
            for: Schema(versionedSchema: WorkoutLogSchemaV7.self),
            configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
        let context = ModelContext(container)
        // The call sites are unconditional, so this has to be a safe no-op.
        DraftMode.note(exercise: UUID(), in: context)
        #expect(try context.fetch(FetchDescriptor<DraftSession>()).isEmpty)
    }

    @Test @MainActor func aV6StoreReachesV7WithItsDataIntact() throws {
        let url = temporaryStoreURL(); defer { removeStore(at: url) }
        do {
            let container = try ModelContainer(
                for: Schema(versionedSchema: WorkoutLogSchemaV2.self),
                configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
            let context = ModelContext(container)
            context.insert(WorkoutLogSchemaV1.ExerciseDef(name: "Squat"))
            try context.save()
        }
        let container = try ModelContainer(
            for: Schema(versionedSchema: WorkoutLogSchemaV7.self),
            migrationPlan: WorkoutMigrationPlan.self,
            configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
        let exercise = try #require(try ModelContext(container)
            .fetch(FetchDescriptor<ExerciseDef>()).first)
        #expect(exercise.name == "Squat")
        #expect(!DraftMode.isOn(in: ModelContext(container)))
    }

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
            for: Schema(versionedSchema: WorkoutLogSchemaV6.self),
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
            for: Schema(versionedSchema: WorkoutLogSchemaV6.self),
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
            for: Schema(versionedSchema: WorkoutLogSchemaV6.self),
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
            for: Schema(versionedSchema: WorkoutLogSchemaV6.self),
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

    // MARK: - The Watch sync contract
    //
    // The phone and the Watch app update independently: a Watch on the new build
    // can be handed a payload from the old phone build for as long as it takes the
    // user to update the other one, and vice versa. A field added to this contract
    // must therefore never be the reason a payload fails to decode — that would
    // take the Watch's whole exercise list away, not just its rest times.

    @Test func aPayloadFromBeforeTheRestTimerStillDecodes() throws {
        let json = """
        {"workouts":[{"id":"w1","name":"Upper","exerciseOrder":["e1"]}],
         "exercises":[{"id":"e1","name":"Row","numberOfSeries":3,"lowestWeight":20,
                       "highestWeight":120,"weightIncrement":5}],
         "lastEntries":{},"healthSharingEnabled":true}
        """
        let payload = try JSONDecoder().decode(SyncPayload.self, from: Data(json.utf8))
        #expect(payload.exercises.count == 1)
        #expect(payload.exercises[0].name == "Row")
        // The rest has to land on something usable: zero would mean "no rest" and
        // the Watch would never run the timer for that exercise.
        #expect(payload.exercises[0].restSeconds == SyncDefaults.restSeconds)
        #expect(payload.healthSharingEnabled)
        // An old phone cannot have the timer on, so off is the only honest reading.
        #expect(!payload.restTimerEnabled)
    }

    @Test func restTimesAndTheSwitchSurviveTheRoundTrip() throws {
        let payload = SyncPayload(
            workouts: [SyncWorkout(id: "w1", name: "Upper", exerciseOrder: ["e1"])],
            exercises: [SyncExercise(id: "e1", name: "Row", numberOfSeries: 3,
                                     lowestWeight: 20, highestWeight: 120,
                                     weightIncrement: 5, restSeconds: 150)],
            lastEntries: [:],
            healthSharingEnabled: false,
            restTimerEnabled: true)
        let restored = try JSONDecoder().decode(
            SyncPayload.self, from: try JSONEncoder().encode(payload))
        #expect(restored.exercises[0].restSeconds == 150)
        #expect(restored.restTimerEnabled)
    }

    @Test func theSyncFallbackMatchesThePhonesDefault() {
        // Two literals in two files that must not drift: the Watch copy of the
        // sync contract cannot see RestTimerDefaults.
        #expect(SyncDefaults.restSeconds == RestTimerDefaults.seconds)
    }

    // MARK: - The rest, drained across the log screen
    //
    // The grey used to be a three-second settle before a separate countdown
    // screen; it is now the whole rest, on the log screen. It is still derived
    // from two dates rather than animated — each turn of a wheel once reset an
    // animation, and SwiftUI blended the stack of them into a drain far longer
    // than the rest itself. These pin the shape, because that failure was
    // invisible to reading the code.

    private let restTotal: TimeInterval = 90
    private let restStart = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func theGreyIsFullWhenTheRestStarts() {
        let fill = RestTimer.restFill(endsAt: restStart.addingTimeInterval(restTotal),
                                      now: restStart, total: restTotal)
        #expect(abs(fill - 1) < 1e-9)
    }

    @Test func theGreyIsHalfwayDownHalfwayThroughTheRest() {
        let fill = RestTimer.restFill(endsAt: restStart.addingTimeInterval(restTotal),
                                      now: restStart.addingTimeInterval(restTotal / 2),
                                      total: restTotal)
        #expect(abs(fill - 0.5) < 1e-9)
    }

    @Test func theGreyIsGoneWhenTheRestIsOver() {
        // However many times a wheel moved on the way: at the end there must be
        // nothing left, and nothing after it either.
        let end = restStart.addingTimeInterval(restTotal)
        #expect(RestTimer.restFill(endsAt: end, now: end, total: restTotal) == 0)
        #expect(RestTimer.restFill(endsAt: end, now: end.addingTimeInterval(60),
                                   total: restTotal) == 0)
    }

    @Test func noRestLeavesNothingOnScreen() {
        // Quitting mid-rest must not leave grey over the workout list.
        #expect(RestTimer.restFill(endsAt: nil, now: restStart, total: restTotal) == 0)
        #expect(RestTimer.restFill(endsAt: restStart, now: restStart, total: 0) == 0)
    }

    @Test func theGreyNeverExceedsTheScreen() {
        // A clock that jumped backwards must not produce a rectangle taller than
        // the screen it covers.
        let fill = RestTimer.restFill(endsAt: restStart.addingTimeInterval(600),
                                      now: restStart, total: restTotal)
        #expect(fill == 1)
    }

    // MARK: - V6: aerobic exercises
    //
    // V6 is the first version to change WorkoutLog since V2. That class had been
    // the live one AND the shape V3, V4 and V5 all described, so adding a field to
    // it would have changed four versions at once — the collision that aborted
    // staged migration twice before. V2's copy is frozen and the live log is new.
    // These check that the rows survived that move.

    @Test func anExerciseFromBeforeAerobicIsAStrengthExercise() throws {
        let url = temporaryStoreURL()
        defer { removeStore(at: url) }
        do {
            let container = try ModelContainer(
                for: Schema(versionedSchema: WorkoutLogSchemaV2.self),
                configurations: ModelConfiguration(url: url, cloudKitDatabase: .none)
            )
            let context = ModelContext(container)
            context.insert(WorkoutLogSchemaV1.ExerciseDef(name: "Squat"))
            try context.save()
        }
        let container = try ModelContainer(
            for: Schema(versionedSchema: WorkoutLogSchemaV6.self),
            migrationPlan: WorkoutMigrationPlan.self,
            configurations: ModelConfiguration(url: url, cloudKitDatabase: .none)
        )
        let exercise = try #require(try ModelContext(container)
            .fetch(FetchDescriptor<ExerciseDef>()).first)
        #expect(exercise.kind == .strength)
        #expect(exercise.aerobicActivity == nil)
    }
    @Test func anAerobicSessionKeepsItsMeasurements() throws {
        let url = temporaryStoreURL()
        defer { removeStore(at: url) }
        let container = try ModelContainer(
            for: Schema(versionedSchema: WorkoutLogSchemaV6.self),
            configurations: ModelConfiguration(url: url, cloudKitDatabase: .none)
        )
        let context = ModelContext(container)
        let rower = ExerciseDef(name: "Exercise bike", kind: .aerobic, aerobicActivity: .indoorCycle)
        context.insert(rower)
        let log = WorkoutLog(workoutId: UUID(), exerciseId: rower.id, weights: [], reps: [])
        context.insert(log)
        context.insert(AerobicResult(logId: log.id, durationSeconds: 1200,
                                     averageHeartRate: 138, maximumHeartRate: 161,
                                     zoneSeconds: [120, 300, 600, 180, 0]))
        try context.save()

        let fresh = ModelContext(container)
        let result = try #require(try fresh.fetch(FetchDescriptor<AerobicResult>()).first)
        #expect(result.logId == log.id)
        #expect(result.durationSeconds == 1200)
        #expect(result.averageHeartRate == 138)
        #expect(result.maximumHeartRate == 161)
        #expect(result.zoneSeconds == [120, 300, 600, 180, 0])

        let exercise = try #require(try fresh.fetch(FetchDescriptor<ExerciseDef>()).first)
        #expect(exercise.kind == .aerobic)
        #expect(exercise.aerobicActivity == .indoorCycle)
    }
    /// The trap that shaped the design above, kept as a test so the reasoning is
    /// not just a comment: measurements set in `init` must survive, which is what
    /// failed while these lived on a second class also called WorkoutLog.
    @Test func aerobicMeasurementsSetInInitSurvive() throws {
        let url = temporaryStoreURL()
        defer { removeStore(at: url) }
        let container = try ModelContainer(
            for: Schema(versionedSchema: WorkoutLogSchemaV6.self),
            configurations: ModelConfiguration(url: url, cloudKitDatabase: .none)
        )
        let context = ModelContext(container)
        let logId = UUID()
        context.insert(AerobicResult(logId: logId, durationSeconds: 900,
                                     averageHeartRate: 121, zoneSeconds: [60, 120, 500, 220, 0]))
        try context.save()
        let reread = try #require(try ModelContext(container)
            .fetch(FetchDescriptor<AerobicResult>()).first)
        #expect(reread.durationSeconds == 900)
        #expect(reread.averageHeartRate == 121)
        #expect(reread.maximumHeartRate == 0)
        #expect(reread.zoneSeconds == [60, 120, 500, 220, 0])
    }
    /// The V6 schema must open. It did not, while `AerobicResult` carried optional
    /// `Int?` columns: CoreData threw from `encodeNil` building the entity's
    /// defaults, and every test that opened a container died with it. The heart
    /// rates are plain `Int` with zero meaning "not measured" for that reason.
    @Test func theAerobicSchemaOpens() throws {
        let url = temporaryStoreURL()
        defer { removeStore(at: url) }
        _ = try ModelContainer(
            for: Schema(versionedSchema: WorkoutLogSchemaV6.self),
            configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
    }
    @Test func propertiesSetInInitActuallyPersist() throws {
        // Does an ExerciseDef built by its initialiser keep what it was built with,
        // once inserted and read back? `ExerciseDefaults.makeExercise` sets every
        // value that way, so if this fails, the rest a user chose never reaches
        // their exercises — in the shipped version, not just on this branch.
        let url = temporaryStoreURL()
        defer { removeStore(at: url) }
        let container = try ModelContainer(
            for: Schema(versionedSchema: WorkoutLogSchemaV6.self),
            configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
        let context = ModelContext(container)
        context.insert(ExerciseDef(name: "Exercise bike", numberOfSeries: 4,
                                   restSeconds: 120,
                                   kind: .aerobic, aerobicActivity: .indoorCycle))
        try context.save()

        let reread = try #require(try ModelContext(container)
            .fetch(FetchDescriptor<ExerciseDef>()).first)
        #expect(reread.name == "Exercise bike")
        #expect(reread.numberOfSeries == 4)
        #expect(reread.restSeconds == 120)
        #expect(reread.kind == .aerobic)
    }
}

// MARK: - The aerobic countdown

@Test func aerobicMinutesCoverAUsefulRange() {
    #expect(AerobicDefaults.minuteChoices.first == 1)
    #expect(AerobicDefaults.minuteChoices.last == 120)
    // The default has to be one of the choices or the wheel opens blank.
    #expect(AerobicDefaults.minuteChoices.contains(AerobicDefaults.defaultMinutes))
}

@Test func aerobicDurationsAreLabelledAsMinutesAndSeconds() {
    #expect(AerobicDefaults.label(1200) == "20:00")
    #expect(AerobicDefaults.label(90) == "1:30")
    #expect(AerobicDefaults.label(0) == "0:00")
    // Over an hour keeps counting in minutes rather than wrapping to 0:00,
    // because a 75-minute ride shown as "15:00" would be a lie.
    #expect(AerobicDefaults.label(4500) == "75:00")
}

// MARK: - What each kind of exercise requires

@Test func aStrengthExerciseStillNeedsAMuscleGroup() {
    let e = ExerciseDef(name: "Bench press")
    #expect(e.kind == .strength)
    #expect(e.primaryMuscle == nil)          // so it is not saveable yet
    e.primaryMuscle = .chest
    #expect(e.primaryMuscle == .chest)
}

@Test func anAerobicExerciseCarriesAnActivityInsteadOfMuscles() {
    let e = ExerciseDef(name: "Exercise bike", kind: .aerobic, aerobicActivity: .indoorCycle)
    #expect(e.kind == .aerobic)
    #expect(e.aerobicActivity == .indoorCycle)
    // Muscle groups are not forbidden on the model — nothing reads them for an
    // aerobic exercise, and forbidding them would mean destroying what someone
    // had already set if they switched a strength exercise over by mistake.
    #expect(e.primaryMuscle == nil)
}

@Test func bothKindsAreOfferedAndLabelled() {
    #expect(ExerciseKind.allCases == [.strength, .aerobic])
    for kind in ExerciseKind.allCases { #expect(!kind.label.isEmpty) }
}

@Test func theIndoorActivitiesAreNamedAsAppleNamesThem() {
    // The order is chosen — machines first — and the head of it is pinned so a
    // case added later cannot quietly push the common ones down the picker.
    #expect(AerobicActivity.allCases.prefix(5).map(\.label) ==
            ["Indoor walk", "Indoor run", "Indoor cycle", "Elliptical", "Rower"])

    // Traditional strength training is an indoor Apple workout, but it is what
    // this app writes for a strength session; offering it here would let one
    // exercise claim to be both kinds at once.
    #expect(!AerobicActivity.allCases.contains {
        $0.label.localizedCaseInsensitiveContains("traditional")
    })

    for activity in AerobicActivity.allCases {
        #expect(!activity.label.isEmpty)
        #expect(AerobicActivity(rawValue: activity.rawValue) == activity)
    }
    // Two identical rows in a picker cannot be told apart.
    #expect(Set(AerobicActivity.allCases.map(\.label)).count == AerobicActivity.allCases.count)
}

// MARK: - Library order

@Test func starredAndUsedExercisesComeFirst() {
    let starred = LibraryOrder.rank(isFavourite: true, isInAnyWorkout: false,
                                    choosingForWorkout: false)
    let used = LibraryOrder.rank(isFavourite: false, isInAnyWorkout: true,
                                 choosingForWorkout: false)
    let unused = LibraryOrder.rank(isFavourite: false, isInAnyWorkout: false,
                                   choosingForWorkout: false)
    #expect(starred < used)
    #expect(used < unused)
}

@Test func aStarBeatsBeingInAWorkout() {
    // Starring is the explicit signal; being in a workout is circumstantial.
    #expect(LibraryOrder.rank(isFavourite: true, isInAnyWorkout: false,
                              choosingForWorkout: false)
            < LibraryOrder.rank(isFavourite: false, isInAnyWorkout: true,
                                choosingForWorkout: false))
}

@Test func choosingForAWorkoutDoesNotReorderOnEveryTap() {
    // Tapping a row is what changes membership here, so membership must not
    // decide position — otherwise each tick throws the list about under the
    // finger that made it.
    let inIt = LibraryOrder.rank(isFavourite: false, isInAnyWorkout: true,
                                 choosingForWorkout: true)
    let notInIt = LibraryOrder.rank(isFavourite: false, isInAnyWorkout: false,
                                    choosingForWorkout: true)
    #expect(inIt == notInIt)
    // Stars still float, as they always did.
    #expect(LibraryOrder.rank(isFavourite: true, isInAnyWorkout: false,
                              choosingForWorkout: true) < inIt)
}

// MARK: - Taking a ready-made exercise
//
// Both the phone and the Mac take library entries through ExerciseLibrary.take.
// It replaced a helper that nothing called and that quietly disagreed with what
// the phone actually did — the sort of thing the second caller finds the hard
// way.

@Test func takingALibraryEntryKeepsItsKeyAndItsMuscles() {
    let entry = ExerciseLibrary.entry(key: "bench-press")!
    let taken = ExerciseLibrary.take(entry, existingNames: [])

    #expect(taken.name == "Bench press")
    #expect(taken.libraryKey == "bench-press")
    #expect(taken.primaryMuscle == .chest)
    #expect(taken.secondaryMuscles.contains(.triceps))
    #expect(taken.kind == .strength)
}

@Test func takingAnAerobicEntryCarriesTheAppleWorkout() {
    let entry = ExerciseLibrary.aerobic.first { $0.activity == .indoorCycle }!
    let taken = ExerciseLibrary.take(entry, existingNames: [])

    #expect(taken.kind == .aerobic)
    #expect(taken.aerobicActivity == .indoorCycle)
    #expect(taken.libraryKey == entry.key)
}

@Test func aSecondCopyGetsANumberRatherThanTheSameName() {
    // Two exercises with one name are indistinguishable in every list that
    // shows them.
    let entry = ExerciseLibrary.entry(key: "squat")!
    #expect(ExerciseLibrary.take(entry, existingNames: ["Squat"]).name == "Squat 2")
    #expect(ExerciseLibrary.take(entry, existingNames: ["Squat", "Squat 2"]).name == "Squat 3")
    // Case is not what makes two names different to a reader.
    #expect(ExerciseLibrary.take(entry, existingNames: ["squat"]).name == "Squat 2")
}

@Test func anEntryAlreadyTakenIsNotOfferedAgain() {
    let mine = [ExerciseLibrary.take(ExerciseLibrary.entry(key: "deadlift")!,
                                     existingNames: []),
                ExerciseDef(name: "Something I invented")]
    let taken = ExerciseLibrary.takenKeys(in: mine)

    #expect(taken.contains("deadlift"))
    #expect(taken.count == 1)          // the invented one has no key to clash
}

@Test func everyLibraryKeyIsUnique() {
    // The key is what identifies a movement across users; two entries sharing
    // one would merge two different lifts in any aggregate.
    let keys = ExerciseLibrary.all.map(\.key) + ExerciseLibrary.aerobic.map(\.key)
    #expect(Set(keys).count == keys.count)
}

// MARK: - Reading a log list
//
// Grouping and colouring moved to Shared when the Mac grew a logs screen. Both
// are claims about the user's training rather than decoration, so they are
// tested rather than eyeballed on one device.
//
// Not serialized: nothing here opens a store or writes a default. The suite is
// a grouping, not a lock.

struct LogListTests {

    private func log(_ minutesAgo: Int, workout: UUID, exercise: UUID,
                     weights: [Int] = [50], reps: [Int] = [8]) -> WorkoutLog {
        WorkoutLog(date: Date(timeIntervalSince1970: 1_000_000 - Double(minutesAgo) * 60),
                   workoutId: workout, exerciseId: exercise,
                   weights: weights, reps: reps)
    }

    @Test func exercisesDoneTogetherBecomeOneSession() {
        let w = UUID(), a = UUID(), b = UUID(), c = UUID()
        // Newest first, as the screens query them.
        let logs = [log(0, workout: w, exercise: a),
                    log(10, workout: w, exercise: b),
                    log(20, workout: w, exercise: c)]
        let sessions = LogSessions.group(logs, workoutNames: [w: "Upper"])

        #expect(sessions.count == 1)
        #expect(sessions[0].logs.count == 3)
        #expect(sessions[0].workoutName == "Upper")
    }

    @Test func anHourApartStartsANewSession() {
        // The same workout twice in a week must not read as one impossibly
        // long session.
        let w = UUID(), a = UUID()
        let logs = [log(0, workout: w, exercise: a),
                    log(61, workout: w, exercise: a)]
        #expect(LogSessions.group(logs, workoutNames: [w: "Upper"]).count == 2)
    }

    @Test func switchingWorkoutStartsANewSessionEvenBackToBack() {
        let a = UUID(), b = UUID(), e = UUID()
        let logs = [log(0, workout: a, exercise: e),
                    log(2, workout: b, exercise: e)]
        let sessions = LogSessions.group(logs, workoutNames: [a: "Upper", b: "Lower"])
        #expect(sessions.count == 2)
        #expect(sessions.map(\.workoutName) == ["Upper", "Lower"])
    }

    @Test func aWorkoutWithNoNameStillGroups() {
        // A log whose workout was deleted must not vanish from the list.
        let w = UUID(), e = UUID()
        let sessions = LogSessions.group([log(0, workout: w, exercise: e)], workoutNames: [:])
        #expect(sessions.count == 1)
        #expect(sessions[0].workoutName == "Workout")
    }

    @Test func theEarlierEntryIsTheMostRecentOlderOne() {
        let w = UUID(), mine = UUID(), other = UUID()
        let newest = log(0, workout: w, exercise: mine, weights: [60])
        let middle = log(30, workout: w, exercise: other, weights: [40])
        let older = log(60, workout: w, exercise: mine, weights: [55])
        let oldest = log(90, workout: w, exercise: mine, weights: [50])
        let logs = [newest, middle, older, oldest]

        let found = LogComparison.previous(for: mine, before: newest.date, in: logs)
        #expect(found?.weights == [55])          // not the oldest, not the other exercise
        #expect(LogComparison.previous(for: mine, before: oldest.date, in: logs) == nil)
    }

    @Test func moreWeightReadsAsProgressAndLessDoesNot() {
        #expect(LogComparison.weightColour(current: 60, previous: 55) == .green)
        #expect(LogComparison.weightColour(current: 50, previous: 55) == .red)
        #expect(LogComparison.weightColour(current: 55, previous: 55) == .primary)
        // Nothing to compare against is not progress and not a decline.
        #expect(LogComparison.weightColour(current: 55, previous: nil) == .primary)
    }

    @Test func extraRepsBoughtByDroppingTheWeightAreNotProgress() {
        // Ten reps at 40 after eight at 60 is not a better set, and colouring
        // it green would be flattery rather than information.
        #expect(LogComparison.repsColour(current: 10, previous: 8,
                                         currentWeight: 40, previousWeight: 60) == .primary)
        #expect(LogComparison.repsColour(current: 10, previous: 8,
                                         currentWeight: 60, previousWeight: 60) == .green)
        #expect(LogComparison.repsColour(current: 6, previous: 8,
                                         currentWeight: 60, previousWeight: 60) == .red)
        // Fewer reps at more weight is not a decline either.
        #expect(LogComparison.repsColour(current: 6, previous: 8,
                                         currentWeight: 70, previousWeight: 60) == .primary)
    }
}

// MARK: - Time labels

@Test func minutesAndSecondsDoNotWrapIntoHours() {
    #expect(minutesSeconds(90) == "1:30")
    #expect(minutesSeconds(45) == "0:45")
    #expect(minutesSeconds(0) == "0:00")
    // Someone timing a two-hour ride means 120 minutes, not "2:00:00".
    #expect(minutesSeconds(7200) == "120:00")
}

// MARK: - Editing logs undoably
//
// The log is the one thing in this app that cannot be re-made: a workout can be
// rebuilt in a minute, but nobody remembers what they lifted in March. The
// editor takes a copy first and "discard" puts it back, so the putting-back is
// tested against a real store rather than trusted.
//
// Serialized with the other container tests, for the reason given above them.

// MARK: - When a workout is over
//
// The user puts the phone in a pocket and forgets to press quit. Two things
// follow from that, and both are decided here rather than by whatever the app
// happens to be doing at the time.

@Test func aForgottenWorkoutEndsAtTheLastSetNotWhenItWasNoticed() {
    let started = Date(timeIntervalSince1970: 1_000_000)
    let lastSet = started.addingTimeInterval(45 * 60)      // 45 minutes of training
    let noticed = started.addingTimeInterval(6 * 3600)     // spotted six hours later

    let end = OpenWorkoutPolicy.endDate(startedAt: started,
                                        lastActivityAt: lastSet, now: noticed)
    // Not `noticed`: a forgotten workout must not be recorded as six hours of
    // strength training, which is what the Move ring would then be told.
    #expect(end == lastSet)
}

@Test func aWorkoutStillInProgressIsNotClosed() {
    let started = Date(timeIntervalSince1970: 1_000_000)
    let lastSet = started.addingTimeInterval(600)
    // Ten minutes between sets is a long rest, not the end of a workout.
    let soon = lastSet.addingTimeInterval(10 * 60)
    #expect(OpenWorkoutPolicy.endDate(startedAt: started,
                                      lastActivityAt: lastSet, now: soon) == nil)
    // An hour and a second is the end of it.
    let later = lastSet.addingTimeInterval(OpenWorkoutPolicy.idleLimit + 1)
    #expect(OpenWorkoutPolicy.endDate(startedAt: started,
                                      lastActivityAt: lastSet, now: later) == lastSet)
}

@Test func aWorkoutWithNothingLoggedIsNotRecordedAtAll() {
    // Opened the workout, changed their mind, walked out. Nothing happened,
    // and Health should not be told that something did.
    let started = Date(timeIntervalSince1970: 1_000_000)
    #expect(OpenWorkoutPolicy.closingDate(startedAt: started, lastActivityAt: started) == nil)
    #expect(OpenWorkoutPolicy.endDate(startedAt: started, lastActivityAt: started,
                                      now: started.addingTimeInterval(9999)) == nil)
}

@Test func anInterruptedSessionIsResumableForExactlyAsLongAsItIsOpen() {
    // One rule for both: a session the app will still resume is one it has not
    // yet declared finished. If these ever disagreed, there would be a window
    // where the workout had been written to Health and the app offered to carry
    // on with it anyway.
    let touched = Date(timeIntervalSince1970: 1_000_000)
    let inside = touched.addingTimeInterval(OpenWorkoutPolicy.idleLimit - 1)
    let outside = touched.addingTimeInterval(OpenWorkoutPolicy.idleLimit + 1)

    #expect(OpenWorkoutPolicy.isResumable(lastActivityAt: touched, now: inside))
    #expect(!OpenWorkoutPolicy.isResumable(lastActivityAt: touched, now: outside))
    #expect(OpenWorkoutPolicy.endDate(startedAt: touched.addingTimeInterval(-600),
                                      lastActivityAt: touched, now: inside) == nil)
    #expect(OpenWorkoutPolicy.endDate(startedAt: touched.addingTimeInterval(-600),
                                      lastActivityAt: touched, now: outside) != nil)
}

@Test func aClockThatWentBackwardsDoesNotThrowTheSessionAway() {
    // Crossing a timezone, or the phone correcting itself, can leave the saved
    // moment slightly in the future. Losing a workout in progress over that
    // would be a poor trade.
    let touched = Date(timeIntervalSince1970: 1_000_000)
    let earlier = touched.addingTimeInterval(-120)
    #expect(OpenWorkoutPolicy.isResumable(lastActivityAt: touched, now: earlier))
}

// MARK: - A rest carried across a hand-over
//
// Moving from phone to Watch is most likely exactly during a rest, and takes
// long enough that a rest begun again at the top would be noticeably wrong. The
// snapshot now carries the rest's end date, so the time the hand-over takes
// comes off the rest instead of being added to it.

@Test func aSnapshotFromBeforeRestsTravelledStillDecodes() throws {
    // A phone and a Watch can run different versions for a while after an
    // update. The older side's snapshot must still be read, as having no rest.
    let json = """
    {"workoutId":"W","currentIndex":1,"weights":[[50]],"reps":[[10]],
     "loggedIndices":[0],"startedAt":1000}
    """
    let snap = try JSONDecoder().decode(SessionSnapshot.self, from: Data(json.utf8))
    #expect(snap.currentIndex == 1)
    #expect(snap.restEndsAt == nil)
    #expect(snap.pendingRest() == nil)
    // No timestamp means it cannot be shown to be current, so it is not
    // offered for taking over from the application context.
    #expect(!snap.isFresh())
}

@Test func aRestInProgressSurvivesTheRoundTrip() throws {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let snap = SessionSnapshot(workoutId: "W", currentIndex: 0, weights: [], reps: [],
                               loggedIndices: [], startedAt: 0,
                               restEndsAt: now.timeIntervalSince1970 + 40, restTotal: 90,
                               updatedAt: now.timeIntervalSince1970)
    let back = try JSONDecoder().decode(SessionSnapshot.self,
                                        from: try JSONEncoder().encode(snap))
    let rest = try #require(back.pendingRest(now: now))
    // Forty seconds left of ninety: the other device picks up two thirds of the
    // way through, not at the top.
    #expect(rest.endsAt.timeIntervalSince(now) == 40)
    #expect(rest.total == 90)
}

@Test func aRestThatEndedDuringTheHandOverIsNotStartedAgain() {
    // The hand-over took longer than the rest had left. Nothing to carry on.
    let now = Date(timeIntervalSince1970: 1_000_000)
    let snap = SessionSnapshot(workoutId: "W", currentIndex: 0, weights: [], reps: [],
                               loggedIndices: [], startedAt: 0,
                               restEndsAt: now.timeIntervalSince1970 - 1, restTotal: 90)
    #expect(snap.pendingRest(now: now) == nil)
}

@Test func aStashedWorkoutGoesStaleAfterTheSameHourAsAutoEnd() {
    // The Watch cannot see Shared/, so the hour is written twice. A workout
    // the phone would already have closed must not be offered to the Watch.
    #expect(SessionSnapshot.staleAfter == OpenWorkoutPolicy.idleLimit)

    let now = Date(timeIntervalSince1970: 1_000_000)
    func stamped(_ secondsAgo: TimeInterval) -> SessionSnapshot {
        SessionSnapshot(workoutId: "W", currentIndex: 0, weights: [], reps: [],
                        loggedIndices: [], startedAt: 0,
                        updatedAt: now.timeIntervalSince1970 - secondsAgo)
    }
    #expect(stamped(60).isFresh(now: now))
    #expect(!stamped(OpenWorkoutPolicy.idleLimit + 1).isFresh(now: now))
}

@Test func theTwoCopiesOfTheSyncContractAreIdentical() throws {
    // Edited in pairs by hand; a snapshot field added to one side only would
    // decode as absent on the other and quietly drop the rest.
    let here = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
    let phone = try Data(contentsOf: here.appendingPathComponent("workout_aicode/WatchSync.swift"))
    let watch = try Data(contentsOf: here.appendingPathComponent("workout_aicode Watch App/WatchSync.swift"))
    #expect(phone == watch)
}

// MARK: - Heart rate zones
//
// A stand-in until the OS 27 SDK, where HealthKit hands over the user's real
// configuration. These pin the arithmetic and, more importantly, the edges —
// an empty Health database supplies nonsense, and the boundaries have to stay
// in order regardless.

@Test func fourThresholdsDivideTheFiveZones() {
    // Resting 60, max 180 → reserve 120. Thresholds at 50/60/70/80%.
    // Four, not five: zone 1 has no floor and zone 5 no ceiling.
    let z = HeartRateZones(restingHeartRate: 60, maximumHeartRate: 180)
    #expect(z.boundaries == [120, 132, 144, 156])
    #expect(z.boundaries.count == HeartRateZones.zoneCount - 1)
}

@Test func aHeartRateLandsInTheRightZone() {
    let z = HeartRateZones(restingHeartRate: 60, maximumHeartRate: 180)
    #expect(z.zone(for: 119) == 1)       // below the first threshold IS zone 1
    #expect(z.zone(for: 120) == 2)       // exactly on a threshold is the zone above
    #expect(z.zone(for: 131) == 2)
    #expect(z.zone(for: 143) == 3)
    #expect(z.zone(for: 144) == 4)
    #expect(z.zone(for: 175) == 5)
    #expect(z.zone(for: 250) == 5)       // above maximum is still the top zone
}

@Test func aRestingHeartRateIsInZoneOneNotBelowIt() {
    // The bug this replaced: sitting on the bike at 69 bpm lit no segment at
    // all and the phone said "below zone 1". Apple's zone 1 has no floor — it
    // is described as "under 90", not as a range — so every rate is in a zone.
    let z = HeartRateZones()
    #expect(z.zone(for: 40) == 1)
    #expect(z.zone(for: 69) == 1)
    #expect((1...HeartRateZones.zoneCount).contains(z.zone(for: 1)))
}

@Test func zoneRangesMeetWithoutOverlapping() {
    let z = HeartRateZones(restingHeartRate: 55, maximumHeartRate: 185)
    for zone in 1..<HeartRateZones.zoneCount {
        let this = z.range(forZone: zone)!
        let next = z.range(forZone: zone + 1)!
        #expect(this.upper! + 1 == next.lower!)
    }
    // Both ends are open: there is always a little less, and a little more.
    #expect(z.range(forZone: 1)?.lower == nil)
    #expect(z.range(forZone: 5)?.upper == nil)
    #expect(z.range(forZone: 0) == nil)
    #expect(z.range(forZone: 6) == nil)
}

@Test func nonsenseFromAnEmptyHealthDatabaseStillGivesUsableZones() {
    // A maximum at or below resting would stack every boundary on the next and
    // make "which zone" meaningless.
    let z = HeartRateZones(restingHeartRate: 200, maximumHeartRate: 50)
    #expect(z.maximumHeartRate > z.restingHeartRate)
    #expect(z.boundaries == z.boundaries.sorted())
    #expect(Set(z.boundaries).count == HeartRateZones.zoneCount - 1)
}

@Test func theEstimatedMaximumFollowsAgeButStaysSane() {
    #expect(HeartRateZones.estimatedMaximum(forAge: 40) == 180)
    #expect(HeartRateZones.estimatedMaximum(forAge: 20) == 200)
    // Nonsense ages come from a mis-set birth date, not from a 300-year-old.
    #expect(HeartRateZones.estimatedMaximum(forAge: 300) == 100)
    #expect(HeartRateZones.estimatedMaximum(forAge: -5) == 220)
}

@Test func zonesSayWhereTheyCameFrom() {
    // Nothing should ever claim to be the Workout app's own zones until it is.
    #expect(HeartRateZones().source == .estimated)
}

// MARK: - Time in zone

private func at(_ seconds: Int) -> Date {
    Date(timeIntervalSince1970: 1_700_000_000).addingTimeInterval(Double(seconds))
}

@Test func timeIsCreditedToTheZoneItWasSpentIn() {
    let zones = HeartRateZones(restingHeartRate: 60, maximumHeartRate: 180)
    var tally = ZoneTally(zones: zones)
    tally.add(beatsPerMinute: 130, at: at(0))    // zone 2, from here
    tally.add(beatsPerMinute: 150, at: at(30))   // 30s credited to zone 2
    tally.add(beatsPerMinute: 150, at: at(60))   // 30s to zone 4
    #expect(tally.seconds[1] == 30)
    #expect(tally.seconds[3] == 30)
    #expect(tally.totalCountedSeconds == 60)
}

@Test func theFirstReadingCreditsNothing() {
    // There is no interval before the first sample, and inventing one would
    // credit time that had not happened.
    var tally = ZoneTally(zones: HeartRateZones())
    tally.add(beatsPerMinute: 150, at: at(0))
    #expect(tally.totalCountedSeconds == 0)
}

@Test func easyEffortIsCountedInZoneOne() {
    // It used to be set aside as "below zone 1", which meant a gentle warm-up
    // vanished from the totals.
    let zones = HeartRateZones(restingHeartRate: 60, maximumHeartRate: 180)
    var tally = ZoneTally(zones: zones)
    tally.add(beatsPerMinute: 80, at: at(0))
    tally.add(beatsPerMinute: 80, at: at(45))
    #expect(tally.seconds[0] == 45)
    #expect(tally.totalCountedSeconds == 45)
}

@Test func aLongGapInReadingsIsNotGuessedAt() {
    // The wrist went down or the app slept. Filling in five minutes at the last
    // known rate would be inventing the middle of the session.
    let zones = HeartRateZones(restingHeartRate: 60, maximumHeartRate: 180)
    var tally = ZoneTally(zones: zones)
    tally.add(beatsPerMinute: 150, at: at(0))
    tally.add(beatsPerMinute: 150, at: at(300))
    #expect(tally.totalCountedSeconds == 0)
    // ...and it picks straight back up afterwards.
    tally.add(beatsPerMinute: 150, at: at(310))
    #expect(tally.totalCountedSeconds == 10)
}

@Test func totalsDoNotDependOnHowOftenTheWatchSamples() {
    // Dense and sparse streams over the same minute must agree, which counting
    // readings rather than intervals would not.
    let zones = HeartRateZones(restingHeartRate: 60, maximumHeartRate: 180)
    var dense = ZoneTally(zones: zones)
    for second in stride(from: 0, through: 60, by: 5) {
        dense.add(beatsPerMinute: 150, at: at(second))
    }
    var sparse = ZoneTally(zones: zones)
    sparse.add(beatsPerMinute: 150, at: at(0))
    sparse.add(beatsPerMinute: 150, at: at(60))
    #expect(dense.seconds == sparse.seconds)
    #expect(dense.totalCountedSeconds == 60)
}

// MARK: - Activity → Apple workout

@Test func everyActivityStartsTheRightAppleWorkout() {
    // A missing case does not fail, it starts a workout called "Other" — so
    // the absence of .other is the assertion that matters here.
    for activity in AerobicActivity.allCases {
        let type = WatchAerobicActivity.activityType(for: activity.rawValue)
        #expect(type != .other, "\(activity.rawValue) has no HealthKit workout type")
    }
}

@Test func distinctActivitiesStartDistinctWorkouts() {
    // Two activities mapped to the same HealthKit type would be
    // indistinguishable in Fitness afterwards.
    let types = AerobicActivity.allCases.map {
        WatchAerobicActivity.activityType(for: $0.rawValue)
    }
    #expect(Set(types).count == types.count)
}

@Test func anUnknownActivityStillProducesAWorkout() {
    // A newer phone naming something this build has never heard of should get
    // a workout, just an unlabelled one — not a crash and not nothing.
    #expect(WatchAerobicActivity.activityType(for: "jetpacking") == .other)
    #expect(WatchAerobicActivity.activityType(for: nil) == .other)
}

@Test func everyAerobicWorkoutIsAnIndoorOne() {
    // "Indoor" is the location type, not the activity — the whole reason the
    // names read as the Workout app's do.
    let configuration = WatchAerobicActivity.configuration(for: "indoorRun")
    #expect(configuration.activityType == .running)
    #expect(configuration.locationType == .indoor)
}

@Test func aZoneWorkedOutElsewhereTalliesTheSameWay() {
    // The phone takes the Watch's word for the zone, because the Watch is the
    // one that can read the resting rate the boundaries come from. Both routes
    // must credit time identically or the two devices would disagree about the
    // same session.
    let zones = HeartRateZones(restingHeartRate: 60, maximumHeartRate: 180)
    var byRate = ZoneTally(zones: zones)
    byRate.add(beatsPerMinute: 150, at: at(0))
    byRate.add(beatsPerMinute: 150, at: at(40))

    var byZone = ZoneTally(zones: zones)
    byZone.add(zone: zones.zone(for: 150), at: at(0))
    byZone.add(zone: zones.zone(for: 150), at: at(40))

    #expect(byRate.seconds == byZone.seconds)
    #expect(byZone.totalCountedSeconds == 40)
}

@Test func aReadingThatNeverArrivedIsCreditedNowhere() {
    // nil is not a zone, it is the absence of a measurement, and inventing a
    // home for it would put time in the totals that nobody trained.
    var tally = ZoneTally(zones: HeartRateZones())
    tally.add(zone: nil, at: at(0))
    tally.add(zone: nil, at: at(25))
    #expect(tally.totalCountedSeconds == 0)
}

// MARK: - Ready-made aerobic exercises
//
// These exist because the AE filter was otherwise an empty room: the activities
// were only ever choices on an exercise you first had to invent yourself, so
// there was nothing to find under the filter that advertises them.

@Test func everyIndoorWorkoutIsOfferedReadyMade() {
    #expect(ExerciseLibrary.aerobic.count == AerobicActivity.allCases.count)
    #expect(ExerciseLibrary.aerobic.map(\.activity) == AerobicActivity.allCases)
}

@Test func readyMadeAerobicKeysAreStableAndDistinct() {
    // The key is what makes the same activity comparable between people
    // however they rename their copy, so it must not collide with a strength
    // entry's key either.
    let aerobicKeys = Set(ExerciseLibrary.aerobic.map(\.key))
    #expect(aerobicKeys.count == ExerciseLibrary.aerobic.count)
    let strengthKeys = Set(ExerciseLibrary.all.map(\.key))
    #expect(aerobicKeys.isDisjoint(with: strengthKeys))
    #expect(ExerciseLibrary.aerobicEntry(key: "ae-indoorCycle")?.activity == .indoorCycle)
}

@Test func aReadyMadeAerobicExerciseIsNamedAsAppleNamesIt() {
    // "Indoor cycle" is what it is called on the Watch and in Fitness; a
    // private name here would mean the two never look like the same thing.
    for entry in ExerciseLibrary.aerobic {
        #expect(entry.name == entry.activity.label)
    }
}

// MARK: - Aerobic without a Watch
//
// The ordinary case for anyone who does not own one, and it has to be a
// complete experience rather than a degraded one: the countdown runs, the
// session is logged, and the only thing missing is the heart rate.

@Test func noHeartRateIsNotTheSameAsNoTimeInAnyZone() {
    // Five zeroes would claim a session was measured and spent nowhere; an
    // empty list says nothing was measured at all. The graphs will one day
    // have to tell those apart.
    let unmeasured = AerobicResult(logId: UUID(), durationSeconds: 600)
    #expect(unmeasured.zoneSeconds.isEmpty)
    #expect(unmeasured.averageHeartRate == 0)

    let measured = AerobicResult(logId: UUID(), durationSeconds: 600,
                                 averageHeartRate: 120, maximumHeartRate: 140,
                                 zoneSeconds: [600, 0, 0, 0, 0])
    #expect(!measured.zoneSeconds.isEmpty)
}

// MARK: - Zone colours and the remembered duration

@Test func eachZoneHasItsOwnColour() {
    // The phone painted every lit zone red, so zone 1 — the easy one — arrived
    // looking like the hardest, and the two devices disagreed about the same
    // heart rate. One shared table now.
    #expect(ZoneColour.all.count == HeartRateZones.zoneCount)
    #expect(Set(ZoneColour.all.map(String.init(describing:))).count == HeartRateZones.zoneCount)
    for zone in 1...HeartRateZones.zoneCount {
        #expect(ZoneColour.colour(zone) == ZoneColour.all[zone - 1])
    }
}

@Test func anOutOfRangeZoneDoesNotCrashTheBand() {
    #expect(ZoneColour.colour(0) == .secondary)
    #expect(ZoneColour.colour(99) == .secondary)
}

@Test func theWatchIsToldHowLongAnExerciseRanLastTime() throws {
    // Without this the Watch wheel opened at a flat twenty minutes for every
    // aerobic exercise, however long it was actually done for.
    let entry = SyncLastEntry(weights: [], reps: [], durationSeconds: 1080)
    let restored = try JSONDecoder().decode(
        SyncLastEntry.self, from: try JSONEncoder().encode(entry))
    #expect(restored.durationSeconds == 1080)
}

@Test func aLastEntryFromBeforeDurationsStillDecodes() throws {
    // The two apps update independently, so an older phone's payload must not
    // cost the Watch its whole exercise list.
    let json = """
    {"weights":[50,55],"reps":[10,8]}
    """
    let restored = try JSONDecoder().decode(SyncLastEntry.self, from: Data(json.utf8))
    #expect(restored.weights == [50, 55])
    #expect(restored.durationSeconds == 0)   // "not an aerobic exercise"
}
