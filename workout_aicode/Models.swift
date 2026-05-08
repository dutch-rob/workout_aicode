import Foundation
import SwiftData

@Model
final class ExerciseDef: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var name: String = ""
    var numberOfSeries: Int = 3
    var lowestWeight: Int = 0
    var highestWeight: Int = 200
    var weightIncrement: Int = 5

    init(id: UUID = UUID(), name: String, numberOfSeries: Int = 3, lowestWeight: Int = 0, highestWeight: Int = 200, weightIncrement: Int = 5) {
        let clampedNumberOfSeries = max(0, numberOfSeries)
        let clampedLowest = max(0, lowestWeight)
        let clampedHighest = max(clampedLowest, highestWeight)
        let clampedIncrement = max(1, weightIncrement)

        self.id = id
        self.name = name
        self.numberOfSeries = clampedNumberOfSeries
        self.lowestWeight = clampedLowest
        self.highestWeight = clampedHighest
        self.weightIncrement = clampedIncrement
    }

    enum CodingKeys: String, CodingKey { case id, name, numberOfSeries, lowestWeight, highestWeight, weightIncrement }
    convenience init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(UUID.self, forKey: .id)
        let name = try c.decode(String.self, forKey: .name)
        let numberOfSeries = try c.decode(Int.self, forKey: .numberOfSeries)
        let lowestWeight = try c.decode(Int.self, forKey: .lowestWeight)
        let highestWeight = try c.decode(Int.self, forKey: .highestWeight)
        let weightIncrement = try c.decode(Int.self, forKey: .weightIncrement)
        self.init(id: id, name: name, numberOfSeries: numberOfSeries, lowestWeight: lowestWeight, highestWeight: highestWeight, weightIncrement: weightIncrement)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(numberOfSeries, forKey: .numberOfSeries)
        try c.encode(lowestWeight, forKey: .lowestWeight)
        try c.encode(highestWeight, forKey: .highestWeight)
        try c.encode(weightIncrement, forKey: .weightIncrement)
    }
}

@Model
final class WorkoutDef: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var name: String = ""
    var exerciseOrder: [UUID] = []
    var sortIndex: Int = 0

    init(id: UUID = UUID(), name: String, exerciseOrder: [UUID] = [], sortIndex: Int = 0) {
        self.id = id
        self.name = name
        self.exerciseOrder = exerciseOrder
        self.sortIndex = sortIndex
    }

    enum CodingKeys: String, CodingKey { case id, name, exerciseOrder, sortIndex }
    convenience init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(UUID.self, forKey: .id)
        let name = try c.decode(String.self, forKey: .name)
        let exerciseOrder = try c.decode([UUID].self, forKey: .exerciseOrder)
        let sortIndex = try c.decode(Int.self, forKey: .sortIndex)
        self.init(id: id, name: name, exerciseOrder: exerciseOrder, sortIndex: sortIndex)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(exerciseOrder, forKey: .exerciseOrder)
        try c.encode(sortIndex, forKey: .sortIndex)
    }
}

// MARK: - WorkoutLog versioned schema
//
// V1 stored an array of entries inside one log row. In practice every row had
// exactly one entry, so V2 collapses it to a single flat row per
// (workout, exercise, date). The custom migration below preserves all data:
// each V1 entry becomes one V2 row, so users with old data don't lose
// anything when they update.

enum WorkoutLogSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [ExerciseDef.self, WorkoutDef.self, WorkoutLog.self]
    }

    struct Entry: Codable, Hashable {
        var exerciseId: UUID
        var weights: [Int]
        var reps: [Int]
    }

    @Model
    final class WorkoutLog {
        var id: UUID = UUID()
        var date: Date = Date()
        var workoutId: UUID = UUID()
        var entries: [Entry] = []

        init(id: UUID = UUID(),
             date: Date = Date(),
             workoutId: UUID,
             entries: [Entry]) {
            self.id = id
            self.date = date
            self.workoutId = workoutId
            self.entries = entries
        }
    }
}

enum WorkoutLogSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [ExerciseDef.self, WorkoutDef.self, WorkoutLog.self]
    }

    @Model
    final class WorkoutLog: Identifiable, Codable {
        var id: UUID = UUID()
        var date: Date = Date()
        var workoutId: UUID = UUID()
        var exerciseId: UUID = UUID()
        var weights: [Int] = []
        var reps: [Int] = []

        init(id: UUID = UUID(),
             date: Date = Date(),
             workoutId: UUID,
             exerciseId: UUID,
             weights: [Int],
             reps: [Int]) {
            self.id = id
            self.date = date
            self.workoutId = workoutId
            self.exerciseId = exerciseId
            self.weights = weights
            self.reps = reps
        }

        enum CodingKeys: String, CodingKey { case id, date, workoutId, exerciseId, weights, reps }
        convenience init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                id:         try c.decode(UUID.self, forKey: .id),
                date:       try c.decode(Date.self, forKey: .date),
                workoutId:  try c.decode(UUID.self, forKey: .workoutId),
                exerciseId: try c.decode(UUID.self, forKey: .exerciseId),
                weights:    try c.decode([Int].self, forKey: .weights),
                reps:       try c.decode([Int].self, forKey: .reps)
            )
        }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id,         forKey: .id)
            try c.encode(date,       forKey: .date)
            try c.encode(workoutId,  forKey: .workoutId)
            try c.encode(exerciseId, forKey: .exerciseId)
            try c.encode(weights,    forKey: .weights)
            try c.encode(reps,       forKey: .reps)
        }
    }
}

