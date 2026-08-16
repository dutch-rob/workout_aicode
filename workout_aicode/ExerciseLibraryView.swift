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

/// Where an exercise sits in the library list.
///
/// What you use floats to the top: starred first, then anything that is in a
/// workout, then the rest, each alphabetical within its band. A long list is
/// mostly exercises tried once, and those should not sit between the ones done
/// every week.
///
/// The exception is choosing exercises FOR a workout. There, tapping a row is
/// what changes its membership, so ranking by membership would move every row
/// out from under the finger that just tapped it. The order stays still:
/// starred, then everything else.
enum LibraryOrder {
    static func rank(isFavourite: Bool,
                     isInAnyWorkout: Bool,
                     choosingForWorkout: Bool) -> Int {
        if isFavourite { return 0 }
        guard !choosingForWorkout else { return 1 }
        return isInAnyWorkout ? 1 : 2
    }
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
    /// Aerobic and a muscle group are mutually exclusive — see the two
    /// onChange handlers below. An exercise is one kind or the other, so both
    /// at once could only ever show nothing.
    @State private var aerobicOnly = false
    @State private var pendingExercise: ExerciseDef? = nil
    @State private var exerciseToDuplicate: ExerciseDef? = nil
    @State private var exercisePendingDelete: ExerciseDef? = nil
    @State private var showDeleteConfirm = false

    private var style: MusclePickerStyle {
        MusclePickerStyle(rawValue: pickerStyle) ?? .body
    }

    var body: some View {
        VStack(spacing: 0) {
            if style == .body {
                MuscleBodyPicker(selection: $filter, aerobic: $aerobicOnly)
            } else {
                MuscleButtonGrid(selection: $filter, aerobic: $aerobicOnly)
            }

            controls

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
                if !aerobicTemplates.isEmpty {
                    Section("Ready-made") {
                        ForEach(aerobicTemplates) { entry in
                            aerobicTemplateRow(entry)
                        }
                    }
                }
                if ownExercises.isEmpty && templates.isEmpty && aerobicTemplates.isEmpty {
                    ContentUnavailableView("Nothing here",
                                           systemImage: "line.3.horizontal.decrease.circle",
                                           description: Text(emptyExplanation))
                }
            }
            .listStyle(.insetGrouped)
        }
        .onChange(of: aerobicOnly) { _, on in
            if on { filter = nil }
        }
        .onChange(of: filter) { _, group in
            if group != nil { aerobicOnly = false }
        }
        .navigationTitle(context_.workout == nil ? "exercise library" : "select exercise")
        .navigationBarTitleDisplayMode(.inline)
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

