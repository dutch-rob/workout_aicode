import Foundation
import SwiftData

// MARK: - Editing logs, undoably
//
// The log is the one thing in this app that cannot be re-made: a workout can be
// rebuilt in a minute, but nobody remembers what they lifted in March. So the
// screen that edits it takes a copy of the whole set first, and "discard" puts
// that copy back.
//
// Edits go straight to the real rows rather than to the copy. That is the
// opposite of what it sounds like it should be, and it is the safer way round:
// editing a copy means a swap at the end — deleting every real row and
// re-inserting the edited ones — which is a great deal of destruction to
// perform on the irreplaceable thing, through CloudKit, at the exact moment the
// user said "yes, keep it". Restoring only ever happens when the user asks to
// throw work away, and even then it is an upsert rather than a wipe.
//
// KNOWN GAP: the copy lives in memory for as long as the editing screen is
// open. Edits are written as they are made, so a crash mid-edit leaves them in
// place with nothing to undo them.

/// Everything the log editor can change, frozen.
struct LogSnapshot {
    let takenAt: Date
    /// The logs and their aerobic measurements, encoded. Held as data rather
    /// than as model objects: a decoded @Model instance belongs to no context,
    /// and keeping a few hundred of them alive beside the real ones is a good
    /// way to end up unsure which is which.
    let logs: Data
    let aerobic: Data
    /// The assisted sets' body weights and machine settings. Here for the same
    /// reason the aerobic measurements are: editing a weight on an assisted
    /// set rewrites one of these, and "discard" has to put that back too.
    let assisted: Data
    /// The weights themselves, which live beside the log — see LogWeights.
    let weights: Data
    /// What the logs looked like when this was taken, for telling whether
    /// anything actually changed.
    let signature: [String]
}

@MainActor
enum LogEditing {

    // MARK: Taking a copy

    static func snapshot(in context: ModelContext) throws -> LogSnapshot {
        let logs = (try? context.fetch(FetchDescriptor<WorkoutLog>())) ?? []
        let aerobic = (try? context.fetch(FetchDescriptor<AerobicResult>())) ?? []
        let assisted = (try? context.fetch(FetchDescriptor<AssistedResult>())) ?? []
        let weights = (try? context.fetch(FetchDescriptor<LogWeights>())) ?? []
        let encoder = JSONEncoder()
        return LogSnapshot(takenAt: Date(),
                           logs: try encoder.encode(logs),
                           aerobic: try encoder.encode(aerobic),
                           assisted: try encoder.encode(assisted),
                           weights: try encoder.encode(weights),
                           signature: signature(of: logs))
    }

    /// A stable description of the whole set, order-independent.
    ///
    /// Compared against a later one to answer "did anything change?". Asking
    /// the rows themselves would mean trusting every edit path to report
    /// itself, and the one that forgot would silently lose the user's work.
    static func signature(of logs: [WorkoutLog]) -> [String] {
        logs.map {
            "\($0.id.uuidString)|\(Int($0.date.timeIntervalSince1970))|" +
            "\($0.workoutId.uuidString)|\($0.exerciseId.uuidString)|" +
            "\($0.weights.map(String.init).joined(separator: ","))|" +
            "\($0.reps.map(String.init).joined(separator: ","))"
        }.sorted()
    }

    static func hasChanged(from snapshot: LogSnapshot, in context: ModelContext) -> Bool {
        let now = (try? context.fetch(FetchDescriptor<WorkoutLog>())) ?? []
        return signature(of: now) != snapshot.signature
    }

    // MARK: Putting it back

