import SwiftUI
import SwiftData

// MARK: - Workouts
//
// A workout is a name and an order of exercises. On a Mac the order is worth
// having properly: drag to reorder, and a second list to add from, rather than
// the phone's sheet-and-back dance.

struct MacWorkoutsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\WorkoutDef.sortIndex),
                  SortDescriptor(\WorkoutDef.name)]) private var workouts: [WorkoutDef]
    @Query(sort: [SortDescriptor(\ExerciseDef.name)]) private var exercises: [ExerciseDef]
    @Query private var drafts: [DraftSession]
    @State private var selection: UUID?

    private var draft: DraftSession? { drafts.first { $0.isActive } }
    private var selected: WorkoutDef? {
        workouts.first { $0.id == selection && !$0.isDeleted }
    }
    /// Deleted ones are gone from here before anything draws them — see
    /// MacExercisesView.own for what reading one costs.
    private var living: [WorkoutDef] { workouts.filter { !$0.isDeleted } }

    var body: some View {
        HSplitView {
            list.frame(minWidth: 200, idealWidth: 240, maxHeight: .infinity)
            Group {
                if let selected {
                    MacWorkoutDetail(workout: selected, allExercises: exercises)
                } else {
                    ContentUnavailableView("No workout selected", systemImage: "hand.point.left")
                }
            }
            // See MacExercisesView: without a stated height the split view
            // sized itself to whichever half was shorter, so the list shrank
            // whenever nothing was selected.
            .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The seeded store arrives after the first draw, so this watches for
        // it rather than running once.
        .onChange(of: living.count, initial: true) { _, _ in showOneForAScreenshot() }
        .navigationTitle("Workouts")
        .toolbar {
            ToolbarItem {
                Button(action: create) { Label("New workout", systemImage: "plus") }
                    .help("Add a workout")
            }
        }
    }

    /// A capture of "No workout selected" shows the app doing nothing, with
    /// two thirds of the window empty. Screenshot runs open the first one.
    private func showOneForAScreenshot() {
        #if DEBUG
        guard MacDemoData.isEnabled, selection == nil else { return }
        selection = living.first?.id
        #endif
    }

    @ViewBuilder private var list: some View {
        if living.isEmpty {
            MacEmptyState(thing: "workouts", onCreate: create)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(selection: $selection) {
                ForEach(living) { workout in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(workout.name.isEmpty ? "(unnamed)" : workout.name)
                            Text("\(workout.exerciseOrder.count) exercises")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if draft?.contains(workout: workout.id) == true {
                            Image(systemName: "pencil.and.outline")
                                .foregroundStyle(.orange)
                                .help("Made while drafting")
                        }
                    }
                    .tag(workout.id)
                }
                .onDelete(perform: delete)
            }
        }
    }

    private func create() {
        let workout = WorkoutDef(name: "New workout",
                                 sortIndex: (workouts.map(\.sortIndex).max() ?? 0) + 1)
        context.insert(workout)
        DraftMode.note(workout: workout.id, in: context)
        try? context.save()
        selection = workout.id
    }

    private func delete(_ offsets: IndexSet) {
        // Offsets index the list as shown.
        for index in offsets {
            let workout = living[index]
            DraftMode.forget(id: workout.id, in: context)
            context.delete(workout)
        }
        try? context.save()
    }
}

// MARK: - One workout

struct MacWorkoutDetail: View {
    @Environment(\.modelContext) private var context
    @Bindable var workout: WorkoutDef
    let allExercises: [ExerciseDef]

    @State private var sieve = MacExerciseSieve()
    /// Folded shut to begin with: the exercise list is what this pane is for,
    /// and the body is the way in when a name will not come to mind.
    @State private var showBody = false

    private var inWorkout: [ExerciseDef] {
        workout.exerciseOrder.compactMap { id in
            allExercises.first { $0.id == id && !$0.isDeleted }
        }
    }

