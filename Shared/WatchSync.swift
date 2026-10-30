import Foundation

// MARK: - Watch ⇄ Phone sync contract
//
// Plain Codable value types used as the wire format between the iPhone and the
// Apple Watch. Both ends compile THIS file — it is in Shared/, which every
// target synchronizes — so the JSON keys below cannot drift apart. They were
// once two hand-synced copies, which is the failure this placement removes.
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
    /// A machine that takes weight OFF you — an assisted chin-up. The Watch
    /// only needs it to label the row: the wheels show what is set on the
    /// machine either way, and the phone turns that into the weight lifted.
    var subtractsFromBodyWeight: Bool
    /// The wheel's range, in grams. The three unit-less fields above are the
    /// originals and are no longer written; a Watch on an older build still
    /// reads them, which is why they are still sent.
    var lowestGrams: Int
    var highestGrams: Int
    var incrementGrams: Int

    enum CodingKeys: String, CodingKey {
        case id, name, numberOfSeries, lowestWeight, highestWeight, weightIncrement
        case restSeconds, kindRaw, aerobicActivityRaw, subtractsFromBodyWeight
        case lowestGrams, highestGrams, incrementGrams
    }
    init(id: String, name: String, numberOfSeries: Int, lowestWeight: Int,
         highestWeight: Int, weightIncrement: Int,
         restSeconds: Int = SyncDefaults.restSeconds,
         kindRaw: String = SyncDefaults.strengthKind,
         aerobicActivityRaw: String? = nil,
         subtractsFromBodyWeight: Bool = false,
         lowestGrams: Int = 0, highestGrams: Int = 0, incrementGrams: Int = 0) {
        self.id = id
        self.name = name
        self.numberOfSeries = numberOfSeries
        self.lowestWeight = lowestWeight
        self.highestWeight = highestWeight
        self.weightIncrement = weightIncrement
        self.restSeconds = restSeconds
        self.kindRaw = kindRaw
        self.aerobicActivityRaw = aerobicActivityRaw
        self.subtractsFromBodyWeight = subtractsFromBodyWeight
        self.lowestGrams = lowestGrams
        self.highestGrams = highestGrams
        self.incrementGrams = incrementGrams
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
        // A phone that predates assisted machines describes exercises that add
        // weight rather than take it off.
        subtractsFromBodyWeight = try c.decodeIfPresent(
            Bool.self, forKey: .subtractsFromBodyWeight) ?? false
        lowestGrams = try c.decodeIfPresent(Int.self, forKey: .lowestGrams) ?? 0
        highestGrams = try c.decodeIfPresent(Int.self, forKey: .highestGrams) ?? 0
        incrementGrams = try c.decodeIfPresent(Int.self, forKey: .incrementGrams) ?? 0
    }

    /// Whether this is one the Watch should offer a duration and a workout for
    /// rather than weight and reps wheels.
    var isAerobic: Bool { kindRaw == SyncDefaults.aerobicKind }
}

// MARK: - Two numbers for every weight
//
// The iPhone app, the Watch app and the Mac app are three separate installs
// that update when they each feel like it: the Watch when it is next charging
// on wifi, the Mac whenever its own App Store entry is opened. So a phone that
// has learned about grams WILL at some point be talking to a Watch that has
// not, for hours or for weeks.
//
// Nothing here may therefore change what an existing key MEANS. `weights` is
// the plain unit-less number it has always been, and the grams travel beside
// it under a new key. Each side reads the one it understands: an older Watch
// finds `weights` exactly where it expects it, and this one prefers the grams
// and falls back to reading `weights` through the exercise's own wheel.
//
// Getting this wrong is not a cosmetic matter. Sending grams in `weights` to
// an older Watch opens its wheels at the top of the range; receiving an older
// Watch's `weights` as though they were grams logs 130 lb as 130 g, which is
// a real set recorded at a four-hundredth of its weight.

extension SyncExercise {

    /// Whether the range in grams is one that can actually be used.
    ///
    /// Positive, not merely present: a zeroed range is a wheel with a single
    /// value on it, which logs every set at nothing.
    var hasGramRange: Bool {
        incrementGrams > 0 && highestGrams > 0 && highestGrams >= lowestGrams
    }