    /// Restores the logs to how they were when the snapshot was taken.
    ///
    /// An upsert, not a wipe: rows that still exist are written back over,
    /// rows that were added since are removed, rows that were deleted come
    /// back. Nothing is deleted before the replacement has been decoded, so a
    /// malformed copy fails without having destroyed anything.
    @discardableResult
    static func restore(_ snapshot: LogSnapshot, in context: ModelContext) throws -> Int {
        let decoder = JSONDecoder()
        let wanted = try decoder.decode([WorkoutLog].self, from: snapshot.logs)
        let wantedAerobic = try decoder.decode([AerobicResult].self, from: snapshot.aerobic)
        let wantedAssisted = try decoder.decode([AssistedResult].self, from: snapshot.assisted)
        let wantedWeights = try decoder.decode([LogWeights].self, from: snapshot.weights)

        var restored = 0
        let current = (try? context.fetch(FetchDescriptor<WorkoutLog>())) ?? []
        var byId = Dictionary(current.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        for log in wanted {
            if let existing = byId.removeValue(forKey: log.id) {
                if existing.date != log.date { existing.date = log.date }
                if existing.workoutId != log.workoutId { existing.workoutId = log.workoutId }
                if existing.exerciseId != log.exerciseId { existing.exerciseId = log.exerciseId }
                if existing.weights != log.weights { existing.weights = log.weights }
                if existing.reps != log.reps { existing.reps = log.reps }
            } else {
                context.insert(log)          // deleted since the copy: bring it back
            }
            restored += 1
        }

        // Whatever is left in byId was added after the copy was taken.
        for (id, log) in byId {
            for result in aerobicResults(forLog: id, in: context) { context.delete(result) }
            for result in assistedResults(forLog: id, in: context) { context.delete(result) }
            for record in weightRecords(forLog: id, in: context) { context.delete(record) }
            context.delete(log)
        }

        // The same for the aerobic measurements, which belong to their log.
        let currentAerobic = (try? context.fetch(FetchDescriptor<AerobicResult>())) ?? []
        var aerobicById = Dictionary(currentAerobic.map { ($0.id, $0) },
                                     uniquingKeysWith: { a, _ in a })
        for result in wantedAerobic {
            if let existing = aerobicById.removeValue(forKey: result.id) {
                existing.logId = result.logId
                existing.durationSeconds = result.durationSeconds
                existing.averageHeartRate = result.averageHeartRate
                existing.maximumHeartRate = result.maximumHeartRate
                existing.zoneSeconds = result.zoneSeconds
            } else {
                context.insert(result)
            }
        }
        for (_, result) in aerobicById { context.delete(result) }

        // And the assisted sets' own numbers, which an edit to a weight here
        // rewrites — see MacEditLogsView.
        let currentAssisted = (try? context.fetch(FetchDescriptor<AssistedResult>())) ?? []
        var assistedById = Dictionary(currentAssisted.map { ($0.id, $0) },
                                      uniquingKeysWith: { a, _ in a })
        for result in wantedAssisted {
            if let existing = assistedById.removeValue(forKey: result.id) {
                existing.logId = result.logId
                existing.bodyWeight = result.bodyWeight
                existing.machineSettings = result.machineSettings
            } else {
                context.insert(result)
            }
        }
        for (_, result) in assistedById { context.delete(result) }

        // And the weights, which an edit here writes directly.
        let currentWeights = (try? context.fetch(FetchDescriptor<LogWeights>())) ?? []
        var weightsById = Dictionary(currentWeights.map { ($0.id, $0) },
                                     uniquingKeysWith: { a, _ in a })
        for record in wantedWeights {
            if let existing = weightsById.removeValue(forKey: record.id) {
                existing.logId = record.logId
                existing.grams = record.grams
            } else {
                context.insert(record)
            }
        }
        for (_, record) in weightsById { context.delete(record) }

        try context.save()
        return restored
    }

    private static func aerobicResults(forLog id: UUID,
                                       in context: ModelContext) -> [AerobicResult] {
        let descriptor = FetchDescriptor<AerobicResult>(
            predicate: #Predicate<AerobicResult> { $0.logId == id })
        return (try? context.fetch(descriptor)) ?? []
    }

    static func weightRecords(forLog id: UUID, in context: ModelContext) -> [LogWeights] {
        let descriptor = FetchDescriptor<LogWeights>(
            predicate: #Predicate<LogWeights> { $0.logId == id })
        return (try? context.fetch(descriptor)) ?? []
    }

    static func assistedResults(forLog id: UUID,
                                in context: ModelContext) -> [AssistedResult] {
        let descriptor = FetchDescriptor<AssistedResult>(
            predicate: #Predicate<AssistedResult> { $0.logId == id })
        return (try? context.fetch(descriptor)) ?? []
    }

    /// An assisted set's weight was edited. The log holds what was LIFTED, so
    /// the machine's own number has to follow it or the two would contradict
    /// each other: body weight 82, lifted 55, machine still saying 30.
    ///
    /// The body weight used is the one recorded WITH THAT SET, not today's —
    /// the set happened at the weight the user was then, and correcting a typo
    /// in it is not a reason to restate what they weighed.
    static func realignAssisted(log: WorkoutLog, set index: Int,
                                in context: ModelContext) {
        guard let result = assistedResults(forLog: log.id, in: context).first,
              let bodyWeight = result.bodyWeightGrams, bodyWeight > 0 else { return }
        let lifted = grams(for: log, in: context)
        guard index < lifted.count else { return }
        // Only when the stored body weight can actually account for the new
        // number. A set logged before the body weight was known holds one that
        // is too small — correcting the weight to what was really lifted would
        // then compute a NEGATIVE machine setting and clamp it to zero,
        // throwing away the one number in that record still worth having.
        guard bodyWeight > lifted[index] else { return }
        var settings = result.machineSettingsGrams ?? []
        while settings.count <= index { settings.append(0) }
        settings[index] = max(0, bodyWeight - lifted[index])
        result.machineSettingsGrams = settings
    }

    // MARK: Keeping a row tidy

    // MARK: Weights, which live beside the log

    /// The record holding this log's weights, made if it is not there yet.
    ///
    /// A log edited on a device that has only just learned about units may not
    /// have one — the editor is as good a place as any to give it one.
    static func weightsRecord(for log: WorkoutLog, in context: ModelContext) -> LogWeights {
        let id = log.id
        let descriptor = FetchDescriptor<LogWeights>(
            predicate: #Predicate<LogWeights> { $0.logId == id })
        if let existing = (try? context.fetch(descriptor))?.first { return existing }
        let made = LogWeights(logId: log.id, grams: [])
        context.insert(made)
        return made
    }

    static func grams(for log: WorkoutLog, in context: ModelContext) -> [Int] {
        weightsRecord(for: log, in: context).grams
    }

    /// Writes one set's weight, in grams, lengthening both arrays to reach it.
    static func setGrams(_ value: Int, at index: Int,
                         for log: WorkoutLog, in context: ModelContext) {
        let record = weightsRecord(for: log, in: context)
        var grams = record.grams
        while grams.count <= index { grams.append(0) }
        grams[index] = max(0, value)
        record.grams = grams
        while log.reps.count < grams.count { log.reps.append(0) }
    }

    /// Drops trailing sets that are 0 × 0.
    ///
    /// Typing into the fifth set column of a three-set row has to lengthen the
    /// arrays to reach it, which leaves empty sets behind if the user changes
    /// their mind. A trailing 0 × 0 is not a set anybody did.
    static func trimEmptyTrailingSets(_ log: WorkoutLog, in context: ModelContext) {
        let record = weightsRecord(for: log, in: context)
        var grams = record.grams
        var reps = log.reps
        while let w = grams.last, let r = reps.last, w == 0, r == 0 {
            grams.removeLast()
            reps.removeLast()
        }
        if grams != record.grams { record.grams = grams }
        if reps != log.reps { log.reps = reps }
    }

    /// Makes both arrays at least `count` long, so set `count - 1` can be
    /// written. They are kept the same length: a weight without its reps is a
    /// row that every reader of the log has to guess about.
    static func extend(_ log: WorkoutLog, toSets count: Int, in context: ModelContext) {
        let record = weightsRecord(for: log, in: context)
        while record.grams.count < count { record.grams.append(0) }
        while log.reps.count < count { log.reps.append(0) }
    }
}