/// Module-level alias so the rest of the app can keep saying `WorkoutLog`.
typealias WorkoutLog = WorkoutLogSchemaV2.WorkoutLog

// MARK: - Migration plan (V1 → V2)
//
// SwiftData's lightweight migration would silently drop the V1 `entries` array
// and leave V2 rows with empty `weights`/`reps`. The custom stage below reads
// V1 rows in `willMigrate` (V1 schema active), persists their data to
// UserDefaults, deletes the V1 rows, then in `didMigrate` (V2 schema active)
// recreates one V2 row per V1 entry — preserving every set of weights/reps.

enum WorkoutMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [WorkoutLogSchemaV1.self, WorkoutLogSchemaV2.self]
    }
    static var stages: [MigrationStage] { [v1toV2] }

    private struct V1Snapshot: Codable {
        let id: UUID
        let date: Date
        let workoutId: UUID
        let entries: [Entry]
        struct Entry: Codable {
            let exerciseId: UUID
            let weights: [Int]
            let reps: [Int]
        }
    }
    private static let snapshotKey = "WorkoutLogV1MigrationSnapshot"

    static let v1toV2 = MigrationStage.custom(
        fromVersion: WorkoutLogSchemaV1.self,
        toVersion:   WorkoutLogSchemaV2.self,
        willMigrate: { context in
            let oldLogs = (try? context.fetch(FetchDescriptor<WorkoutLogSchemaV1.WorkoutLog>())) ?? []
            let snapshots = oldLogs.map { log in
                V1Snapshot(
                    id:        log.id,
                    date:      log.date,
                    workoutId: log.workoutId,
                    entries:   log.entries.map {
                        V1Snapshot.Entry(exerciseId: $0.exerciseId,
                                         weights:    $0.weights,
                                         reps:       $0.reps)
                    }
                )
            }
            if let data = try? JSONEncoder().encode(snapshots) {
                UserDefaults.standard.set(data, forKey: snapshotKey)
            }
            for log in oldLogs { context.delete(log) }
            try? context.save()
        },
        didMigrate: { context in
            guard let data = UserDefaults.standard.data(forKey: snapshotKey),
                  let snapshots = try? JSONDecoder().decode([V1Snapshot].self, from: data)
            else { return }
            for v1 in snapshots {
                for (i, entry) in v1.entries.enumerated() {
                    let log = WorkoutLogSchemaV2.WorkoutLog(
                        id:         i == 0 ? v1.id : UUID(),
                        date:       v1.date,
                        workoutId:  v1.workoutId,
                        exerciseId: entry.exerciseId,
                        weights:    entry.weights,
                        reps:       entry.reps
                    )
                    context.insert(log)
                }
            }
            try? context.save()
            UserDefaults.standard.removeObject(forKey: snapshotKey)
        }
    )
}

struct ExportEnvelope: Codable {
    let exportVersion: String
    let appIdentifier: String
    let appVersion: String
    let build: String
    let exportedAt: String
    let device: DeviceInfo
    let locale: String
    let timeZone: String
    let counts: Counts
    let data: AllData

    struct DeviceInfo: Codable {
        let model: String
        let system: String
        let version: String
    }

    struct Counts: Codable {
        let workouts: Int
        let exercises: Int
        let logs: Int
    }

    struct AllData: Codable {
        let workouts: [WorkoutDef]
        let exercises: [ExerciseDef]
        let logs: [WorkoutLog]
    }
}

// MARK: - Legacy import support (logJSON.1)
// The original export format wrapped each log in an entries array. We only
// keep these types to read old export files; they are NEVER written.

struct LegacyExerciseLogEntry: Codable {
    let exerciseId: UUID
    let weights: [Int]
    let reps: [Int]
}

struct LegacyWorkoutLog: Codable {
    let id: UUID
    let date: Date
    let workoutId: UUID
    let entries: [LegacyExerciseLogEntry]
}

struct LegacyExportEnvelope: Codable {
    let exportVersion: String
    let appIdentifier: String
    let appVersion: String
    let build: String
    let exportedAt: String
    let device: ExportEnvelope.DeviceInfo
    let locale: String
    let timeZone: String
    let counts: ExportEnvelope.Counts
    let data: LegacyAllData

    struct LegacyAllData: Codable {
        let workouts: [WorkoutDef]
        let exercises: [ExerciseDef]
        let logs: [LegacyWorkoutLog]
    }
}

extension LegacyWorkoutLog {
    /// Expand a legacy log (one row, multiple entries) into one flat WorkoutLog
    /// per entry. The first entry keeps the original id; subsequent entries get
    /// new ids so they remain unique in the new schema.
    func flatten() -> [WorkoutLog] {
        entries.enumerated().map { idx, entry in
            WorkoutLog(
                id:         idx == 0 ? id : UUID(),
                date:       date,
                workoutId:  workoutId,
                exerciseId: entry.exerciseId,
                weights:    entry.weights,
                reps:       entry.reps
            )
        }
    }
}