    /// This exercise with its gram range filled in from the unit-less numbers
    /// beside it, for definitions that came from a phone which had no grams to
    /// send. Without it a Watch on this build shows empty wheels for every
    /// exercise until the phone catches up.
    func repairingGramRange(in unit: WeightUnit) -> SyncExercise {
        guard !hasGramRange else { return self }
        var repaired = self
        repaired.lowestGrams = unit.grams(from: Double(lowestWeight))
        repaired.highestGrams = unit.grams(from: Double(highestWeight))
        repaired.incrementGrams = max(1, unit.grams(from: Double(weightIncrement)))
        return repaired
    }

    /// One of the old unit-less numbers, in grams.
    ///
    /// Counted in STEPS of this exercise's own wheel rather than converted on
    /// its own, because rounding does not distribute: 130 lb by itself is
    /// 58,967 g, while the wheel's twenty-sixth step is 26 × 2,268 = 58,968 g.
    /// A weight converted on its own therefore lands a gram off the wheel it
    /// came from, the Picker finds no value matching it, and the wheel opens
    /// somewhere else entirely. The phone's `WeightHistory.converted` counts
    /// the same steps for the same reason.
    func grams(fromLegacy weight: Int, in unit: WeightUnit) -> Int {
        let step = max(1, weightIncrement)
        let offset = weight - lowestWeight
        guard weight >= lowestWeight, offset % step == 0 else {
            return unit.grams(from: Double(weight))
        }
        guard hasGramRange, legacyRangeIsTheSameWheel(in: unit) else {
            return unit.grams(from: Double(lowestWeight))
                + (offset / step) * unit.grams(from: Double(step))
        }
        // The ends exactly: the top of a wheel need not be a whole number of
        // steps from the bottom, and counting to it lands beside it.
        if weight == lowestWeight { return lowestGrams }
        if weight == highestWeight { return highestGrams }
        return lowestGrams + (offset / step) * incrementGrams
    }

    /// A weight in grams written back as the unit-less number an older build
    /// expects — the inverse of the above, by the same step count, so a set
    /// that goes out and comes back is the same set.
    ///
    /// An exercise with no unit-less range of its own (one defined on this
    /// build, which never had one) can only be read out in the current unit.
    func legacy(fromGrams grams: Int, in unit: WeightUnit) -> Int {
        guard hasGramRange, weightIncrement > 0, grams >= lowestGrams,
              legacyRangeIsTheSameWheel(in: unit) else {
            return Int((unit.display(grams: grams)).rounded())
        }
        if grams == lowestGrams { return lowestWeight }
        if grams == highestGrams { return highestWeight }
        let steps = Int((Double(grams - lowestGrams) / Double(incrementGrams)).rounded())
        return lowestWeight + steps * weightIncrement
    }

