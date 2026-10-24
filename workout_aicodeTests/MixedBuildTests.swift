import Testing
import Foundation
import SwiftData
@testable import workout_aicode

// MARK: - A phone on one build, a Watch on another
//
// The iPhone app, the Watch app and the Mac app are three separate installs
// that update when they each feel like it. The Watch updates when it is next
// charging on wifi; the Mac when its own App Store entry is opened. So the
// release that introduced grams WILL run against devices that know nothing
// about them, for hours or for weeks.
//
// The cost of getting this wrong is not cosmetic. `weights` has always been a
// plain unit-less number, and a build that reads it as grams records a 130 lb
// set as 130 g — one four-hundredth of the real weight, in a log nobody can
// reconstruct from memory. These tests hold both directions still.

@Suite(.serialized)
struct MixedBuildTests {

    /// A 20–120 lb wheel in 5 lb steps, the shape of a real machine.
    @MainActor private func store(unit: WeightUnit) throws -> (AppStore, ModelContext, ExerciseDef) {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mixed-\(UUID().uuidString).sqlite")
        let container = try ModelContainer(
            for: Schema(versionedSchema: WorkoutLogSchemaV9.self),
            configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
        let context = ModelContext(container)
        let press = ExerciseDef(name: "Chest press", numberOfSeries: 2,
                                lowestWeight: 20, highestWeight: 120, weightIncrement: 5)
        press.setWeightRange(lowest: 20, highest: 120, increment: 5, unit: unit)
        context.insert(press)
        try context.save()
        let store = AppStore(context: context)
        store.reloadAll()
        return (store, context, press)
    }

    /// Both unit keys set and put back: the history's unit, which these tests
    /// are about, and the display unit, which `AppStore` also reads.
    @MainActor private func withUnit(_ unit: WeightUnit, _ body: () throws -> Void) rethrows {
        let defaults = UserDefaults.standard
        let keys = [WeightHistory.statedUnitKey, WeightUnit.key]
        let saved = keys.map { defaults.string(forKey: $0) }
        for key in keys { defaults.set(unit.rawValue, forKey: key) }
        defer {
            for (key, value) in zip(keys, saved) {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        try body()
    }

    // MARK: The dangerous direction: an old Watch logging to a new phone

    @MainActor @Test func aSetFromAWatchThatKnowsNoGramsIsStoredAtItsRealWeight() throws {
        try withUnit(.pounds) {
            let (store, context, press) = try store(unit: .pounds)
            let logId = UUID()

            // What a Watch on the shipping build sends: the unit-less numbers
            // under "weights", and no grams at all.
            store.addWatchLog(id: logId, date: Date(), workoutId: UUID(),
                              exerciseId: press.id,
                              weights: [], reps: [10, 8],
                              legacyWeights: [130, 135])

            let stored = try #require(
                try context.fetch(FetchDescriptor<LogWeights>()).first { $0.logId == logId })
            // 130 lb, not 130 grams — which would read as 0 in any unit.
            #expect(stored.grams.map { WeightUnit.pounds.display(grams: $0) } == [130, 135])
            #expect(stored.grams.allSatisfy { $0 > 1000 })
        }
    }

    @MainActor @Test func aSetFromAWatchOnThisBuildIsStoredExactlyAsSent() throws {
        try withUnit(.pounds) {
            let (store, context, press) = try store(unit: .pounds)
            let logId = UUID()
            let grams = [WeightUnit.pounds.grams(from: 130)]

            // Both keys present, as this build sends them. The grams win, and
            // the unit-less numbers beside them are not consulted.
            store.addWatchLog(id: logId, date: Date(), workoutId: UUID(),
                              exerciseId: press.id,
                              weights: grams, reps: [10],
                              legacyWeights: [999])

            let stored = try #require(
                try context.fetch(FetchDescriptor<LogWeights>()).first { $0.logId == logId })
            #expect(stored.grams == grams)
        }
    }

    @MainActor @Test func anAssistedSetFromAnOldWatchSubtractsTheRightWeight() throws {
        try withUnit(.pounds) {
            let defaults = UserDefaults.standard
            let savedSource = defaults.string(forKey: BodyWeight.sourceKey)
            let savedManual = defaults.double(forKey: BodyWeight.manualKey)
            defaults.set(BodyWeightSource.manual.rawValue, forKey: BodyWeight.sourceKey)
            defaults.set(214.0, forKey: BodyWeight.manualKey)
            defer {
                if let savedSource { defaults.set(savedSource, forKey: BodyWeight.sourceKey) }
                else { defaults.removeObject(forKey: BodyWeight.sourceKey) }
                if savedManual > 0 { defaults.set(savedManual, forKey: BodyWeight.manualKey) }
                else { defaults.removeObject(forKey: BodyWeight.manualKey) }
            }

            let (store, context, _) = try store(unit: .pounds)
            let chinUp = ExerciseDef(name: "Assisted chin-up",
                                     lowestWeight: 0, highestWeight: 200, weightIncrement: 5,
                                     subtractsFromBodyWeight: true)
            chinUp.setWeightRange(lowest: 0, highest: 200, increment: 5, unit: .pounds)
            context.insert(chinUp)
            try context.save()
            store.reloadAll()

            let logId = UUID()
            store.addWatchLog(id: logId, date: Date(), workoutId: UUID(),
                              exerciseId: chinUp.id,
                              weights: [], reps: [8],
                              legacyWeights: [130])

            // The user's own arithmetic: 214 lb less the 130 the machine took.
            let stored = try #require(
                try context.fetch(FetchDescriptor<LogWeights>()).first { $0.logId == logId })
            #expect(stored.grams.map { WeightUnit.pounds.display(grams: $0) } == [84])
        }
    }

