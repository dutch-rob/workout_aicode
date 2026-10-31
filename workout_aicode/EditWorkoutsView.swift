// The two workout-editing screens: the list of workouts, and one workout's
// own screen. They are together because the second is only ever reached from
// the first, and they share the drag-and-drop reordering between them.

import SwiftUI
import SwiftData

// MARK: - Edit Workouts Screen
struct EditWorkoutsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var showDeleteConfirm = false
    @State private var workoutPendingDelete: WorkoutDef?
    @State private var editMode: EditMode = .inactive
    @State private var pendingNewWorkout: WorkoutDef? = nil
    /// The workout waiting to be joined to one the user is about to pick.
    @State private var mergeSource: WorkoutDef? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    let workout = WorkoutDef(name: "")
                    store.saveWorkout(workout)
                    pendingNewWorkout = workout
                } label: {
                    Text("new workout").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                if store.workouts.count >= 2 {
                    Button {
                        editMode = (editMode == .active ? .inactive : .active)
                    } label: {
                        Text(editMode == .active ? "end reorder" : "reorder workouts")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }

            if store.workouts.isEmpty {
                ContentUnavailableView("No workouts to edit", systemImage: "list.bullet")
            } else {
                List {
                    Section {
                        ForEach(store.workouts) { workout in
                            HStack(spacing: 12) {
                                if editMode == .active {
                                    // Reorder mode: show title; system shows drag handles
                                    Text(workout.name)
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                } else {
                                    // Normal mode: make the whole row a NavigationLink to edit
                                    NavigationLink(destination: EditWorkoutView(workout: workout)) {
                                        HStack(spacing: 12) {
                                            // Place a red delete button on the left to mimic reorder screen placement
                                            DeleteCircleButton {
                                                workoutPendingDelete = workout
                                                showDeleteConfirm = true
                                            }

                                            Text(workout.name)
                                                .lineLimit(1)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                    }
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    workoutPendingDelete = workout
                                    showDeleteConfirm = true
                                } label: { Label("Delete", systemImage: "trash") }
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button {
                                    pendingNewWorkout = store.duplicateWorkout(workout)
                                } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                                    .tint(.blue)
                                if store.workouts.count >= 2 {
                                    Button { mergeSource = workout } label: {
                                        Label("Merge", systemImage: "arrow.triangle.merge")
                                    }
                                    .tint(.indigo)
                                }
                            }
                            // The same two on a long press, because a swipe
                            // that only deletes is the one people learn.
                            .contextMenu {
                                Button {
                                    pendingNewWorkout = store.duplicateWorkout(workout)
                                } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                                if store.workouts.count >= 2 {
                                    Button { mergeSource = workout } label: {
                                        Label("Merge with…", systemImage: "arrow.triangle.merge")
                                    }
                                }
                            }
                        }
                        .onMove { indices, newOffset in
                            var newOrder = store.workouts
                            newOrder.move(fromOffsets: indices, toOffset: newOffset)
                            store.reorderWorkouts(newOrder)
                        }
                        .onDelete { indexSet in
                            for idx in indexSet {
                                let workout = store.workouts[idx]
                                workoutPendingDelete = workout
                                showDeleteConfirm = true
                            }
                        }
                    }
                }
                .environment(\.editMode, $editMode)
            }
        }
        .padding()
        .navigationTitle("edit workouts")
        .navigationDestination(item: $pendingNewWorkout) { workout in
            EditWorkoutView(workout: workout)
        }
        .confirmationDialog("Delete Workout?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let workout = workoutPendingDelete {
                    store.deleteWorkout(workout)
                }
                workoutPendingDelete = nil
            }
            Button("Cancel", role: .cancel) { workoutPendingDelete = nil }
        } message: {
            Text("Are you sure you want to delete this workout?")
        }
        // Which workout to add on the end. Both originals are left alone, so
        // there is nothing here to undo — the result is a third workout, and
        // it opens for editing so the name can be changed straight away.
        .confirmationDialog("Add which workout's exercises?",
                            isPresented: Binding(get: { mergeSource != nil },
                                                 set: { if !$0 { mergeSource = nil } }),
                            titleVisibility: .visible) {
            if let first = mergeSource {
                ForEach(store.workouts.filter { $0.id != first.id }) { other in
                    Button(other.name.isEmpty ? "(unnamed)" : other.name) {
                        pendingNewWorkout = store.mergeWorkouts(first, other)
                        mergeSource = nil
                    }
                }
            }
            Button("Cancel", role: .cancel) { mergeSource = nil }
        } message: {
            Text("A new workout is made from \(mergeSource?.name ?? "this one") followed by the one you pick. Neither is changed.")
        }
    }
}

