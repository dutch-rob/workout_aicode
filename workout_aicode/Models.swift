import Foundation
import SwiftData

// MARK: - MovementType  (legacy — no longer used)
//
// This once described the axis a wrist follows during a rep, for an Apple Watch
// motion rep-counter that was abandoned. Nothing reads it any more: there is no
// motion sensing anywhere in the app, and the editor no longer offers it.
//
// It is kept ONLY so stored data and previously exported JSON still decode —
// `ExerciseDef` persists the field and the exporter writes it. Removing the type
// would break existing databases and older export files. Every exercise is
// `.none` in practice.
enum MovementType: String, Codable, CaseIterable, Identifiable {
    case none
    case vertical
    case horizontal
    case rotational

    var id: String { rawValue }
}

/// What sort of thing an exercise is. Not a muscle group, despite appearing
/// next to them in the picker as "AE": a muscle group says which part of you a
/// movement works, and every strength statistic in this app — estimated 1RM,
/// hard sets, the trend ranking — is computed from weights and repetitions. A
/// twenty-minute row has neither, so it must be excluded from those by
/// construction rather than by remembering to check for one special group.
enum ExerciseKind: String, Codable, CaseIterable, Identifiable {
    case strength
    case aerobic

    var id: String { rawValue }
    var label: String {
        switch self {
        case .strength: return "Strength"
        case .aerobic:  return "Aerobic"
        }
    }
}

/// Which activity, named as the Apple Workout app names its indoor workouts,
/// so what you pick here is what appears in Fitness afterwards.
///
/// "Indoor" is not a separate HealthKit activity — it is
/// `HKWorkoutConfiguration.locationType = .indoor` alongside an ordinary
/// activity type, which is exactly why Apple's own list reads this way. The
/// HealthKit type each case maps to is named beside it, for when the Watch
/// starts the session.
///
/// Ordered by how likely they are to be wanted rather than alphabetically: the
/// machines first, then the classes, then the rest. Traditional Strength
/// Training is deliberately absent — it is an indoor Apple workout, but it is
/// what this app already writes for a *strength* session, and offering it here
/// would let one exercise claim to be both kinds at once.
enum AerobicActivity: String, Codable, CaseIterable, Identifiable {
    // Machines and the indoor variants of the outdoor three
    case indoorWalk         // .walking + indoor
    case indoorRun          // .running + indoor
    case indoorCycle        // .cycling + indoor
    case elliptical         // .elliptical
    case rower              // .rowing
    case stairStepper       // .stepTraining
    case stairs             // .stairs
    case handCycling        // .handCycling
    case wheelchairWalkPace // .wheelchairWalkPace
    case wheelchairRunPace  // .wheelchairRunPace

    // Conditioning
    case hiit               // .highIntensityIntervalTraining
    case crossTraining      // .crossTraining
    case functionalStrength // .functionalStrengthTraining
    case coreTraining       // .coreTraining
    case jumpRope           // .jumpRope
    case mixedCardio        // .mixedCardio
    case kickboxing         // .kickboxing

    // Classes and low-intensity
    case dance              // .cardioDance
    case socialDance        // .socialDance
    case yoga               // .yoga
    case pilates            // .pilates
    case barre              // .barre
    case taiChi             // .taiChi
    case mindAndBody        // .mindAndBody
    case flexibility        // .flexibility
    case cooldown           // .cooldown

    // Water and everything else indoors
    case poolSwim           // .swimming + indoor
    case waterFitness       // .waterFitness
    case fitnessGaming      // .fitnessGaming

    var id: String { rawValue }

    var label: String {
        switch self {
        case .indoorWalk:         return "Indoor walk"
        case .indoorRun:          return "Indoor run"
        case .indoorCycle:        return "Indoor cycle"
        case .elliptical:         return "Elliptical"
        case .rower:              return "Rower"
        case .stairStepper:       return "Stair stepper"
        case .stairs:             return "Stairs"
        case .handCycling:        return "Hand cycling"
        case .wheelchairWalkPace: return "Wheelchair walk pace"
        case .wheelchairRunPace:  return "Wheelchair run pace"
        case .hiit:               return "High intensity interval training"
        case .crossTraining:      return "Cross training"
        case .functionalStrength: return "Functional strength training"
        case .coreTraining:       return "Core training"
        case .jumpRope:           return "Jump rope"
        case .mixedCardio:        return "Mixed cardio"
        case .kickboxing:         return "Kickboxing"
        case .dance:              return "Dance"
        case .socialDance:        return "Social dance"
        case .yoga:               return "Yoga"
        case .pilates:            return "Pilates"
        case .barre:              return "Barre"
        case .taiChi:             return "Tai chi"
        case .mindAndBody:        return "Mind and body"
        case .flexibility:        return "Flexibility"
        case .cooldown:           return "Cooldown"
        case .poolSwim:           return "Pool swim"
        case .waterFitness:       return "Water fitness"
        case .fitnessGaming:      return "Fitness gaming"
        }
    }
}

