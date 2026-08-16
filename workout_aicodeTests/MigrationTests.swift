import Testing
import Foundation
import SwiftData
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

    @Test func theRestTimerIsOffUntilItIsTurnedOn() {
        UserDefaults.standard.removeObject(forKey: RestTimerKey.enabled)
        #expect(!RestTimerDefaults.isEnabled)
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

    // MARK: - The settle acknowledgement
    //
    // This used to be animated state: each turn of a wheel reset a three-second
    // animation, and because the Digital Crown reports every value it passes, one
    // spin stacked dozens of overlapping animations of one property. SwiftUI
    // blended them, and the grey took far longer to drain than the rest itself —
    // on a 0:15 rest the haptic fired while it was still going down. It is now
    // derived from two dates, and these pin the shape of it, because the failure
    // was invisible to reading the code.

    private let settleWindow: TimeInterval = 3
    private let settleNow = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func theAcknowledgementIsFullAtTheMomentOfTheTouch() {
        let fill = RestTimer.settleFill(coverAt: settleNow.addingTimeInterval(settleWindow),
                                        now: settleNow, window: settleWindow)
        #expect(abs(fill - 1) < 1e-9)
    }

    @Test func theAcknowledgementIsHalfwayDownHalfwayThrough() {
        let fill = RestTimer.settleFill(coverAt: settleNow.addingTimeInterval(settleWindow),
                                        now: settleNow.addingTimeInterval(settleWindow / 2),
                                        window: settleWindow)
        #expect(abs(fill - 0.5) < 1e-9)
    }

    @Test func theAcknowledgementIsGoneWhenTheCoverIsDue() {
        // The whole complaint in one assertion: at the end of the window there must
        // be nothing left, however many times the wheel moved on the way there.
        let coverAt = settleNow.addingTimeInterval(settleWindow)
        #expect(RestTimer.settleFill(coverAt: coverAt, now: coverAt, window: settleWindow) == 0)
        #expect(RestTimer.settleFill(coverAt: coverAt,
                                     now: coverAt.addingTimeInterval(60),
                                     window: settleWindow) == 0)
    }

    @Test func aCancelledRestLeavesNothingOnScreen() {
        // Quitting mid-drain used to leave the grey sliding down over the workout
        // list, because the animation did not care that it had been called off.
        #expect(RestTimer.settleFill(coverAt: nil, now: settleNow, window: settleWindow) == 0)
    }

    @Test func theAcknowledgementNeverExceedsTheScreen() {
        // A clock that jumped backwards, or a cover date further out than the
        // window, must not produce a rectangle taller than what it covers.
        let fill = RestTimer.settleFill(coverAt: settleNow.addingTimeInterval(600),
                                        now: settleNow, window: settleWindow)
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
