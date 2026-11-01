import Foundation
import SwiftData

// MARK: - Reading and writing the whole log
//
// The rules for a transfer file, away from any one screen: what a file may
// say, what replacing means, what merging means, and what the user is told
// afterwards.
//
// The FORMAT is all here, and both apps use it: what an export says it is,
// what metadata it carries, what the counts count, how a file of any version
// is read back, and what a spreadsheet row looks like. It did not start that
// way — the phone grew its own copy inside a view, and the two had already
// drifted: the phone wrote its version string as a literal while the Mac read
// it from `currentVersion`, and its spreadsheet was still the one from before
// weights had a unit, bare numbers with no column saying what they were.
//
// What each screen still owns is what it DOES with a file — which buttons it
// offers, what it says afterwards, whether it backs up first. That is a
// screen's business and differs on purpose.
//
// Nothing here presents anything. It throws or returns a summary, and the
// screen decides how to say it.

enum LogTransfer {

    /// What this app writes today. Every version only ADDED optional arrays,
    /// so an older file decodes into the current shape with those missing.
    static let currentVersion = "logJSON.4"

    enum Failure: LocalizedError {
        case notAnExport(String)
        case missingMetadata
        case countsDisagree(said: String, found: String)

        var errorDescription: String? {
            switch self {
            case .notAnExport(let version):
                return version.isEmpty
                    ? "This file is not a SetsRepsWheels export."
                    : "This file says it is version “\(version)”, which this app does not read."
            case .missingMetadata:
                return "This file is missing the app information every export carries, so it cannot be trusted to be complete."
            case .countsDisagree(let said, let found):
                return "This file says it holds \(said) but actually holds \(found)."
            }
        }
    }

    /// "1 workout", "3 workouts". Counts are read out all over both apps and
    /// English will not let a number stand next to a bare noun — "Added 1
    /// workouts" was on the screen until somebody imported a file with one
    /// thing in it.
    static func counted(_ n: Int, _ noun: String) -> String {
        "\(n) \(noun)\(n == 1 ? "" : "s")"
    }

    // MARK: Reading

    /// Decodes a file into the current shape, whatever version wrote it.
    ///
    /// The oldest format wrapped a whole session in one row with an entries
    /// array; those are flattened into one log per exercise, which is what
    /// everything since has stored.
    static func load(_ data: Data) throws -> ExportEnvelope {
        struct VersionPeek: Decodable { let exportVersion: String }
        let version = (try? JSONDecoder().decode(VersionPeek.self, from: data))?.exportVersion ?? ""
        let decoder = JSONDecoder()

        if version.hasPrefix("logJSON.1") {
            let legacy = try decoder.decode(LegacyExportEnvelope.self, from: data)
            let flat = legacy.data.logs.flatMap { $0.flatten() }
            return ExportEnvelope(
                exportVersion: "logJSON.2",
                appIdentifier: legacy.appIdentifier, appVersion: legacy.appVersion,
                build: legacy.build, exportedAt: legacy.exportedAt,
                device: legacy.device, locale: legacy.locale, timeZone: legacy.timeZone,
                counts: ExportEnvelope.Counts(workouts: legacy.data.workouts.count,
                                              exercises: legacy.data.exercises.count,
                                              logs: flat.count),
                data: ExportEnvelope.AllData(workouts: legacy.data.workouts,
                                             exercises: legacy.data.exercises,
                                             logs: flat))
        }
        // Anything else is tried as the current shape, including a version
        // newer than this build knows: the fields it does not recognise are
        // ignored, which is better than refusing a file outright.
        return try decoder.decode(ExportEnvelope.self, from: data)
    }

    /// Everything that can be checked without touching the store.
    static func validate(_ envelope: ExportEnvelope) throws {
        guard envelope.exportVersion.hasPrefix("logJSON.") else {
            throw Failure.notAnExport(envelope.exportVersion)
        }
        guard !envelope.appIdentifier.isEmpty, !envelope.appVersion.isEmpty,
              !envelope.build.isEmpty else {
            throw Failure.missingMetadata
        }
        let said = envelope.counts
        let data = envelope.data
        guard said.workouts == data.workouts.count,
              said.exercises == data.exercises.count,
              said.logs == data.logs.count else {
            throw Failure.countsDisagree(
                said: "\(counted(said.workouts, "workout")), \(counted(said.exercises, "exercise")) and \(counted(said.logs, "logged exercise"))",
                found: "\(data.workouts.count), \(data.exercises.count) and \(data.logs.count)")
        }
    }

    // MARK: What a file would do

    struct Preview {
        let version: String
        let exportedAt: String
        let workouts: Int
        let exercises: Int
        let logs: Int
        let oldest: Date?
        let newest: Date?
        /// Whether the file carries weights with a unit. One without them is
        /// from before weights had one, and its numbers mean whatever the
        /// person who exported it meant.
        let hasWeightsInGrams: Bool