@Model
final class ExerciseDef: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var name: String = ""
    var numberOfSeries: Int = 3
    var lowestWeight: Int = 0
    var highestWeight: Int = 200
    var weightIncrement: Int = 5
    var movementType: MovementType = MovementType.none

    // MARK: Muscle groups
    //
    // Stored as raw strings rather than enums: SwiftData migrates String
    // attributes without ceremony, and an unrecognised value from a future
    // version (or a hand-edited export) degrades to "unset" instead of failing
    // to decode the whole exercise. Use `primaryMuscle` / `secondaryMuscles`.
    var primaryMuscleRaw: String? = nil
    var secondaryMuscleRaw: [String] = []

    /// Which library movement this exercise came from, if any. Survives
    /// renaming, and is what makes one movement comparable across users in
    /// shared data. Nil for exercises the user invented.
    var libraryKey: String? = nil

    /// Starred by the user, to pull the handful they actually train to the top
    /// of a long list.
    var isFavourite: Bool = false

    /// Strength or aerobic. Stored as a raw string for the same reason the
    /// muscle groups are: an unrecognised value from a future version degrades
    /// to "strength" instead of failing to decode the whole exercise.
    var kindRaw: String = ExerciseKind.strength.rawValue
    /// Which cardio activity, for aerobic exercises. Nil for strength.
    var aerobicActivityRaw: String? = nil

    /// Seconds of rest after a set of this exercise. Per exercise, because a
    /// heavy compound needs longer than a light isolation movement. Only used
    /// when the rest timer is switched on in Settings.
    var restSeconds: Int = RestTimerDefaults.seconds

    var kind: ExerciseKind {
        get { ExerciseKind(rawValue: kindRaw) ?? .strength }
        set { kindRaw = newValue.rawValue }
    }

    var aerobicActivity: AerobicActivity? {
        get { aerobicActivityRaw.flatMap(AerobicActivity.init(rawValue:)) }
        set { aerobicActivityRaw = newValue?.rawValue }
    }

    var primaryMuscle: MuscleGroup? {
        get { primaryMuscleRaw.flatMap(MuscleGroup.init(rawValue:)) }
        set { primaryMuscleRaw = newValue?.rawValue }
    }

    var secondaryMuscles: [MuscleGroup] {
        get { secondaryMuscleRaw.compactMap(MuscleGroup.init(rawValue:)) }
        set { secondaryMuscleRaw = Array(newValue.prefix(MuscleGroup.maximumSecondary)).map(\.rawValue) }
    }

    init(id: UUID = UUID(),
         name: String,
         numberOfSeries: Int = 3,
         lowestWeight: Int = 0,
         highestWeight: Int = 200,
         weightIncrement: Int = 5,
         movementType: MovementType = .none,
         primaryMuscle: MuscleGroup? = nil,
         secondaryMuscles: [MuscleGroup] = [],
         libraryKey: String? = nil,
         isFavourite: Bool = false,
         restSeconds: Int = RestTimerDefaults.seconds,
         kind: ExerciseKind = .strength,
         aerobicActivity: AerobicActivity? = nil) {
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
        self.movementType = movementType
        self.primaryMuscleRaw = primaryMuscle?.rawValue
        self.secondaryMuscleRaw = Array(secondaryMuscles.prefix(MuscleGroup.maximumSecondary)).map(\.rawValue)
        self.libraryKey = libraryKey
        self.isFavourite = isFavourite
        self.restSeconds = restSeconds
        self.kindRaw = kind.rawValue
        self.aerobicActivityRaw = aerobicActivity?.rawValue
    }

    enum CodingKeys: String, CodingKey {
        case id, name, numberOfSeries, lowestWeight, highestWeight, weightIncrement, movementType
        case primaryMuscle, secondaryMuscles, libraryKey, isFavourite, restSeconds
        case kind, aerobicActivity
    }
    convenience init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(UUID.self, forKey: .id)
        let name = try c.decode(String.self, forKey: .name)
        let numberOfSeries = try c.decode(Int.self, forKey: .numberOfSeries)
        let lowestWeight = try c.decode(Int.self, forKey: .lowestWeight)
        let highestWeight = try c.decode(Int.self, forKey: .highestWeight)
        let weightIncrement = try c.decode(Int.self, forKey: .weightIncrement)
        // movementType is a new field — accept old exports without it.
        let movementType = try c.decodeIfPresent(MovementType.self, forKey: .movementType) ?? .none
        // Muscle groups and libraryKey likewise post-date the first exports.
        // Unknown group names are dropped rather than failing the import.
        let primary = try c.decodeIfPresent(String.self, forKey: .primaryMuscle)
            .flatMap(MuscleGroup.init(rawValue:))
        let secondary = (try c.decodeIfPresent([String].self, forKey: .secondaryMuscles) ?? [])
            .compactMap(MuscleGroup.init(rawValue:))
        let libraryKey = try c.decodeIfPresent(String.self, forKey: .libraryKey)
        let favourite = try c.decodeIfPresent(Bool.self, forKey: .isFavourite) ?? false
        let rest = try c.decodeIfPresent(Int.self, forKey: .restSeconds) ?? RestTimerDefaults.seconds
        // An export from before aerobic exercises existed describes a strength
        // exercise, and an unknown kind from a future one is safer read as
        // strength than dropped.
        let kind = (try c.decodeIfPresent(String.self, forKey: .kind))
            .flatMap(ExerciseKind.init(rawValue:)) ?? .strength
        let activity = (try c.decodeIfPresent(String.self, forKey: .aerobicActivity))
            .flatMap(AerobicActivity.init(rawValue:))
        self.init(id: id, name: name,
                  numberOfSeries: numberOfSeries,
                  lowestWeight: lowestWeight,
                  highestWeight: highestWeight,
                  weightIncrement: weightIncrement,
                  movementType: movementType,
                  primaryMuscle: primary,
                  secondaryMuscles: secondary,
                  libraryKey: libraryKey,
                  isFavourite: favourite,
                  restSeconds: rest,
                  kind: kind,
                  aerobicActivity: activity)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(numberOfSeries, forKey: .numberOfSeries)
        try c.encode(lowestWeight, forKey: .lowestWeight)
        try c.encode(highestWeight, forKey: .highestWeight)
        try c.encode(weightIncrement, forKey: .weightIncrement)
        try c.encode(movementType, forKey: .movementType)
        try c.encodeIfPresent(primaryMuscle?.rawValue, forKey: .primaryMuscle)
        try c.encode(secondaryMuscles.map(\.rawValue), forKey: .secondaryMuscles)
        try c.encodeIfPresent(libraryKey, forKey: .libraryKey)
        try c.encode(isFavourite, forKey: .isFavourite)
        try c.encode(restSeconds, forKey: .restSeconds)
        try c.encode(kind.rawValue, forKey: .kind)
        try c.encodeIfPresent(aerobicActivity?.rawValue, forKey: .aerobicActivity)
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

    /// ExerciseDef as it was before muscle groups — frozen, never edited again.
    ///
    /// A VersionedSchema is only meaningful if its model shapes stay fixed. The
    /// live `ExerciseDef` is listed by V3 alone; if V1 and V2 kept pointing at
    /// it, every field added to it would silently change what V1 and V2 claim
    /// to be, all three versions would describe the same shape, and SwiftData
    /// could no longer tell which stage an existing store is at — it aborts
    /// with a staged-migration failure rather than guessing.
    ///
    /// Shape must match the shipped 1.2 class exactly, including `movementType`
    /// and every default, or the checksum changes and stores written by 1.2
    /// stop matching this stage.
    @Model
    final class ExerciseDef {
        var id: UUID = UUID()
        var name: String = ""
        var numberOfSeries: Int = 3
        var lowestWeight: Int = 0
        var highestWeight: Int = 200
        var weightIncrement: Int = 5
        var movementType: MovementType = MovementType.none

        init(id: UUID = UUID(), name: String, numberOfSeries: Int = 3,
             lowestWeight: Int = 0, highestWeight: Int = 200,
             weightIncrement: Int = 5, movementType: MovementType = .none) {
            self.id = id
            self.name = name
            self.numberOfSeries = numberOfSeries
            self.lowestWeight = lowestWeight
            self.highestWeight = highestWeight
            self.weightIncrement = weightIncrement
            self.movementType = movementType
        }
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
    /// ExerciseDef did not change between V1 and V2, so V2 reuses V1's frozen
    /// copy. WorkoutDef never changes at all and stays a single shared class.
    static var models: [any PersistentModel.Type] {
        [WorkoutLogSchemaV1.ExerciseDef.self, WorkoutDef.self, WorkoutLog.self]
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

// V3 adds the muscle-group and library-key attributes to ExerciseDef — and is
// the only version that lists the *live* class, so future edits to it change V3
// alone. The WorkoutLog shape is unchanged, so V3 reuses V2's model.
//
// Every new attribute is optional or defaulted, which is exactly what SwiftData
// can migrate by itself, so the stage is lightweight rather than the
// hand-written kind V2 needed.
enum WorkoutLogSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [WorkoutLogSchemaV3.ExerciseDef.self, WorkoutDef.self,
         WorkoutLogSchemaV2.WorkoutLog.self]
    }

    /// ExerciseDef as of V3 — muscle groups, but no favourite flag. Frozen.
    ///
    /// The same rule as V1's copy, and worth restating because it caught me
    /// twice: only the NEWEST schema may list the live class. When V3 and V4
    /// both pointed at it, adding one field changed both of them at once, the
    /// two versions described the same shape, and staged migration aborted with
    /// no way to tell which one a store was at.
    @Model
    final class ExerciseDef {
        var id: UUID = UUID()
        var name: String = ""
        var numberOfSeries: Int = 3
        var lowestWeight: Int = 0
        var highestWeight: Int = 200
        var weightIncrement: Int = 5
        var movementType: MovementType = MovementType.none
        var primaryMuscleRaw: String? = nil
        var secondaryMuscleRaw: [String] = []
        var libraryKey: String? = nil

        init(id: UUID = UUID(), name: String) {
            self.id = id
            self.name = name
        }
    }
}

