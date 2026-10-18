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
    /// Keep in step with `ExerciseKind`'s raw values.
    static let strengthKind = "strength"
    static let aerobicKind = "aerobic"
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
    /// "strength" or "aerobic", and for an aerobic one which activity. Raw
    /// strings rather than the enums: those live in the phone's Models.swift,
    /// which the Watch target does not compile, and an unrecognised value from
    /// a newer phone should cost one attribute rather than the whole payload.
    var kindRaw: String
    var aerobicActivityRaw: String?

    enum CodingKeys: String, CodingKey {
        case id, name, numberOfSeries, lowestWeight, highestWeight, weightIncrement
        case restSeconds, kindRaw, aerobicActivityRaw
    }
    init(id: String, name: String, numberOfSeries: Int, lowestWeight: Int,
         highestWeight: Int, weightIncrement: Int,
         restSeconds: Int = SyncDefaults.restSeconds,
         kindRaw: String = SyncDefaults.strengthKind,
         aerobicActivityRaw: String? = nil) {
        self.id = id
        self.name = name
        self.numberOfSeries = numberOfSeries
        self.lowestWeight = lowestWeight
        self.highestWeight = highestWeight
        self.weightIncrement = weightIncrement
        self.restSeconds = restSeconds
        self.kindRaw = kindRaw
        self.aerobicActivityRaw = aerobicActivityRaw
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
        // A payload from a phone that predates aerobic exercises describes
        // strength ones, which is also the safe reading of anything unknown:
        // the Watch shows its wheels rather than a workout it cannot start.
        kindRaw = try c.decodeIfPresent(String.self, forKey: .kindRaw)
            ?? SyncDefaults.strengthKind
        aerobicActivityRaw = try c.decodeIfPresent(String.self, forKey: .aerobicActivityRaw)
    }

    /// Whether this is one the Watch should offer a duration and a workout for
    /// rather than weight and reps wheels.
    var isAerobic: Bool { kindRaw == SyncDefaults.aerobicKind }
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
    /// How long an aerobic exercise ran last time, so its wheel opens where it
    /// was left — the same courtesy the weight wheels have always had. Zero for
    /// a strength exercise, and for a payload written before this existed.
    var durationSeconds: Int

    enum CodingKeys: String, CodingKey { case weights, reps, durationSeconds }
    init(weights: [Int], reps: [Int], durationSeconds: Int = 0) {
        self.weights = weights
        self.reps = reps
        self.durationSeconds = durationSeconds
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        weights = try c.decode([Int].self, forKey: .weights)
        reps = try c.decode([Int].self, forKey: .reps)
        durationSeconds = try c.decodeIfPresent(Int.self, forKey: .durationSeconds) ?? 0
    }
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
    /// The rest in progress, if any, so the device taking over carries on with
    /// it rather than starting from nothing. Moving from phone to Watch is most
    /// likely exactly during a rest — that is when the hands are free — and it
    /// takes long enough that a rest which began again at the top would be
    /// noticeably wrong. An end DATE rather than seconds left, so the time the
    /// hand-over itself takes comes off the rest instead of being added to it.
    var restEndsAt: Double?
    /// Full length of that rest, for how much of the screen to grey.
    var restTotal: Int?
    /// When this snapshot was last written (epoch seconds). Lets a device that
    /// finds one lying in the application context tell a workout in progress
    /// from one abandoned yesterday.
    var updatedAt: Double?

    /// How old a snapshot may be and still be offered for taking over. Same
    /// hour as the phone's OpenWorkoutPolicy.idleLimit — a test holds the two
    /// together, since the Watch cannot see Shared/.
    static let staleAfter: TimeInterval = 3600

    func isFresh(now: Date = Date()) -> Bool {
        guard let updatedAt else { return false }
        return now.timeIntervalSince1970 - updatedAt <= Self.staleAfter
    }

    /// The rest still to run, if there is one.
    func pendingRest(now: Date = Date()) -> (endsAt: Date, total: Int)? {
        guard let restEndsAt, let restTotal, restTotal > 0 else { return nil }
        let end = Date(timeIntervalSince1970: restEndsAt)
        return end > now ? (end, restTotal) : nil
    }

    enum CodingKeys: String, CodingKey {
        case workoutId, currentIndex, weights, reps, loggedIndices, startedAt
        case restEndsAt, restTotal, updatedAt
    }
    init(workoutId: String, currentIndex: Int, weights: [[Int]], reps: [[Int]],
         loggedIndices: [Int], startedAt: Double,
         restEndsAt: Double? = nil, restTotal: Int? = nil, updatedAt: Double? = nil) {
        self.workoutId = workoutId
        self.currentIndex = currentIndex
        self.weights = weights
        self.reps = reps
        self.loggedIndices = loggedIndices
        self.startedAt = startedAt
        self.restEndsAt = restEndsAt
        self.restTotal = restTotal
        self.updatedAt = updatedAt
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
        // Absent from anything written before rests travelled with the
        // snapshot, which then simply has none.
        restEndsAt = try c.decodeIfPresent(Double.self, forKey: .restEndsAt)
        restTotal = try c.decodeIfPresent(Int.self, forKey: .restTotal)
        updatedAt = try c.decodeIfPresent(Double.self, forKey: .updatedAt)
    }
}

