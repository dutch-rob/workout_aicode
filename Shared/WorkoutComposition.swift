import Foundation

// MARK: - Making one workout out of others
//
// Copying a workout and joining two of them are the same small operation seen
// twice: a new WorkoutDef over a list of exercise ids that already exist.
//
// The exercises themselves are NOT copied, and that is the point. An
// ExerciseDef carries the wheel's range, the increment and the rest, and every
// logged set points at one by id. A copied workout that pointed at copied
// exercises would start its history again from nothing, and the graphs would
// show one lift as two — so both workouts name the same chest press, and a set
// logged under either counts once.
//
// Shared, because the phone and the Mac both offer this and a workout joined
// differently on two devices would be two different workouts in one iCloud
// store.

nonisolated enum WorkoutComposition {

    /// A copy of `workout` under a new name, at the end of the list.
    static func copy(of workout: WorkoutDef, named name: String,
                     among all: [WorkoutDef]) -> WorkoutDef {
        WorkoutDef(name: name,
                   exerciseOrder: workout.exerciseOrder,
                   sortIndex: nextSortIndex(among: all))
    }

    /// One workout holding `first`'s exercises and then `second`'s.
    ///
    /// An exercise in both appears once, where it first falls. Two "warm-up"
    /// rows in one workout would be two sets of the same lift to log and two
    /// identical rows to read back, and nobody means that by joining two
    /// workouts.
    static func merge(_ first: WorkoutDef, _ second: WorkoutDef, named name: String,
                      among all: [WorkoutDef]) -> WorkoutDef {
        var seen = Set<UUID>()
        let order = (first.exerciseOrder + second.exerciseOrder).filter { seen.insert($0).inserted }
        return WorkoutDef(name: name, exerciseOrder: order,
                          sortIndex: nextSortIndex(among: all))
    }

    /// "Leg day copy", then "Leg day copy 2" — never a second workout with a
    /// name already in use, which on a watch face is indistinguishable.
    static func copyName(for workout: WorkoutDef, among all: [WorkoutDef]) -> String {
        unused("\(workout.name.isEmpty ? "Workout" : workout.name) copy", among: all)
    }

    /// "Upper body + Leg day", shortened at both ends if that would be absurd
    /// to read. The user can rename it; this only has to be a sane start.
    static func mergedName(_ first: WorkoutDef, _ second: WorkoutDef,
                           among all: [WorkoutDef]) -> String {
        let left = first.name.isEmpty ? "Workout" : first.name
        let right = second.name.isEmpty ? "Workout" : second.name
        return unused("\(left) + \(right)", among: all)
    }

    /// `name`, or `name` with the lowest number that nobody is using.
    static func unused(_ name: String, among all: [WorkoutDef]) -> String {
        let taken = Set(all.map { $0.name })
        guard taken.contains(name) else { return name }
        var n = 2
        while taken.contains("\(name) \(n)") { n += 1 }
        return "\(name) \(n)"
    }

    static func nextSortIndex(among all: [WorkoutDef]) -> Int {
        (all.map(\.sortIndex).max() ?? -1) + 1
    }
}