    // MARK: The other direction: what this phone sends out

    @MainActor @Test func thePrefillCarriesBothNumbersAndTheyAgree() throws {
        try withUnit(.pounds) {
            let (store, context, press) = try store(unit: .pounds)
            let workout = WorkoutDef(name: "Upper")
            workout.exerciseOrder = [press.id]
            context.insert(workout)
            let log = WorkoutLog(workoutId: workout.id, exerciseId: press.id,
                                 weights: [], reps: [10])
            context.insert(log)
            context.insert(LogWeights(logId: log.id,
                                      grams: [WeightWheel.snap(
                                        WeightUnit.pounds.grams(from: 100), for: press)]))
            try context.save()
            store.reloadAll()

            let data = try #require(store.watchSyncPayloadData())
            let payload = try JSONDecoder().decode(SyncPayload.self, from: data)
            let entry = try #require(payload.lastEntries[
                SyncPayload.lastEntryKey(workoutId: workout.id.uuidString,
                                         exerciseId: press.id.uuidString)])

            // An older Watch reads this and finds the number it expects.
            #expect(entry.weights == [100])
            // This one reads the grams, and they are a value on the wheel.
            #expect(entry.weightsGrams == [WeightWheel.snap(
                WeightUnit.pounds.grams(from: 100), for: press)])
            #expect(WeightWheel.values(for: press).contains(entry.weightsGrams[0]))
        }
    }

    @MainActor @Test func anOlderWatchFindsWeightsWhereItAlwaysWas() throws {
        // The payload as an older build decodes it: no gram keys anywhere,
        // because that build's types do not have them.
        let json = """
        {"weights":[130,135],"reps":[10,8],"durationSeconds":0}
        """
        let entry = try JSONDecoder().decode(SyncLastEntry.self, from: Data(json.utf8))
        #expect(entry.weights == [130, 135])
        #expect(entry.weightsGrams.isEmpty)
    }

    // MARK: A Watch on this build, a phone that is not

    @MainActor @Test func aPhoneWithNoGramsStillGivesTheWatchAUsableWheel() throws {
        // What an older phone sends: the three unit-less numbers, and zeros
        // where the grams would be.
        let sent = SyncExercise(id: UUID().uuidString, name: "Chest press",
                                numberOfSeries: 2,
                                lowestWeight: 20, highestWeight: 120, weightIncrement: 5,
                                restSeconds: 90, kindRaw: "strength",
                                aerobicActivityRaw: nil, subtractsFromBodyWeight: false)
        #expect(sent.hasGramRange == false)

        let repaired = sent.repairingGramRange(in: .pounds)
        #expect(repaired.hasGramRange)
        #expect(WeightUnit.pounds.display(grams: repaired.lowestGrams) == 20)
        #expect(WeightUnit.pounds.display(grams: repaired.highestGrams) == 120)
        #expect(WeightUnit.pounds.display(grams: repaired.incrementGrams) == 5)

        // And last time's 130 is read through that wheel rather than taken for
        // grams, which would have opened it at the bottom.
        let entry = SyncLastEntry(weights: [130], reps: [10])
        let grams = entry.grams(for: repaired, in: .pounds)
        #expect(grams.count == 1)
        #expect(WeightUnit.pounds.display(grams: grams[0]) == 130)
    }

    // MARK: Out and back again

    @MainActor @Test func aWeightSurvivesTheRoundTripThroughAnOlderDevice() throws {
        try withUnit(.pounds) {
            let (_, _, press) = try store(unit: .pounds)
            // Every value the wheel offers, written down for an older build and
            // read back again. None may move.
            for grams in WeightWheel.values(for: press) {
                let legacy = press.legacyWeight(fromGrams: grams, in: .pounds)
                let back = WeightHistory.grams(fromLegacy: legacy, of: press, in: .pounds)
                #expect(back == grams, "\(grams) g went out as \(legacy) and came back \(back)")
            }
        }
    }

    @MainActor @Test func theWheelsTicksAreTheSameTicksOnBothSides() throws {
        try withUnit(.kilograms) {
            let (_, _, press) = try store(unit: .kilograms)
            // The Watch's own conversion (on SyncExercise, which is all it has)
            // must agree with the phone's (on ExerciseDef) value for value, or
            // a set logged on the wrist lands between two steps.
            let sent = SyncExercise(id: press.id.uuidString, name: press.name,
                                    numberOfSeries: 2,
                                    lowestWeight: press.lowestWeight,
                                    highestWeight: press.highestWeight,
                                    weightIncrement: press.weightIncrement,
                                    restSeconds: 90, kindRaw: "strength",
                                    aerobicActivityRaw: nil, subtractsFromBodyWeight: false,
                                    lowestGrams: press.lowestWeightGrams ?? 0,
                                    highestGrams: press.highestWeightGrams ?? 0,
                                    incrementGrams: press.weightIncrementGrams ?? 0)
            for grams in WeightWheel.values(for: press) {
                #expect(sent.legacy(fromGrams: grams, in: .kilograms)
                        == press.legacyWeight(fromGrams: grams, in: .kilograms))
            }
            for legacy in stride(from: press.lowestWeight, through: press.highestWeight,
                                 by: press.weightIncrement) {
                #expect(sent.grams(fromLegacy: legacy, in: .kilograms)
                        == WeightHistory.grams(fromLegacy: legacy, of: press, in: .kilograms))
            }
        }
    }

    @MainActor @Test func aRangeRetypedInAnotherUnitIsReadAsAWeightNotATick() throws {
        try withUnit(.pounds) {
            let (_, context, press) = try store(unit: .pounds)
            // The user moved gym: same exercise, wheel re-typed in kilograms.
            // Its unit-less fields still describe the old pounds wheel.
            press.setWeightRange(lowest: 0, highest: 90, increment: 2.5, unit: .kilograms)
            try context.save()
            #expect(press.legacyRangeIsTheSameWheel(in: .pounds) == false)

            // A Watch that has not updated sends 100, meaning 100 lb. Counting
            // that as the sixteenth tick of the new wheel would make it 40 kg;
            // 100 lb is 45.
            let grams = WeightHistory.grams(fromLegacy: 100, of: press, in: .pounds)
            #expect(WeightUnit.kilograms.display(grams: grams) == 45.25)
            #expect(WeightUnit.pounds.display(grams: grams) == 100)
        }
    }

    // MARK: Changing units while one device is still behind

    @MainActor @Test func switchingTheDisplayUnitLeavesAnOlderWatchAlone() throws {
        try withUnit(.pounds) {
            let (store, context, press) = try store(unit: .pounds)
            let workout = WorkoutDef(name: "Upper")
            workout.exerciseOrder = [press.id]
            context.insert(workout)
            let log = WorkoutLog(workoutId: workout.id, exerciseId: press.id,
                                 weights: [], reps: [10])
            context.insert(log)
            context.insert(LogWeights(logId: log.id,
                                      grams: [WeightUnit.pounds.grams(from: 100)]))
            try context.save()
            store.reloadAll()

            func sentToTheWatch() throws -> SyncLastEntry {
                let data = try #require(store.watchSyncPayloadData())
                let payload = try JSONDecoder().decode(SyncPayload.self, from: data)
                return try #require(payload.lastEntries[
                    SyncPayload.lastEntryKey(workoutId: workout.id.uuidString,
                                             exerciseId: press.id.uuidString)])
            }

            let inPounds = try sentToTheWatch()
            // The user switches the app to kilograms. Their HISTORY is still in
            // pounds, and that — not the unit on screen — is what the
            // unit-less numbers are written in, so a Watch that has not
            // updated sees no change at all.
            UserDefaults.standard.set(WeightUnit.kilograms.rawValue, forKey: WeightUnit.key)
            let inKilograms = try sentToTheWatch()

            #expect(inPounds.weights == [100])
            #expect(inKilograms.weights == inPounds.weights)
            #expect(inKilograms.weightsGrams == inPounds.weightsGrams)
        }
    }

    @MainActor @Test func aWheelRetypedInTheOtherUnitStillLogsTheRightWeight() throws {
        try withUnit(.pounds) {
            let (store, context, press) = try store(unit: .pounds)
            // Moved gym: the wheel is re-typed in kilograms, 0–90 by 2.5.
            press.setWeightRange(lowest: 0, highest: 90, increment: 2.5, unit: .kilograms)
            try context.save()
            store.reloadAll()

            // A Watch that has not updated is sent that wheel rounded into the
            // user's history unit — 2.5 kg of increment cannot be written as a
            // whole number of pounds, so it arrives coarser.
            #expect(press.weightIncrement == 6)
            #expect(press.legacyRangeIsTheSameWheel(in: .pounds) == false)

            // It logs 132 from that coarser wheel. Read as a POSITION it would
            // be the twenty-second step of the kilogram wheel, 55 kg; read as
            // a weight, which is what it is, it is 59.9 kg — and the nearest
            // step of the real wheel is 60.
            let logId = UUID()
            store.addWatchLog(id: logId, date: Date(), workoutId: UUID(),
                              exerciseId: press.id,
                              weights: [], reps: [8], legacyWeights: [132])
            let stored = try #require(
                try context.fetch(FetchDescriptor<LogWeights>()).first { $0.logId == logId })
            #expect(WeightUnit.pounds.display(grams: stored.grams[0]) == 132)
            #expect(WeightWheel.snap(stored.grams[0], for: press)
                    == WeightUnit.kilograms.grams(from: 60))
        }
    }

    // MARK: Half-unit increments, typed on the phone

    @MainActor @Test func anIncrementOfHalfAUnitIsKeptAndShown() throws {
        try withUnit(.kilograms) {
            let (_, _, press) = try store(unit: .kilograms)
            press.setWeightRange(lowest: 0, highest: 10, increment: 0.5, unit: .kilograms)

            let range = try #require(press.weightRangeGrams)
            #expect(range.increment == 500)
            #expect(WeightUnit.kilograms.display(grams: range.increment) == 0.5)
            // And the wheel really does step in halves.
            let values = WeightWheel.values(for: press)
            #expect(values.count == 21)
            #expect(WeightUnit.kilograms.display(grams: values[1]) == 0.5)
            #expect(WeightText.string(grams: values[1], in: .kilograms) == "0½")
        }
    }

    @MainActor @Test func aQuarterIsTheFinestIncrementThatSurvives() throws {
        try withUnit(.kilograms) {
            let (_, _, press) = try store(unit: .kilograms)
            press.setWeightRange(lowest: 0, highest: 2, increment: 0.25, unit: .kilograms)
            #expect(try #require(press.weightRangeGrams).increment == 250)

            // Finer than a quarter is not a number any plate or machine is
            // marked in, and `setWeightRange` floors the increment there
            // rather than storing something the wheels cannot show.
            press.setWeightRange(lowest: 0, highest: 2, increment: 0.1, unit: .kilograms)
            let increment = try #require(press.weightRangeGrams).increment
            #expect(WeightUnit.kilograms.display(grams: increment) == 0.25)
        }
    }

    @MainActor @Test func editingTheWheelKeepsTheUnitLessRangeInStep() throws {
        try withUnit(.pounds) {
            let (_, _, press) = try store(unit: .pounds)
            #expect(press.weightIncrement == 5)

            // What the edit screen does: writes one gram field at a time,
            // never through `setWeightRange`. Found by reading a real store
            // after a real edit — the unit-less fields had not moved, so an
            // older Watch was still being sent the wheel from before.
            press.weightIncrementGrams = WeightUnit.kilograms.grams(from: 0.5)
            press.syncLegacyRange()

            #expect(press.weightIncrement == 1)
            #expect(press.legacyRangeIsTheSameWheel(in: .pounds) == false)
        }
    }

    @MainActor @Test func theUnitLessRangeIsLeftAloneWhileTheHistoryHasNoUnit() throws {
        let exercise = ExerciseDef(name: "New machine", numberOfSeries: 2,
                                   lowestWeight: 20, highestWeight: 120, weightIncrement: 5)
        // No grams yet — the question has not been answered. Writing zeros
        // over these would destroy the only numbers `adopt` has to work from.
        exercise.syncLegacyRange()
        #expect(exercise.lowestWeight == 20)
        #expect(exercise.highestWeight == 120)
        #expect(exercise.weightIncrement == 5)
    }

    @MainActor @Test func aNewExerciseCanStartOnAFractionalIncrement() throws {
        let d = UserDefaults.standard
        let keys = [ExerciseDefaultsKey.lowest, ExerciseDefaultsKey.highest,
                    ExerciseDefaultsKey.increment]
        let saved = keys.map { d.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) {
                if let value { d.set(value, forKey: key) } else { d.removeObject(forKey: key) }
            }
        }
        try withUnit(.kilograms) {
            // A rack of dumbbells going up in 2.5s — which the first-run
            // question could not express while these were whole numbers.
            d.set(2.5, forKey: ExerciseDefaultsKey.lowest)
            d.set(30.0, forKey: ExerciseDefaultsKey.highest)
            d.set(2.5, forKey: ExerciseDefaultsKey.increment)

            let exercise = ExerciseDefaults.makeExercise(name: "Dumbbell curl")
            let range = try #require(exercise.weightRangeGrams)
            #expect(WeightUnit.kilograms.display(grams: range.increment) == 2.5)
            #expect(WeightUnit.kilograms.display(grams: range.lowest) == 2.5)

            // And a whole number stored by a version that only had those still
            // reads back, rather than falling to the built-in default.
            d.set(5, forKey: ExerciseDefaultsKey.increment)
            #expect(ExerciseDefaults.current.increment == 5)
        }
    }

    // MARK: Weights zeroed by a version that has since been rolled back
    //
    // Reported from a real device, and the shape of the report is the whole
    // diagnosis: logs from 17 October onwards were right and everything older
    // read zero. The units work ran on that phone, wrote zeros, and was rolled
    // back — but rolling back the CODE does not roll back iCloud. The zeroed
    // LogWeights rows stayed in the account and synced down again, and
    // anything logged AFTER the rollback never had one, which is exactly where
    // the date splits.
    //
    // Both `pendingCount` and `adopt` asked whether a row EXISTED. A row full
    // of zeros exists, so it was skipped, every time, for ever. The same
    // mistake was made and fixed once already for the exercise range, whose
    // comment says it plainly: zero matters as much as nil.

    @MainActor @Test func weightsZeroedByAnEarlierVersionAreRepaired() throws {
        try withNoHistoryUnit {
            let (store, context, press) = try store(unit: .pounds)
            let log = WorkoutLog(workoutId: UUID(), exerciseId: press.id,
                                 weights: [100, 100], reps: [10, 8])
            context.insert(log)
            // What that version left behind: a row that is there and says
            // nothing.
            context.insert(LogWeights(logId: log.id, grams: [0, 0]))
            try context.save()
            store.reloadAll()

            #expect(WeightHistory.pendingCount(in: context) > 0,
                    "a zeroed row is unfinished business, not finished")
            #expect(WeightHistory.shouldAsk(in: context))

            WeightHistory.adopt(.pounds, in: context)

            let grams = store.weightsGrams(forLogId: log.id)
            #expect(grams.map { WeightUnit.pounds.display(grams: $0) } == [100, 100])
        }
    }

    @MainActor @Test func aSetGenuinelyLoggedAtNothingIsLeftAlone() throws {
        try withNoHistoryUnit {
            let (store, context, press) = try store(unit: .pounds)
            // Zero in the old field too: there is nothing to recover here, and
            // rewriting it would invent a weight the user never lifted.
            let log = WorkoutLog(workoutId: UUID(), exerciseId: press.id,
                                 weights: [0, 0], reps: [12, 12])
            context.insert(log)
            context.insert(LogWeights(logId: log.id, grams: [0, 0]))
            try context.save()
            store.reloadAll()

            WeightHistory.adopt(.pounds, in: context)
            #expect(store.weightsGrams(forLogId: log.id) == [0, 0])
        }
    }

    @MainActor @Test func aRepairedRowIsNotConvertedTwice() throws {
        try withNoHistoryUnit {
            let (store, context, press) = try store(unit: .pounds)
            let log = WorkoutLog(workoutId: UUID(), exerciseId: press.id,
                                 weights: [100], reps: [10])
            context.insert(log)
            context.insert(LogWeights(logId: log.id, grams: [0]))
            try context.save()
            store.reloadAll()

            WeightHistory.adopt(.pounds, in: context)
            let once = store.weightsGrams(forLogId: log.id)
            // `catchUp` runs on every launch, every foreground and every time
            // a record arrives. It must be able to run a hundred times.
            WeightHistory.catchUp(in: context)
            WeightHistory.catchUp(in: context)
            #expect(store.weightsGrams(forLogId: log.id) == once)
            #expect(WeightUnit.pounds.display(grams: once[0]) == 100)
        }
    }

    @MainActor @Test func anAssistedRecordZeroedTheSameWayIsRepaired() throws {
        try withNoHistoryUnit {
            let (store, context, press) = try store(unit: .pounds)
            let log = WorkoutLog(workoutId: UUID(), exerciseId: press.id,
                                 weights: [100], reps: [10])
            context.insert(log)
            context.insert(LogWeights(logId: log.id, grams: [0]))
            context.insert(AssistedResult(logId: log.id,
                                          bodyWeight: 214, machineSettings: [130],
                                          bodyWeightGrams: 0, machineSettingsGrams: [0]))
            try context.save()
            store.reloadAll()

            WeightHistory.adopt(.pounds, in: context)

            let assisted = try #require(store.assistedResult(forLogId: log.id))
            #expect(assisted.bodyWeightGrams == WeightUnit.pounds.grams(from: 214))
            #expect(assisted.machineSettingsGrams?
                        .map { WeightUnit.pounds.display(grams: $0) } == [130])
        }
    }

    /// With no answer recorded yet, as a phone meeting this version has.
    @MainActor private func withNoHistoryUnit(_ body: () throws -> Void) rethrows {
        let d = UserDefaults.standard
        let saved = d.string(forKey: WeightHistory.statedUnitKey)
        d.removeObject(forKey: WeightHistory.statedUnitKey)
        defer {
            if let saved { d.set(saved, forKey: WeightHistory.statedUnitKey) }
            else { d.removeObject(forKey: WeightHistory.statedUnitKey) }
        }
        try body()
    }

    // MARK: What the Mac app, and a rolled-back phone, can still read

    @MainActor @Test func aNewLogAlsoWritesTheNumberAnOlderBuildReads() throws {
        try withUnit(.pounds) {
            let (store, context, press) = try store(unit: .pounds)
            let logId = UUID()
            store.addWatchLog(id: logId, date: Date(), workoutId: UUID(),
                              exerciseId: press.id,
                              weights: [WeightUnit.pounds.grams(from: 130)], reps: [10],
                              legacyWeights: [])

            let log = try #require(
                try context.fetch(FetchDescriptor<WorkoutLog>()).first { $0.id == logId })
            // The old unit-less field is filled in too, so the Mac app shows
            // the set rather than a blank until its own update arrives.
            #expect(log.weights == [130])
        }
    }
}
