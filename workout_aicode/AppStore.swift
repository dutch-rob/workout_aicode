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