/// The full snapshot the phone pushes to the Watch whenever its data changes.
/// How a workout logged on the Apple Watch is recorded.
///
/// `.handover` is the original behaviour: the workout can move between the
/// iPhone and the Watch as often as you like, and the PHONE writes a single
/// Traditional Strength Training workout to Health at the end, if that was
/// asked for.
///
/// `.appleWorkout` has the Watch run a real `HKWorkoutSession` for the whole
/// workout — heart rate, the zone behind the exercise name, an entry in
/// Fitness that counts towards the rings — at the price of the workout not
/// being able to come back to the phone part-way through. It can still go
/// phone → Watch: the session is back-dated to when the workout really began,
/// so the duration is whole even though the heart rate only starts at the wrist.
///
/// The setting lives on the phone. `current` is the phone's reading of it; the
/// Watch is told through `SyncPayload` and keeps its own copy, exactly as it
/// does for the rest timer.
enum WatchWorkoutMode: String, Codable, CaseIterable, Identifiable {
    case handover
    case appleWorkout

    var id: String { rawValue }

    static let key = "watchWorkoutMode"

    static var current: WatchWorkoutMode {
        WatchWorkoutMode(rawValue: UserDefaults.standard.string(forKey: key) ?? "")
            ?? .handover
    }

    var label: String {
        switch self {
        case .handover:     return "Hand over between devices"
        case .appleWorkout: return "Apple workout on the Watch"
        }
    }
}

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
    /// Which of the two ways a Watch workout is recorded — see
    /// `WatchWorkoutMode`. Sent as its raw value so an older Watch build
    /// simply does not find the key and carries on handing over.
    var watchWorkoutMode: String

    static func lastEntryKey(workoutId: String, exerciseId: String) -> String {
        "\(workoutId)|\(exerciseId)"
    }

    enum CodingKeys: String, CodingKey {
        case workouts, exercises, lastEntries, healthSharingEnabled, restTimerEnabled
        case watchWorkoutMode
    }
    init(workouts: [SyncWorkout], exercises: [SyncExercise],
         lastEntries: [String: SyncLastEntry], healthSharingEnabled: Bool = false,
         restTimerEnabled: Bool = false,
         watchWorkoutMode: String = WatchWorkoutMode.handover.rawValue) {
        self.workouts = workouts
        self.exercises = exercises
        self.lastEntries = lastEntries
        self.healthSharingEnabled = healthSharingEnabled
        self.restTimerEnabled = restTimerEnabled
        self.watchWorkoutMode = watchWorkoutMode
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        workouts = try c.decode([SyncWorkout].self, forKey: .workouts)
        exercises = try c.decode([SyncExercise].self, forKey: .exercises)
        lastEntries = try c.decode([String: SyncLastEntry].self, forKey: .lastEntries)
        healthSharingEnabled = try c.decodeIfPresent(Bool.self, forKey: .healthSharingEnabled) ?? false
        restTimerEnabled = try c.decodeIfPresent(Bool.self, forKey: .restTimerEnabled) ?? false
        watchWorkoutMode = try c.decodeIfPresent(String.self, forKey: .watchWorkoutMode)
            ?? WatchWorkoutMode.handover.rawValue
    }
}