        /// When the file was written, as a date rather than the string on the
        /// wire. Nil when that string cannot be read, and nil means say
        /// nothing: the phone used to put `Date.description(with: .current)`
        /// straight into an alert, which is a format for a debugger, and a
        /// stamp shown raw is worse than one left out.
        var written: Date? { ISO8601DateFormatter().date(from: exportedAt) }
    }

    static func preview(_ envelope: ExportEnvelope) -> Preview {
        let logs = envelope.data.logs
        return Preview(version: envelope.exportVersion,
                       exportedAt: envelope.exportedAt,
                       workouts: envelope.data.workouts.count,
                       exercises: envelope.data.exercises.count,
                       logs: logs.count,
                       oldest: logs.map(\.date).min(),
                       newest: logs.map(\.date).max(),
                       hasWeightsInGrams: !(envelope.data.logWeights ?? []).isEmpty)
    }

    // MARK: Writing it in

    struct MergeSummary {
        var insertedWorkouts = 0
        var insertedExercises = 0
        var insertedLogs = 0
        var renamedWorkouts = 0
        var renamedExercises = 0
        /// Rows already here with the same date, workout and exercise but
        /// different numbers. The one already here is kept.
        var conflicts = 0
    }

    /// Throws everything away and puts the file in its place.
    @MainActor
    static func replace(with envelope: ExportEnvelope, in context: ModelContext) throws {
        try validate(envelope)

        for log in (try? context.fetch(FetchDescriptor<WorkoutLog>())) ?? [] { context.delete(log) }
        for workout in (try? context.fetch(FetchDescriptor<WorkoutDef>())) ?? [] { context.delete(workout) }
        for exercise in (try? context.fetch(FetchDescriptor<ExerciseDef>())) ?? [] { context.delete(exercise) }
        // These hang off logs that are going, so they go too. Left behind they
        // would be orphans, and would then attach themselves to an imported
        // log that happened to reuse an id.
        for r in (try? context.fetch(FetchDescriptor<AerobicResult>())) ?? [] { context.delete(r) }
        for r in (try? context.fetch(FetchDescriptor<AssistedResult>())) ?? [] { context.delete(r) }
        for r in (try? context.fetch(FetchDescriptor<LogWeights>())) ?? [] { context.delete(r) }

        for exercise in envelope.data.exercises { context.insert(exercise) }
        for workout in envelope.data.workouts { context.insert(workout) }
        for log in envelope.data.logs { context.insert(log) }
        for r in envelope.data.aerobicResults ?? [] { context.insert(r) }
        for r in envelope.data.assistedResults ?? [] { context.insert(r) }
        for r in envelope.data.logWeights ?? [] { context.insert(r) }
        try context.save()
    }

    /// Adds what is missing and leaves what is here alone.
    ///
    /// Logs are matched on date, workout and exercise rather than on id,
    /// because the same set logged on two devices before they ever met has two
    /// ids and is still one set. Where the numbers disagree the row already
    /// here wins and the disagreement is counted, so the user is told rather
    /// than quietly overruled.
    @MainActor
    @discardableResult
    static func merge(_ envelope: ExportEnvelope, into context: ModelContext) throws -> MergeSummary {
        try validate(envelope)
        var summary = MergeSummary()

        let exercises = (try? context.fetch(FetchDescriptor<ExerciseDef>())) ?? []
        let workouts = (try? context.fetch(FetchDescriptor<WorkoutDef>())) ?? []
        let logs = (try? context.fetch(FetchDescriptor<WorkoutLog>())) ?? []

        for imported in envelope.data.exercises {
            if let existing = exercises.first(where: { $0.id == imported.id }) {
                if existing.name != imported.name {
                    existing.name = imported.name
                    summary.renamedExercises += 1
                }
            } else {
                context.insert(imported)
                summary.insertedExercises += 1
            }
        }
        for imported in envelope.data.workouts {
            if let existing = workouts.first(where: { $0.id == imported.id }) {
                if existing.name != imported.name {
                    existing.name = imported.name
                    summary.renamedWorkouts += 1
                }
            } else {
                context.insert(imported)
                summary.insertedWorkouts += 1
            }
        }

        struct Signature: Hashable {
            let date: Date
            let workoutId: UUID
            let exerciseId: UUID
        }
        let here = Dictionary(logs.map {
            (Signature(date: $0.date, workoutId: $0.workoutId, exerciseId: $0.exerciseId), $0)
        }, uniquingKeysWith: { first, _ in first })

        var arrivedLogIds: Set<UUID> = []
        for imported in envelope.data.logs {
            let key = Signature(date: imported.date, workoutId: imported.workoutId,
                                exerciseId: imported.exerciseId)
            if let existing = here[key] {
                if existing.weights != imported.weights || existing.reps != imported.reps {
                    summary.conflicts += 1
                }
            } else {
                context.insert(imported)
                summary.insertedLogs += 1
                arrivedLogIds.insert(imported.id)
            }
        }

        // A result belongs to one log. Where the log was skipped as a
        // duplicate its result is skipped too: the log that won is the one
        // already here, with whatever results it already had.
        let aerobicIds = Set(((try? context.fetch(FetchDescriptor<AerobicResult>())) ?? []).map(\.id))
        for r in envelope.data.aerobicResults ?? []
        where arrivedLogIds.contains(r.logId) && !aerobicIds.contains(r.id) {
            context.insert(r)
        }
        let assistedIds = Set(((try? context.fetch(FetchDescriptor<AssistedResult>())) ?? []).map(\.id))
        for r in envelope.data.assistedResults ?? []
        where arrivedLogIds.contains(r.logId) && !assistedIds.contains(r.id) {
            context.insert(r)
        }
        let weightIds = Set(((try? context.fetch(FetchDescriptor<LogWeights>())) ?? []).map(\.id))
        for r in envelope.data.logWeights ?? []
        where arrivedLogIds.contains(r.logId) && !weightIds.contains(r.id) {
            context.insert(r)
        }

        try context.save()
        return summary
    }

