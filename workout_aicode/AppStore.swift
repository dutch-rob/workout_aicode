import SwiftUI
import SwiftData
import Combine

final class AppStore: ObservableObject {
    @Published var workouts: [WorkoutDef] = []
    @Published var exercises: [ExerciseDef] = []

    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
        reloadAll()
    }

    func reloadAll() {
        do {
            let workoutsDescriptor = FetchDescriptor<WorkoutDef>(sortBy: [SortDescriptor(\WorkoutDef.name)])
            let exercisesDescriptor = FetchDescriptor<ExerciseDef>(sortBy: [SortDescriptor(\ExerciseDef.name)])
            workouts = (try context.fetch(workoutsDescriptor)).sorted { a, b in
                if a.sortIndex != b.sortIndex { return a.sortIndex < b.sortIndex }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
            var changed = false
            for (idx, workout) in workouts.enumerated() {
                if workout.sortIndex != idx {
                    workout.sortIndex = idx
                    changed = true
                }
            }
            if changed { try? context.save() }
            exercises = try context.fetch(exercisesDescriptor)
        } catch {
            workouts = []
            exercises = []
        }
        // Keep the Apple Watch in sync with the latest definitions.
        PhoneSessionManager.shared.pushDefinitions()
    }

    func saveWorkout(_ workout: WorkoutDef) {
        do {
            let targetID = workout.id
            let descriptor = FetchDescriptor<WorkoutDef>(predicate: #Predicate<WorkoutDef> { obj in obj.id == targetID })
            let existing = try context.fetch(descriptor)
            if existing.isEmpty {
                context.insert(workout)
            }
            try? context.save()
        } catch {
            context.insert(workout)
            try? context.save()
        }
        reloadAll()
    }

    func deleteWorkout(_ workout: WorkoutDef) {
        context.delete(workout)
        try? context.save()
        reloadAll()
    }

    func saveExercise(_ exercise: ExerciseDef) {
        do {
            let targetID = exercise.id
            let descriptor = FetchDescriptor<ExerciseDef>(predicate: #Predicate<ExerciseDef> { obj in obj.id == targetID })
            let existing = try context.fetch(descriptor)
            if existing.isEmpty {
                context.insert(exercise)
            }
            try? context.save()
        } catch {
            context.insert(exercise)
            try? context.save()
        }
        reloadAll()
    }

    func deleteExercise(_ exercise: ExerciseDef) {
        // Also drop it from every workout that referenced it. Leaving the id
        // behind produced a blank "phantom" exercise at the end of a workout
        // that the log button could not get past.
        let deletedID = exercise.id
        if let allWorkouts = try? context.fetch(FetchDescriptor<WorkoutDef>()) {
            for workout in allWorkouts where workout.exerciseOrder.contains(deletedID) {
                workout.exerciseOrder.removeAll { $0 == deletedID }
            }
        }
        context.delete(exercise)
        try? context.save()
        reloadAll()
    }

    /// A copy of a workout under a new name, listing the SAME exercises.
    ///
    /// Not copies of the exercises: see WorkoutComposition for why, and what
    /// copying them would do to the history.
    @discardableResult
    func duplicateWorkout(_ workout: WorkoutDef) -> WorkoutDef {
        let made = WorkoutComposition.copy(
            of: workout,
            named: WorkoutComposition.copyName(for: workout, among: workouts),
            among: workouts)
        saveWorkout(made)
        return made
    }

    /// One workout holding the first's exercises and then the second's, with
    /// anything in both appearing once. Neither original is touched.
    @discardableResult
    func mergeWorkouts(_ first: WorkoutDef, _ second: WorkoutDef) -> WorkoutDef {
        let made = WorkoutComposition.merge(
            first, second,
            named: WorkoutComposition.mergedName(first, second, among: workouts),
            among: workouts)
        saveWorkout(made)
        return made
    }

    func reorderWorkouts(_ newOrder: [WorkoutDef]) {
        for (idx, workout) in newOrder.enumerated() {
            workout.sortIndex = idx
        }
        try? context.save()
        reloadAll()
    }

    /// For each exercise in the workout, the most recent log row (used to
    /// pre-fill the picker wheels). Returns at most one row per exercise.
    /// The last logged set per exercise, as grams — what the wheels open on.
    func lastGrams(for workout: WorkoutDef,
                   acrossWorkouts: Bool = PrefillScope.acrossWorkouts) -> [UUID: [Int]] {
        lastEntries(for: workout, acrossWorkouts: acrossWorkouts)
            .compactMapValues { log -> [Int]? in
                let grams = weightsGrams(forLogId: log.id)
                return grams.isEmpty ? nil : grams
            }
    }

    /// The last logged set per exercise in `workout`, to open the wheels on.
    ///
    /// `acrossWorkouts` decides whether an exercise remembers its own history
    /// or only what was logged under this workout — see `PrefillScope`. The
    /// parameter exists so tests can pin it; everything else takes the setting.
    func lastEntries(for workout: WorkoutDef,
                     acrossWorkouts: Bool = PrefillScope.acrossWorkouts) -> [UUID: WorkoutLog] {
        do {
            let workoutID = workout.id
            let descriptor: FetchDescriptor<WorkoutLog>
            if acrossWorkouts {
                // Every log, newest first; the loop below stops as soon as it
                // has one for each exercise in this workout.
                descriptor = FetchDescriptor<WorkoutLog>(
                    sortBy: [SortDescriptor(\WorkoutLog.date, order: .reverse)]
                )
            } else {
                descriptor = FetchDescriptor<WorkoutLog>(
                    predicate: #Predicate<WorkoutLog> { $0.workoutId == workoutID },
                    sortBy: [SortDescriptor(\WorkoutLog.date, order: .reverse)]
                )
            }
            let logs = try context.fetch(descriptor)
            var map: [UUID: WorkoutLog] = [:]
            let targetSet = Set(workout.exerciseOrder)
            let aerobicLogIds = Set(((try? context.fetch(FetchDescriptor<AerobicResult>())) ?? [])
                .map(\.logId))
            let gramsByLog = LogWeightsIndex.byLogId(
                (try? context.fetch(FetchDescriptor<LogWeights>())) ?? [])
            for log in logs {
                guard targetSet.contains(log.exerciseId), map[log.exerciseId] == nil else {
                    if map.count == targetSet.count { break }
                    continue
                }
                // "Last time" means the last time something was actually
                // logged. A row of nothing — no weight, no repetition, and no
                // aerobic session either — is not a session to open the wheels
                // on: it drops the weight wheel to its lowest value and the
                // repetitions to zero, and the next set logged from there
                // records those, so one empty row quietly becomes a run of
                // them. (A real set of 0 × 10 is a bodyweight set and counts;
                // this is 0 × 0.)
                guard !isEmptyRow(log, grams: gramsByLog[log.id] ?? [],
                                  aerobicLogIds: aerobicLogIds) else { continue }
                map[log.exerciseId] = log
                if map.count == targetSet.count { break }
            }
            return map
        } catch {
            return [:]
        }
    }

    /// A log's weights, in grams. Empty for a log written before weights had
    /// a unit and not yet filled in — see `WeightHistory`.
    func weightsGrams(forLogId logId: UUID) -> [Int] {
        let descriptor = FetchDescriptor<LogWeights>(
            predicate: #Predicate<LogWeights> { $0.logId == logId })
        return (try? context.fetch(descriptor))?.first?.grams ?? []
    }

    /// Records a log's weights. The log's own `weights` is left alone: it is
    /// the original unit-less field, and writing it would hand a device still
    /// on the old build a number in the wrong scale.
    func setWeightsGrams(_ grams: [Int], forLogId logId: UUID) {
        let descriptor = FetchDescriptor<LogWeights>(
            predicate: #Predicate<LogWeights> { $0.logId == logId })
        if let existing = (try? context.fetch(descriptor))?.first {
            existing.grams = grams
        } else {
            context.insert(LogWeights(logId: logId, grams: grams))
        }
    }

    /// A log with nothing in it: no weight, no repetition, no aerobic session.
    ///
    /// The weights are the GRAMS beside the log, not the old unit-less field,
    /// which nothing writes any more — judging emptiness by that field would
    /// call every new log empty.
    private func isEmptyRow(_ log: WorkoutLog, grams: [Int],
                            aerobicLogIds: Set<UUID>) -> Bool {
        guard !aerobicLogIds.contains(log.id) else { return false }
        let hasWeight = grams.contains { $0 != 0 }
        let hasReps = log.reps.contains { $0 != 0 }
        return !hasWeight && !hasReps
    }

    /// What an assisted set was worked out from, for the log that holds it.
    func assistedResult(forLogId logId: UUID) -> AssistedResult? {
        let descriptor = FetchDescriptor<AssistedResult>(
            predicate: #Predicate<AssistedResult> { $0.logId == logId })
        return (try? context.fetch(descriptor))?.first
    }

    // MARK: - Apple Watch sync

    /// Build the JSON payload the Watch needs to select and log a workout on its
    /// own: all workout + exercise definitions plus the most recent logged
    /// weights/reps per (workout, exercise) so the Watch pickers pre-fill.
    func watchSyncPayloadData() -> Data? {
        // Aerobic durations, keyed by the log they belong to, so the Watch can
        // open its wheel where the last session left it.
        let aerobic = (try? context.fetch(FetchDescriptor<AerobicResult>())) ?? []
        let durationByLog = Dictionary(aerobic.map { ($0.logId, $0.durationSeconds) },
                                       uniquingKeysWith: { a, _ in a })
        let assistedIds = Set(exercises.filter(\.subtractsFromBodyWeight).map(\.id))
        // For writing the unit-less numbers an older Watch reads: the unit the
        // user said their history was in, so those numbers stay of a piece with
        // the ones that build already has. Not the display unit, which they may
        // change this afternoon.
        let legacyUnit = WeightHistory.statedUnit ?? .current
        let byExerciseId = Dictionary(exercises.map { ($0.id, $0) },
                                      uniquingKeysWith: { first, _ in first })
        var lastMap: [String: SyncLastEntry] = [:]
        for workout in workouts {
            let entries = lastEntries(for: workout)
            for (exId, log) in entries {
                let key = SyncPayload.lastEntryKey(workoutId: workout.id.uuidString,
                                                   exerciseId: exId.uuidString)
                // The Watch opens its wheels on what it is sent, so an assisted
                // exercise is sent last time's MACHINE SETTING — the weight
                // lifted would creep with the user's body weight and is not a
                // number anyone sets on a machine.
                var wheels = weightsGrams(forLogId: log.id)
                if assistedIds.contains(exId),
                   let settings = assistedResult(forLogId: log.id)?.machineSettingsGrams,
                   !settings.isEmpty {
                    wheels = settings
                }
                // Both numbers, every time. The grams are what a Watch on this
                // build opens its wheels on; the unit-less ones beside them are
                // what a Watch that has not updated yet reads, and sending it
                // grams there would open every wheel at the top of its range.
                let definition = byExerciseId[exId]
                let legacyWheels = wheels.map {
                    definition?.legacyWeight(fromGrams: $0, in: legacyUnit)
                        ?? Int(legacyUnit.display(grams: $0).rounded())
                }
                lastMap[key] = SyncLastEntry(weights: legacyWheels, reps: log.reps,
                                             durationSeconds: durationByLog[log.id] ?? 0,
                                             weightsGrams: wheels)
            }
        }

        // Drop references to exercises that no longer exist, so the Watch never
        // shows a blank "phantom" exercise.
        let existingExerciseIDs = Set(exercises.map(\.id))
        let syncWorkouts = workouts
            .filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { workout in
                SyncWorkout(id: workout.id.uuidString,
                            name: workout.name,
                            exerciseOrder: workout.exerciseOrder
                                .filter { existingExerciseIDs.contains($0) }
                                .map(\.uuidString))
            }

        let syncExercises = exercises.map {
            SyncExercise(id: $0.id.uuidString,
                         name: $0.name,
                         numberOfSeries: $0.numberOfSeries,
                         lowestWeight: $0.lowestWeight,
                         highestWeight: $0.highestWeight,
                         weightIncrement: $0.weightIncrement,
                         restSeconds: $0.restSeconds,
                         kindRaw: $0.kindRaw,
                         aerobicActivityRaw: $0.aerobicActivityRaw,
                         subtractsFromBodyWeight: $0.subtractsFromBodyWeight,
                         lowestGrams: $0.lowestWeightGrams ?? 0,
                         highestGrams: $0.highestWeightGrams ?? 0,
                         incrementGrams: $0.weightIncrementGrams ?? 0)
        }

        let payload = SyncPayload(
            workouts: syncWorkouts,
            exercises: syncExercises,
            lastEntries: lastMap,
            healthSharingEnabled: UserDefaults.standard.bool(forKey: "healthSharingEnabled"),
            restTimerEnabled: ExerciseDefaults.restTimerIsOn(),
            watchWorkoutMode: WatchWorkoutMode.current.rawValue,
            zoneTint: WatchPreferences.zoneTint,
            restTaps: WatchPreferences.restTaps,
            wheelRows: WatchPreferences.wheelRows,
            zoneBoundaries: WatchPreferences.zoneBoundaries,
            weightUnit: WeightUnit.current.rawValue,
            scheduleEnabled: WorkoutSchedule.isEnabled,
            scheduleDaysAhead: WorkoutSchedule.daysAhead,
            scheduleCount: WorkoutSchedule.count
        )
        return try? JSONEncoder().encode(payload)
    }

    /// Insert a set logged on the Apple Watch. De-duplicates on the incoming id
    /// so re-delivered messages don't create duplicate rows.
    func addWatchLog(id: UUID, date: Date, workoutId: UUID, exerciseId: UUID,
                     weights: [Int], reps: [Int],
                     legacyWeights: [Int] = [],
                     durationSeconds: Int? = nil,
                     averageHeartRate: Int = 0,
                     maximumHeartRate: Int = 0,
                     zoneSeconds: [Int] = []) {
        let targetID = id
        let descriptor = FetchDescriptor<WorkoutLog>(
            predicate: #Predicate<WorkoutLog> { $0.id == targetID }
        )
        if let existing = try? context.fetch(descriptor), !existing.isEmpty { return }

        // An assisted machine's wheels show what is SET on it. The Watch sends
        // that back unchanged — it has no business knowing what the user
        // weighs — and the conversion to the weight actually lifted happens
        // here, in the one place that writes a log from the Watch.
        let exercise = exercises.first { $0.id == exerciseId }
        let legacyUnit = WeightHistory.statedUnit ?? .current

        // `weights` is in GRAMS. A Watch that has not updated yet sends none,
        // only the unit-less numbers it has always sent, and reading THOSE as
        // grams would record a 130 lb set as 130 g. So the grams are used when
        // they are there and the old numbers are read through the exercise's
        // own wheel when they are not.
        let onTheWheels: [Int] = {
            guard weights.isEmpty, !legacyWeights.isEmpty else { return weights }
            guard let exercise else {
                return legacyWeights.map { legacyUnit.grams(from: Double($0)) }
            }
            return legacyWeights.map {
                WeightHistory.grams(fromLegacy: $0, of: exercise, in: legacyUnit)
            }
        }()

        let assisted = exercise?.subtractsFromBodyWeight == true
        let bodyWeightGrams = BodyWeight.currentGrams
        let lifted = assisted
            ? onTheWheels.map { max(0, bodyWeightGrams - $0) }
            : onTheWheels

        let log = WorkoutLog(id: id, date: date, workoutId: workoutId,
                             exerciseId: exerciseId,
                             weights: WeightHistory.legacyNumbers(for: lifted, of: exercise,
                                                                  in: legacyUnit),
                             reps: reps)
        context.insert(log)
        context.insert(LogWeights(logId: log.id, grams: lifted))
        if assisted {
            context.insert(AssistedResult(
                logId: log.id,
                bodyWeight: legacyUnit.display(grams: bodyWeightGrams),
                machineSettings: WeightHistory.legacyNumbers(for: onTheWheels, of: exercise,
                                                            in: legacyUnit),
                bodyWeightGrams: bodyWeightGrams,
                machineSettingsGrams: onTheWheels))
        }
        // Only for an aerobic session, and only one that actually ran.
        if let durationSeconds, durationSeconds > 0 {
            context.insert(AerobicResult(logId: log.id,
                                         durationSeconds: durationSeconds,
                                         averageHeartRate: averageHeartRate,
                                         maximumHeartRate: maximumHeartRate,
                                         zoneSeconds: zoneSeconds))
        }
        try? context.save()
        reloadAll()
    }

    func exportLogs() -> URL? {
        do {
            let descriptor = FetchDescriptor<WorkoutLog>(sortBy: [SortDescriptor(\WorkoutLog.date, order: .forward)])
            let logs = try context.fetch(descriptor)
            var text = ""
            for log in logs {
                let workoutText = workouts.first(where: { $0.id == log.workoutId })?.name ?? "Workout"
                let exerciseName = exercises.first(where: { $0.id == log.exerciseId })?.name ?? "Exercise"
                let weightsText = log.weights.map(String.init).joined(separator: "\t")
                let repsText = log.reps.map(String.init).joined(separator: "\t")
                text += "\(log.date.formatted(date: .numeric, time: .omitted))\t"
                text += "\(log.date.formatted(date: .omitted, time: .shortened))\t"
                text += "workout\t\"\(workoutText)\"\texercise\t\"\(exerciseName)\"\tweights\t\(weightsText)\trepetitions\t\(repsText)\n"
            }
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("workout_logs.txt")
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}
