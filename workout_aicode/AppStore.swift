import SwiftUI
import SwiftData

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
            workouts = try context.fetch(workoutsDescriptor)
            exercises = try context.fetch(exercisesDescriptor)
        } catch {
            workouts = []
            exercises = []
        }
    }

    func saveWorkout(_ workout: WorkoutDef) {
        do {
            let descriptor = FetchDescriptor<WorkoutDef>(predicate: #Predicate { $0.id == workout.id })
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
            let descriptor = FetchDescriptor<ExerciseDef>(predicate: #Predicate { $0.id == exercise.id })
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
}