// MARK: - Edit Workout Screen
struct EditWorkoutView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Bindable var workout: WorkoutDef
    @State private var hasInserted = false
    @State private var pendingNewExercise: ExerciseDef? = nil
    /// Name and exercise order on arrival, so "quit" can put them back.
    @State private var original: (name: String, order: [UUID], isNew: Bool)? = nil
    @State private var showLibrary = false

    private var isWorkoutValid: Bool {
        !workout.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            Section(header: Text("Workout name")) {
                TextField("Workout name", text: $workout.name)
                if let clash = duplicateName {
                    Text("You already have a workout called “\(clash)”. Two workouts with one name are impossible to tell apart in your logs.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section {
                ForEach(exercisesInWorkout, id: \.slot) { entry in
                    HStack(spacing: 12) {
                        // Tapping an exercise opens it. It used to open a menu
                        // of every exercise grouped by muscle, which read as
                        // neither "edit this" nor "swap this" — to replace one
                        // now, remove it and add another.
                        // A raw tap gesture, not a NavigationLink: the list is
                        // in edit mode so the handles show, and edit mode
                        // disables controls — a gesture still fires.
                        Text(entry.exercise?.name ?? "(missing exercise)")
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if let exercise = entry.exercise {
                                    pendingNewExercise = exercise
                                }
                            }
                    }
                }
                .onMove { from, to in
                    workout.exerciseOrder.move(fromOffsets: from, toOffset: to)
                }
                .onDelete { offsets in
                    workout.exerciseOrder.remove(atOffsets: offsets)
                }
            } header: {
                HStack {
                    Text("Exercises")
                    Spacer()
                    // A tap gesture rather than a Button: edit mode is on for
                    // the handles, and it disables controls — including one in
                    // a section header — but a gesture still fires.
                    Label("add exercise", systemImage: "plus")
                        .font(.footnote)
                        .foregroundStyle(Color.accentColor)
                        .textCase(nil)
                        .contentShape(Rectangle())
                        .onTapGesture { showLibrary = true }
                }
            } footer: {
                Text("Tap an exercise to edit it, drag the handle on the right to reorder, and use the red button to take it out of this workout.")
            }
        }
        // Edit mode keeps every row's drag handle on screen, which is what
        // replaced the separate reorder screen.
        .environment(\.editMode, .constant(.active))
        .navigationTitle("edit workout")
        .navigationBarBackButtonHidden(true)
        .toolbar {
            // Same pair as the exercise screen, and for the same reason: a
            // workout row exists from the moment "new workout" is tapped, so
            // leaving without a name used to strand an invisible one in the
            // database.
            ToolbarItem(placement: .topBarLeading) {
                Button("quit", role: .cancel) { revertAndLeave() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("save") { dismiss() }
                    .disabled(!canSave)
                    .bold()
            }
        }
        .navigationDestination(item: $pendingNewExercise) { exercise in
            EditExerciseView(exercise: exercise)
        }
        .navigationDestination(isPresented: $showLibrary) {
            ExerciseLibraryView(context_: .selecting(workout))
        }
        .onAppear {
            guard original == nil else { return }
            original = (name: workout.name,
                        order: workout.exerciseOrder,
                        isNew: workout.name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private var canSave: Bool {
        !workout.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && duplicateName == nil
    }

    private func revertAndLeave() {
        if let o = original {
            if o.isNew {
                store.deleteWorkout(workout)
            } else {
                workout.name = o.name
                workout.exerciseOrder = o.order
                StoreSave.save(context)
            }
        }
        dismiss()
    }

    /// One row per slot in the workout. Keyed by position, not by exercise, so
    /// the same exercise appearing twice still moves independently.
    private var exercisesInWorkout: [(slot: Int, exercise: ExerciseDef?)] {
        workout.exerciseOrder.enumerated().map { index, id in
            (slot: index, exercise: allExercises.first { $0.id == id })
        }
    }

    /// Another workout with this name, if any.
    private var duplicateName: String? {
        let mine = workout.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !mine.isEmpty else { return nil }
        return allWorkouts.first {
            $0.id != workout.id && $0.name.lowercased() == mine.lowercased()
        }?.name
    }

    @Query(sort: [SortDescriptor(\ExerciseDef.name)]) private var allExercises: [ExerciseDef]
    @Query private var allWorkouts: [WorkoutDef]
}
