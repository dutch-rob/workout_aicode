import Testing
import Foundation
import SwiftData
@testable import workout_aicode

// MARK: - The units conversion, against a real export
//
// RealExport.json is a user's own logJSON.3 export from build 11, taken before
// any of the units work existed: 32 exercises and 138 logs, in the original
// unit-less fields. Three attempts at this change went wrong ON A PHONE SOMEONE
// TRAINS WITH, each verified by reasoning rather than against data of this
// shape. This suite is the answer to that: the conversion has to survive a real
// history before it goes anywhere near one again.
//
// In its own suite, serialized, and it opens containers — see the note in
// SchemaMigrationTests about two serialized suites running in parallel. These
// stores are created per test and thrown away, and nothing here writes
// UserDefaults except through `withStatedUnit`, which puts it back.
@Suite(.serialized)
struct RealDataTests {

    private func loadExport() throws -> ExportEnvelope {
        let url = try #require(Bundle(for: BundleToken.self)
            .url(forResource: "RealExport", withExtension: "json"))
        return try JSONDecoder().decode(ExportEnvelope.self, from: Data(contentsOf: url))
    }

    /// A store holding that export as it was: legacy numbers, no grams.
    @MainActor private func storeFromExport() throws -> (ModelContext, ExportEnvelope) {
        let envelope = try loadExport()
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("real-\(UUID().uuidString).sqlite")
        let container = try ModelContainer(
            for: Schema(versionedSchema: WorkoutLogSchemaV9.self),
            configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
        let context = ModelContext(container)
        for exercise in envelope.data.exercises { context.insert(exercise) }
        for workout in envelope.data.workouts { context.insert(workout) }
        for log in envelope.data.logs { context.insert(log) }
        try context.save()
        return (context, envelope)
    }

    @MainActor private func withStatedUnit(_ unit: WeightUnit?, _ body: () throws -> Void) rethrows {
        let defaults = UserDefaults.standard
        let savedHistory = defaults.string(forKey: WeightHistory.statedUnitKey)
        let savedDisplay = defaults.string(forKey: WeightUnit.key)
        if let unit { defaults.set(unit.rawValue, forKey: WeightHistory.statedUnitKey) }
        else { defaults.removeObject(forKey: WeightHistory.statedUnitKey) }
        defer {
            if let savedHistory { defaults.set(savedHistory, forKey: WeightHistory.statedUnitKey) }
            else { defaults.removeObject(forKey: WeightHistory.statedUnitKey) }
            if let savedDisplay { defaults.set(savedDisplay, forKey: WeightUnit.key) }
            else { defaults.removeObject(forKey: WeightUnit.key) }
        }
        try body()
    }

    // MARK: The question

    @MainActor @Test func aRealExportArrivesWantingAUnit() throws {
        try withStatedUnit(nil) {
            let (context, envelope) = try storeFromExport()
            #expect(envelope.data.exercises.count == 32)
            #expect(envelope.data.logs.count == 138)
            // Everything in it is waiting: 32 exercises, and every log that
            // has weights in it.
            let logsWithWeights = envelope.data.logs.filter { !$0.weights.isEmpty }.count
            #expect(WeightHistory.pendingCount(in: context) == 32 + logsWithWeights)
            #expect(WeightHistory.shouldAsk(in: context) == true)
        }
    }

    // MARK: What the answer does to it

    @MainActor @Test func everyLoggedWeightSurvivesTheConversion() throws {
        try withStatedUnit(nil) {
            let (context, envelope) = try storeFromExport()
            WeightHistory.adopt(.pounds, in: context)

            let byLog = LogWeightsIndex.byLogId(
                try context.fetch(FetchDescriptor<LogWeights>()))
            var checked = 0
            for log in envelope.data.logs where !log.weights.isEmpty {
                let grams = try #require(byLog[log.id],
                                         Comment(rawValue: "no weights for log \(log.id)"))
                let back = grams.map { WeightUnit.pounds.display(grams: $0) }
                #expect(back == log.weights.map(Double.init),
                        Comment(rawValue: "log \(log.id) came back as \(back), "
                                + "was \(log.weights)"))
                checked += 1
            }
            #expect(checked > 100)
        }
    }

    @MainActor @Test func everyExerciseEndsUpWithAUsableWheel() throws {
        try withStatedUnit(nil) {
            let (context, _) = try storeFromExport()
            WeightHistory.adopt(.pounds, in: context)

            for exercise in try context.fetch(FetchDescriptor<ExerciseDef>()) {
                let range = try #require(exercise.weightRangeGrams,
                                         Comment(rawValue: "\(exercise.name) has no range"))
                #expect(range.increment > 0)
                let values = WeightWheel.values(for: exercise)
                #expect(!values.isEmpty,
                        Comment(rawValue: "\(exercise.name) has an empty wheel"))
                // The ends the user set are the ends they get back.
                #expect(WeightUnit.pounds.display(grams: values.first ?? -1)
                        == Double(exercise.lowestWeight))
                #expect(WeightUnit.pounds.display(grams: values.last ?? -1)
                        == Double(exercise.highestWeight))
            }
        }
    }

    /// The property that actually matters at a machine: last time's number has
    /// to be ON the wheel, or the wheel cannot open where the user left it.
    @MainActor @Test func everyWeightEverLoggedIsStillOnItsWheel() throws {
        try withStatedUnit(nil) {
            let (context, envelope) = try storeFromExport()
            WeightHistory.adopt(.pounds, in: context)

            let exercises = Dictionary(
                try context.fetch(FetchDescriptor<ExerciseDef>()).map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first })
            let byLog = LogWeightsIndex.byLogId(
                try context.fetch(FetchDescriptor<LogWeights>()))

            for log in envelope.data.logs where !log.weights.isEmpty {
                guard let exercise = exercises[log.exerciseId],
                      exercise.kind == .strength else { continue }
                let wheel = Set(WeightWheel.values(for: exercise))
                for grams in byLog[log.id] ?? [] {
                    #expect(wheel.contains(grams),
                            Comment(rawValue: "\(exercise.name): "
                                    + WeightText.string(grams: grams, in: .pounds)
                                    + " was logged but is not on its wheel"))
                }
            }
        }
    }

    /// Reading the same history in the other unit changes the numbers on
    /// screen and nothing else.
    @MainActor @Test func switchingUnitsReReadsTheSameHistory() throws {
        try withStatedUnit(nil) {
            let (context, envelope) = try storeFromExport()
            WeightHistory.adopt(.pounds, in: context)

            let byLog = LogWeightsIndex.byLogId(
                try context.fetch(FetchDescriptor<LogWeights>()))
            let heavy = try #require(envelope.data.logs
                .first { $0.weights.contains(130) })
            let grams = try #require(byLog[heavy.id]).first ?? 0
            #expect(WeightUnit.pounds.display(grams: grams) == 130)
            // 130 lb is 59 kg, to the nearest quarter.
            #expect(WeightUnit.kilograms.display(grams: grams) == 59)
        }
    }

    /// The rows that were already odd in the real data stay odd rather than
    /// being invented into something.
    @MainActor @Test func theEmptyRowsInTheRealDataAreLeftAlone() throws {
        try withStatedUnit(nil) {
            let (context, envelope) = try storeFromExport()
            WeightHistory.adopt(.pounds, in: context)

            let empties = envelope.data.logs.filter { $0.weights.isEmpty }
            #expect(!empties.isEmpty)
            let byLog = LogWeightsIndex.byLogId(
                try context.fetch(FetchDescriptor<LogWeights>()))
            for log in empties {
                #expect((byLog[log.id] ?? []).isEmpty,
                        "an empty row was given weights it never had")
            }
        }
    }
}

/// Only to find the test bundle.
private final class BundleToken {}