// V4 adds the favourite flag to ExerciseDef. Additive and defaulted, like V3,
// so the stage is lightweight — but it still has to exist, or the store stays
// declared at V3 while the classes describe V4 and opening it fails.
enum WorkoutLogSchemaV4: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(4, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [WorkoutLogSchemaV4.ExerciseDef.self, WorkoutDef.self,
         WorkoutLogSchemaV2.WorkoutLog.self]
    }

    /// ExerciseDef as of V4 — favourites, but no rest timer. Frozen.
    ///
    /// The rule this codebase learned the hard way, twice: only the NEWEST
    /// schema may list the live class. Two versions pointing at it means one
    /// added field changes both, they describe the same shape, and staged
    /// migration aborts at launch with "unknown model version".
    @Model
    final class ExerciseDef {
        var id: UUID = UUID()
        var name: String = ""
        var numberOfSeries: Int = 3
        var lowestWeight: Int = 0
        var highestWeight: Int = 200
        var weightIncrement: Int = 5
        var movementType: MovementType = MovementType.none
        var primaryMuscleRaw: String? = nil
        var secondaryMuscleRaw: [String] = []
        var libraryKey: String? = nil
        var isFavourite: Bool = false

        init(id: UUID = UUID(), name: String) {
            self.id = id
            self.name = name
        }
    }
}

