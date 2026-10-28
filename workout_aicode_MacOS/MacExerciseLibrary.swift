import SwiftUI
import SwiftData

// MARK: - The ready-made exercises, on the Mac
//
// The same catalogue the phone offers: thirty-odd strength movements with
// their muscle groups already filled in, and one aerobic entry per Apple
// indoor workout. The Mac had been compiling ExerciseLibrary all along and
// never showing it, so the only way to get an exercise here was to make a
// blank one and type everything — including the muscle groups, which is the
// part the library exists to save.
//
// Taking one goes through ExerciseLibrary.take, which is where the phone goes
// too: same numbers, same unique-name rule, same library key. The key is the
// point — it is what lets one person's renamed "Lat pulldown" still be
// recognised as the same movement as another's.

/// What the list is showing. Aerobic sits among the muscle groups rather than
/// beside them because on the phone the two are one choice: an exercise is one
/// kind or the other, so both at once could only ever show nothing.
enum MacExerciseFilter: Hashable, Identifiable {
    case all
    case aerobic
    case muscle(MuscleGroup)

    var id: String {
        switch self {
        case .all:              return "all"
        case .aerobic:          return "aerobic"
        case .muscle(let g):    return g.rawValue
        }
    }

    var label: String {
        switch self {
        case .all:              return "All exercises"
        case .aerobic:          return "Aerobic"
        case .muscle(let g):    return g.label
        }
    }

    var muscle: MuscleGroup? {
        if case .muscle(let g) = self { return g }
        return nil
    }

    var isAerobic: Bool { self == .aerobic }

    static var choices: [MacExerciseFilter] {
        [.all, .aerobic] + MuscleGroup.displayOrder.map(MacExerciseFilter.muscle)
    }
}

/// Filtering that both the exercises screen and the workout builder need, kept
/// in one place so the two cannot come to different answers about what "Chest"
/// or a typed search means.
struct MacExerciseSieve {
    var filter: MacExerciseFilter = .all
    var search: String = ""

    private var needle: String {
        search.trimmingCharacters(in: .whitespaces).lowercased()
    }

    private func matches(name: String) -> Bool {
        needle.isEmpty || name.lowercased().contains(needle)
    }

    func own(_ exercises: [ExerciseDef]) -> [ExerciseDef] {
        exercises.filter { exercise in
            guard matches(name: exercise.name) else { return false }
            switch filter {
            case .all:              return true
            case .aerobic:          return exercise.kind == .aerobic
            case .muscle(let g):    return exercise.kind == .strength
                                        && exercise.primaryMuscle == g
            }
        }
    }

    /// Ready-made strength entries not taken yet.
    func strengthTemplates(taken: Set<String>) -> [LibraryExercise] {
        guard !filter.isAerobic else { return [] }
        return ExerciseLibrary.forPrimary(filter.muscle)
            .filter { !taken.contains($0.key) && matches(name: $0.name) }
    }

    /// Ready-made aerobic entries not taken yet.
    ///
    /// Offered under "All" as well as under "Aerobic", unlike the phone, which
    /// shows them only under its AE button. There is a search field here:
    /// someone typing "cycle" with no filter set means it, and finding nothing
    /// would be the app hiding an exercise it has.
    func aerobicTemplates(taken: Set<String>) -> [AerobicLibraryExercise] {
        guard filter == .all || filter.isAerobic else { return [] }
        return ExerciseLibrary.aerobic
            .filter { !taken.contains($0.key) && matches(name: $0.name) }
    }
}

// MARK: - Rows

/// One ready-made entry, with the muscles it works written out.
struct MacTemplateRow: View {
    let name: String
    let detail: String
    let add: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                Text(detail).macFont(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: add) { Image(systemName: "plus.circle") }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
                .help("Add to your exercises")
        }
        .contentShape(Rectangle())
        // The whole row, not only the little button — a two-millimetre target
        // is a poor way to ask for something the user is going to do thirty
        // times in a row.
        .onTapGesture(perform: add)
    }
}

extension LibraryExercise {
    /// "Chest · also Front delts, Triceps"
    var muscleSummary: String {
        let also = secondary.map(\.shortLabel).joined(separator: ", ")
        return also.isEmpty ? primary.label : "\(primary.label) · also \(also)"
    }
}

// MARK: - Filter bar

struct MacExerciseFilterBar: View {
    @Binding var sieve: MacExerciseSieve

    var body: some View {
        VStack(spacing: 6) {
            Picker("", selection: $sieve.filter) {
                ForEach(MacExerciseFilter.choices) { choice in
                    Text(choice.label).tag(choice)
                }
            }
            .labelsHidden()
            TextField("Search", text: $sieve.search)
                .textFieldStyle(.roundedBorder)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}
