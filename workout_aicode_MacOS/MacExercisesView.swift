import SwiftUI
import SwiftData


// MARK: - Exercises
//
// A list on the left, a form on the right. Numbers are typed rather than
// rolled: a Mac has no touchscreen, and a picker wheel driven by a trackpad is
// worse than a text field at everything a text field does.
//
// The body diagram is the filter, exactly as on the phone: it stands in the
// detail pane until an exercise is chosen, and pointing at a muscle shows the
// exercises that work it. Selecting an exercise replaces it with the form, the
// way tapping a row on the phone pushes the edit screen — and "all exercises"
// brings the body back.
//
// An earlier version had the diagram inside the form, setting the exercise's
// own muscle groups by clicking and Option-clicking. It went the other way
// round from the phone, and one app should not have two ideas about what a
// picture of a body is for. The groups are set from a list again.

struct MacExercisesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\ExerciseDef.name)]) private var exercises: [ExerciseDef]
    @Query private var workouts: [WorkoutDef]
    @Query private var drafts: [DraftSession]
    @State private var selection: UUID?
    @State private var sieve = MacExerciseSieve()

    private var draft: DraftSession? { drafts.first { $0.isActive } }

    private var selected: ExerciseDef? {
        guard let selection else { return nil }
        return exercises.first { $0.id == selection && !$0.isDeleted }
    }

    /// Your own, what you use first: starred, then whatever is in a workout,
    /// then the rest — the same order the phone's library uses.
    private var own: [ExerciseDef] {
        // Deleted ones filtered out before anything draws them: SwiftData tears
        // a deleted object's backing data away at once, and reading a name off
        // it in the next redraw is a crash — the one the log editor hit.
        sieve.own(exercises.filter { !$0.isDeleted }).sorted { a, b in
            let ra = rank(a), rb = rank(b)
            if ra != rb { return ra < rb }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    private func rank(_ exercise: ExerciseDef) -> Int {
        LibraryOrder.rank(isFavourite: exercise.isFavourite,
                          isInAnyWorkout: workouts.contains {
                              $0.exerciseOrder.contains(exercise.id)
                          },
                          choosingForWorkout: false)
    }

    private var takenKeys: Set<String> { ExerciseLibrary.takenKeys(in: exercises) }

    var body: some View {
        HSplitView {
            list
                .frame(minWidth: 220, idealWidth: 260, maxHeight: .infinity)
            Group {
                if let selected {
                    VStack(alignment: .leading, spacing: 0) {
                        Button {
                            selection = nil
                        } label: {
                            Label("All exercises", systemImage: "chevron.left")
                        }
                        .buttonStyle(.link)
                        .padding(.leading, 16)
                        .padding(.top, 10)
                        .help("Back to the muscle groups")

                        MacExerciseForm(exercise: selected)
                    }
                } else {
                    picker
                }
            }
            // Both halves take the whole height they are given. Without this
            // the split view sized itself to the shorter side, and an empty
            // detail pane left the list floating in the middle of the window
            // with its own scroll bar — the list changing height depending on
            // whether something was selected.
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Exercises")
        .toolbar {
            ToolbarItem {
                Button(action: create) { Label("New exercise", systemImage: "plus") }
                    .help("Add an exercise")
            }
        }
    }

    // MARK: The body, as the filter

    /// What stands in the detail pane until an exercise is chosen.
    private var picker: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)

            MuscleBodyPicker(selection: muscleBinding,
                             aerobic: aerobicBinding,
                             height: 420)
                .padding(.horizontal, 12)

            HStack(spacing: 10) {
                Button("All groups") { sieve.filter = .all }
                    .disabled(sieve.filter == .all)
                Text(showingLine)
                    .font(.callout).foregroundStyle(.secondary)
            }

            Text("Click a muscle, or the heart, to show what works it. Click an exercise in the list to open it.")
                .font(.footnote).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var showingLine: String {
        switch sieve.filter {
        case .all:              return "Showing every exercise"
        case .aerobic:          return "Showing aerobic exercises"
        case .muscle(let g):    return "Showing \(g.label)"
        }
    }

    /// The diagram speaks in muscle groups and a heart; the list speaks in one
    /// filter. These two bindings are the join, and they give the phone's rule
    /// for free: choosing a muscle lets go of aerobic and the other way round,
    /// because an exercise is one kind or the other and both at once could only
    /// ever show nothing.
    private var muscleBinding: Binding<MuscleGroup?> {
        Binding(get: { sieve.filter.muscle },
                set: { sieve.filter = $0.map(MacExerciseFilter.muscle) ?? .all })
    }

    private var aerobicBinding: Binding<Bool> {
        Binding(get: { sieve.filter.isAerobic },
                set: { sieve.filter = $0 ? .aerobic : .all })
    }

    private var list: some View {
        VStack(spacing: 0) {
            MacExerciseFilterBar(sieve: $sieve)
            Divider()
            rows
        }
    }

    @ViewBuilder private var rows: some View {
        // "Nothing yet" is about the database, not about the filter: the
        // ready-made list is never empty, so someone with no exercises of
        // their own still has something to click.
        if exercises.isEmpty && sieve.search.isEmpty && sieve.filter == .all {
            MacEmptyState(thing: "exercises", onCreate: create)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(selection: $selection) {
                if !own.isEmpty {
                    Section("Your exercises") {
                        ForEach(own) { exercise in
                            ownRow(exercise).tag(exercise.id)
                        }
                        .onDelete(perform: deleteFromOwn)
                    }
                }

                let strength = sieve.strengthTemplates(taken: takenKeys)
                let aerobic = sieve.aerobicTemplates(taken: takenKeys)

                if !strength.isEmpty {
                    Section("Ready-made") {
                        ForEach(strength) { entry in
                            MacTemplateRow(name: entry.name,
                                           detail: entry.muscleSummary) { take(entry) }
                        }
                    }
                }
                if !aerobic.isEmpty {
                    Section("Ready-made · aerobic") {
                        ForEach(aerobic) { entry in
                            MacTemplateRow(name: entry.name,
                                           detail: "Aerobic — an Apple workout") { take(entry) }
                        }
                    }
                }

                if own.isEmpty && strength.isEmpty && aerobic.isEmpty {
                    // Which filter emptied the list, not just that it is empty:
                    // otherwise it reads as the app having lost the exercises.
                    ContentUnavailableView("Nothing matches",
                                           systemImage: "line.3.horizontal.decrease.circle",
                                           description: Text(emptyExplanation))
                }
            }
        }
    }

    private var emptyExplanation: String {
        let where_ = sieve.filter == .all ? "" : " under \(sieve.filter.label.lowercased())"
        if !sieve.search.isEmpty {
            return "Nothing called “\(sieve.search)”\(where_), and nothing ready-made either."
        }
        return "Nothing\(where_) yet, and every ready-made one is already in your list."
    }

    private func ownRow(_ exercise: ExerciseDef) -> some View {
        HStack(spacing: 8) {
            Button {
                exercise.isFavourite.toggle()
            } label: {
                Image(systemName: exercise.isFavourite ? "star.fill" : "star")
                    .foregroundStyle(exercise.isFavourite ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
            .help(exercise.isFavourite ? "Remove from favourites" : "Mark as a favourite")

            VStack(alignment: .leading, spacing: 1) {
                Text(exercise.name.isEmpty ? "(unnamed)" : exercise.name)
                Text(subtitle(exercise))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            // Made during the draft in progress: marked so it is obvious what
            // is at stake when draft ends.
            if draft?.contains(exercise: exercise.id) == true {
                Image(systemName: "pencil.and.outline")
                    .foregroundStyle(.orange)
                    .help("Made while drafting")
            }
        }
    }

    // MARK: Taking a ready-made one

    private func take(_ entry: LibraryExercise) {
        insert(ExerciseLibrary.take(entry, existingNames: exercises.map(\.name)))
    }

    private func take(_ entry: AerobicLibraryExercise) {
        insert(ExerciseLibrary.take(entry, existingNames: exercises.map(\.name)))
    }

    /// Selects what was just taken, so the form on the right opens on it —
    /// taking a ready-made exercise is usually the first half of setting its
    /// weights for your own gym.
    private func insert(_ exercise: ExerciseDef) {
        context.insert(exercise)
        DraftMode.note(exercise: exercise.id, in: context)
        try? context.save()
        selection = exercise.id
    }

    private func subtitle(_ exercise: ExerciseDef) -> String {
        switch exercise.kind {
        case .aerobic:  return exercise.aerobicActivity?.label ?? "Aerobic"
        case .strength:
            guard let primary = exercise.primaryMuscle else { return "No muscle group yet" }
            let also = exercise.secondaryMuscles.filter { $0 != primary }
            guard !also.isEmpty else { return primary.shortLabel }
            return "\(primary.shortLabel) + \(also.map(\.shortLabel).joined(separator: ", "))"
        }
    }

    private func create() {
        // Through ExerciseDefaults, so a new exercise made here starts on the
        // same sets and weights as one made on the phone rather than on the
        // built-in 0…200 in 5s.
        let exercise = ExerciseDefaults.makeExercise(name: "New exercise")
        context.insert(exercise)
        DraftMode.note(exercise: exercise.id, in: context)
        try? context.save()
        selection = exercise.id
    }

    /// Offsets are into the list as shown, which is filtered and re-ordered —
    /// indexing the unfiltered query here would delete whatever happened to
    /// sit at that position in a different list.
    private func deleteFromOwn(_ offsets: IndexSet) {
        for index in offsets {
            let exercise = own[index]
            // Stop offering it back when draft ends, or the count would lie.
            DraftMode.forget(id: exercise.id, in: context)
            context.delete(exercise)
        }
        try? context.save()
    }
}

// MARK: - One exercise

struct MacExerciseForm: View {
    @Bindable var exercise: ExerciseDef

    /// Fifteen names, and how many more may be added.
    private var secondaryRoom: Int {
        MuscleGroup.maximumSecondary - exercise.secondaryMuscles.count
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $exercise.name)
                Picker("Kind", selection: Binding(
                    get: { exercise.kind }, set: { exercise.kind = $0 })) {
                    ForEach(ExerciseKind.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            if exercise.kind == .aerobic {
                Section("Activity") {
                    Picker("Activity", selection: Binding(
                        get: { exercise.aerobicActivity },
                        set: { exercise.aerobicActivity = $0 })) {
                        Text("Choose…").tag(AerobicActivity?.none)
                        ForEach(AerobicActivity.allCases) {
                            Text($0.label).tag(AerobicActivity?.some($0))
                        }
                    }
                }
            } else {
                Section("Numbers") {
                    // Typed, not rolled. Steppers alongside so the keyboard is
                    // not the only way in.
                    LabeledContent("Sets") {
                        Stepper(value: $exercise.numberOfSeries, in: 1...10) {
                            TextField("", value: $exercise.numberOfSeries, format: .number)
                                .frame(width: 60)
                        }
                    }
                    LabeledContent("Lowest weight") {
                        TextField("", value: $exercise.lowestWeight, format: .number)
                            .frame(width: 80)
                    }
                    LabeledContent("Highest weight") {
                        TextField("", value: $exercise.highestWeight, format: .number)
                            .frame(width: 80)
                    }
                    LabeledContent("Increment") {
                        TextField("", value: $exercise.weightIncrement, format: .number)
                            .frame(width: 80)
                    }
                }

                muscleSection
            }

            Section("Rest after a set") {
                Picker("Rest", selection: $exercise.restSeconds) {
                    ForEach(ExerciseDefaults.restChoices, id: \.self) {
                        Text(ExerciseDefaults.restLabel($0)).tag($0)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(.top, 4)
    }

    // MARK: Muscle groups
    //
    // A picker for the one it mainly works, and a checkable list for the rest —
    // the same shape as the phone's edit screen, so a person moving between the
    // two is not learning the field twice.

    private var muscleSection: some View {
        Section {
            Picker("Primary", selection: Binding(
                get: { exercise.primaryMuscle },
                set: { newValue in
                    exercise.primaryMuscle = newValue
                    // A muscle is one or the other. Left in both lists it would
                    // be counted twice by anything grouping work per muscle.
                    if let newValue {
                        setSecondary(exercise.secondaryMuscles.filter { $0 != newValue })
                    }
                })) {
                Text("not set").tag(MuscleGroup?.none)
                ForEach(MuscleGroup.displayOrder) { group in
                    Text(group.label).tag(MuscleGroup?.some(group))
                }
            }

            LabeledContent("Also worked") {
                Text(secondarySummary).foregroundStyle(.secondary)
            }

            ForEach(MuscleGroup.displayOrder) { group in
                secondaryRow(group)
            }
        } header: {
            Text("Muscle groups")
        } footer: {
            Text("Used to group your training by muscle group, and to compare exercises. Up to \(MuscleGroup.maximumSecondary) also-worked groups.\n\nThe body diagram on the exercises screen is a filter — it shows what works a muscle. This is where an exercise's own groups are set.")
        }
    }

    private var secondarySummary: String {
        let s = exercise.secondaryMuscles.filter { $0 != exercise.primaryMuscle }
        return s.isEmpty ? "none" : s.map(\.shortLabel).joined(separator: ", ")
    }

    private func secondaryRow(_ group: MuscleGroup) -> some View {
        let isPrimary = group == exercise.primaryMuscle
        let isOn = exercise.secondaryMuscles.contains(group)
        // Full, and this one is not already ticked: there is nothing a click
        // could do, and a row that silently ignores clicks is worse than one
        // that says it is unavailable.
        let blocked = isPrimary || (secondaryRoom <= 0 && !isOn)
        return Button {
            toggleSecondary(group)
        } label: {
            HStack {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isOn ? Color.accentColor : .secondary)
                Text(group.label)
                    .foregroundStyle(blocked ? .secondary : .primary)
                Spacer()
                if isPrimary {
                    Text("primary").font(.caption).foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(blocked)
    }

    private func toggleSecondary(_ group: MuscleGroup) {
        if exercise.secondaryMuscles.contains(group) {
            setSecondary(exercise.secondaryMuscles.filter { $0 != group })
        } else {
            setSecondary(exercise.secondaryMuscles + [group])
        }
    }

    private func setSecondary(_ groups: [MuscleGroup]) {
        exercise.secondaryMuscles = Array(groups.prefix(MuscleGroup.maximumSecondary))
    }
}
