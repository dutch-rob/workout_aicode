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
    private var selected: WorkoutDef? { workouts.first { $0.id == selection } }

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
        .navigationTitle("Workouts")
        .toolbar {
            ToolbarItem {
                Button(action: create) { Label("New workout", systemImage: "plus") }
                    .help("Add a workout")
            }
        }
    }

    @ViewBuilder private var list: some View {
        if workouts.isEmpty {
            MacEmptyState(thing: "workouts", onCreate: create)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(selection: $selection) {
                ForEach(workouts) { workout in
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
        for index in offsets {
            let workout = workouts[index]
            DraftMode.forget(id: workout.id, in: context)
            context.delete(workout)
        }
        try? context.save()
    }
}

// MARK: - One workout

struct MacWorkoutDetail: View {
    @Bindable var workout: WorkoutDef
    let allExercises: [ExerciseDef]

    @State private var filter = ""

    private var inWorkout: [ExerciseDef] {
        workout.exerciseOrder.compactMap { id in allExercises.first { $0.id == id } }
    }

    /// Every exercise there is, not only the ones missing from this workout.
    ///
    /// It used to hide what was already in, which was tidy and confusing in
    /// equal measure: the right-hand list was a different length and a
    /// different set of names for every workout, with nothing on screen saying
    /// why. Showing all of them and ticking the ones already in makes the list
    /// the same everywhere, and answers the question without a sentence.
    private var offered: [ExerciseDef] {
        let needle = filter.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return allExercises }
        return allExercises.filter { $0.name.lowercased().contains(needle) }
    }

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

    private var library: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("All your exercises — ticked ones are already in")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 8)
            TextField("Filter", text: $filter)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 8)
            List(offered) { exercise in
                let already = workout.exerciseOrder.contains(exercise.id)
                HStack {
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
                        .help("Add to this workout")
                    }
                }
            }
        }
        .frame(minWidth: 200, maxHeight: .infinity)
    }
}