    // MARK: Writing it out

    /// The envelope an export writes.
    ///
    /// One place, because an envelope that does not match what `load` and
    /// `validate` expect is a file that leaves one app and is refused by the
    /// other — and the counts here are checked against the data there.
    /// `device` is the one thing the caller supplies: only it knows what it
    /// is running on.
    @MainActor
    static func envelope(workouts: [WorkoutDef], exercises: [ExerciseDef],
                         logs: [WorkoutLog],
                         aerobicResults: [AerobicResult] = [],
                         assistedResults: [AssistedResult] = [],
                         logWeights: [LogWeights] = [],
                         device: ExportEnvelope.DeviceInfo) -> ExportEnvelope {
        let bundle = Bundle.main
        return ExportEnvelope(
            exportVersion: currentVersion,
            appIdentifier: bundle.bundleIdentifier ?? "",
            appVersion: bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
            build: bundle.infoDictionary?["CFBundleVersion"] as? String ?? "",
            exportedAt: ISO8601DateFormatter().string(from: Date()),
            device: device,
            locale: Locale.current.identifier,
            timeZone: TimeZone.current.identifier,
            counts: ExportEnvelope.Counts(workouts: workouts.count,
                                          exercises: exercises.count,
                                          logs: logs.count),
            data: ExportEnvelope.AllData(workouts: workouts, exercises: exercises,
                                         logs: logs,
                                         aerobicResults: aerobicResults,
                                         assistedResults: assistedResults,
                                         logWeights: logWeights))
    }

    /// Pretty-printed, because a file a person may open in a text editor to
    /// see what is in it should be readable when they do.
    @MainActor
    static func encoded(_ envelope: ExportEnvelope) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        return try encoder.encode(envelope)
    }


    /// Every logged set as a row, for a spreadsheet.
    ///
    /// The weight is written in the unit the user reads, with a column saying
    /// which — a spreadsheet of bare numbers is the exact problem units were
    /// added to solve, and a file that leaves the shop without saying what its
    /// numbers mean recreates it outside the app.
    @MainActor
    static func tsv(logs: [WorkoutLog], workouts: [WorkoutDef], exercises: [ExerciseDef],
                    weightsByLog: [UUID: [Int]], unit: WeightUnit) -> String {
        var lines = ["date\ttime\tworkout\texercise\tset\tweight\tunit\treps\tlog output version: logTSV.2"]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd\tHH:mm"

        let workoutName = Dictionary(workouts.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        let exerciseName = Dictionary(exercises.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })

        for log in logs {
            let grams = weightsByLog[log.id] ?? []
            let count = max(grams.count, log.reps.count)
            guard count > 0 else { continue }
            let when = formatter.string(from: log.date)
            let workout = quoted(workoutName[log.workoutId] ?? "Workout")
            let exercise = quoted(exerciseName[log.exerciseId] ?? "Exercise")
            for index in 0..<count {
                let weight = index < grams.count
                    ? WeightText.string(grams: grams[index], in: unit) : ""
                let reps = index < log.reps.count ? "\(log.reps[index])" : ""
                lines.append("\(when)\t\(workout)\t\(exercise)\t\(index + 1)\t\(weight)\t\(unit.label)\t\(reps)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func quoted(_ text: String) -> String {
        guard text.contains("\t") || text.contains("\"") || text.contains("\n") else { return text }
        return "\"\(text.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
