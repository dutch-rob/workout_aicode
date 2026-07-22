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

    func reorderWorkouts(_ newOrder: [WorkoutDef]) {
        for (idx, workout) in newOrder.enumerated() {
            workout.sortIndex = idx
        }
        try? context.save()
        reloadAll()
    }

    /// For each exercise in the workout, the most recent log row (used to
    /// pre-fill the picker wheels). Returns at most one row per exercise.
    func lastEntries(for workout: WorkoutDef) -> [UUID: WorkoutLog] {
        do {
            let workoutID = workout.id
            let descriptor = FetchDescriptor<WorkoutLog>(
                predicate: #Predicate<WorkoutLog> { $0.workoutId == workoutID },
                sortBy: [SortDescriptor(\WorkoutLog.date, order: .reverse)]
            )
            let logs = try context.fetch(descriptor)
            var map: [UUID: WorkoutLog] = [:]
            let targetSet = Set(workout.exerciseOrder)
            for log in logs {
                if targetSet.contains(log.exerciseId) && map[log.exerciseId] == nil {
                    map[log.exerciseId] = log
                }
                if map.count == targetSet.count { break }
            }
            return map
        } catch {
            return [:]
        }
    }

    // MARK: - Apple Watch sync

    /// Build the JSON payload the Watch needs to select and log a workout on its
    /// own: all workout + exercise definitions plus the most recent logged
    /// weights/reps per (workout, exercise) so the Watch pickers pre-fill.
    func watchSyncPayloadData() -> Data? {
        var lastMap: [String: SyncLastEntry] = [:]
        for workout in workouts {
            let entries = lastEntries(for: workout)
            for (exId, log) in entries {
                let key = SyncPayload.lastEntryKey(workoutId: workout.id.uuidString,
                                                   exerciseId: exId.uuidString)
                lastMap[key] = SyncLastEntry(weights: log.weights, reps: log.reps)
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
                         weightIncrement: $0.weightIncrement)
        }

        let payload = SyncPayload(
            workouts: syncWorkouts,
            exercises: syncExercises,
            lastEntries: lastMap,
            healthSharingEnabled: UserDefaults.standard.bool(forKey: "healthSharingEnabled")
        )
        return try? JSONEncoder().encode(payload)
    }

    /// Insert a set logged on the Apple Watch. De-duplicates on the incoming id
    /// so re-delivered messages don't create duplicate rows.
    func addWatchLog(id: UUID, date: Date, workoutId: UUID, exerciseId: UUID,
                     weights: [Int], reps: [Int]) {
        let targetID = id
        let descriptor = FetchDescriptor<WorkoutLog>(
            predicate: #Predicate<WorkoutLog> { $0.id == targetID }
        )
        if let existing = try? context.fetch(descriptor), !existing.isEmpty { return }

        let log = WorkoutLog(id: id, date: date, workoutId: workoutId,
                             exerciseId: exerciseId, weights: weights, reps: reps)
        context.insert(log)
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
