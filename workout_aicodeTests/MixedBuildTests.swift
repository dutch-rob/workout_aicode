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
