import SwiftUI
import SwiftData

// MARK: - Exercise library
//
// One screen for every exercise: the ones the user has made and the ready-made
// ones they have not taken yet, with a single muscle-group selector over both.
// It replaces the old pair of screens — "edit exercises" plus a separate
// library sheet — which had two selectors and made "mine" and "available" feel
// like different worlds when they are really one list.
//
// The same screen serves two errands, and the tick on the right means whichever
// one you came for:
//
//   • from the workouts screen — browsing: the tick says the exercise is in at
//     least one workout, and tapping opens it for editing;
//   • from a workout — selecting: the tick says it is in THAT workout, and
//     tapping puts it in or takes it out.

enum LibraryContext {
    case browsing
    /// Choosing exercises for one particular workout.
    case selecting(WorkoutDef)

    var workout: WorkoutDef? {
        if case .selecting(let w) = self { return w }
        return nil
    }
}

/// How the muscle-group filter is presented.
enum MusclePickerStyle: String, CaseIterable, Identifiable {
    /// Two body diagrams with a labelled button beside each muscle.
    case body
    /// Plain buttons, four columns, in the same reading order.
    case buttons

    var id: String { rawValue }
    var label: String { self == .body ? "body diagram" : "buttons" }
    var icon: String { self == .body ? "figure.arms.open" : "square.grid.2x2" }
}

