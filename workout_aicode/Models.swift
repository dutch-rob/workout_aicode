import Foundation
import SwiftData

@Model
final class ExerciseDef: Identifiable, Hashable, Codable {
    @Attribute(.unique) var id: UUID
    var name: String
    var numberOfSeries: Int
    var lowestWeight: Int
    var highestWeight: Int
    var weightIncrement: Int

    init(id: UUID = UUID(), name: String, numberOfSeries: Int = 3, lowestWeight: Int = 0, highestWeight: Int = 200, weightIncrement: Int = 5) {
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
    }

    enum CodingKeys: String, CodingKey { case id, name, numberOfSeries, lowestWeight, highestWeight, weightIncrement }
    convenience init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(UUID.self, forKey: .id)
        let name = try c.decode(String.self, forKey: .name)
        let numberOfSeries = try c.decode(Int.self, forKey: .numberOfSeries)
        let lowestWeight = try c.decode(Int.self, forKey: .lowestWeight)
        let highestWeight = try c.decode(Int.self, forKey: .highestWeight)
        let weightIncrement = try c.decode(Int.self, forKey: .weightIncrement)
        self.init(id: id, name: name, numberOfSeries: numberOfSeries, lowestWeight: lowestWeight, highestWeight: highestWeight, weightIncrement: weightIncrement)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(numberOfSeries, forKey: .numberOfSeries)
        try c.encode(lowestWeight, forKey: .lowestWeight)
        try c.encode(highestWeight, forKey: .highestWeight)
        try c.encode(weightIncrement, forKey: .weightIncrement)
    }
}

@Model
final class WorkoutDef: Identifiable, Hashable, Codable {
    @Attribute(.unique) var id: UUID
    var name: String
    // Ordered list of exercise IDs to preserve order
    var exerciseOrder: [UUID]
    var sortIndex: Int

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

@Model
final class WorkoutLog: Identifiable, Codable {
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

    enum CodingKeys: String, CodingKey { case id, date, workoutId, entries }
    convenience init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(UUID.self, forKey: .id)
        let date = try c.decode(Date.self, forKey: .date)
        let workoutId = try c.decode(UUID.self, forKey: .workoutId)
        let entries = try c.decode([ExerciseLogEntry].self, forKey: .entries)
        self.init(id: id, date: date, workoutId: workoutId, entries: entries)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(date, forKey: .date)
        try c.encode(workoutId, forKey: .workoutId)
        try c.encode(entries, forKey: .entries)
    }
}

struct ExerciseLogEntry: Codable, Hashable {
    var exerciseId: UUID
    var weights: [Int]
    var reps: [Int]
}