    /// One row of controls under the picker, with "all muscle groups" kept
    /// near the middle so it stays where the eye last left it when the two
    /// sides change width.
    private var controls: some View {
        HStack(spacing: 8) {
            Button {
                let exercise = ExerciseDefaults.makeExercise(primary: filter)
                store.saveExercise(exercise)
                if let workout = context_.workout {
                    workout.exerciseOrder.append(exercise.id)
                }
                pendingExercise = exercise
            } label: {
                Text("new exercise").font(.subheadline).lineLimit(1)
            }
            .buttonStyle(.bordered)

            Spacer(minLength: 0)

            Button {
                filter = nil
                // "all groups" means everything, so it lets go of AE as well.
                // Leaving it on lit both this and AE at once while showing only
                // the aerobic exercises, which said two contradictory things.
                aerobicOnly = false
            } label: {
                // "all muscle groups" does not fit beside the other three
                // controls on a phone — it came out as "all muscle gro…".
                Text("all groups")
                    .font(.subheadline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(showingEverything
                                               ? Color.blue : Color.secondary.opacity(0.15)))
                    .foregroundStyle(showingEverything ? Color.white : Color.primary)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Button { favouritesOnly.toggle() } label: {
                Image(systemName: favouritesOnly ? "star.fill" : "star")
                    .foregroundStyle(favouritesOnly ? .yellow : .secondary)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(favouritesOnly ? "Showing favourites only" : "Show favourites only")

            Button {
                pickerStyle = (style == .body ? MusclePickerStyle.buttons : .body).rawValue
            } label: {
                Image(systemName: style.icon)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(style == .body ? "Show buttons instead of the body"
                                              : "Show the body diagram")
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
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

    private func aerobicTemplateRow(_ entry: AerobicLibraryExercise) -> some View {
        Button {
            let exercise = addAerobic(entry)
            if case .browsing = context_ { pendingExercise = exercise }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle").foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name).foregroundStyle(.primary)
                    Text("aerobic").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Takes a ready-made aerobic exercise into the user's own list. Keeps the
    /// library key, like the strength side, so the same activity logged by
    /// different people stays comparable however they rename their copy.
    private func addAerobic(_ entry: AerobicLibraryExercise) -> ExerciseDef {
        let exercise = ExerciseDefaults.makeExercise(name: entry.name,
                                                     libraryKey: entry.key)
        exercise.name = uniqueName(entry.name)
        exercise.kind = .aerobic
        exercise.aerobicActivity = entry.activity
        store.saveExercise(exercise)
        if let workout = context_.workout {
            workout.exerciseOrder.append(exercise.id)
        }
        return exercise
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

    /// The empty list has to say which filter emptied it, or it reads as the
    /// app having lost the exercises. "This muscle group" was wrong the moment
    /// AE existed — aerobic is not a muscle group.
    /// No filter of any sort in force.
    private var showingEverything: Bool { filter == nil && !aerobicOnly }

    private var emptyExplanation: String {
        switch (aerobicOnly, favouritesOnly) {
        case (true, true):   return "No aerobic favourites yet."
        case (true, false):  return "No aerobic exercises yet. Tap “new exercise” to add one."
        case (false, true):  return filter == nil ? "No favourites yet."
                                                  : "No favourites in this muscle group."
        case (false, false): return filter == nil ? "No exercises yet."
                                                  : "No exercises for this muscle group."
        }
    }

    private var ownExercises: [ExerciseDef] {
        exercises
            .filter { aerobicOnly ? $0.kind == .aerobic : $0.kind == .strength }
            .filter { filter == nil || $0.primaryMuscle == filter }
            .filter { !favouritesOnly || $0.isFavourite }
            .sorted { a, b in
                let ra = libraryRank(a), rb = libraryRank(b)
                if ra != rb { return ra < rb }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
    }

    private func libraryRank(_ exercise: ExerciseDef) -> Int {
        LibraryOrder.rank(isFavourite: exercise.isFavourite,
                          isInAnyWorkout: workouts.contains {
                              $0.exerciseOrder.contains(exercise.id)
                          },
                          choosingForWorkout: context_.workout != nil)
    }

    /// Library entries the user has not taken yet. Favourites are a property of
    /// the user's own exercises, so filtering by them hides this section
    /// entirely rather than showing entries that can never match.
    /// Ready-made aerobic exercises the user has not taken yet — the same
    /// courtesy the strength side has always had.
    private var aerobicTemplates: [AerobicLibraryExercise] {
        guard aerobicOnly, !favouritesOnly else { return [] }
        let taken = Set(exercises.compactMap(\.libraryKey))
        return ExerciseLibrary.aerobic.filter { !taken.contains($0.key) }
    }

    private var templates: [LibraryExercise] {
        // The strength catalogue has nothing to offer under the aerobic filter;
        // aerobicTemplates covers that case instead.
        guard !favouritesOnly, !aerobicOnly else { return [] }
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
    @Binding var aerobic: Bool

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                column(MuscleBodyPicker.frontOrder, caption: "front")
                column(MuscleBodyPicker.backOrder, caption: "back")
            }
            AerobicFilterButton(isOn: $aerobic, size: 38)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    /// One figure's groups across two columns, filled top-to-bottom then
    /// left-to-right so the order still reads like the body.
    ///
    /// Side delts is lifted out and put at the HEAD of the second column: it
    /// shows on both figures, so sitting beside the dividing line keeps it
    /// near its neighbours on either side. The front's seven then read three
    /// and four rather than four and three.
    private func column(_ groups: [MuscleGroup], caption: String) -> some View {
        let (first, second) = columns(groups)
        return VStack(spacing: 4) {
            Text(caption).font(.caption2).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 4) {
                subColumn(first)
                subColumn(second)
            }
        }
    }

    private func columns(_ groups: [MuscleGroup]) -> ([MuscleGroup], [MuscleGroup]) {
        guard groups.contains(.sideDelts) else {
            let half = (groups.count + 1) / 2
            return (Array(groups.prefix(half)), Array(groups.dropFirst(half)))
        }
        // An earlier attempt only moved side delts when it was NOT already
        // first — which is precisely where it always was, so it never moved.
        let rest = groups.filter { $0 != .sideDelts }
        let half = rest.count / 2
        return (Array(rest.prefix(half)), [.sideDelts] + Array(rest.dropFirst(half)))
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
            Text("Tap to add this exercise to a workout or take it out. It goes on the end; drag it by its handle in the workout to move it.")
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