// V5 adds the per-exercise rest time. Additive and defaulted, so lightweight.
enum WorkoutLogSchemaV5: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(5, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [WorkoutLogSchemaV5.ExerciseDef.self, WorkoutDef.self,
         WorkoutLogSchemaV2.WorkoutLog.self]
    }

    /// ExerciseDef as of V5 — the rest timer, but nothing aerobic. Frozen, for
    /// the reason restated at every version: only the newest schema may name
    /// the live class.
    @Model
    final class ExerciseDef {
        var id: UUID = UUID()
        var name: String = ""
        var numberOfSeries: Int = 3
        var lowestWeight: Int = 0
        var highestWeight: Int = 200
        var weightIncrement: Int = 5
        var movementType: MovementType = MovementType.none
        var primaryMuscleRaw: String? = nil
        var secondaryMuscleRaw: [String] = []
        var libraryKey: String? = nil
        var isFavourite: Bool = false
        var restSeconds: Int = RestTimerDefaults.seconds

        init(id: UUID = UUID(), name: String) {
            self.id = id
            self.name = name
        }
    }
}

// V6 adds the aerobic side: what kind of exercise this is, and what a finished
// aerobic session measured.
//
// The measurements live in their own entity rather than as new columns on
// WorkoutLog, and that is not a stylistic choice. WorkoutLog had never changed
// since V2, so V2's class was the live one AND the shape V3, V4 and V5
// described; adding fields meant freezing V2's copy and making a new live class
// with the same name. SwiftData takes the entity name from the class name, and
// with two classes called WorkoutLog the new properties were silently dropped:
// a value set in init came back as its default, though the store had the
// column and assigning after insert worked. A separate entity has a name of its
// own, so nothing collides, and adding an entity is as lightweight a migration
// as adding a column.
enum WorkoutLogSchemaV6: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(6, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [ExerciseDef.self, WorkoutDef.self, WorkoutLogSchemaV2.WorkoutLog.self,
         AerobicResult.self]
    }
}