    /// Every exercise there is, not only the ones missing from this workout.
    ///
    /// It used to hide what was already in, which was tidy and confusing in
    /// equal measure: the right-hand list was a different length and a
    /// different set of names for every workout, with nothing on screen saying
    /// why. Showing all of them and ticking the ones already in makes the list
    /// the same everywhere, and answers the question without a sentence.
    ///
    /// Order stays put while you click: starred first, then everything else
    /// alphabetically, with no regard for what is already in. Ranking by
    /// membership here would move a row out from under the pointer the moment
    /// it was clicked.
    private var offered: [ExerciseDef] {
        sieve.own(allExercises.filter { !$0.isDeleted }).sorted { a, b in
            let ra = LibraryOrder.rank(isFavourite: a.isFavourite, isInAnyWorkout: true,
                                       choosingForWorkout: true)
            let rb = LibraryOrder.rank(isFavourite: b.isFavourite, isInAnyWorkout: true,
                                       choosingForWorkout: true)
            if ra != rb { return ra < rb }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    private var takenKeys: Set<String> { ExerciseLibrary.takenKeys(in: allExercises) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Workout name", text: $workout.name)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .padding()

            HSplitView {
                chosen
                library
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var chosen: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("In this workout — drag to reorder")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 8)
            List {
                ForEach(inWorkout) { exercise in
                    Text(exercise.name.isEmpty ? "(unnamed)" : exercise.name)
                }
                .onMove { from, to in
                    workout.exerciseOrder.move(fromOffsets: from, toOffset: to)
                }
                .onDelete { offsets in
                    // Taking an exercise out of a workout never deletes the
                    // exercise itself — it is very likely in others.
                    for index in offsets.sorted(by: >) {
                        workout.exerciseOrder.remove(at: index)
                    }
                }
            }
        }
        .frame(minWidth: 200, maxHeight: .infinity)
    }

    private var muscleBinding: Binding<MuscleGroup?> {
        Binding(get: { sieve.filter.muscle },
                set: { sieve.filter = $0.map(MacExerciseFilter.muscle) ?? .all })
    }

    private var aerobicBinding: Binding<Bool> {
        Binding(get: { sieve.filter.isAerobic },
                set: { sieve.filter = $0 ? .aerobic : .all })
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Add an exercise — ticked ones are already in")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 8)

            // The same body as the exercises screen, and for the same reason:
            // building a workout is thinking in muscles — "something for
            // back now" — rather than in names you can already recall. It
            // folds away because this pane shares a window with the workout
            // itself, and some days you know exactly what you are adding.
            DisclosureGroup(isExpanded: $showBody) {
                MuscleBodyPicker(selection: muscleBinding,
                                 aerobic: aerobicBinding,
                                 height: 260)
                    .padding(.vertical, 4)
                if sieve.filter != .all {
                    Button("All groups") { sieve.filter = .all }
                        .buttonStyle(.link)
                }
            } label: {
                Text(bodyLabel).font(.caption)
            }
            .padding(.horizontal, 8)

            MacExerciseFilterBar(sieve: $sieve)

            List {
                if !offered.isEmpty {
                    Section("Your exercises") {
                        ForEach(offered) { exercise in
                            ownRow(exercise)
                        }
                    }
                }

                // The ready-made catalogue, offered here as well as on the
                // exercises screen. Building a workout is exactly when you
                // notice a lift you have not defined yet, and sending someone
                // to another screen and back to fetch it — losing which
                // workout they were building on the way — is the kind of
                // errand the Mac has room not to ask for.
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
            }
        }
        .frame(minWidth: 220, maxHeight: .infinity)
    }

    /// Says what the body is currently filtering to, so the heading is still
    /// useful when it is folded shut.
    private var bodyLabel: String {
        switch sieve.filter {
        case .all:           return "Find by muscle"
        case .aerobic:       return "Find by muscle — showing aerobic"
        case .muscle(let g): return "Find by muscle — showing \(g.label)"
        }
    }

    private func ownRow(_ exercise: ExerciseDef) -> some View {
        let already = workout.exerciseOrder.contains(exercise.id)
        return HStack {
            Text(exercise.name.isEmpty ? "(unnamed)" : exercise.name)
                .foregroundStyle(already ? .secondary : .primary)
            Spacer()
            if already {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .help("Already in this workout")
            } else {
                Button {
                    workout.exerciseOrder.append(exercise.id)
                } label: { Image(systemName: "plus.circle") }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
                .help("Add to this workout")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !already else { return }
            workout.exerciseOrder.append(exercise.id)
        }
    }

    // MARK: Taking a ready-made one straight into this workout

    private func take(_ entry: LibraryExercise) {
        insert(ExerciseLibrary.take(entry, existingNames: allExercises.map(\.name)))
    }

    private func take(_ entry: AerobicLibraryExercise) {
        insert(ExerciseLibrary.take(entry, existingNames: allExercises.map(\.name)))
    }

    private func insert(_ exercise: ExerciseDef) {
        context.insert(exercise)
        DraftMode.note(exercise: exercise.id, in: context)
        workout.exerciseOrder.append(exercise.id)
        try? context.save()
    }
}