struct ExerciseLibraryView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\ExerciseDef.name)]) private var exercises: [ExerciseDef]
    @Query private var workouts: [WorkoutDef]

    var context_: LibraryContext = .browsing

    @AppStorage("musclePickerStyle") private var pickerStyle = MusclePickerStyle.body.rawValue
    @AppStorage("libraryFavouritesOnly") private var favouritesOnly = false

    @State private var filter: MuscleGroup? = nil
    @State private var pendingExercise: ExerciseDef? = nil
    @State private var exerciseToDuplicate: ExerciseDef? = nil
    @State private var exercisePendingDelete: ExerciseDef? = nil
    @State private var showDeleteConfirm = false

    private var style: MusclePickerStyle {
        MusclePickerStyle(rawValue: pickerStyle) ?? .body
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    let exercise = ExerciseDefaults.makeExercise(primary: filter)
                    store.saveExercise(exercise)
                    if let workout = context_.workout {
                        workout.exerciseOrder.append(exercise.id)
                    }
                    pendingExercise = exercise
                } label: {
                    Text("new exercise").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    favouritesOnly.toggle()
                } label: {
                    Label(favouritesOnly ? "favourites" : "all",
                          systemImage: favouritesOnly ? "star.fill" : "star")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)
            .padding(.bottom, 6)

            if style == .body {
                MuscleBodyPicker(selection: $filter)
            } else {
                MuscleButtonGrid(selection: $filter)
            }

            List {
                if !ownExercises.isEmpty {
                    Section("Your exercises") {
                        ForEach(ownExercises) { exercise in
                            ownRow(exercise)
                        }
                    }
                }
                if !templates.isEmpty {
                    Section("Ready-made") {
                        ForEach(templates) { entry in
                            templateRow(entry)
                        }
                    }
                }
                if ownExercises.isEmpty && templates.isEmpty {
                    ContentUnavailableView("Nothing here",
                                           systemImage: "line.3.horizontal.decrease.circle",
                                           description: Text(favouritesOnly
                                                             ? "No favourites in this muscle group."
                                                             : "No exercises for this muscle group."))
                }
            }
            .listStyle(.insetGrouped)
        }
        .navigationTitle(context_.workout == nil ? "exercise library" : "select exercise")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                // A plain toggle, not a menu: there are two states, so one tap
                // should switch them.
                Button {
                    pickerStyle = (style == .body ? MusclePickerStyle.buttons : .body).rawValue
                } label: {
                    Image(systemName: style.icon)
                }
                .accessibilityLabel(style == .body ? "Show buttons instead of the body"
                                                   : "Show the body diagram")
            }
        }
        .navigationDestination(item: $pendingExercise) { exercise in
            EditExerciseView(exercise: exercise)
        }
        .sheet(item: $exerciseToDuplicate) { source in
            DuplicateExerciseView(source: source) { copy in pendingExercise = copy }
                .environmentObject(store)
        }
        .confirmationDialog("Delete Exercise?", isPresented: $showDeleteConfirm,
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let exercise = exercisePendingDelete { store.deleteExercise(exercise) }
                exercisePendingDelete = nil
            }
            Button("Cancel", role: .cancel) { exercisePendingDelete = nil }
        } message: {
            Text("This removes it from your list and from any workout that uses it. Logged sets are kept.")
        }
        .onAppear { store.reloadAll() }
    }

    // MARK: Rows

    private func ownRow(_ exercise: ExerciseDef) -> some View {
        Button {
            switch context_ {
            case .browsing:
                pendingExercise = exercise
            case .selecting(let workout):
                toggle(exercise, in: workout)
            }
        } label: {
            HStack(spacing: 10) {
                Button {
                    exercise.isFavourite.toggle()
                } label: {
                    Image(systemName: exercise.isFavourite ? "star.fill" : "star")
                        .foregroundStyle(exercise.isFavourite ? .yellow : .secondary)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name.isEmpty ? "(unnamed)" : exercise.name)
                        .foregroundStyle(.primary)
                    if let primary = exercise.primaryMuscle {
                        Text(primary.shortLabel).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                tick(isOn: isTicked(exercise))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                exercisePendingDelete = exercise
                showDeleteConfirm = true
            } label: { Label("Delete", systemImage: "trash") }

            Button { exerciseToDuplicate = exercise } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            .tint(.blue)

            if context_.workout != nil {
                Button { pendingExercise = exercise } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .tint(.gray)
            }
        }
    }

    private func templateRow(_ entry: LibraryExercise) -> some View {
        Button {
            let exercise = add(entry)
            if let workout = context_.workout {
                workout.exerciseOrder.append(exercise.id)
            } else {
                pendingExercise = exercise
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "star").foregroundStyle(.clear)   // keeps names aligned
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name).foregroundStyle(.primary)
                    Text(muscleSummary(entry)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "plus.circle").foregroundStyle(.blue)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func tick(isOn: Bool) -> some View {
        Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(isOn ? Color.blue : Color.secondary.opacity(0.4))
    }

    /// What the tick means depends on why the screen was opened.
    private func isTicked(_ exercise: ExerciseDef) -> Bool {
        switch context_ {
        case .browsing:
            return workouts.contains { $0.exerciseOrder.contains(exercise.id) }
        case .selecting(let workout):
            return workout.exerciseOrder.contains(exercise.id)
        }
    }

    // MARK: Contents

    private var ownExercises: [ExerciseDef] {
        exercises
            .filter { filter == nil || $0.primaryMuscle == filter }
            .filter { !favouritesOnly || $0.isFavourite }
            .sorted { a, b in
                if a.isFavourite != b.isFavourite { return a.isFavourite }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
    }

    /// Library entries the user has not taken yet. Favourites are a property of
    /// the user's own exercises, so filtering by them hides this section
    /// entirely rather than showing entries that can never match.
    private var templates: [LibraryExercise] {
        guard !favouritesOnly else { return [] }
        let taken = Set(exercises.compactMap(\.libraryKey))
        return ExerciseLibrary.forPrimary(filter).filter { !taken.contains($0.key) }
    }

    private func muscleSummary(_ entry: LibraryExercise) -> String {
        let secondary = entry.secondary.map(\.shortLabel).joined(separator: ", ")
        return secondary.isEmpty ? entry.primary.label
                                 : "\(entry.primary.label) · also \(secondary)"
    }

    // MARK: Actions

    private func add(_ entry: LibraryExercise) -> ExerciseDef {
        let exercise = ExerciseDefaults.makeExercise(name: entry.name,
                                                     primary: entry.primary,
                                                     secondary: entry.secondary,
                                                     libraryKey: entry.key)
        exercise.name = uniqueName(entry.name)
        store.saveExercise(exercise)
        return exercise
    }

    private func uniqueName(_ base: String) -> String {
        let taken = Set(exercises.map { $0.name.lowercased() })
        guard taken.contains(base.lowercased()) else { return base }
        var n = 2
        while taken.contains("\(base) \(n)".lowercased()) { n += 1 }
        return "\(base) \(n)"
    }

    private func toggle(_ exercise: ExerciseDef, in workout: WorkoutDef) {
        if let index = workout.exerciseOrder.firstIndex(of: exercise.id) {
            workout.exerciseOrder.remove(at: index)
        } else {
            workout.exerciseOrder.append(exercise.id)
        }
        try? context.save()
    }
}

// MARK: - Buttons instead of the diagram

/// The same groups as the body diagram, in the same reading order — down the
/// front, then down the back — but as plain buttons in four columns, two per
/// figure. For anyone who would rather not hunt on a picture, and for a screen
/// where the diagram is more height than they want to give it.
struct MuscleButtonGrid: View {
    @Binding var selection: MuscleGroup?

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                column(MuscleBodyPicker.frontOrder, caption: "front")
                column(MuscleBodyPicker.backOrder, caption: "back")
            }
            Button {
                selection = nil
            } label: {
                Text("all muscle groups")
                    .font(.subheadline)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(Capsule().fill(selection == nil
                                               ? Color.blue : Color.secondary.opacity(0.15)))
                    .foregroundStyle(selection == nil ? Color.white : Color.primary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    /// One figure's groups across two columns, filled top-to-bottom then
    /// left-to-right so the order still reads like the body.
    private func column(_ groups: [MuscleGroup], caption: String) -> some View {
        let half = (groups.count + 1) / 2
        return VStack(spacing: 4) {
            Text(caption).font(.caption2).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 4) {
                subColumn(Array(groups.prefix(half)))
                subColumn(Array(groups.dropFirst(half)))
            }
        }
    }

    private func subColumn(_ groups: [MuscleGroup]) -> some View {
        VStack(spacing: 4) {
            ForEach(groups) { group in
                Button {
                    selection = (selection == group) ? nil : group
                } label: {
                    Text(group.shortLabel)
                        .font(.caption)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(selection == group
                                                   ? Color.blue
                                                   : Color.secondary.opacity(0.15)))
                        .foregroundStyle(selection == group ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
            }
        }
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
    private var isTaken: Bool {
        existing.contains { $0.name.lowercased() == trimmed.lowercased() }
    }
    private var isValid: Bool { !trimmed.isEmpty && !isTaken }

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

// MARK: - Which workouts use this exercise

/// Shown on the edit-exercise screen, and editable there.
///
/// The same relationship can be edited from either end: a workout's screen says
/// which exercises are in it, and this says which workouts an exercise is in.
/// Someone who has just made a new exercise usually wants it in a workout right
/// away, and going back out to each workout to add it is the long way round.
struct WorkoutMembershipSection: View {
    @Bindable var exercise: ExerciseDef
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\WorkoutDef.sortIndex),
                  SortDescriptor(\WorkoutDef.name)]) private var workouts: [WorkoutDef]

    var body: some View {
        Section {
            if named.isEmpty {
                Text("No workouts yet.").foregroundStyle(.secondary)
            } else {
                ForEach(named) { workout in
                    Button {
                        toggle(workout)
                    } label: {
                        HStack {
                            Text(workout.name).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: contains(workout)
                                  ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(contains(workout)
                                                 ? Color.blue : Color.secondary.opacity(0.4))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text("In these workouts")
        } footer: {
            Text("Tap to add this exercise to a workout or take it out. It is added at the end; use *reorder exercises* in the workout to move it.")
        }
    }

    private var named: [WorkoutDef] {
        workouts.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private func contains(_ workout: WorkoutDef) -> Bool {
        workout.exerciseOrder.contains(exercise.id)
    }

    private func toggle(_ workout: WorkoutDef) {
        if let index = workout.exerciseOrder.firstIndex(of: exercise.id) {
            workout.exerciseOrder.remove(at: index)
        } else {
            workout.exerciseOrder.append(exercise.id)
        }
        try? context.save()
    }
}