    /// Whether the gram range is the unit-less one converted rather than one
    /// re-typed in another unit — the phone's
    /// `ExerciseDef.legacyRangeIsTheSameWheel`, which this must agree with.
    func legacyRangeIsTheSameWheel(in unit: WeightUnit) -> Bool {
        guard hasGramRange, weightIncrement > 0 else { return false }
        let tolerance = 2
        return abs(lowestGrams - unit.grams(from: Double(lowestWeight))) <= tolerance
            && abs(incrementGrams - unit.grams(from: Double(weightIncrement))) <= tolerance
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
    /// Last time's weights as the plain unit-less numbers. Still written, and
    /// still meaning exactly what they always did, because a Watch on an older
    /// build reads nothing else — see "Two numbers for every weight" above.
    var weights: [Int]
    var reps: [Int]
    /// How long an aerobic exercise ran last time, so its wheel opens where it
    /// was left — the same courtesy the weight wheels have always had. Zero for
    /// a strength exercise, and for a payload written before this existed.
    var durationSeconds: Int
    /// The same weights in grams, which is what both sides now store. Empty in
    /// a payload from a phone that knew nothing of grams, and then worked out
    /// from the numbers above.
    var weightsGrams: [Int]

    enum CodingKeys: String, CodingKey {
        case weights, reps, durationSeconds, weightsGrams
    }
    init(weights: [Int], reps: [Int], durationSeconds: Int = 0,
         weightsGrams: [Int] = []) {
        self.weights = weights
        self.reps = reps
        self.durationSeconds = durationSeconds
        self.weightsGrams = weightsGrams
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        weights = try c.decode([Int].self, forKey: .weights)
        reps = try c.decode([Int].self, forKey: .reps)
        durationSeconds = try c.decodeIfPresent(Int.self, forKey: .durationSeconds) ?? 0
        weightsGrams = try c.decodeIfPresent([Int].self, forKey: .weightsGrams) ?? []
    }

    /// Where to open the wheels, in grams: what the phone sent if it knew, and
    /// otherwise its unit-less numbers read through the exercise's own wheel.
    func grams(for exercise: SyncExercise?, in unit: WeightUnit) -> [Int] {
        guard weightsGrams.isEmpty else { return weightsGrams }
        guard let exercise else { return weights.map { unit.grams(from: Double($0)) } }
        return weights.map { exercise.grams(fromLegacy: $0, in: unit) }
    }
}

/// A live snapshot of an in-progress workout, transferred between devices on
/// handover so the taking-over device continues exactly where the other left
/// off (same exercise, same wheel values, same logged sets).
struct SessionSnapshot: Codable, Equatable {
    var workoutId: String
    var currentIndex: Int
    /// The wheels as the unit-less numbers an older build understands, with
    /// the grams beside them in `weightsGrams` — see "Two numbers for every
    /// weight". A hand-over is precisely the moment the two builds meet.
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

    /// The same wheels in grams. Empty in a snapshot from a build that had no
    /// grams, and then read from `weights`.
    var weightsGrams: [[Int]]

    enum CodingKeys: String, CodingKey {
        case workoutId, currentIndex, weights, reps, loggedIndices, startedAt
        case restEndsAt, restTotal, updatedAt, weightsGrams
    }
    init(workoutId: String, currentIndex: Int, weights: [[Int]], reps: [[Int]],
         loggedIndices: [Int], startedAt: Double,
         restEndsAt: Double? = nil, restTotal: Int? = nil, updatedAt: Double? = nil,
         weightsGrams: [[Int]] = []) {
        self.workoutId = workoutId
        self.currentIndex = currentIndex
        self.weights = weights
        self.reps = reps
        self.loggedIndices = loggedIndices
        self.startedAt = startedAt
        self.restEndsAt = restEndsAt
        self.restTotal = restTotal
        self.updatedAt = updatedAt
        self.weightsGrams = weightsGrams
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
        weightsGrams = try c.decodeIfPresent([[Int]].self, forKey: .weightsGrams) ?? []
    }

