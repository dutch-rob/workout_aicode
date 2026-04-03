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
            workouts = (try context.fetch(workoutsDescriptor)).sorted { lhs, rhs in
                if lhs.sortIndex != rhs.sortIndex { return lhs.sortIndex < rhs.sortIndex }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            var changed = false
            for (idx, w) in workouts.enumerated() {
                if w.sortIndex != idx {
                    w.sortIndex = idx
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
        for (idx, w) in newOrder.enumerated() {
            w.sortIndex = idx
        }
        try? context.save()
        reloadAll()
    }

    func lastEntries(for workout: WorkoutDef) -> [UUID: ExerciseLogEntry] {
        do {
            let workoutID = workout.id
            let descriptor = FetchDescriptor<WorkoutLog>(
                predicate: #Predicate<WorkoutLog> { $0.workoutId == workoutID },
                sortBy: [SortDescriptor(\WorkoutLog.date, order: .reverse)]
            )
            let logs = try context.fetch(descriptor)
            var map: [UUID: ExerciseLogEntry] = [:]
            let targetSet = Set(workout.exerciseOrder)
            for log in logs { 
                for e in log.entries {
                    if targetSet.contains(e.exerciseId) && map[e.exerciseId] == nil {
                        map[e.exerciseId] = e
                    }
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
                for e in log.entries {
                    let workoutText = workouts.first(where: { $0.id == log.workoutId })?.name ?? "Workout"
                    let exName = exercises.first(where: { $0.id == e.exerciseId })?.name ?? "Exercise"
                    let weightsText = e.weights.map(String.init).joined(separator: "\t")
                    let repsText = e.reps.map(String.init).joined(separator: "\t")
                    text += "\(log.date.formatted(date: .numeric, time: .omitted))\t"
                    text += "\(log.date.formatted(date: .omitted, time: .shortened))\t"
                    text += "workout\t\"\(workoutText)\"\texercise\t\"\(exName)\"\tweights\t\(weightsText)\trepetitions\t\(repsText)\n"
                }
            }
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("workout_logs.txt")
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}
