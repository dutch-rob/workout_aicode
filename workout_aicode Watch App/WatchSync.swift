import Foundation

// MARK: - Watch ⇄ Phone sync contract
//
// Plain Codable value types used as the wire format between the iPhone and the
// Apple Watch. A byte-identical copy of this file lives in the Watch App target
// ("workout_aicode Watch App/WatchSync.swift"). The two targets are separate
// synchronized folders and do not share source, so the JSON keys defined here
// MUST stay in sync on both sides.
//
// Direction of travel:
//   • Phone → Watch : SyncPayload (workout + exercise definitions, prefill
//     history) delivered via WCSession.updateApplicationContext.
//   • Watch → Phone : a completed set ("logSet" userInfo dictionary) delivered
//     via WCSession.transferUserInfo — see PhoneSessionManager / WatchSessionManager.
//   • Phone → Watch : live "mirror" messages so the Watch can follow the
//     exercise the phone is currently logging.

/// Values this file needs that live in phone-only types. Repeated as literals
/// because this file must compile unchanged in the Watch target, which has no
/// access to `RestTimerDefaults`.
enum SyncDefaults {
    /// Keep in step with `RestTimerDefaults.seconds`.
    static let restSeconds = 90
}

/// One exercise definition, flattened to primitive types (UUIDs as strings).
struct SyncExercise: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var numberOfSeries: Int
    var lowestWeight: Int
    var highestWeight: Int
    var weightIncrement: Int
    /// Rest after a set of this exercise, so a set logged on the Watch rests
    /// for as long as the same set logged on the phone.
    var restSeconds: Int

    enum CodingKeys: String, CodingKey {
        case id, name, numberOfSeries, lowestWeight, highestWeight, weightIncrement
        case restSeconds
    }
    init(id: String, name: String, numberOfSeries: Int, lowestWeight: Int,
         highestWeight: Int, weightIncrement: Int,
         restSeconds: Int = SyncDefaults.restSeconds) {
        self.id = id
        self.name = name
        self.numberOfSeries = numberOfSeries
        self.lowestWeight = lowestWeight
        self.highestWeight = highestWeight
        self.weightIncrement = weightIncrement
        self.restSeconds = restSeconds
    }
    // Lenient, because the two apps update independently: a Watch on the new
    // build can be handed a payload from the old phone build for as long as it
    // takes the user to update, and an exercise arriving without a rest is
    // better than a whole payload that will not decode.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        numberOfSeries = try c.decode(Int.self, forKey: .numberOfSeries)
        lowestWeight = try c.decode(Int.self, forKey: .lowestWeight)
        highestWeight = try c.decode(Int.self, forKey: .highestWeight)
        weightIncrement = try c.decode(Int.self, forKey: .weightIncrement)
        restSeconds = try c.decodeIfPresent(Int.self, forKey: .restSeconds)
            ?? SyncDefaults.restSeconds
    }
}

/// One workout definition. `exerciseOrder` holds exercise ids (as strings).
struct SyncWorkout: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var exerciseOrder: [String]
}

/// The most recent logged weights/reps for a (workout, exercise) pair, used to
/// pre-fill the Watch picker wheels the same way the phone pre-fills them.
struct SyncLastEntry: Codable, Hashable {
    var weights: [Int]
    var reps: [Int]
}

/// A live snapshot of an in-progress workout, transferred between devices on
/// handover so the taking-over device continues exactly where the other left
/// off (same exercise, same wheel values, same logged sets).
struct SessionSnapshot: Codable, Equatable {
    var workoutId: String
    var currentIndex: Int
    var weights: [[Int]]
    var reps: [[Int]]
    var loggedIndices: [Int]
    /// When the workout began (epoch seconds), preserved across hand-overs so
    /// Apple Health gets the full duration regardless of which device finishes.
    var startedAt: Double

    enum CodingKeys: String, CodingKey {
        case workoutId, currentIndex, weights, reps, loggedIndices, startedAt
    }
    init(workoutId: String, currentIndex: Int, weights: [[Int]], reps: [[Int]],
         loggedIndices: [Int], startedAt: Double) {
        self.workoutId = workoutId
        self.currentIndex = currentIndex
        self.weights = weights
        self.reps = reps
        self.loggedIndices = loggedIndices
        self.startedAt = startedAt
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        workoutId = try c.decode(String.self, forKey: .workoutId)
        currentIndex = try c.decode(Int.self, forKey: .currentIndex)
        weights = try c.decode([[Int]].self, forKey: .weights)
        reps = try c.decode([[Int]].self, forKey: .reps)
        loggedIndices = try c.decode([Int].self, forKey: .loggedIndices)
        startedAt = try c.decodeIfPresent(Double.self, forKey: .startedAt)
            ?? Date().timeIntervalSince1970
    }
}

/// The full snapshot the phone pushes to the Watch whenever its data changes.
struct SyncPayload: Codable {
    var workouts: [SyncWorkout]
    var exercises: [SyncExercise]
    /// Keyed by "\(workoutId)|\(exerciseId)".
    var lastEntries: [String: SyncLastEntry]
    /// Whether the user opted in to saving finished workouts to Apple Health.
    var healthSharingEnabled: Bool
    /// Whether the rest timer is switched on. The setting lives on the phone,
    /// so the Watch has to be told, exactly like Health sharing.
    var restTimerEnabled: Bool

    static func lastEntryKey(workoutId: String, exerciseId: String) -> String {
        "\(workoutId)|\(exerciseId)"
    }

    enum CodingKeys: String, CodingKey {
        case workouts, exercises, lastEntries, healthSharingEnabled, restTimerEnabled
    }
    init(workouts: [SyncWorkout], exercises: [SyncExercise],
         lastEntries: [String: SyncLastEntry], healthSharingEnabled: Bool = false,
         restTimerEnabled: Bool = false) {
        self.workouts = workouts
        self.exercises = exercises
        self.lastEntries = lastEntries
        self.healthSharingEnabled = healthSharingEnabled
        self.restTimerEnabled = restTimerEnabled
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        workouts = try c.decode([SyncWorkout].self, forKey: .workouts)
        exercises = try c.decode([SyncExercise].self, forKey: .exercises)
        lastEntries = try c.decode([String: SyncLastEntry].self, forKey: .lastEntries)
        healthSharingEnabled = try c.decodeIfPresent(Bool.self, forKey: .healthSharingEnabled) ?? false
        restTimerEnabled = try c.decodeIfPresent(Bool.self, forKey: .restTimerEnabled) ?? false
    }
}