    /// The wheels in grams, per exercise of the workout being taken over.
    ///
    /// `exercises` is that workout's exercises in order, so a snapshot from an
    /// older build can have each row read through the wheel it came off.
    func grams(for exercises: [SyncExercise?], in unit: WeightUnit) -> [[Int]] {
        guard weightsGrams.isEmpty else { return weightsGrams }
        return weights.enumerated().map { index, row in
            guard let exercise = index < exercises.count ? exercises[index] : nil else {
                return row.map { unit.grams(from: Double($0)) }
            }
            return row.map { exercise.grams(fromLegacy: $0, in: unit) }
        }
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

/// What the Watch last told the phone about itself.
///
/// Only its OS version so far, and only so the phone can stop offering a
/// setting that device cannot use. It travels on the `requestSync` message,
/// which the Watch app sends every time it opens, and is kept on the phone
/// because the phone is where the settings screen is.
///
/// Zero when no Watch has ever said — a Watch app that predates this, or one
/// that has not been opened since. The settings screen then offers the manual
/// boundaries, on the grounds that a setting nobody needs is a smaller harm
/// than one the user cannot reach.
enum WatchSystemVersion {

    static let key = "watchOSMajorVersion"

    /// The version from which HealthKit will hand over the user's own zone
    /// configuration — see `HeartRateZones`.
    static let firstWithZoneConfiguration = 27

    static var major: Int {
        UserDefaults.standard.integer(forKey: key)
    }

    static var readsAppleZones: Bool {
        major >= firstWithZoneConfiguration
    }

    /// "26.6" → 26. Anything unreadable is nothing heard.
    static func majorVersion(of text: String) -> Int {
        Int(text.split(separator: ".").first ?? "") ?? 0
    }

    static func record(_ text: String) {
        let major = majorVersion(of: text)
        guard major > 0 else { return }
        UserDefaults.standard.set(major, forKey: key)
    }
}

/// Settings that live on the phone but are acted on by the Watch.
///
/// All of them are sent with the definitions, like the rest-timer switch, and
/// all of them have a default that an older Watch build — or one that has not
/// heard from the phone yet — falls back to.
enum WatchPreferences {

    /// How strongly the heart rate band behind the exercise name is drawn:
    /// 0.1 is barely there, 1 is the colour at full strength. Chosen on the
    /// phone against a preview, because how vivid is vivid enough depends on
    /// the wrist, the light and the person.
    static let zoneTintKey = "watchZoneTint"
    static let defaultZoneTint: Double = 0.5
    static let minimumZoneTint: Double = 0.1

    /// Taps on the wrist when a rest ends. One is easy to miss in a gym; the
    /// haptic itself cannot be made stronger, so the only dial is how many.
    static let restTapsKey = "watchRestTaps"
    static let defaultRestTaps = 2
    static let maximumRestTaps = 5

    /// One row of wheels with a reps/weights toggle, or both rows at once.
    static let wheelRowsKey = "watchWheelRows"
    static let defaultWheelRows = 1

    /// The four heart rate zone thresholds, typed in by hand, comma-separated
    /// — "91,115,139,164". Empty for "work them out", which is the default.
    ///
    /// Stored as text rather than as numbers because `@AppStorage` on the
    /// settings screen holds one value, and four separate keys for four
    /// numbers that are only ever meaningful together is four chances to be
    /// half-saved.
    static let zoneBoundariesKey = "watchZoneBoundaries"

    static var zoneTint: Double {
        let stored = UserDefaults.standard.object(forKey: zoneTintKey) as? Double
        return clampTint(stored ?? defaultZoneTint)
    }

    static var restTaps: Int {
        let stored = UserDefaults.standard.object(forKey: restTapsKey) as? Int
        return clampTaps(stored ?? defaultRestTaps)
    }

    static var wheelRows: Int {
        let stored = UserDefaults.standard.object(forKey: wheelRowsKey) as? Int
        return clampRows(stored ?? defaultWheelRows)
    }

    static func clampTint(_ value: Double) -> Double {
        min(1, max(minimumZoneTint, value))
    }

    static func clampTaps(_ value: Int) -> Int {
        min(maximumRestTaps, max(1, value))
    }

    static func clampRows(_ value: Int) -> Int {
        value == 2 ? 2 : 1
    }

    /// The thresholds as stored, or an empty array when there are none worth
    /// using. Nothing half-valid ever comes out of here: a set of four that
    /// does not make sense is no better than none, and a band drawn from it
    /// would be a confident lie.
    static var zoneBoundaries: [Int] {
        parseBoundaries(UserDefaults.standard.string(forKey: zoneBoundariesKey) ?? "")
    }

    static func parseBoundaries(_ text: String) -> [Int] {
        let numbers = text.split(separator: ",").compactMap {
            Int($0.trimmingCharacters(in: .whitespaces))
        }
        return validBoundaries(numbers)
    }

    static func boundariesText(_ values: [Int]) -> String {
        validBoundaries(values).map(String.init).joined(separator: ",")
    }

    /// Four thresholds, in order, no two the same, all of them a heart rate a
    /// person could actually have. Anything else is []. The same shape
    /// `HeartRateZones.init(boundaries:)` insists on, checked here too so the
    /// settings screen can say whether what has been typed will be used.
    static func validBoundaries(_ values: [Int]) -> [Int] {
        guard values.count == HeartRateZones.zoneCount - 1,
              values == values.sorted(),
              Set(values).count == values.count,
              values.allSatisfy({ $0 >= 40 && $0 <= 240 })
        else { return [] }
        return values
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
    /// See `WatchPreferences` — the band's strength, the taps at the end of a
    /// rest, and whether the Watch shows one row of wheels or two.
    var zoneTint: Double
    var restTaps: Int
    var wheelRows: Int
    /// The four zone thresholds the user typed in, or empty for none. Only of
    /// use to a Watch that cannot read them from Health itself — see
    /// `WatchSystemVersion`.
    var zoneBoundaries: [Int]
    /// Which unit to WRITE weights in. The numbers themselves are grams, as
    /// they are on the phone; this is only how they are read out.
    var weightUnit: String
    /// Whether the user asked to be offered the next workout at the end of
    /// one, and how it should be proposed. The Watch needs these to make the
    /// offer itself: EventKit on watchOS cannot write an event — saveEvent is
    /// __WATCHOS_PROHIBITED — so the Watch asks and the phone writes.
    var scheduleEnabled: Bool
    var scheduleDaysAhead: Int
    var scheduleCount: Int

    static func lastEntryKey(workoutId: String, exerciseId: String) -> String {
        "\(workoutId)|\(exerciseId)"
    }

    enum CodingKeys: String, CodingKey {
        case workouts, exercises, lastEntries, healthSharingEnabled, restTimerEnabled
        case watchWorkoutMode, zoneTint, restTaps, wheelRows, zoneBoundaries, weightUnit
        case scheduleEnabled, scheduleDaysAhead, scheduleCount
    }
    init(workouts: [SyncWorkout], exercises: [SyncExercise],
         lastEntries: [String: SyncLastEntry], healthSharingEnabled: Bool = false,
         restTimerEnabled: Bool = false,
         watchWorkoutMode: String = WatchWorkoutMode.handover.rawValue,
         zoneTint: Double = WatchPreferences.defaultZoneTint,
         restTaps: Int = WatchPreferences.defaultRestTaps,
         wheelRows: Int = WatchPreferences.defaultWheelRows,
         zoneBoundaries: [Int] = [],
         weightUnit: String = WeightUnit.regionDefault.rawValue,
         scheduleEnabled: Bool = false,
         scheduleDaysAhead: Int = WorkoutSchedule.defaultDaysAhead,
         scheduleCount: Int = WorkoutSchedule.defaultCount) {
        self.workouts = workouts
        self.exercises = exercises
        self.lastEntries = lastEntries
        self.healthSharingEnabled = healthSharingEnabled
        self.restTimerEnabled = restTimerEnabled
        self.watchWorkoutMode = watchWorkoutMode
        self.zoneTint = zoneTint
        self.restTaps = restTaps
        self.wheelRows = wheelRows
        self.zoneBoundaries = WatchPreferences.validBoundaries(zoneBoundaries)
        self.weightUnit = weightUnit
        self.scheduleEnabled = scheduleEnabled
        self.scheduleDaysAhead = scheduleDaysAhead
        self.scheduleCount = scheduleCount
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
        zoneTint = WatchPreferences.clampTint(
            try c.decodeIfPresent(Double.self, forKey: .zoneTint) ?? WatchPreferences.defaultZoneTint)
        restTaps = WatchPreferences.clampTaps(
            try c.decodeIfPresent(Int.self, forKey: .restTaps) ?? WatchPreferences.defaultRestTaps)
        wheelRows = WatchPreferences.clampRows(
            try c.decodeIfPresent(Int.self, forKey: .wheelRows) ?? WatchPreferences.defaultWheelRows)
        // Absent from a phone that predates them, and then the Watch works
        // the zones out for itself exactly as it always did.
        zoneBoundaries = WatchPreferences.validBoundaries(
            try c.decodeIfPresent([Int].self, forKey: .zoneBoundaries) ?? [])
        weightUnit = try c.decodeIfPresent(String.self, forKey: .weightUnit)
            ?? WeightUnit.regionDefault.rawValue
        // Absent from a phone that predates scheduling, and then the Watch
        // simply never offers.
        scheduleEnabled = try c.decodeIfPresent(Bool.self, forKey: .scheduleEnabled) ?? false
        scheduleDaysAhead = try c.decodeIfPresent(Int.self, forKey: .scheduleDaysAhead)
            ?? WorkoutSchedule.defaultDaysAhead
        scheduleCount = try c.decodeIfPresent(Int.self, forKey: .scheduleCount)
            ?? WorkoutSchedule.defaultCount
    }
}
