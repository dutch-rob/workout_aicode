import SwiftUI
import SwiftData

// MARK: - Adding an exercise from the library

/// Browse the built-in catalog and copy one into your own exercises.
/// Filtering is by primary muscle group, which is the whole point of the
/// filter: it turns a 30-item list into a handful.
struct AddFromLibraryView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Query private var existing: [ExerciseDef]

    @State private var filter: MuscleGroup? = nil
    /// Exercise created here, so the caller can open it for editing.
    var onAdd: (ExerciseDef) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                MuscleGroupFilterBar(selection: $filter)
                List {
                    ForEach(ExerciseLibrary.forPrimary(filter)) { entry in
                        Button {
                            add(entry)
                        } label: {
                            LibraryRow(entry: entry, alreadyAdded: isAlreadyAdded(entry))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("exercise library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    /// Already-added entries stay tappable — someone may genuinely want two
    /// variants of a movement — but are marked so the list is honest.
    private func isAlreadyAdded(_ entry: LibraryExercise) -> Bool {
        existing.contains { $0.libraryKey == entry.key }
    }

    private func add(_ entry: LibraryExercise) {
        let exercise = ExerciseLibrary.makeExercise(from: entry)
        // A duplicate name would be confusing in every picker, so the second
        // copy is numbered rather than silently identical.
        exercise.name = uniqueName(for: entry.name)
        store.saveExercise(exercise)
        onAdd(exercise)
        dismiss()
    }

    private func uniqueName(for base: String) -> String {
        let taken = Set(existing.map { $0.name.lowercased() })
        guard taken.contains(base.lowercased()) else { return base }
        var n = 2
        while taken.contains("\(base) \(n)".lowercased()) { n += 1 }
        return "\(base) \(n)"
    }
}

private struct LibraryRow: View {
    let entry: LibraryExercise
    let alreadyAdded: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name).font(.body)
                Text(muscleSummary).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if alreadyAdded {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("already in your exercises")
            } else {
                Image(systemName: "plus.circle").foregroundStyle(.blue)
            }
        }
        .contentShape(Rectangle())
    }

    private var muscleSummary: String {
        let secondary = entry.secondary.map(\.shortLabel).joined(separator: ", ")
        return secondary.isEmpty
            ? entry.primary.label
            : "\(entry.primary.label) · also \(secondary)"
    }
}

// MARK: - Filter bar

/// Horizontal muscle-group chips, with "all" first. Scrolls because fifteen
/// groups never fit across a phone.
struct MuscleGroupFilterBar: View {
    @Binding var selection: MuscleGroup?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "all", isSelected: selection == nil) { selection = nil }
                ForEach(MuscleGroup.displayOrder) { group in
                    chip(title: group.shortLabel, isSelected: selection == group) {
                        selection = (selection == group) ? nil : group
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func chip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(isSelected ? Color.blue : Color.secondary.opacity(0.15))
                )
                .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Muscle group editing

/// Primary group plus up to four secondary ones, for the edit exercise screen.
struct MuscleGroupSection: View {
    @Bindable var exercise: ExerciseDef

    var body: some View {
        Section {
            Picker("Primary muscle group", selection: primaryBinding) {
                Text("not set").tag(MuscleGroup?.none)
                ForEach(MuscleGroup.displayOrder) { group in
                    Text(group.label).tag(MuscleGroup?.some(group))
                }
            }

            NavigationLink {
                SecondaryMusclePicker(exercise: exercise)
            } label: {
                LabeledContent("Secondary muscle groups") {
                    Text(secondarySummary).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Muscle groups")
        } footer: {
            Text("Used to group your training by muscle group, and to compare exercises. Up to \(MuscleGroup.maximumSecondary) secondary groups.")
        }
    }

    private var primaryBinding: Binding<MuscleGroup?> {
        Binding(get: { exercise.primaryMuscle }, set: { exercise.primaryMuscle = $0 })
    }

    private var secondarySummary: String {
        let s = exercise.secondaryMuscles
        return s.isEmpty ? "none" : s.map(\.shortLabel).joined(separator: ", ")
    }
}

struct SecondaryMusclePicker: View {
    @Bindable var exercise: ExerciseDef

    var body: some View {
        List {
            Section {
                ForEach(MuscleGroup.displayOrder) { group in
                    Button {
                        toggle(group)
                    } label: {
                        HStack {
                            Text(group.label).foregroundStyle(.primary)
                            Spacer()
                            if exercise.secondaryMuscles.contains(group) {
                                Image(systemName: "checkmark").foregroundStyle(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .disabled(isFull && !exercise.secondaryMuscles.contains(group))
                }
            } footer: {
                Text(isFull
                     ? "That is the maximum of \(MuscleGroup.maximumSecondary). Deselect one to choose another."
                     : "Choose up to \(MuscleGroup.maximumSecondary).")
            }
        }
        .navigationTitle("secondary muscles")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var isFull: Bool { exercise.secondaryMuscles.count >= MuscleGroup.maximumSecondary }

    private func toggle(_ group: MuscleGroup) {
        var current = exercise.secondaryMuscles
        if let idx = current.firstIndex(of: group) {
            current.remove(at: idx)
        } else if current.count < MuscleGroup.maximumSecondary {
            current.append(group)
        }
        exercise.secondaryMuscles = current
    }
}

// MARK: - Duplicating an exercise

/// Copies an exercise's settings under a new name. The name is required to be
/// new: two exercises with one name are indistinguishable everywhere they are
/// picked, and their logs could not be told apart afterwards either.
struct DuplicateExerciseView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Query private var existing: [ExerciseDef]

    let source: ExerciseDef
    var onDuplicate: (ExerciseDef) -> Void

    @State private var name: String = ""

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isEmpty: Bool { trimmed.isEmpty }
    private var isTaken: Bool {
        existing.contains { $0.name.lowercased() == trimmed.lowercased() }
    }
    private var isValid: Bool { !isEmpty && !isTaken }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name for the copy", text: $name)
                        .autocorrectionDisabled()
                } footer: {
                    if isTaken {
                        Text("You already have an exercise called “\(trimmed)”. Pick another name.")
                            .foregroundStyle(.red)
                    } else {
                        Text("Copies the sets, weight range and muscle groups of “\(source.name)”. Logs are not copied.")
                    }
                }
            }
            .navigationTitle("duplicate exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Duplicate") { duplicate() }.disabled(!isValid)
                }
            }
            .onAppear { if name.isEmpty { name = suggestedName } }
        }
    }

    private var suggestedName: String {
        let taken = Set(existing.map { $0.name.lowercased() })
        var candidate = "\(source.name) copy"
        var n = 2
        while taken.contains(candidate.lowercased()) {
            candidate = "\(source.name) copy \(n)"
            n += 1
        }
        return candidate
    }

    private func duplicate() {
        guard isValid else { return }
        let copy = ExerciseDef(name: trimmed,
                               numberOfSeries: source.numberOfSeries,
                               lowestWeight: source.lowestWeight,
                               highestWeight: source.highestWeight,
                               weightIncrement: source.weightIncrement,
                               movementType: source.movementType,
                               primaryMuscle: source.primaryMuscle,
                               secondaryMuscles: source.secondaryMuscles,
                               libraryKey: source.libraryKey)
        store.saveExercise(copy)
        onDuplicate(copy)
        dismiss()
    }
}
