import Foundation
import SwiftData

@Model
final class ExerciseDef: Identifiable, Hashable {
    @Attribute(.unique) var id: UUID
    var name: String
    var numberOfSeries: Int
    var lowestWeight: Int
    var highestWeight: Int
    var weightIncrement: Int

    init(id: UUID = UUID(), name: String, numberOfSeries: Int = 3, lowestWeight: Int = 0, highestWeight: Int = 200, weightIncrement: Int = 5) {
        self.id = id
        self.name = name
        self.numberOfSeries = max(0, numberOfSeries)
        self.lowestWeight = max(0, lowestWeight)
        self.highestWeight = max(self.lowestWeight, highestWeight)
        self.weightIncrement = max(1, weightIncrement)
    }
}

@Model
final class WorkoutDef: Identifiable, Hashable {
    @Attribute(.unique) var id: UUID
    var name: String
    // Ordered list of exercise IDs to preserve order
    var exerciseOrder: [UUID]

    init(id: UUID = UUID(), name: String, exerciseOrder: [UUID] = []) {
        self.id = id
        self.name = name
        self.exerciseOrder = exerciseOrder
    }
}

@Model
final class WorkoutLog: Identifiable {
    @Attribute(.unique) var id: UUID
    var date: Date
    var workoutId: UUID
    var entries: [ExerciseLogEntry]

    init(id: UUID = UUID(), date: Date = Date(), workoutId: UUID, entries: [ExerciseLogEntry]) {
        self.id = id
        self.date = date
        self.workoutId = workoutId
        self.entries = entries
    }
}

struct ExerciseLogEntry: Codable, Hashable {
    var exerciseId: UUID
    var weights: [Int]
    var reps: [Int]
}
