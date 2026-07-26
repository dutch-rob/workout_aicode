import Foundation

// MARK: - Prepopulated exercise library
//
// A catalog defined in code, NOT rows in the database. Picking one copies it
// into the user's own exercises, so nobody inherits a list they have to prune
// and the app keeps starting empty as it always has.
//
// Every entry carries a stable `key`. A copy keeps that key, which is what lets
// "Lat pulldown" logged by different users — under whatever name they renamed
// it to — be recognised as the same movement in aggregate data and in the
// regression work planned later. User-invented exercises simply have no key.
//
// Defaults for every entry: 3 sets, weight range 0–200, increment 5.

struct LibraryExercise: Identifiable, Hashable {
    let key: String
    let name: String
    let primary: MuscleGroup
    let secondary: [MuscleGroup]

    var id: String { key }

    static let defaultSeries = 3
    static let defaultLowest = 0
    static let defaultHighest = 200
    static let defaultIncrement = 5
}

enum ExerciseLibrary {

    /// Every primary muscle group is represented at least once, so the filter
    /// never lands on an empty list.
    static let all: [LibraryExercise] = [
        // Chest
        .init(key: "bench-press",        name: "Bench press",
              primary: .chest,      secondary: [.frontDelts, .triceps]),
        .init(key: "incline-press",      name: "Incline chest press",
              primary: .chest,      secondary: [.frontDelts, .triceps]),
        .init(key: "chest-fly",          name: "Chest fly",
              primary: .chest,      secondary: [.frontDelts]),

        // Back
        .init(key: "lat-pulldown",       name: "Lat pulldown",
              primary: .back,       secondary: [.biceps, .rearDelts, .forearms]),
        .init(key: "seated-row",         name: "Seated row",
              primary: .back,       secondary: [.biceps, .rearDelts, .traps]),
        .init(key: "pull-up",            name: "Pull-up",
              primary: .back,       secondary: [.biceps, .forearms, .absCore]),

        // Traps
        .init(key: "shrug",              name: "Shrug",
              primary: .traps,      secondary: [.forearms]),
        .init(key: "upright-row",        name: "Upright row",
              primary: .traps,      secondary: [.sideDelts, .biceps]),

        // Delts
        .init(key: "overhead-press",     name: "Overhead press",
              primary: .frontDelts, secondary: [.triceps, .sideDelts, .traps]),
        .init(key: "front-raise",        name: "Front raise",
              primary: .frontDelts, secondary: []),
        .init(key: "lateral-raise",      name: "Lateral raise",
              primary: .sideDelts,  secondary: [.traps]),
        .init(key: "reverse-fly",        name: "Reverse fly",
              primary: .rearDelts,  secondary: [.traps, .back]),
        .init(key: "face-pull",          name: "Face pull",
              primary: .rearDelts,  secondary: [.traps, .back]),

        // Arms
        .init(key: "biceps-curl",        name: "Biceps curl",
              primary: .biceps,     secondary: [.forearms]),
        .init(key: "hammer-curl",        name: "Hammer curl",
              primary: .biceps,     secondary: [.forearms]),
        .init(key: "triceps-pushdown",   name: "Triceps pushdown",
              primary: .triceps,    secondary: []),
        .init(key: "triceps-extension",  name: "Overhead triceps extension",
              primary: .triceps,    secondary: []),
        .init(key: "wrist-curl",         name: "Wrist curl",
              primary: .forearms,   secondary: []),
        .init(key: "farmers-walk",       name: "Farmer's walk",
              primary: .forearms,   secondary: [.traps, .absCore, .glutes]),

        // Legs
        .init(key: "squat",              name: "Squat",
              primary: .quads,      secondary: [.glutes, .hamstrings, .lowerBack, .absCore]),
        .init(key: "leg-press",          name: "Leg press",
              primary: .quads,      secondary: [.glutes, .hamstrings]),
        .init(key: "leg-extension",      name: "Leg extension",
              primary: .quads,      secondary: []),
        .init(key: "romanian-deadlift",  name: "Romanian deadlift",
              primary: .hamstrings, secondary: [.glutes, .lowerBack, .forearms]),
        .init(key: "leg-curl",           name: "Leg curl",
              primary: .hamstrings, secondary: [.calves]),
        .init(key: "hip-thrust",         name: "Hip thrust",
              primary: .glutes,     secondary: [.hamstrings, .lowerBack]),
        .init(key: "lunge",              name: "Lunge",
              primary: .glutes,     secondary: [.quads, .hamstrings, .absCore]),
        .init(key: "calf-raise",         name: "Calf raise",
              primary: .calves,     secondary: []),
        .init(key: "seated-calf-raise",  name: "Seated calf raise",
              primary: .calves,     secondary: []),

        // Trunk
        .init(key: "cable-crunch",       name: "Cable crunch",
              primary: .absCore,    secondary: [.lowerBack]),
        .init(key: "plank",              name: "Plank",
              primary: .absCore,    secondary: [.lowerBack, .frontDelts]),
        .init(key: "hanging-leg-raise",  name: "Hanging leg raise",
              primary: .absCore,    secondary: [.forearms]),
        .init(key: "back-extension",     name: "Back extension",
              primary: .lowerBack,  secondary: [.glutes, .hamstrings]),
        .init(key: "deadlift",           name: "Deadlift",
              primary: .lowerBack,  secondary: [.glutes, .hamstrings, .traps, .forearms]),
    ]

    static func forPrimary(_ group: MuscleGroup?) -> [LibraryExercise] {
        guard let group else { return all }
        return all.filter { $0.primary == group }
    }

    static func entry(key: String) -> LibraryExercise? {
        all.first { $0.key == key }
    }

    /// Build an editable exercise from a library entry. The copy is the user's:
    /// they can rename it or change its ranges, and `libraryKey` still records
    /// which movement it started as.
    static func makeExercise(from entry: LibraryExercise) -> ExerciseDef {
        ExerciseDef(name: entry.name,
                    numberOfSeries: LibraryExercise.defaultSeries,
                    lowestWeight: LibraryExercise.defaultLowest,
                    highestWeight: LibraryExercise.defaultHighest,
                    weightIncrement: LibraryExercise.defaultIncrement,
                    primaryMuscle: entry.primary,
                    secondaryMuscles: entry.secondary,
                    libraryKey: entry.key)
    }
}