/// What a finished aerobic session measured, alongside the WorkoutLog row that
/// records it happened.
///
/// Joined by `logId` rather than a SwiftData relationship: every other model
/// here refers to its neighbours by UUID, the Watch sync and the exports are
/// built on those ids, and a relationship would be the only one of its kind.
@Model
final class AerobicResult: Identifiable, Codable {
    var id: UUID = UUID()
    /// The WorkoutLog this belongs to.
    var logId: UUID = UUID()
    /// How long the session actually ran.
    var durationSeconds: Int = 0
    /// Zero when there was no Watch, or Health access was refused — a normal
    /// outcome rather than an error, so the session still stands without them.
    /// A sentinel rather than an optional: SwiftData threw from `encodeNil`
    /// while building this entity's defaults, and nobody has a heart rate of
    /// zero, so nothing is lost by saying it plainly.
    var averageHeartRate: Int = 0
    var maximumHeartRate: Int = 0
    /// Seconds in each of the five zones, lowest first. Empty when no heart
    /// rate was measured; five entries when it was.
    var zoneSeconds: [Int] = []

    init(id: UUID = UUID(),
         logId: UUID,
         durationSeconds: Int,
         averageHeartRate: Int = 0,
         maximumHeartRate: Int = 0,
         zoneSeconds: [Int] = []) {
        self.id = id
        self.logId = logId
        self.durationSeconds = durationSeconds
        self.averageHeartRate = averageHeartRate
        self.maximumHeartRate = maximumHeartRate
        self.zoneSeconds = zoneSeconds
    }

    enum CodingKeys: String, CodingKey {
        case id, logId, durationSeconds, averageHeartRate, maximumHeartRate, zoneSeconds
    }
    convenience init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id:               try c.decode(UUID.self, forKey: .id),
            logId:            try c.decode(UUID.self, forKey: .logId),
            durationSeconds:  try c.decode(Int.self, forKey: .durationSeconds),
            averageHeartRate: try c.decodeIfPresent(Int.self, forKey: .averageHeartRate) ?? 0,
            maximumHeartRate: try c.decodeIfPresent(Int.self, forKey: .maximumHeartRate) ?? 0,
            zoneSeconds:      try c.decodeIfPresent([Int].self, forKey: .zoneSeconds) ?? []
        )
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(logId, forKey: .logId)
        try c.encode(durationSeconds, forKey: .durationSeconds)
        try c.encode(averageHeartRate, forKey: .averageHeartRate)
        try c.encode(maximumHeartRate, forKey: .maximumHeartRate)
        try c.encode(zoneSeconds, forKey: .zoneSeconds)
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
        [WorkoutLogSchemaV1.self, WorkoutLogSchemaV2.self,
         WorkoutLogSchemaV3.self, WorkoutLogSchemaV4.self, WorkoutLogSchemaV5.self,
         WorkoutLogSchemaV6.self]
    }
    static var stages: [MigrationStage] { [v1toV2, v2toV3, v3toV4, v4toV5, v5toV6] }

    /// Additive only — see WorkoutLogSchemaV6.
    static let v5toV6 = MigrationStage.lightweight(
        fromVersion: WorkoutLogSchemaV5.self,
        toVersion:   WorkoutLogSchemaV6.self
    )

    /// Additive only — see WorkoutLogSchemaV5.
    static let v4toV5 = MigrationStage.lightweight(
        fromVersion: WorkoutLogSchemaV4.self,
        toVersion:   WorkoutLogSchemaV5.self
    )

    /// Additive only — see WorkoutLogSchemaV4.
    static let v3toV4 = MigrationStage.lightweight(
        fromVersion: WorkoutLogSchemaV3.self,
        toVersion:   WorkoutLogSchemaV4.self
    )

    /// Additive only — see WorkoutLogSchemaV3.
    static let v2toV3 = MigrationStage.lightweight(
        fromVersion: WorkoutLogSchemaV2.self,
        toVersion:   WorkoutLogSchemaV3.self
    )

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
