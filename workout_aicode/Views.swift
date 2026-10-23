import SwiftUI
import SwiftData
import UniformTypeIdentifiers

extension Notification.Name {
    static let modelDataDidChange = Notification.Name("ModelDataDidChange")
}
// Transferable payload and UTType for drag/drop
struct WorkoutDragPayload: Transferable, Hashable, Codable {
    let id: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .workoutDragPayload)
    }
}

extension UTType {
    static let workoutDragPayload = UTType.data
}

// Reusable red delete circle button
struct DeleteCircleButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Color.red).frame(width: 28, height: 28)
                Image(systemName: "minus")
                    .foregroundStyle(.white)
                    .font(.system(size: 14, weight: .bold))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Delete")
    }
}

// Helper to get exercise name by id
extension Collection where Element == ExerciseDef {
    func name(for id: UUID) -> String { first(where: { $0.id == id })?.name ?? "Exercise" }
}

// MARK: - Edit Workouts Screen
struct EditWorkoutsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var showDeleteConfirm = false
    @State private var workoutPendingDelete: WorkoutDef?
    @State private var editMode: EditMode = .inactive
    @State private var pendingNewWorkout: WorkoutDef? = nil

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
                try? context.save()
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

// MARK: - Edit Exercise Screen
struct EditExerciseView: View {
    /// Asked once, the first time any exercise is set to subtract from body
    /// weight — see the alert below.
    static let unitCheckedKey = "bodyWeightUnitChecked"
    @State private var confirmUnit = false

    /// A weight field: typed in the user's unit, stored in grams.
    ///
    /// Nil means an exercise whose weights have not been given a unit yet —
    /// see `WeightHistory`. It reads as zero until the user answers, which is
    /// the one honest thing to show for a number whose meaning is unknown.
    private func weightField(_ keyPath: ReferenceWritableKeyPath<ExerciseDef, Int?>) -> Binding<Double> {
        Binding(
            get: {
                guard let grams = exercise[keyPath: keyPath] else { return 0 }
                return WeightUnit.current.display(grams: grams)
            },
            set: { typed in
                // A field with nothing in it shows 0, and SwiftUI commits what
                // it shows — which turned "no unit yet" into a stored zero,
                // and a stored zero into a wheel with one value on it. Writing
                // the placeholder back is therefore refused: only a number the
                // user actually put there counts.
                let grams = WeightUnit.current.grams(from: max(0, typed))
                guard grams > 0 || exercise[keyPath: keyPath] != nil else { return }
                exercise[keyPath: keyPath] = grams
                // Keep the unit-less fields describing the same wheel, for
                // every device that can only read those.
                exercise.syncLegacyRange()
            }
        )
    }

    @Bindable var exercise: ExerciseDef
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var store: AppStore
    @Query(sort: [SortDescriptor(\ExerciseDef.name)]) private var allExercises: [ExerciseDef]

    /// Everything as it was on arrival, so "quit" can put it back. SwiftData
    /// edits the live object as you type — there is no draft copy to throw
    /// away — so the old values are kept here instead.
    @State private var original: Snapshot? = nil

    private struct Snapshot {
        let name: String
        let sets: Int
        let lowest: Int
        let highest: Int
        let increment: Int
        let primary: MuscleGroup?
        let secondary: [MuscleGroup]
        let restSeconds: Int
        let kind: ExerciseKind
        let activity: AerobicActivity?
        /// True when the exercise was created just before this screen opened,
        /// in which case quitting should remove it rather than restore it.
        let isNew: Bool
    }

    private var trimmedName: String {
        exercise.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Another exercise already using this name.
    private var duplicateName: String? {
        guard !trimmedName.isEmpty else { return nil }
        return allExercises.first {
            $0.id != exercise.id && $0.name.lowercased() == trimmedName.lowercased()
        }?.name
    }

    /// A name, and then whatever that kind of exercise cannot do without.
    ///
    /// A strength exercise needs a primary muscle: without one it cannot be
    /// found by the muscle-group filter, is left out of any grouping by muscle,
    /// and would be a blank in shared data. An aerobic one needs an activity
    /// instead, because that is what the Apple workout is started as — a rest
    /// timer can fall back on a default, but "which workout is this" cannot.
    private var canSave: Bool {
        guard !trimmedName.isEmpty, duplicateName == nil else { return false }
        switch exercise.kind {
        case .strength: return exercise.primaryMuscle != nil
        case .aerobic:  return exercise.aerobicActivity != nil
        }
    }

    var body: some View {
        Form {
            TextField("Exercise name", text: $exercise.name)
            if let clash = duplicateName {
                Text("You already have an exercise called “\(clash)”. Give this one a different name — two exercises with the same name cannot be told apart in your logs or graphs.")
                    .font(.footnote)
                    .foregroundStyle(.red)
            } else if trimmedName.isEmpty {
                Text("An exercise needs a name before it can be saved.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if exercise.kind == .strength, exercise.primaryMuscle == nil {
                Text("Choose a primary muscle group below before saving.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if exercise.kind == .aerobic, exercise.aerobicActivity == nil {
                Text("Choose which activity this is before saving.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Picker("Kind", selection: Binding(
                get: { exercise.kind },
                set: { exercise.kind = $0 }
            )) {
                ForEach(ExerciseKind.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            if exercise.kind == .aerobic {
                Picker(selection: Binding(
                    get: { exercise.aerobicActivity },
                    set: { exercise.aerobicActivity = $0 }
                )) {
                    Text("Choose…").tag(AerobicActivity?.none)
                    ForEach(AerobicActivity.allCases) {
                        Text($0.label).tag(AerobicActivity?.some($0))
                    }
                } label: {
                    Text("Activity")
                }
            }

            if exercise.kind == .strength {
            LabeledContent {
                Stepper(value: $exercise.numberOfSeries, in: 1...10) {
                    Text("\(exercise.numberOfSeries)")
                }
                // The stored property is still numberOfSeries — renaming it
                // would break existing databases and exports for a word.
            } label: { Text("Number of sets") }

            // In the user's unit, with the unit written beside it — this is
            // the one screen where a weight is typed rather than rolled, and
            // the one place the question "kilograms or pounds?" actually
            // arises. The wheels, logs and graphs are left unlabelled: the
            // unit is the same down the whole screen and the space is not.
            LabeledContent {
                HStack(spacing: 4) {
                    TextField("", value: weightField(\.lowestWeightGrams), format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                    Text(WeightUnit.current.label).foregroundStyle(.secondary)
                }
            } label: { Text("Lowest weight") }

            LabeledContent {
                HStack(spacing: 4) {
                    TextField("", value: weightField(\.highestWeightGrams), format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                    Text(WeightUnit.current.label).foregroundStyle(.secondary)
                }
            } label: { Text("Highest weight") }

            LabeledContent {
                HStack(spacing: 4) {
                    TextField("", value: weightField(\.weightIncrementGrams), format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                    Text(WeightUnit.current.label).foregroundStyle(.secondary)
                }
            } label: { Text("Weight increment") }

            Toggle(isOn: $exercise.subtractsFromBodyWeight) {
                Text("Subtracted from body weight")
            }
            .onChange(of: exercise.subtractsFromBodyWeight) { _, on in
                // The first exercise to use body weight is the first time the
                // unit actually matters for arithmetic rather than for
                // reading: body weight in one unit against a machine in the
                // other is what logged a set at zero.
                if on, !UserDefaults.standard.bool(forKey: Self.unitCheckedKey) {
                    confirmUnit = true
                }
            }
            .alert("Weights in \(WeightUnit.current.label)?", isPresented: $confirmUnit) {
                Button("Yes, \(WeightUnit.current.label)") {
                    UserDefaults.standard.set(true, forKey: Self.unitCheckedKey)
                }
                Button("No, switch to \(WeightUnit.current == .kilograms ? "lb" : "kg")") {
                    let other: WeightUnit = WeightUnit.current == .kilograms ? .pounds : .kilograms
                    UserDefaults.standard.set(other.rawValue, forKey: WeightUnit.key)
                    UserDefaults.standard.set(true, forKey: Self.unitCheckedKey)
                }
            } message: {
                Text("This exercise works out what you lifted from your body weight, so the two have to be in the same units. Your weights are currently shown in \(WeightUnit.current.label).")
            }
            if exercise.subtractsFromBodyWeight {
                Text("For machines that take weight off you instead of adding it, such as an assisted chin-up or dip. The wheels show what you set on the machine; what is logged is what you lifted — your body weight less that setting — so the graphs and trends read the right way round. Your body weight comes from Settings.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            }

            // Shown whether or not the timer is switched on, so the value is
            // already right if it is turned on later — and so the setting is
            // discoverable from the place it applies to.
            Section {
                RestSecondsPicker(title: "Rest after a set", seconds: $exercise.restSeconds)
            } footer: {
                if RestTimerDefaults.isEnabled {
                    Text("How long the rest timer counts after each set of this exercise, and after logging it.")
                } else {
                    Text("Used when you switch the rest timer on in settings.")
                }
            }

            // NOTE: the "Movement type" picker used to live here. It only fed the
            // Watch's motion-based rep counter, which no longer exists, so the
            // control did nothing while promising a feature. `movementType` stays
            // on the model so existing data and JSON exports keep working.

            if exercise.kind == .strength {
                MuscleGroupSection(exercise: exercise)
            }

            WorkoutMembershipSection(exercise: exercise)
        }
        .onChange(of: exercise.lowestWeightGrams) { _, newValue in
            guard let newValue else { return }
            if (exercise.highestWeightGrams ?? 0) < newValue {
                exercise.highestWeightGrams = newValue
            }
            exercise.syncLegacyRange()
        }
        .onChange(of: exercise.highestWeightGrams) { _, newValue in
            guard let newValue, let lowest = exercise.lowestWeightGrams else { return }
            if newValue < lowest { exercise.lowestWeightGrams = newValue }
            exercise.syncLegacyRange()
        }
        .navigationTitle("edit exercise")
        .navigationBarBackButtonHidden(true)
        .toolbar {
            // Replaces the back chevron. Leaving by the chevron used to save
            // whatever was on screen, including a nameless exercise that then
            // sat in the list as "(unnamed)".
            ToolbarItem(placement: .topBarLeading) {
                Button("quit", role: .cancel) { revertAndLeave() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("save") { dismiss() }
                    .disabled(!canSave)
                    .bold()
            }
        }
        .onAppear {
            guard original == nil else { return }
            original = Snapshot(name: exercise.name,
                                sets: exercise.numberOfSeries,
                                lowest: exercise.lowestWeight,
                                highest: exercise.highestWeight,
                                increment: exercise.weightIncrement,
                                primary: exercise.primaryMuscle,
                                secondary: exercise.secondaryMuscles,
                                restSeconds: exercise.restSeconds,
                                kind: exercise.kind,
                                activity: exercise.aerobicActivity,
                                isNew: exercise.name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    /// Undo everything done on this screen, then leave.
    private func revertAndLeave() {
        if let o = original {
            if o.isNew {
                // Created for this screen and never named: it should not linger.
                store.deleteExercise(exercise)
            } else {
                exercise.name = o.name
                exercise.numberOfSeries = o.sets
                exercise.lowestWeight = o.lowest
                exercise.highestWeight = o.highest
                exercise.weightIncrement = o.increment
                exercise.primaryMuscle = o.primary
                exercise.secondaryMuscles = o.secondary
                exercise.restSeconds = o.restSeconds
                exercise.kind = o.kind
                exercise.aerobicActivity = o.activity
                try? context.save()
            }
        }
        dismiss()
    }
}

// MARK: - Log Exercise Screen
struct LogExerciseView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allExercises: [ExerciseDef]

    let workout: WorkoutDef
    /// Clears the navigation path in ContentView. Popping this way is
    /// deterministic — `dismiss()` and state-change propagation both proved
    /// unreliable here with a path-bound NavigationStack.
    var onEndSession: () -> Void = {}

    @ObservedObject private var handoff = PhoneSessionManager.shared
    @ObservedObject private var aerobic = AerobicCountdown.shared

    /// The camera / clock / wifi band on the trailing edge of the Duo's
    /// screens, and 0 everywhere else. The wheels run under it; the rows that
    /// sit alongside the icons stop short of it. See `FoldLayout`.
    @Environment(\.sensorBandWidth) private var sensorBand

    /// Deliberately NOT @ObservedObject.
    ///
    /// The rest timer publishes a tick twenty times a second so the grey can
    /// drain smoothly. Observed here, every one of those ticks rebuilt this
    /// whole screen — measured at 21 rebuilds a second — and the "list" menu
    /// is part of it. A menu whose presenting view is torn down and rebuilt at
    /// that rate stops accepting taps and scrolls: the list appeared and then
    /// ignored everything, while a swipe on the plain view underneath still
    /// worked. That was the reported bug, and it was present only while a rest
    /// was counting down.
    ///
    /// Nothing in this view's body reads a published value from the timer —
    /// every use is a method call. The two things that DO need the ticks, the
    /// draining grey and the counter beside the title, observe it themselves
    /// and are leaves, so a tick now redraws them and nothing else.
    private var restTimer: RestTimer { .shared }
    /// Every aerobic result, to pre-fill the wheel with what was done last
    /// time — the same courtesy the weight wheels have always paid.
    @Query private var aerobicResults: [AerobicResult]

    @State private var startedAt = Date()
    /// Set when this screen picked up an interrupted session rather than
    /// starting a new one. Shown once, because the difference between "your
    /// three logged exercises are still here" and "you are starting again"
    /// is not something to leave the user to work out from the wheels.
    @State private var carriedOn = false
    @State private var currentIndex: Int = 0
    @State private var weights: [[Int]] = []
    @State private var reps: [[Int]] = []

    @State private var loggedIndices: Set<Int> = []
    /// What the wheel is set to, per exercise: how long you mean to go.
    @State private var durations: [Int] = []
    /// What each aerobic session came to, per exercise. Held here rather than
    /// read off the countdown at log time: the countdown keeps only the last
    /// session, so anything logged out of order would take the wrong numbers.
    @State private var summaries: [AerobicSummary?] = []
    /// What was actually done, per exercise; 0 until a session has run.
    ///
    /// Kept apart from the wheel deliberately. Folding the two together meant
    /// stopping twenty seconds into an eighteen-minute row rewrote the wheel to
    /// "1" — the wheel counts whole minutes and cannot say twenty seconds — so
    /// the number you had chosen was destroyed by the act of measuring it.
    @State private var actualSeconds: [Int] = []
    @State private var showAllLoggedAlert = false
    /// How far the page is slid across, while the app is sliding it: the
    /// "log, next" animation and the tail of a swipe.
    @State private var slideOffset: CGFloat = 0
    /// How far the FINGER has dragged the page, right now.
    ///
    /// @GestureState, not @State, and that is the point of it: SwiftUI puts a
    /// gesture state back to its initial value when the gesture ends OR is
    /// cancelled, and a drag over these wheels does get cancelled — the
    /// pickers are UIKit and can claim the touch mid-drag. Held in @State, a
    /// cancelled drag left the page sitting wherever the finger had got to,
    /// with nothing to put it back: every control then sat somewhere other
    /// than where it was drawn.
    @GestureState private var dragTranslation: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    /// True while an exercise is sliding off and the next one in.
    @State private var isSliding = false

    /// The workout's exercises that still exist. A workout can retain a
    /// reference to a deleted exercise; including it produced a blank "phantom"
    /// exercise at the end that the log button could not get past.
    private var exerciseIds: [UUID] {
        let existing = Set(allExercises.map(\.id))
        return workout.exerciseOrder.filter { existing.contains($0) }
    }

    private var isLastUnlogged: Bool {
        let total = exerciseIds.count
        // If after adding currentIndex, loggedIndices count would equal total, means last unlogged
        return loggedIndices.count == total - 1 && !loggedIndices.contains(currentIndex)
    }

    var body: some View {
        GeometryReader { geo in
            pageContent(exercise: exerciseAt(currentIndex))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .contentShape(Rectangle())
                .offset(x: slideOffset + dragTranslation)
                .padding()
                .modifier(RestDrain(height: geo.size.height))
                // At the bottom, in the space under the wheels. At the top it
                // sat over "log" and "quit", where a tap meant for a button
                // would land on the badge instead.
                .overlay(alignment: .bottom) {
                    if carriedOn {
                        Text("Carried on from earlier")
                            .font(.footnote).bold()
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(Capsule().fill(Color.blue))
                            .foregroundStyle(.white)
                            .padding(.bottom, 8)
                            .transition(.opacity)
                            // Goes on the first thing the user does: a tap on
                            // it, a wheel, a swipe, a log, the list. Hooked to
                            // those actions rather than to the index changing,
                            // because restoring the session changes the index
                            // itself — and hid the badge before it was seen.
                            .onTapGesture { carriedOn = false }
                    }
                }
                .onAppear {
                    containerWidth = geo.size.width
                    pickerHeight = max(160, (geo.size.height - 220) / 2)
                    prepareBuffers()
                    ensureBufferShape()
                    startOrAdoptSession()
                }
                .onChange(of: geo.size.width) { _, newWidth in
                    containerWidth = newWidth
                }
                .onChange(of: geo.size.height) { _, newHeight in
                    pickerHeight = max(160, (newHeight - 220) / 2)
                }
                // Report state to the handover coordinator so the Watch can take
                // over from exactly here. Exercise/log boundaries also checkpoint.
                .onChange(of: currentIndex) { _, _ in
                    handoff.updateLiveSnapshot(currentSnapshot()); handoff.checkpoint()
                }
                .onChange(of: weights) { _, _ in handoff.updateLiveSnapshot(currentSnapshot()) }
                .onChange(of: reps) { _, _ in handoff.updateLiveSnapshot(currentSnapshot()) }
                .onChange(of: loggedIndices) { _, _ in
                    handoff.updateLiveSnapshot(currentSnapshot()); handoff.checkpoint()
                }
                .onDisappear { handoff.leaveSession(); restTimer.cancel(); aerobic.cancel() }
                // Reloaded state after reclaiming the session in place.
                .onChange(of: handoff.adoptSnapshot) { _, _ in
                    if let snap = handoff.takeAdoptSnapshot(for: workout.id.uuidString) {
                        adopt(snap)
                    }
                }
                // While paused, the root Paused screen covers us; ignore drags.
                .simultaneousGesture(handoff.role == .paused ? nil : dragGesture)
        }
        .ignoresSafeArea(.container, edges: sensorBand > 0 ? .trailing : [])
        .navigationTitle("log exercise")
        .navigationBarBackButtonHidden(true)
        .toolbar {
            // The title with a slot either side of equal width, so it stays
            // centred whether or not a rest is counting down beside it.
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    Color.clear.frame(width: 86, height: 1)
                    Text("log exercise").font(.headline).fixedSize()
                    // The slot holds its width with nothing in it. A frame on
                    // the counter alone collapsed when no rest was running,
                    // and the title slid off centre.
                    ZStack(alignment: .leading) {
                        Color.clear.frame(width: 86, height: 1)
                        RestCounter()
                    }
                }
            }
        }
        .sheet(isPresented: $showAllLoggedAlert) {
            allLoggedSheet
        }
        .fullScreenCover(isPresented: Binding(
            get: { aerobic.isShowing },
            set: { shown in if !shown, aerobic.isShowing { aerobic.stop() } }
        )) {
            AerobicCountdownView()
        }
        // What was actually done replaces what was planned. Recorded against
        // the exercise that was on screen, not whatever is current when the
        // value arrives — a notification tap can bring the app back elsewhere.
        .onChange(of: aerobic.finishedSeconds) { _, seconds in
            guard let seconds, seconds > 0, currentIndex < actualSeconds.count else { return }
            actualSeconds[currentIndex] = seconds
            summaries[currentIndex] = AerobicSummary(
                seconds: seconds,
                averageHeartRate: aerobic.averageHeartRate,
                maximumHeartRate: aerobic.maximumHeartRate,
                zoneSeconds: aerobic.zoneSeconds)
            aerobic.finishedSeconds = nil
        }
    }

    // MARK: - Rest timer

    /// Rest for the exercise on screen. An exercise from before the rest timer
    /// existed migrates in with the built-in default, so this is never zero.
    private var restSecondsForCurrent: Int {
        exerciseAt(currentIndex)?.restSeconds ?? RestTimerDefaults.newExerciseSeconds
    }

    /// A set ended. What counts as the end of a set is a touch on a wheel: the
    /// user rolls a wheel to what they just lifted, and that is the moment the
    /// rest begins. Deliberately a *touch* and not a value change, because the
    /// spec case that matters is repeating the previous set — the wheel is
    /// moved and put back on the same number, which no `onChange` would ever
    /// report. A plain tap on a wheel therefore also starts the rest, which is
    /// the easiest way to start it by hand.
    ///
    /// Only wheels, not the whole screen: a tap anywhere would fire on the log,
    /// quit and list buttons, which are not the end of anything.
    private func wheelTouchEnded(_ translation: CGSize) {
        carriedOn = false
        // A horizontal fling is the page swipe to another exercise, not a set.
        if abs(translation.width) > 40, abs(translation.width) > abs(translation.height) {
            return
        }
        restTimer.setFinished(exercise: exerciseAt(currentIndex)?.name ?? "",
                              seconds: restSecondsForCurrent)
    }

    private var wheelTouchGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onEnded { wheelTouchEnded($0.translation) }
    }

    // MARK: - Handover helpers

    private func currentSnapshot() -> SessionSnapshot {
        // Grams for a Watch on this build, and the unit-less numbers beside
        // them for one that has not updated: a hand-over in the middle of a
        // workout is exactly where the two builds meet.
        let legacyUnit = WeightHistory.statedUnit ?? .current
        let legacy = weights.enumerated().map { index, row in
            WeightHistory.legacyNumbers(for: row, of: exerciseAt(index), in: legacyUnit)
        }
        return SessionSnapshot(workoutId: workout.id.uuidString,
                               currentIndex: currentIndex,
                               weights: legacy,
                               reps: reps,
                               loggedIndices: Array(loggedIndices),
                               startedAt: startedAt.timeIntervalSince1970,
                               weightsGrams: weights)
    }

    /// A snapshot's wheels in grams: as sent when the other device knew grams,
    /// and otherwise its unit-less numbers read through each exercise's wheel.
    private func snapshotGrams(_ snap: SessionSnapshot) -> [[Int]] {
        guard snap.weightsGrams.isEmpty else { return snap.weightsGrams }
        let legacyUnit = WeightHistory.statedUnit ?? .current
        return snap.weights.enumerated().map { index, row in
            let exercise = exerciseAt(index)
            return row.map {
                WeightHistory.grams(fromLegacy: $0, of: exercise, in: legacyUnit)
            }
        }
    }

    private func adopt(_ snap: SessionSnapshot) {
        weights       = snapshotGrams(snap)
        reps          = snap.reps
        loggedIndices = Set(snap.loggedIndices)
        startedAt     = Date(timeIntervalSince1970: snap.startedAt)
        ensureBufferShape()
        // Clamp: a stale snapshot may point past the current exercise list.
        currentIndex  = min(max(0, snap.currentIndex),
                            max(0, exerciseIds.count - 1))
        // A rest in progress on the other device — or here, before iOS
        // reclaimed the app — carries on from where it is, not from the top.
        // No exercise name: the rest belongs to the one just finished, which
        // the snapshot does not say, and a notification naming the wrong one
        // is worse than one naming none.
        if let rest = snap.pendingRest() {
            restTimer.resume(endsAt: rest.endsAt, total: rest.total, exercise: "")
        }
    }

    private func startOrAdoptSession() {
        if let snap = handoff.takeAdoptSnapshot(for: workout.id.uuidString) {
            // Opened via handover (the app came forward into an active session).
            adopt(snap)
            handoff.updateLiveSnapshot(currentSnapshot())
        } else {
            // Opened by tapping the workout. Before becoming the driver, pick
            // up an interrupted session for this same workout: the app being
            // killed while the phone sat in a pocket is the ordinary case, and
            // starting again from zero throws away sets that were logged and
            // weights that were dialled in.
            //
            // startedAt comes back with it, so Apple Health still gets the
            // whole workout rather than the part after the interruption.
            if let resumed = handoff.resumableSession(for: workout.id.uuidString) {
                adopt(resumed)
                carriedOn = true
            } else {
                startedAt = Date()
            }
            handoff.enterSession(workoutId: workout.id.uuidString,
                                 current: currentSnapshot()) { snap in adopt(snap) }
        }
    }

    private func pageContent(exercise: ExerciseDef?) -> some View {
        VStack(spacing: 4) {
            // These two sit alongside the clock and the camera, so they stop
            // at the safe area. Everything below them is past the icons and
            // runs the full width of the screen.
            //
            // Measured off the cover screen: the clock starts 83pt down and
            // the wifi/battery ring ends at about 150, and these two rows
            // cover that. Anything new added ABOVE the wheels needs the same
            // padding, or it will run under the icons.
            buttonRow.padding(.trailing, sensorBand)
            Text(exercise?.name ?? "").font(.title2).bold()
                .padding(.trailing, sensorBand)
            if let exercise, let problem = setProblem(for: exercise) {
                Text(problem)
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
                    .padding(.trailing, sensorBand)
            }
            if let exercise {
                if exercise.kind == .aerobic {
                    aerobicContent(for: exercise)
                } else {
                    Text(exercise.subtractsFromBodyWeight ? "set on the machine" : "weight used")
                        .font(.system(size: 18)).frame(maxWidth: .infinity, alignment: .leading)
                    weightPickers(for: exercise)
                    Text("repetitions").font(.system(size: 18)).frame(maxWidth: .infinity, alignment: .leading)
                    repsPickers(for: exercise)
                }
            }
        }
    }

    private var allLoggedSheet: some View {
        VStack(spacing: 20) {
            Text("All exercises logged")
                .font(.title2)
                .bold()
            Button {
                showAllLoggedAlert = false
                let endedAt = Date()
                onEndSession()
                handoff.leaveSession()
                handoff.finishWorkoutHere(startedAt: startedAt, endedAt: endedAt,
                                          workoutId: workout.id)
            } label: {
                VStack(spacing: 2) {
                    Text("Done")
                    Text("end of workout").font(.footnote)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundColor(.white)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)

            Button("View logged exercise only", role: .cancel) {
                showAllLoggedAlert = false
            }

            Button("Overwrite logged exercise") {
                loggedIndices.remove(currentIndex)
                showAllLoggedAlert = false
            }
        }
        .padding()
    }

    private var buttonRow: some View {
        HStack {
            Button {
                logAndNext()
            } label: {
                Text(isLastUnlogged ? "log, end" : "log, next")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canLog(exerciseAt(currentIndex)) || isSliding)

            // Quitting early still ends the workout, so it is recorded too
            // (finishWorkoutHere skips it when no set was logged).
            Button("quit") {
                let endedAt = Date()
                onEndSession()
                handoff.leaveSession()
                handoff.finishWorkoutHere(startedAt: startedAt, endedAt: endedAt,
                                          workoutId: workout.id)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Menu("list") {
                ForEach(exerciseIds.indices, id: \.self) { idx in
                    let exercise = exerciseAt(idx)
                    Button {
                        carriedOn = false
                        currentIndex = idx
                    } label: {
                        // A tick on the ones already logged, rather than greying
                        // them: a greyed row in a menu reads as unavailable, and
                        // a logged exercise is somewhere you may well want to go
                        // back to — to add a set, or to look at what you did.
                        if loggedIndices.contains(idx) {
                            Label(exercise?.name ?? "", systemImage: "checkmark")
                        } else {
                            Text(exercise?.name ?? "")
                        }
                    }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    @State private var pickerHeight: CGFloat = 180

    private func weightPickers(for exercise: ExerciseDef) -> some View {
        // In GRAMS: what the wheel offers is exactly what gets stored, so a
        // set logged at 130½ lb is the same number next week rather than one
        // converted down and back again. The unit is only how it is written.
        let weightOptions = WeightWheel.values(for: exercise)
        let count = max(1, exercise.numberOfSeries)
        let unit = WeightUnit.current
        return HStack(spacing: wheelSpacing) {
            ForEach(0..<count, id: \.self) { series in
                Picker("", selection: weightBinding(series: series,
                                                    defaultValue: weightOptions.first ?? 0)) {
                    ForEach(weightOptions, id: \.self) { grams in
                        Text(WeightText.string(grams: grams, in: unit)).tag(grams)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
                .wheelOutline()
            }
        }
        .frame(height: pickerHeight)
        .simultaneousGesture(wheelTouchGesture)
    }

    private func repsPickers(for exercise: ExerciseDef) -> some View {
        let count = max(1, exercise.numberOfSeries)
        return HStack(spacing: wheelSpacing) {
            ForEach(0..<count, id: \.self) { series in
                Picker("", selection: repsBinding(series: series)) {
                    ForEach(0...200, id: \.self) { reps in Text("\(reps)").tag(reps) }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
                .wheelOutline()
            }
        }
        .frame(height: pickerHeight)
        .simultaneousGesture(wheelTouchGesture)
    }

    private var wheelSpacing: CGFloat { 8 }

    // MARK: - Aerobic

    /// One wheel, a start button, and what the last session came to.
    ///
    /// No swipe-to-page gesture worries here: the wheel is a single column and
    /// the paging gesture lives on the whole page as it always did.
    @ViewBuilder
    private func aerobicContent(for exercise: ExerciseDef) -> some View {
        Text(exercise.aerobicActivity?.label ?? "aerobic")
            .font(.system(size: 18))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)

        // What the session came to, once one has been run: the thing you are
        // about to log, shown before you log it.
        if let summary = summaryFor(currentIndex) {
            AerobicSummaryView(summary: summary)
        }

        Text("minutes").font(.system(size: 18)).frame(maxWidth: .infinity, alignment: .leading)
        Picker("", selection: minutesBinding()) {
            ForEach(AerobicDefaults.minuteChoices, id: \.self) { Text("\($0)").tag($0) }
        }
        .pickerStyle(.wheel)
        .frame(maxWidth: .infinity)
        .frame(height: pickerHeight)
        .wheelOutline()

        Button {
            aerobic.start(exercise: exercise.name,
                          seconds: durationSeconds(at: currentIndex),
                          activityRaw: exercise.aerobicActivityRaw)
        } label: {
            Text("start")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .padding(.top, 8)

        if let done = lastRecorded(for: exercise), summaryFor(currentIndex) == nil {
            Text("last time: \(AerobicDefaults.label(done))")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        Spacer(minLength: 0)
    }

    /// The finished session for this exercise, if one has been run.
    private func summaryFor(_ index: Int) -> AerobicSummary? {
        guard index < summaries.count else { return nil }
        return summaries[index]
    }

    /// Whether the log button has anything to record for an aerobic exercise.
    ///
    /// Nothing to log until a session has actually run: logging the wheel's
    /// number on its own would record a plan as though it were a measurement.
    private func canLog(_ exercise: ExerciseDef?) -> Bool {
        guard let exercise else { return true }
        // An exercise whose wheel has no range in grams has not been given a
        // unit yet. Logging it would write zeros — which is exactly what
        // happened once, and a zero in a log is indistinguishable from a set
        // actually lifted at zero.
        if exercise.kind == .strength, exercise.weightRangeGrams == nil { return false }
        // An assisted machine's set cannot be logged until the app knows what
        // to subtract it from. It used to log it anyway: body weight unknown
        // (or in the other unit) made the subtraction negative, which was
        // clamped to a logged weight of zero — a wrong number, silently, in
        // the one record that cannot be reconstructed later.
        if setProblem(for: exercise) != nil { return false }
        guard exercise.kind == .aerobic else { return true }
        return summaryFor(currentIndex) != nil
    }

    /// What the wheels are SHOWING for this exercise, one value per set.
    ///
    /// The buffer starts empty for an exercise with no previous session, and
    /// a wheel only writes into it when it is actually moved — the numbers on
    /// screen until then come from a default in the binding's getter. Logging
    /// the raw buffer therefore recorded a row with nothing in it at all,
    /// which is where an empty log comes from (one is in the user's own
    /// history, from a tap on "log" before touching anything). What is on
    /// screen is what gets written.
    private func displayed(_ buffer: [[Int]], for exercise: ExerciseDef,
                           default fallback: Int) -> [Int] {
        let count = max(1, exercise.numberOfSeries)
        let row = currentIndex < buffer.count ? buffer[currentIndex] : []
        return (0..<count).map { series in
            series < row.count ? row[series] : fallback
        }
    }

    /// Why a set cannot be logged yet, or nil when it can.
    private func setProblem(for exercise: ExerciseDef) -> String? {
        if let problem = bodyWeightProblem(for: exercise) { return problem }
        guard exercise.kind == .strength else { return nil }
        // Nought repetitions is not a set. Without this, "log" on a screen
        // nobody has touched writes a row of nothing — which then becomes
        // what the wheels open on next time, for this exercise and for the
        // next device that syncs it.
        let reps = displayed(self.reps, for: exercise, default: 0)
        if !reps.contains(where: { $0 > 0 }) {
            return "Set the repetitions before logging — a set with none is not a set."
        }
        return nil
    }

    /// Why an assisted set cannot be worked out yet, or nil when it can.
    private func bodyWeightProblem(for exercise: ExerciseDef) -> String? {
        if exercise.kind == .strength, exercise.weightRangeGrams == nil {
            return "This exercise's weights have no unit yet. Open the app's start screen and answer the kilograms-or-pounds question, or set the weights again on its edit screen."
        }
        guard exercise.subtractsFromBodyWeight else { return nil }
        guard BodyWeight.isKnown else {
            return "Set your body weight in Settings to log this exercise — what you lifted is your body weight less what the machine is carrying."
        }
        let onTheWheels = currentIndex < weights.count ? weights[currentIndex] : []
        let heaviest = onTheWheels.max() ?? 0
        guard BodyWeight.canCompute(machineSettingGrams: heaviest) else {
            let unit = WeightUnit.current
            return "The machine is set to \(WeightText.string(grams: heaviest, in: unit)) \(unit.label), which is more than your body weight of \(WeightText.string(BodyWeight.current)) \(unit.label). Settings holds your body weight."
        }
        return nil
    }

    /// What this exercise came to the last time it was logged, if anything.
    private func lastRecorded(for exercise: ExerciseDef) -> Int? {
        let logs = store.lastEntries(for: workout)
        guard let log = logs[exercise.id] else { return nil }
        return aerobicResults.first { $0.logId == log.id }?.durationSeconds
    }

    private func durationSeconds(at index: Int) -> Int {
        guard index < durations.count, durations[index] > 0 else {
            return AerobicDefaults.defaultMinutes * 60
        }
        return durations[index]
    }

    private func minutesBinding() -> Binding<Int> {
        Binding<Int>(
            get: { max(1, durationSeconds(at: currentIndex) / 60) },
            set: { newValue in
                guard currentIndex < durations.count else { return }
                durations[currentIndex] = newValue * 60
                if let id = exerciseAt(currentIndex)?.id {
                    AerobicDefaults.rememberMinutes(newValue, for: id)
                }
            }
        )
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .local)
            // Horizontal only: a vertical drag belongs to the wheel under the
            // finger, and must not drag the page sideways.
            .updating($dragTranslation) { value, state, _ in
                let horizontal = abs(value.translation.width) > abs(value.translation.height)
                state = horizontal ? value.translation.width : 0
            }
            .onEnded { value in
                let horizontal = value.translation.width
                guard abs(horizontal) > abs(value.translation.height) else { return }

                let threshold: CGFloat = 80
                if horizontal <= -threshold {
                    slideToNext(from: horizontal)
                } else if horizontal >= threshold {
                    slideToPrevious(from: horizontal)
                }
                // Under the threshold there is nothing to do: the finger's
                // offset is gesture state and goes back on its own.
            }
    }

    private func exerciseAt(_ index: Int) -> ExerciseDef? {
        let ids = exerciseIds
        guard index >= 0 && index < ids.count else { return nil }
        let id = ids[index]
        return allExercises.first(where: { $0.id == id })
    }

    private func prepareBuffers() {
        let last = store.lastEntries(for: workout)
        weights = exerciseIds.map { exId -> [Int] in
            guard let log = last[exId] else { return [] }
            let exercise = allExercises.first(where: { $0.id == exId })
            // Put last time's numbers on this wheel's steps, so the wheel
            // opens where it is expected to rather than at its lowest value.
            func snapped(_ grams: [Int]) -> [Int] {
                guard let exercise else { return grams }
                return grams.map { WeightWheel.snap($0, for: exercise) }
            }
            // An assisted machine's wheel shows what you SET on it, so it has
            // to open on last time's setting — the log holds what was lifted,
            // which is a different number and would creep every session as
            // body weight moved.
            if exercise?.subtractsFromBodyWeight == true,
               let assisted = store.assistedResult(forLogId: log.id),
               let settings = assisted.machineSettingsGrams, !settings.isEmpty {
                return snapped(settings)
            }
            return snapped(store.weightsGrams(forLogId: log.id))
        }
        reps = exerciseIds.map { exId in last[exId]?.reps ?? [] }
        // Pre-filled from the last session of each aerobic exercise, so the
        // wheel opens where it was left, exactly like the weight wheels.
        durations = exerciseIds.map { AerobicDefaults.lastMinutes(for: $0) * 60 }
    }

    /// Guarantee one weights/reps row per exercise. An adopted snapshot can be
    /// stale (e.g. taken before the workout gained exercises), and indexing a
    /// short buffer by `currentIndex` would trap.
    private func ensureBufferShape() {
        let n = exerciseIds.count
        if weights.count < n { weights += Array(repeating: [], count: n - weights.count) }
        if weights.count > n { weights = Array(weights.prefix(n)) }
        if reps.count < n { reps += Array(repeating: [], count: n - reps.count) }
        if reps.count > n { reps = Array(reps.prefix(n)) }
        let fallback = AerobicDefaults.defaultMinutes * 60
        if durations.count < n { durations += Array(repeating: fallback, count: n - durations.count) }
        if durations.count > n { durations = Array(durations.prefix(n)) }
        if actualSeconds.count < n { actualSeconds += Array(repeating: 0, count: n - actualSeconds.count) }
        if actualSeconds.count > n { actualSeconds = Array(actualSeconds.prefix(n)) }
        if summaries.count < n { summaries += Array(repeating: nil, count: n - summaries.count) }
        if summaries.count > n { summaries = Array(summaries.prefix(n)) }
    }

    private func setWeight(_ value: Int, series: Int) {
        ensureSeriesCapacity(&weights[currentIndex], upTo: series,
                             fill: exerciseAt(currentIndex)?.lowestWeightGrams ?? 0)
        guard weights[currentIndex][series] != value else { return }
        weights[currentIndex][series] = value
        // Belt and braces: a wheel left on a new number is the end of a set
        // even if the touch gesture above was swallowed by the picker.
        restTimer.setFinished(exercise: exerciseAt(currentIndex)?.name ?? "",
                              seconds: restSecondsForCurrent)
    }

    private func setRep(_ value: Int, series: Int) {
        ensureSeriesCapacity(&reps[currentIndex], upTo: series, fill: 0)
        guard reps[currentIndex][series] != value else { return }
        reps[currentIndex][series] = value
        restTimer.setFinished(exercise: exerciseAt(currentIndex)?.name ?? "",
                              seconds: restSecondsForCurrent)
    }

    private func ensureSeriesCapacity(_ arr: inout [Int], upTo index: Int, fill: Int) {
        while arr.count <= index { arr.append(fill) }
    }

    private func safeValue(_ matrix: [[Int]], _ exIndex: Int, _ series: Int, default def: Int) -> Int {
        guard exIndex < matrix.count, series < matrix[exIndex].count else { return def }
        return matrix[exIndex][series]
    }

    private func weightBinding(series: Int, defaultValue: Int) -> Binding<Int> {
        Binding<Int>(get: {
            safeValue(weights, currentIndex, series, default: defaultValue)
        }, set: { newValue in
            setWeight(newValue, series: series)
        })
    }

    private func repsBinding(series: Int) -> Binding<Int> {
        Binding<Int>(get: {
            safeValue(reps, currentIndex, series, default: 0)
        }, set: { newValue in
            setRep(newValue, series: series)
        })
    }

    private func logAndNext() {
        carriedOn = false
        guard let ex = exerciseAt(currentIndex) else {
            // The exercise was deleted but the workout still references it, so
            // there is nothing to log. Never dead-end the button: treat it as
            // handled and either move on or end the workout.
            loggedIndices.insert(currentIndex)
            if loggedIndices.count >= exerciseIds.count {
                let endedAt = Date()
                onEndSession()
                handoff.leaveSession()
                handoff.finishWorkoutHere(startedAt: startedAt, endedAt: endedAt,
                                          workoutId: workout.id)
            } else {
                goToNextUnlogged()
            }
            return
        }
        // If this is the last unlogged exercise, log and dismiss immediately
        if loggedIndices.count + 1 >= exerciseIds.count {
            loggedIndices.insert(currentIndex)
            writeLog(for: ex)
            handoff.noteActivity()
            // Pop first, then end the session and record to Health.
            let endedAt = Date()
            onEndSession()
            handoff.leaveSession()
            handoff.finishWorkoutHere(startedAt: startedAt, endedAt: endedAt,
                                          workoutId: workout.id)
            return
        }
        loggedIndices.insert(currentIndex)
        writeLog(for: ex)
        handoff.noteActivity()

        guard loggedIndices.count < exerciseIds.count else {
            // All logged, present an alert
            showAllLoggedAlert = true
            return
        }

        // Rest between exercises, for as long as the exercise just finished
        // asks for — read before moving on, because goToNextUnlogged changes
        // what `currentIndex` points at.
        //
        // Never after cardio: you have just done twenty minutes of it, and a
        // ninety-second rest prompt on top would be noise.
        let restAfter = ex.restSeconds
        let restName = ex.name
        let wasAerobic = ex.kind == .aerobic
        // The same slide as a swipe, so the change of exercise is seen rather
        // than having to be noticed: the wheels of two exercises look alike,
        // and a title changing in place was easy to miss.
        slideToNext()
        if !wasAerobic {
            restTimer.setFinished(exercise: restName, seconds: restAfter)
        }
    }

    /// Slides the current exercise off to the left and the next unlogged one
    /// in from the right. Used by a left swipe and by "log, next".
    ///
    /// The log button is disabled for the length of the slide: a second tap
    /// inside it would land before `currentIndex` moves, and log the exercise
    /// just logged a second time.
    private func slideToNext(from start: CGFloat = 0) {
        slide(from: start, out: -1) { goToNextUnlogged() }
    }

    private func slideToPrevious(from start: CGFloat = 0) {
        slide(from: start, out: 1) { goToPrevUnlogged() }
    }

    /// One page out, swap, one page in.
    ///
    /// `start` is where the finger left the page. The slide begins from there
    /// so it continues the swipe rather than jumping back to centre first —
    /// the finger's own offset disappears the moment the gesture ends.
    private func slide(from start: CGFloat, out direction: CGFloat,
                       swap: @escaping () -> Void) {
        carriedOn = false
        guard !isSliding else { return }
        isSliding = true
        slideOffset = start
        withAnimation(.easeInOut(duration: 0.22)) { slideOffset = direction * containerWidth }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            swap()
            slideOffset = -direction * containerWidth
            withAnimation(.easeInOut(duration: 0.22)) { slideOffset = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { isSliding = false }
        }
    }

    /// Store what an aerobic session measured beside the log that records it.
    /// Nothing is written for a strength exercise, and nothing for an aerobic
    /// one that was never actually run.
    /// Writes the set to the store, converting an assisted machine's setting
    /// into the weight actually lifted.
    ///
    /// The wheels hold what is ON THE MACHINE. For an assisted chin-up that is
    /// how much of your own weight it is carrying, so what you lifted is your
    /// body weight minus it — and that is what the log holds, because the
    /// graphs, the trends and the one-rep-max estimates are all about the
    /// weight lifted. What it was worked out from is kept beside it in an
    /// `AssistedResult`, so the set still means something in a year when the
    /// body weight has moved.
    @discardableResult
    private func writeLog(for exercise: ExerciseDef) -> WorkoutLog {
        // All in grams. The log's own `weights` is deliberately left empty:
        // it is the original unit-less field, and a device still on the old
        // build reading grams there would see a weight 2.2 times too big.
        //
        // And what is written is what the wheels SHOW: the buffer is empty
        // until a wheel is moved, which is how a row of nothing got logged.
        let onTheWheels = displayed(weights, for: exercise,
                                    default: exercise.weightRangeGrams?.lowest ?? 0)
        let assisted = exercise.subtractsFromBodyWeight
        let bodyWeightGrams = BodyWeight.currentGrams
        let lifted = assisted
            ? onTheWheels.map { max(0, bodyWeightGrams - $0) }
            : onTheWheels
        // The unit-less numbers go in beside the grams, for every device that
        // cannot read grams yet — see WeightHistory.legacyNumbers.
        let legacyUnit = WeightHistory.statedUnit ?? .current
        let log = WorkoutLog(workoutId: workout.id,
                             exerciseId: exercise.id,
                             weights: WeightHistory.legacyNumbers(
                                for: lifted, of: exercise, in: legacyUnit),
                             reps: displayed(reps, for: exercise, default: 0))
        context.insert(log)
        context.insert(LogWeights(logId: log.id, grams: lifted))
        if assisted {
            context.insert(AssistedResult(
                logId: log.id,
                bodyWeight: legacyUnit.display(grams: bodyWeightGrams),
                machineSettings: WeightHistory.legacyNumbers(
                    for: onTheWheels, of: exercise, in: legacyUnit),
                bodyWeightGrams: bodyWeightGrams,
                machineSettingsGrams: onTheWheels))
        }
        recordAerobicResult(for: exercise, log: log)
        return log
    }

    private func recordAerobicResult(for exercise: ExerciseDef, log: WorkoutLog) {
        guard exercise.kind == .aerobic else { return }
        // What was actually done, if a session ran. Otherwise what the wheel
        // says: someone may have used the machine's own timer and only wants
        // it written down, which is no less a record than the rest of this app.

        // From the snapshot taken when that session ended, so the numbers
        // belong to the exercise that produced them.
        guard let summary = summaryFor(currentIndex) else { return }
        context.insert(AerobicResult(
            logId: log.id,
            durationSeconds: summary.seconds,
            averageHeartRate: summary.averageHeartRate,
            maximumHeartRate: summary.maximumHeartRate,
            zoneSeconds: summary.zoneSeconds))
    }

    private func goToNextUnlogged() {
        let count = max(1, exerciseIds.count)
        var next = (currentIndex + 1) % count
        while loggedIndices.contains(next) && loggedIndices.count < count {
            next = (next + 1) % count
        }
        currentIndex = next
    }

    private func goToPrevUnlogged() {
        let count = max(1, exerciseIds.count)
        var prev = (currentIndex - 1 + count) % count
        while loggedIndices.contains(prev) && loggedIndices.count < count {
            prev = (prev - 1 + count) % count
        }
        currentIndex = prev
    }
}

// MARK: - Wheel outline
//
// Rounded border around a picker wheel, matching the Watch's look so each
// series column reads as its own control.
extension View {
    func wheelOutline(cornerRadius: CGFloat = 12) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Color.secondary.opacity(0.45), lineWidth: 1)
        )
    }
}

// MARK: - Handover Paused overlay
//
// Shown over the log screen when the workout has been taken over on the other
// device. Tapping "Continue here" pulls the session back to this device.
struct HandoverPausedView: View {
    let otherDeviceName: String
    let onContinue: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "arrow.left.arrow.right.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)
                Text("Workout active on \(otherDeviceName)")
                    .font(.title3).bold()
                    .multilineTextAlignment(.center)
                Text("You're logging this workout on your \(otherDeviceName). Continue it here to move it back.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button(action: onContinue) {
                    Text("Continue here")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Not now", action: onDismiss)
                    .buttonStyle(.bordered)
            }
            .padding(32)
        }
    }
}

/// The heart rate band as the Watch will draw it, for choosing how strong it
/// should be.
///
/// All five zones at equal width here, unlike the Watch, where the one you are
/// in is widened: this is about the colour, not about reading a rate, and
/// equal blocks make the five strengths comparable. The name lies across them
/// for the thing that actually matters — whether it can still be read.
struct ZoneTintPreview: View {
    let tint: Double

    /// Long enough to run through every block. No exercise has a name this
    /// long, and the point is to judge white text against all five colours
    /// rather than against the first two, so it borrows the printer's filler
    /// that exists for exactly this.
    private let sample = "Lorem ipsum dolor sit amet, consectetur adipiscing elit"

    var body: some View {
        ZStack(alignment: .leading) {
            // The band is drawn on the Watch's black screen, and these colours
            // are see-through at anything below full strength. Over a Form's
            // own background they would be judged against the wrong thing —
            // paler on a light phone, and a different colour entirely.
            RoundedRectangle(cornerRadius: 3).fill(.black)
            HStack(spacing: 2) {
                ForEach(1...HeartRateZones.zoneCount, id: \.self) { zone in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(ZoneColour.colour(zone).opacity(tint))
                }
            }
            Text(sample)
                .font(.caption).bold()
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.leading, 4)
        }
        .frame(height: 24)
        .padding(.vertical, 2)
    }
}

/// What the log screen becomes while the Watch is running the workout as an
/// Apple workout: a statement, and the way back.
///
/// There is no "Continue here". HealthKit will not move a running session to
/// another device, and ending it early to hand over would put half a workout
/// in Fitness and lose the heart rate for the rest — so the choice the
/// hand-over screen offers does not exist here. Saying so plainly beats a
/// button that cannot work.
struct WatchWorkoutActiveView: View {
    let onReturn: () -> Void

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "applewatch.radiowaves.left.and.right")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)
                Text("Workout active on your Apple Watch")
                    .font(.title3).bold()
                    .multilineTextAlignment(.center)
                Text("It is running as an Apple workout, so it stays on your wrist until you finish it there. Your logs, graphs and progress are still here to look at.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button(action: onReturn) {
                    Text("Return to start screen")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(32)
        }
    }
}

// MARK: - Logs Screen
// MARK: - logs tab
//
// The log list. Import/export lives in ImportExportView; both are tabs of
// LogsStatsView now.

struct LogsListView: View {
    @Query(sort: [SortDescriptor(\WorkoutLog.date, order: .reverse)]) private var logs: [WorkoutLog]
    @Query private var workouts: [WorkoutDef]
    @Query private var exercises: [ExerciseDef]
    @Query private var aerobicResults: [AerobicResult]
    @Query private var logWeights: [LogWeights]

    var body: some View {
        if logs.isEmpty {
            ContentUnavailableView("No logs yet", systemImage: "doc.text", description: Text("Start logging your workouts to see them here."))
        } else {
            List(compactRows()) { row in
                VStack(spacing: 2) {
                    Rectangle()
                        .fill(Color.secondary.opacity(1.0))
                        .frame(height: row.isWorkout ? 3 : 1)
                    HStack(alignment: .center, spacing: 8) {
                        Group {
                            if row.isWorkout {
                                Text(row.left).font(.headline).foregroundStyle(.blue).italic()
                            } else {
                                Text(row.left).font(.headline)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Group {
                            if row.isWorkout {
                                Text(row.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.headline).foregroundStyle(.blue)
                            } else if let log = row.log {
                                weightsRepsGrid(for: log, at: row.date)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .listRowSeparator(.hidden)
            }
        }
    }

    private struct CompactRow: Identifiable {
        let id: String
        let isWorkout: Bool
        let left: String
        let date: Date
        let log: WorkoutLog?
        let workoutId: UUID?
        let exerciseId: UUID?
    }

    private func compactRows() -> [CompactRow] {
        let maxWorkoutPauze: TimeInterval = 3600 // seconds
        var rows: [CompactRow] = []
        var lastExerciseDate: Date? = nil
        var lastWorkoutId: UUID? = nil
        for log in logs {
            let workoutName = workouts.first(where: { $0.id == log.workoutId })?.name ?? "Workout"
            // Insert a workout-header row when more than maxWorkoutPauze has
            // elapsed since the previous logged exercise OR the workout id
            // changed (so adjacent same-workout exercises group together).
            let shouldInsertHeader: Bool = {
                guard let last = lastExerciseDate else { return true }
                if last.timeIntervalSince(log.date) >= maxWorkoutPauze { return true }
                if lastWorkoutId != log.workoutId { return true }
                return false
            }()
            if shouldInsertHeader {
                rows.append(CompactRow(
                    id: "w-\(log.id.uuidString)",
                    isWorkout: true,
                    left: workoutName,
                    date: log.date,
                    log: nil,
                    workoutId: log.workoutId,
                    exerciseId: nil
                ))
            }
            let exerciseName = exercises.first(where: { $0.id == log.exerciseId })?.name ?? "Exercise"
            rows.append(CompactRow(
                id: "e-\(log.id.uuidString)",
                isWorkout: false,
                left: exerciseName,
                date: log.date,
                log: log,
                workoutId: log.workoutId,
                exerciseId: log.exerciseId
            ))
            lastExerciseDate = log.date
            lastWorkoutId = log.workoutId
        }
        return rows
    }

    /// What a finished aerobic session came to, if this log is one.
    private func aerobicSummary(for log: WorkoutLog) -> AerobicSummary? {
        guard let result = aerobicResults.first(where: { $0.logId == log.id }) else { return nil }
        return AerobicSummary(seconds: result.durationSeconds,
                              averageHeartRate: result.averageHeartRate,
                              maximumHeartRate: result.maximumHeartRate,
                              zoneSeconds: result.zoneSeconds)
    }

    @ViewBuilder
    private func weightsRepsGrid(for log: WorkoutLog, at date: Date) -> some View {
        // A ride has no sets, so the w/r grid rendered two empty rows with
        // nothing in them. Its own numbers instead.
        if let summary = aerobicSummary(for: log) {
            AerobicSummaryView(summary: summary, compact: true)
        } else {
            weightsRepsColumns(for: log, at: date)
        }
    }

    private func weightsRepsColumns(for log: WorkoutLog, at date: Date) -> some View {
        let previous = previousEntry(for: log.exerciseId, before: date)
        // Grams, from beside the log. The unit is only how they are written —
        // no "kg" or "lb" here, where every column is already as narrow as it
        // can be and the unit is the same down the whole screen.
        let byLog = LogWeightsIndex.byLogId(logWeights)
        let grams = byLog[log.id] ?? []
        let previousGrams = previous.flatMap { byLog[$0.id] } ?? []
        let unit = WeightUnit.current
        let maxCount = max(grams.count, log.reps.count)
        return Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
            GridRow {
                Text("w").font(.headline)
                ForEach(0..<maxCount, id: \.self) { i in
                    let current = i < grams.count ? grams[i] : 0
                    let prev = previousGrams.indices.contains(i) ? previousGrams[i] : nil
                    Text(WeightText.string(grams: current, in: unit))
                        .foregroundStyle(colorForWeight(current: current, previous: prev,
                                                        exerciseId: log.exerciseId))
                        .font(.headline)
                }
            }
            GridRow {
                Text("r").font(.headline)
                ForEach(0..<maxCount, id: \.self) { i in
                    let current = i < log.reps.count ? log.reps[i] : 0
                    let prevRep = previous?.reps.indices.contains(i) == true ? previous!.reps[i] : nil
                    let currentW = i < grams.count ? grams[i] : 0
                    let prevW = previousGrams.indices.contains(i) ? previousGrams[i] : nil
                    Text("\(current)")
                        .foregroundStyle(colorForReps(current: current, previous: prevRep,
                                                      currentWeight: currentW, previousWeight: prevW,
                                                      exerciseId: log.exerciseId))
                        .font(.headline)
                }
            }
        }
    }

    // The rules themselves live in Shared/StatsPresentation.swift, where the
    // Mac's log screen reads them too. Green and red here are a claim about
    // the user's training, and two devices colouring the same two rows
    // differently would be telling contradictory stories about one workout.

    private func previousEntry(for exerciseId: UUID, before date: Date) -> WorkoutLog? {
        LogComparison.previous(for: exerciseId, before: date, in: logs)
    }

    /// The exercise's own increment, so a difference smaller than half of it
    /// is left uncoloured — see `LogComparison.tolerance`.
    private func increment(for exerciseId: UUID) -> Int? {
        exercises.first(where: { $0.id == exerciseId })?.weightIncrementGrams
    }

    private func colorForWeight(current: Int, previous: Int?, exerciseId: UUID) -> Color {
        LogComparison.weightColour(current: current, previous: previous,
                                   increment: increment(for: exerciseId))
    }

    private func colorForReps(current: Int, previous: Int?, currentWeight: Int,
                              previousWeight: Int?, exerciseId: UUID) -> Color {
        LogComparison.repsColour(current: current, previous: previous,
                                 currentWeight: currentWeight, previousWeight: previousWeight,
                                 increment: increment(for: exerciseId))
    }
}

// MARK: - import/export tab

struct ImportExportView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.modelContext) private var context

    @Query(sort: [SortDescriptor(\WorkoutLog.date, order: .reverse)]) private var logs: [WorkoutLog]
    @Query private var workouts: [WorkoutDef]
    @Query private var exercises: [ExerciseDef]
    @Query private var aerobicResults: [AerobicResult]
    @Query private var assistedResults: [AssistedResult]
    @Query private var logWeights: [LogWeights]

    @State private var exportURL: URL?

    @State private var showImportPicker = false
    @State private var pendingImportURL: URL?
    @State private var showImportActions = false

    // New states for alerts and undo backup
    @State private var showResultAlert: Bool = false
    @State private var resultTitle: String = ""
    @State private var resultMessage: String = ""
    @State private var lastBackupURL: URL? = nil

    var body: some View {
        VStack {
            HStack(spacing: 8) {
                Button {
                    exportLogs()
                } label: {
                    Text("export\nTSV")
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(logs.isEmpty)

                Button {
                    exportJSON()
                } label: {
                    Text("export\nJSON")
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(logs.isEmpty)

                Button {
                    showImportPicker = true
                } label: {
                    Text("import\nJSON")
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    if let backupURL = lastBackupURL {
                        replaceData(with: backupURL)
                        lastBackupURL = nil
                    }
                } label: {
                    Text("undo\nimport")
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(lastBackupURL == nil)
            }
            .padding(.horizontal)

            List {
                Section {
                    Text("**export TSV** writes a tab-separated table of every logged set, for a spreadsheet.")
                    Text("**export JSON** writes everything — workouts, exercises and logs — in the app's own format, which is what **import JSON** reads back.")
                    Text("Importing offers to validate the file, count what is in it, replace everything, or merge it with what you have. **undo import** restores the automatic backup taken just before the last replace or merge.")
                } header: {
                    Text("What these do")
                }
                .font(.footnote)
            }
        }
        .sheet(item: $exportURL, onDismiss: { cleanupExport() }) { url in
            ShareSheet(activityItems: [url])
        }
        .fileImporter(isPresented: $showImportPicker, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                pendingImportURL = url
                showImportActions = true
            case .failure(let error):
                resultTitle = "File Error"
                resultMessage = "Failed to pick file: \(error.localizedDescription)"
                showResultAlert = true
            }
        }
        .confirmationDialog("Import JSON", isPresented: $showImportActions, titleVisibility: .visible) {
            Button("Validate") {
                if let url = pendingImportURL {
                    validateImport(at: url)
                }
            }
            Button("Check Counts") {
                if let url = pendingImportURL {
                    checkCounts(at: url)
                }
            }
            Button("Replace Data", role: .destructive) {
                if let url = pendingImportURL {
                    // Backup before replace
                    if let backup = backupCurrentData() {
                        lastBackupURL = backup
                    }
                    replaceData(with: url)
                }
            }
            Button("Merge Data") {
                if let url = pendingImportURL {
                    // Backup before merge
                    if let backup = backupCurrentData() {
                        lastBackupURL = backup
                    }
                    mergeData(with: url)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert(resultTitle, isPresented: $showResultAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(resultMessage)
        }
    }
    
    private func exportLogs() {
        // Generate TSV content
        let tsv = makeTSV()
        // Write to a temporary file
        let tmpDir = FileManager.default.temporaryDirectory
        let fileURL = tmpDir.appendingPathComponent("workout-logs.tsv")
        do {
            try tsv.data(using: .utf8)?.write(to: fileURL, options: .atomic)
            exportURL = fileURL
        } catch {
            resultTitle = "Export Failed"
            resultMessage = "Failed to write export: \(error.localizedDescription)"
            showResultAlert = true
        }
    }

    private func cleanupExport() {
        if let url = exportURL {
            try? FileManager.default.removeItem(at: url)
        }
        exportURL = nil
    }
    
    private func buildExportEnvelope() -> ExportEnvelope {
        let bundle = Bundle.main
        return ExportEnvelope(
            exportVersion: "logJSON.4",
            appIdentifier: bundle.bundleIdentifier ?? "",
            appVersion: bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
            build: bundle.infoDictionary?["CFBundleVersion"] as? String ?? "",
            exportedAt: ISO8601DateFormatter().string(from: Date()),
            device: ExportEnvelope.DeviceInfo(
                model: UIDevice.current.model,
                system: UIDevice.current.systemName,
                version: UIDevice.current.systemVersion
            ),
            locale: Locale.current.identifier,
            timeZone: TimeZone.current.identifier,
            counts: ExportEnvelope.Counts(
                workouts: workouts.count,
                exercises: exercises.count,
                logs: logs.count
            ),
            data: ExportEnvelope.AllData(
                workouts: workouts,
                exercises: exercises,
                logs: logs,
                aerobicResults: aerobicResults,
                assistedResults: assistedResults,
                logWeights: logWeights
            )
        )
    }

    private func exportJSON() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        do {
            let jsonData = try encoder.encode(buildExportEnvelope())
            let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("workout-logs.json")
            try jsonData.write(to: fileURL, options: .atomic)
            exportURL = fileURL
        } catch {
            resultTitle = "Export Failed"
            resultMessage = "Failed to export JSON: \(error.localizedDescription)"
            showResultAlert = true
        }
    }

    private func backupCurrentData() -> URL? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        do {
            let jsonData = try encoder.encode(buildExportEnvelope())
            let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("workout-backup.json")
            try jsonData.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            resultTitle = "Backup Failed"
            resultMessage = "Failed to backup current data: \(error.localizedDescription)"
            showResultAlert = true
            return nil
        }
    }

    /// Returns an envelope in the *current* (logJSON.2) flat shape regardless
    /// of whether the source file is logJSON.1 or logJSON.2. Old single-row,
    /// multi-entry logs get expanded into one flat WorkoutLog per entry.
    private func loadEnvelope(from url: URL) throws -> ExportEnvelope {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)

        // Peek at exportVersion without committing to either schema yet.
        struct VersionPeek: Decodable { let exportVersion: String }
        let version = (try? JSONDecoder().decode(VersionPeek.self, from: data))?.exportVersion ?? ""

        let decoder = JSONDecoder()
        if version == "logJSON.2" || version == "logJSON.3" || version == "logJSON.4" {
            // Each version only ADDS optional arrays, so an older file decodes
            // into the current shape with none of them. A file older than
            // logJSON.4 holds weights without a unit; they are imported as
            // they are and the app asks, once, what they meant.
            return try decoder.decode(ExportEnvelope.self, from: data)
        } else if version.hasPrefix("logJSON.1") {
            let legacy = try decoder.decode(LegacyExportEnvelope.self, from: data)
            let flatLogs: [WorkoutLog] = legacy.data.logs.flatMap { $0.flatten() }
            return ExportEnvelope(
                exportVersion: "logJSON.2",            // normalized
                appIdentifier: legacy.appIdentifier,
                appVersion:    legacy.appVersion,
                build:         legacy.build,
                exportedAt:    legacy.exportedAt,
                device:        legacy.device,
                locale:        legacy.locale,
                timeZone:      legacy.timeZone,
                counts: ExportEnvelope.Counts(
                    workouts:  legacy.data.workouts.count,
                    exercises: legacy.data.exercises.count,
                    logs:      flatLogs.count            // flattened count
                ),
                data: ExportEnvelope.AllData(
                    workouts:  legacy.data.workouts,
                    exercises: legacy.data.exercises,
                    logs:      flatLogs
                )
            )
        } else {
            // Try V2 anyway so a forward-compat exportVersion still parses.
            return try decoder.decode(ExportEnvelope.self, from: data)
        }
    }

    private func validateImport(at url: URL) {
        do {
            let envelope = try loadEnvelope(from: url)
            guard envelope.exportVersion.starts(with: "logJSON.") else {
                resultTitle = "Validation Failed"
                resultMessage = "Invalid export version: \(envelope.exportVersion)"
                showResultAlert = true
                return
            }
            // Check required fields presence (non-empty strings)
            guard !envelope.appIdentifier.isEmpty, !envelope.appVersion.isEmpty, !envelope.build.isEmpty else {
                resultTitle = "Validation Failed"
                resultMessage = "Missing app metadata in export"
                showResultAlert = true
                return
            }
            // Check counts consistent with data arrays
            guard envelope.counts.workouts == envelope.data.workouts.count,
                  envelope.counts.exercises == envelope.data.exercises.count,
                  envelope.counts.logs == envelope.data.logs.count else {
                resultTitle = "Validation Failed"
                resultMessage = "Counts mismatch with data arrays"
                showResultAlert = true
                return
            }
            // Check logs are reverse chronological order (each date >= next)
            let logs = envelope.data.logs
            for i in 0..<(logs.count - 1) {
                let current = logs[i].date
                let next = logs[i+1].date
                if current < next {
                    resultTitle = "Validation Failed"
                    resultMessage = "Logs are not in reverse chronological order"
                    showResultAlert = true
                    return
                }
            }
            resultTitle = "Validation Successful"
            resultMessage = "The import file is valid and ready to use."
            showResultAlert = true
        } catch {
            resultTitle = "Validation Failed"
            resultMessage = "Failed to validate import: \(error.localizedDescription)"
            showResultAlert = true
        }
    }

    private func checkCounts(at url: URL) {
        do {
            let envelope = try loadEnvelope(from: url)
            let importedCounts = envelope.counts
            let currentCounts = ExportEnvelope.Counts(
                workouts: workouts.count,
                exercises: exercises.count,
                logs: logs.count
            )
            let importedLogs = envelope.data.logs
            let oldestDate = importedLogs.min(by: { $0.date < $1.date })?.date
            let newestDate = importedLogs.max(by: { $0.date < $1.date })?.date
            
            let workoutDiff = importedCounts.workouts - currentCounts.workouts
            let exerciseDiff = importedCounts.exercises - currentCounts.exercises
            let logDiff = importedCounts.logs - currentCounts.logs
            
            var message = """
            Imported counts:
            - Workouts: \(importedCounts.workouts) (\(workoutDiff >= 0 ? "+" : "")\(workoutDiff) compared to current)
            - Exercises: \(importedCounts.exercises) (\(exerciseDiff >= 0 ? "+" : "")\(exerciseDiff))
            - Logs: \(importedCounts.logs) (\(logDiff >= 0 ? "+" : "")\(logDiff))
            """
            message += "\nImported logs span from \(oldestDate?.description(with: .current) ?? "N/A") to \(newestDate?.description(with: .current) ?? "N/A")"
            
            resultTitle = "Counts Summary"
            resultMessage = message
            showResultAlert = true
        } catch {
            resultTitle = "Counts Check Failed"
            resultMessage = "Failed to check counts: \(error.localizedDescription)"
            showResultAlert = true
        }
    }

    private func replaceData(with url: URL) {
        do {
            let envelope = try loadEnvelope(from: url)
            guard envelope.exportVersion.starts(with: "logJSON.") else {
                resultTitle = "Import Failed"
                resultMessage = "Invalid export version: \(envelope.exportVersion)"
                showResultAlert = true
                return
            }
            // Clear existing data
            let fetchLogs: FetchDescriptor<WorkoutLog> = FetchDescriptor()
            if let existingLogs = try? context.fetch(fetchLogs) {
                for log in existingLogs {
                    context.delete(log)
                }
            }
            let fetchWorkouts: FetchDescriptor<WorkoutDef> = FetchDescriptor()
            if let existingWorkouts = try? context.fetch(fetchWorkouts) {
                for workout in existingWorkouts {
                    context.delete(workout)
                }
            }
            let fetchExercises: FetchDescriptor<ExerciseDef> = FetchDescriptor()
            if let existingExercises = try? context.fetch(fetchExercises) {
                for exercise in existingExercises {
                    context.delete(exercise)
                }
            }
            // The results hang off logs that are about to go, so they go too.
            // Left behind they would be orphans, and would then attach
            // themselves to an imported log that happened to reuse the id.
            if let existing = try? context.fetch(FetchDescriptor<AerobicResult>()) {
                for result in existing { context.delete(result) }
            }
            if let existing = try? context.fetch(FetchDescriptor<AssistedResult>()) {
                for result in existing { context.delete(result) }
            }
            if let existing = try? context.fetch(FetchDescriptor<LogWeights>()) {
                for record in existing { context.delete(record) }
            }
            // Insert imported data
            for exercise in envelope.data.exercises {
                context.insert(exercise)
            }
            for workout in envelope.data.workouts {
                context.insert(workout)
            }
            for log in envelope.data.logs {
                context.insert(log)
            }
            for result in envelope.data.aerobicResults ?? [] {
                context.insert(result)
            }
            for result in envelope.data.assistedResults ?? [] {
                context.insert(result)
            }
            for record in envelope.data.logWeights ?? [] {
                context.insert(record)
            }
            try context.save()
            // Notify store or reload
            NotificationCenter.default.post(name: .modelDataDidChange, object: nil)
            resultTitle = "Import Successful"
            resultMessage = "Data replaced successfully."
            showResultAlert = true
        } catch {
            resultTitle = "Import Failed"
            resultMessage = "Failed to replace data: \(error.localizedDescription)"
            showResultAlert = true
        }
    }

    private func mergeData(with url: URL) {
        struct LogSig: Hashable {
            let date: Date
            let workoutId: UUID
            let exerciseId: UUID
        }
        do {
            let envelope = try loadEnvelope(from: url)
            guard envelope.exportVersion.starts(with: "logJSON.") else {
                resultTitle = "Merge Failed"
                resultMessage = "Invalid export version: \(envelope.exportVersion)"
                showResultAlert = true
                return
            }
            var insertedExercises = 0
            var insertedWorkouts = 0
            var updatedExerciseNames = 0
            var updatedWorkoutNames = 0

            // Insert new exercises only; update names for existing
            for importedEx in envelope.data.exercises {
                if let existingEx = exercises.first(where: { $0.id == importedEx.id }) {
                    if existingEx.name != importedEx.name {
                        existingEx.name = importedEx.name
                        updatedExerciseNames += 1
                    }
                } else {
                    context.insert(importedEx)
                    insertedExercises += 1
                }
            }
            // Insert new workouts only; update names for existing
            for importedWorkout in envelope.data.workouts {
                if let existingWorkout = workouts.first(where: { $0.id == importedWorkout.id }) {
                    if existingWorkout.name != importedWorkout.name {
                        existingWorkout.name = importedWorkout.name
                        updatedWorkoutNames += 1
                    }
                } else {
                    context.insert(importedWorkout)
                    insertedWorkouts += 1
                }
            }
            // Logs: dedupe by (date, workoutId, exerciseId). Same signature with
            // differing weights/reps is treated as a conflict; existing wins.
            let existingByKey: [LogSig: WorkoutLog] = Dictionary(
                uniqueKeysWithValues: logs.map {
                    (LogSig(date: $0.date, workoutId: $0.workoutId, exerciseId: $0.exerciseId), $0)
                }
            )

            var insertedLogs = 0
            var conflictCount = 0
            var importedLogIds: Set<UUID> = []

            for importedLog in envelope.data.logs {
                let key = LogSig(date: importedLog.date,
                                 workoutId: importedLog.workoutId,
                                 exerciseId: importedLog.exerciseId)
                if let existing = existingByKey[key] {
                    if existing.weights != importedLog.weights || existing.reps != importedLog.reps {
                        conflictCount += 1
                        // TODO: present UI to resolve; for now keep existing
                    }
                } else {
                    context.insert(importedLog)
                    insertedLogs += 1
                    importedLogIds.insert(importedLog.id)
                }
            }

            // A result belongs to one log. Where the log was skipped as a
            // duplicate, its result is skipped too: the log that won is the
            // one already here, with whatever results it already had.
            let existingAerobicIds = Set(aerobicResults.map(\.id))
            for result in envelope.data.aerobicResults ?? []
            where importedLogIds.contains(result.logId) && !existingAerobicIds.contains(result.id) {
                context.insert(result)
            }
            let existingAssistedIds = Set(assistedResults.map(\.id))
            for result in envelope.data.assistedResults ?? []
            where importedLogIds.contains(result.logId) && !existingAssistedIds.contains(result.id) {
                context.insert(result)
            }
            let existingWeightIds = Set(logWeights.map(\.id))
            for record in envelope.data.logWeights ?? []
            where importedLogIds.contains(record.logId) && !existingWeightIds.contains(record.id) {
                context.insert(record)
            }
            try context.save()
            NotificationCenter.default.post(name: .modelDataDidChange, object: nil)
            var message = "Data merged successfully.\n"
            message += "Inserted Exercises: \(insertedExercises)\n"
            message += "Inserted Workouts: \(insertedWorkouts)\n"
            message += "Inserted Logs: \(insertedLogs)\n"
            message += "Updated Exercise Names: \(updatedExerciseNames)\n"
            message += "Updated Workout Names: \(updatedWorkoutNames)\n"
            if conflictCount > 0 {
                message += "Conflicts detected in \(conflictCount) log rows; existing kept."
            }
            resultTitle = "Merge Complete"
            resultMessage = message
            showResultAlert = true
        } catch {
            resultTitle = "Merge Failed"
            resultMessage = "Failed to merge data: \(error.localizedDescription)"
            showResultAlert = true
        }
    }

    private func makeTSV() -> String {
        // Header
        var lines: [String] = ["date\ttime\tworkout\texercise\tset\tweight\treps\tlog output version: logTSV.1"]
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone.current
        dateFormatter.dateFormat = "yyyy-MM-dd\tHH:mm"
        // Logs are reverse sorted; export newest first is fine
        for log in logs {
            let workoutName = workouts.first(where: { $0.id == log.workoutId })?.name ?? "Workout"
            let exerciseName = exercises.first(where: { $0.id == log.exerciseId })?.name ?? "Exercise"
            let count = max(log.weights.count, log.reps.count)
            for i in 0..<count {
                let weight = i < log.weights.count ? log.weights[i] : 0
                let reps   = i < log.reps.count    ? log.reps[i]    : 0
                let dateStr = dateFormatter.string(from: log.date)
                let quotedWorkout = quoteIfNeeded(workoutName)
                let quotedExercise = quoteIfNeeded(exerciseName)
                lines.append("\(dateStr)\t\(quotedWorkout)\t\(quotedExercise)\t\(i+1)\t\(weight)\t\(reps)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func quoteIfNeeded(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") {
            let escaped = s.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return s
    }

}

// MARK: - Recovery Screen
//
// Shown when both the normal load AND the V1 schema fallback have failed —
// meaning the on-disk store structure is unrecognisable. By this point
// AppSetup has already wiped the local file so the app can run; this view
// explains what happened, lets the user export whatever is still available
// (the fresh empty store — a valid JSON template), and then continues.

struct RecoveryView: View {
    @EnvironmentObject private var setup: AppSetup
    @EnvironmentObject private var store: AppStore

    @Query private var workouts:  [WorkoutDef]
    @Query private var exercises: [ExerciseDef]
    @Query private var logs:      [WorkoutLog]

    @State private var exportURL: URL?
    @State private var showExportSheet = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.orange)
                    .padding(.top, 32)

                Text("Your data couldn't be loaded")
                    .font(.title2).bold()
                    .multilineTextAlignment(.center)

                Text("""
                     The app found a data file it couldn't read. \
                     This can happen when upgrading from a much earlier version.

                     Your workouts and exercise definitions may have been saved \
                     elsewhere (iCloud, a JSON export). You can export what is \
                     currently available — it may be empty, but it gives you a \
                     valid file to compare against any backup you already have.
                     """)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                // Export button — builds a JSON from the current (fresh) store.
                // Even if empty it provides the correct schema for manual editing.
                Button {
                    buildAndShareExport()
                } label: {
                    Label("Export available data", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .padding(.horizontal)

                NavigationLink(destination: SettingsView()) {
                    Label("Go to Settings", systemImage: "gear")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .padding(.horizontal)

                Divider()

                Button(role: .destructive) {
                    setup.startFresh()
                } label: {
                    Label("Continue with empty app", systemImage: "arrow.forward.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .padding(.horizontal)

                Text("You can import a JSON backup later via the Logs screen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(.bottom, 32)
            }
        }
        .navigationTitle("Data Recovery")
        .sheet(item: $exportURL) { url in
            ShareSheet(activityItems: [url])
                .onDisappear {
                    try? FileManager.default.removeItem(at: url)
                    exportURL = nil
                }
        }
    }

    private func buildAndShareExport() {
        let bundle = Bundle.main
        let envelope = ExportEnvelope(
            exportVersion: "logJSON.2",
            appIdentifier: bundle.bundleIdentifier ?? "",
            appVersion:    bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
            build:         bundle.infoDictionary?["CFBundleVersion"] as? String ?? "",
            exportedAt:    ISO8601DateFormatter().string(from: Date()),
            device: ExportEnvelope.DeviceInfo(
                model:   UIDevice.current.model,
                system:  UIDevice.current.systemName,
                version: UIDevice.current.systemVersion),
            locale:   Locale.current.identifier,
            timeZone: TimeZone.current.identifier,
            counts:   ExportEnvelope.Counts(
                workouts:  workouts.count,
                exercises: exercises.count,
                logs:      logs.count),
            data: ExportEnvelope.AllData(
                workouts:  workouts,
                exercises: exercises,
                logs:      logs)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(envelope) else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("workout-recovery-export.json")
        try? data.write(to: url, options: .atomic)
        exportURL = url
    }
}

// MARK: - Settings Screen
struct SettingsView: View {
    @AppStorage(PrefillScope.key) private var prefillAcrossWorkouts = PrefillScope.defaultAcrossWorkouts
    @AppStorage(WatchWorkoutMode.key) private var watchWorkoutModeRaw = WatchWorkoutMode.handover.rawValue
    @ObservedObject private var handoff = PhoneSessionManager.shared
    private var watchWorkoutMode: WatchWorkoutMode {
        WatchWorkoutMode(rawValue: watchWorkoutModeRaw) ?? .handover
    }
    /// Whether to say anything about the Watch at all. Without one, the choice
    /// between the two ways of recording a Watch workout is a setting for a
    /// device the user does not have — and the Health switch keeps its plain
    /// wording, since nothing else is writing workouts.
    private var showsWatchSettings: Bool {
        #if DEBUG
        // A paired simulator never reports the companion as installed, however
        // it is paired and installed — so a screenshot run says there is one.
        if DemoMode.isEnabled { return true }
        #endif
        return handoff.watchAppInstalled
    }
    private var watchRecordsWorkouts: Bool {
        showsWatchSettings && watchWorkoutMode == .appleWorkout
    }
    private var bodyWeightSource: BodyWeightSource {
        BodyWeightSource(rawValue: bodyWeightSourceRaw) ?? .health
    }
    /// Only shown to people who have an exercise that needs it: a body weight
    /// is of no interest to this app otherwise, and asking for one would look
    /// like the start of something it does not do.
    /// What the app makes of the weights it holds: how many exercises and
    /// logs still have no unit, and what the user said theirs were in.
    private var weightUnitStateDescription: String {
        let pending = WeightHistory.pendingCount(in: settingsContext)
        let stated = WeightHistory.statedUnit?.label ?? "not stated"
        if pending == 0 { return "all · history: \(stated)" }
        return "\(pending) waiting · history: \(stated)"
    }

    private var usesBodyWeight: Bool {
        exercises.contains { $0.subtractsFromBodyWeight }
    }
    @Environment(\.modelContext) private var settingsContext
    @AppStorage(WeightUnit.key) private var weightUnitRaw = WeightUnit.regionDefault.rawValue
    @AppStorage(BodyWeight.sourceKey) private var bodyWeightSourceRaw = BodyWeightSource.health.rawValue
    @AppStorage(BodyWeight.manualKey) private var bodyWeightManual = 0
    @State private var bodyWeightFromHealth: Double? = BodyWeight.health
    @AppStorage(WatchPreferences.zoneTintKey) private var zoneTint = WatchPreferences.defaultZoneTint
    @AppStorage(WatchPreferences.restTapsKey) private var restTaps = WatchPreferences.defaultRestTaps
    @AppStorage(WatchPreferences.wheelRowsKey) private var wheelRows = WatchPreferences.defaultWheelRows

    @AppStorage("iCloudSyncEnabled") private var iCloudSyncEnabled = false
    @AppStorage("healthSharingEnabled") private var healthSharingEnabled = false
    @AppStorage(StatsSettingsKey.formula) private var formulaRaw = OneRMFormula.epley.rawValue
    @AppStorage(StatsSettingsKey.window) private var trendWindow = StatsEngine.defaultWindow
    @AppStorage(StatsSettingsKey.smoothing) private var smoothing = StatsEngine.defaultSmoothing
    @AppStorage(SharingKey.consent) private var shareWithDevelopers = false
    @AppStorage(RestTimerKey.enabled) private var restTimerOn = false
    @AppStorage(DeveloperDataSync.withdrawProblemKey) private var withdrawProblem: String?
    @AppStorage(DeveloperDataSync.uploadProblemKey) private var uploadProblem: String?
    @AppStorage(DeveloperDataSync.uploadStatusKey) private var uploadStatus: String?
    @EnvironmentObject private var setup: AppSetup
    @EnvironmentObject private var store: AppStore
    @Query private var logs: [WorkoutLog]
    @Query private var logWeights: [LogWeights]
    @Query private var exercises: [ExerciseDef]
    @State private var showDeleteConfirm = false

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $iCloudSyncEnabled) {
                    Label("Share data among your iPhones/iPads", systemImage: "icloud")
                }
            } footer: {
                if let problem = setup.syncFailureMessage {
                    Text(problem).foregroundStyle(.red)
                } else {
                    Text("Syncs your workouts, exercises, and logs across all your iPhones and iPads signed into the same iCloud account and that have this option turned on. Changes take effect immediately.")
                }
            }

            if showsWatchSettings {
            Section {
                Picker(selection: $watchWorkoutModeRaw) {
                    ForEach(WatchWorkoutMode.allCases) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                } label: {
                    Label("Workouts on the Watch", systemImage: "applewatch")
                }
                .pickerStyle(.inline)
                .disabled(handoff.isLockedByWatchWorkout)
                .onChange(of: watchWorkoutModeRaw) { _, _ in
                    // The Watch is told which way to work, with the definitions.
                    store.reloadAll()
                }
            } footer: {
                if handoff.isLockedByWatchWorkout {
                    Text("A workout is running on your Watch. This is the one setting that cannot change while it does — the workout is being recorded one way or the other, and switching underneath it would lose what has been collected. Everything else here can be changed now, including how the Watch looks.")
                        .foregroundStyle(.orange)
                } else {
                if watchWorkoutMode == .appleWorkout {
                    Text("Starting a workout on the Watch makes it a real Apple workout: your heart rate is recorded, the zone shows behind the exercise name, and it lands in Fitness and counts towards your rings. The price is that a workout on your wrist cannot come back to the phone part-way through — you can still start on the phone and carry on at the machine, and the Apple workout is back-dated to when you really began. An aerobic exercise is still recorded as its own workout of the activity you chose, so a workout with cardio in the middle arrives in Fitness as strength, then cardio, then strength.")
                } else {
                    Text("A workout can be moved between your iPhone and your Watch as often as you like; whichever device you pick it up on asks first. Your Watch does not record a workout of its own, so there is no heart rate during the weights and nothing towards your rings except what an aerobic exercise adds.")
                }
                }
            }
            }

            Section {
                Picker(selection: $weightUnitRaw) {
                    ForEach(WeightUnit.allCases) { unit in
                        Text(unit == .kilograms ? "Kilograms (kg)" : "Pounds (lb)")
                            .tag(unit.rawValue)
                    }
                } label: {
                    Label("Weights in", systemImage: "scalemass")
                }
                .pickerStyle(.inline)
                .onChange(of: weightUnitRaw) { _, _ in
                    // Nothing is converted: weights are stored in grams, so
                    // this changes how they are written and nothing else.
                    store.reloadAll()
                }
                // Plainly, because the alternative is guessing from a
                // screenshot. This is what the app believes right now.
                LabeledContent("Weights with a unit") {
                    Text(weightUnitStateDescription).foregroundStyle(.secondary)
                }
            } footer: {
                Text("Your weights are kept in a form that has no unit, so switching here re-presents everything you have ever logged in the other one — nothing is recalculated and nothing is lost. Weights are written to the nearest quarter: 130, 130¼, 130½, 130¾.")
            }

            if usesBodyWeight {
                Section {
                    Picker(selection: $bodyWeightSourceRaw) {
                        ForEach(BodyWeightSource.allCases) { source in
                            Text(source.label).tag(source.rawValue)
                        }
                    } label: {
                        Label("Body weight", systemImage: "figure.stand")
                    }
                    .pickerStyle(.inline)
                    .onChange(of: bodyWeightSourceRaw) { _, _ in
                        Task {
                            if bodyWeightSource == .health {
                                await HealthBodyWeight.requestAuthorization()
                                bodyWeightFromHealth = await HealthBodyWeight.refresh()
                            }
                            store.reloadAll()
                        }
                    }

                    if bodyWeightSource == .manual {
                        LabeledContent {
                            TextField("", value: $bodyWeightManual, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .onChange(of: bodyWeightManual) { _, _ in store.reloadAll() }
                        } label: { Text("Your weight") }
                    } else if let weight = bodyWeightFromHealth {
                        LabeledContent {
                            Text(weight.formatted(.number.precision(.fractionLength(0...1))))
                                .foregroundStyle(.secondary)
                        } label: { Text("Latest in Health") }
                    } else {
                        Text("No weight found in Apple Health yet. Until one arrives, exercises that subtract from your body weight cannot be logged — choose “Set here” and type it in.")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                } footer: {
                    Text("Used for exercises marked “subtracted from body weight”, such as an assisted chin-up: what you lifted is your body weight less what the machine was carrying. **In the same units as your weights** — this app has no units of its own, so a body weight in kilograms against a machine set in pounds would be nonsense. From Apple Health it arrives in the units you read your weight in there, and follows your weigh-ins on its own. Either way, the weight used is recorded with each set, so an old log still adds up.")
                }
            }

            if showsWatchSettings {
                Section {
                    Picker(selection: $wheelRows) {
                        Text("One row, with a reps/weights toggle").tag(1)
                        Text("Both rows at once").tag(2)
                    } label: {
                        Label("Wheels on the Watch", systemImage: "square.split.1x2")
                    }
                    .pickerStyle(.inline)
                    .onChange(of: wheelRows) { _, _ in store.reloadAll() }
                } footer: {
                    Text("Two rows put the weights and the repetitions on screen together, so there is no switching between them at the machine. The wheels are shorter, the exercise name moves up beside the clock, and the numbers that used to sit under the wheels are no longer needed. One row is how the Watch has always worked.")
                }
            }

            if watchRecordsWorkouts {
                Section {
                    ZoneTintPreview(tint: zoneTint)
                    Slider(value: $zoneTint,
                           in: WatchPreferences.minimumZoneTint...1,
                           step: 0.05) {
                        Text("Band strength")
                    } minimumValueLabel: {
                        Image(systemName: "circle")
                    } maximumValueLabel: {
                        Image(systemName: "circle.fill")
                    }
                    .onChange(of: zoneTint) { _, _ in store.reloadAll() }
                } header: {
                    Text("Heart rate band")
                } footer: {
                    Text("How strongly the zone colours are drawn behind the exercise name on your Watch. The band above shows all five at the strength you pick, with a name over them as it will appear — strong enough to read at a glance, light enough to read the name through.")
                }
            }

            Section {
                Toggle(isOn: $healthSharingEnabled) {
                    Label(watchRecordsWorkouts
                          ? "Save workouts that are only logged on the phone also to Apple Health"
                          : "Save workouts to Apple Health",
                          systemImage: "heart.fill")
                }
                .onChange(of: healthSharingEnabled) { _, enabled in
                    if enabled { HealthWorkoutLogger.shared.requestAuthorization() }
                    // Let the Watch know whether to record to Health too.
                    store.reloadAll()
                }
            } footer: {
                if watchRecordsWorkouts {
                    Text("A workout you log on the Watch is saved to Apple Health by the Watch itself, as the Apple workout it is, whatever this setting says. This setting is for the rest: a workout logged only on the phone, saved as a Traditional Strength Training session with its total duration.")
                } else {
                    Text("When on, a finished workout is saved to Apple Health as a Traditional Strength Training session, with its total duration — including time handed over between iPhone and Apple Watch. Aerobic exercises are separate: your Apple Watch records those as real workouts of the activity you chose, whatever this setting says, which is what makes them appear in Fitness. Heart rate is read on the Watch during an aerobic countdown, and never leaves your devices.")
                }
            }

            Section {
                Toggle(isOn: $restTimerOn) {
                    Label("Rest timer", systemImage: "timer")
                }
                .onChange(of: restTimerOn) { _, on in
                    if on {
                        RestTimerDefaults.requestNotificationPermission()
                    } else {
                        RestTimer.shared.cancel()
                    }
                    // The Watch keeps its own copy of this switch, so it has to
                    // be told — same as the Health toggle above.
                    store.reloadAll()
                }
                if restTimerOn, showsWatchSettings {
                    Stepper(value: $restTaps, in: 1...WatchPreferences.maximumRestTaps) {
                        Label("Taps on the wrist: \(restTaps)", systemImage: "hand.tap")
                    }
                    .onChange(of: restTaps) { _, _ in store.reloadAll() }
                }
            } footer: {
                Text("When on, a rest is counted after every set and after each exercise you log, for as long as that exercise is set to. You can leave the app while it runs: a notification arrives when the rest is over, and an Apple Watch that was nearby when the rest started taps your wrist as well. With this off, the app works exactly as before.")
            }

            Section {
                Toggle(isOn: $prefillAcrossWorkouts) {
                    Label("Remember an exercise across workouts", systemImage: "arrow.triangle.merge")
                }
                .onChange(of: prefillAcrossWorkouts) { _, _ in
                    // The Watch is sent its own copy of the pre-fill numbers,
                    // so they have to be rebuilt and pushed.
                    store.reloadAll()
                }
            } footer: {
                Text("When on, a wheel opens on the last time you did that exercise, whichever workout you did it in — so splitting or reorganising a routine keeps your numbers. With this off, each workout remembers its own, which suits a heavy day and a light day that share the same exercise.")
            }

            Section {
                NavigationLink {
                    ExerciseDefaultsSettings()
                } label: {
                    Label("Numbers for a new exercise", systemImage: "slider.horizontal.3")
                }
            } footer: {
                Text("The sets, weight range, increment and rest each new exercise starts with. Exercises you already have are not changed.")
            }

            Section {
                NavigationLink {
                    ScheduleSettings()
                } label: {
                    Label("Schedule the next workout", systemImage: "calendar")
                }
            } footer: {
                Text("Whether to be offered, at the end of a workout, to put the next one in your calendar — and how far ahead.")
            }

            Section {
                Picker(selection: $formulaRaw) {
                    ForEach(OneRMFormula.allCases) { f in
                        Text(f.label).tag(f.rawValue)
                    }
                } label: {
                    Label("One-rep max formula", systemImage: "function")
                }
            } header: {
                Text("Statistics")
            } footer: {
                let f = OneRMFormula(rawValue: formulaRaw) ?? .epley
                Text("Estimates what you could lift once from a set of several. \(f.label): \(f.formulaText), where w is the weight and r the repetitions. The graphs and the progress order all follow this choice.")
            }

            Section {
                Stepper(value: $trendWindow, in: ExerciseStats.minimumSessions...50) {
                    LabeledContent("Workouts in the trend", value: "\(trendWindow)")
                }
                Picker(selection: $smoothing) {
                    ForEach(StatsEngine.smoothingChoices, id: \.self) { n in
                        Text(n == 1 ? "off" : "\(n)").tag(n)
                    }
                } label: {
                    Text("Averaging in graphs")
                }
            } footer: {
                Text("The trend uses at most this many of your most recent workouts per exercise, and needs at least \(ExerciseStats.minimumSessions). Averaging smooths the dots on the graph over that many workouts; the trendline itself always follows your actual numbers.")
            }

            Section {
                Toggle(isOn: $shareWithDevelopers) {
                    Label("Share anonymous data with the developer", systemImage: "chart.bar.doc.horizontal")
                }
                .onChange(of: shareWithDevelopers) { _, enabled in
                    DeveloperDataSync.sync(consent: enabled, logs: logs, exercises: exercises,
                                           weightsByLog: LogWeightsIndex.byLogId(logWeights),
                                           formula: OneRMFormula(rawValue: formulaRaw) ?? .epley)
                }
            } footer: {
                // Sharing is invisible by nature — there is nothing on screen
                // to show it working. These lines are the only feedback, and
                // the only diagnosis available on a build with no console.
                if shareWithDevelopers, let status = uploadStatus, !status.isEmpty {
                    Text("Last send: \(status).")
                        .foregroundStyle(.secondary)
                }
                if let problem = uploadProblem, !problem.isEmpty {
                    Text("Some data could not be sent (\(problem)). It will be retried.")
                        .foregroundStyle(.red)
                }
                if let problem = withdrawProblem, !problem.isEmpty {
                    Text("Some shared data could not be taken back (\(problem)). The app will try again next time it opens.")
                        .foregroundStyle(.red)
                }
                Text("Off unless you turn it on. When on, it sends the weights, repetitions and dates you log, and which muscle groups an exercise works, so the app can be improved with real training data — in particular the individual advice being considered. It never sends your name or your exercise names: an exercise you named yourself travels as an unreadable code. Turning this off deletes what this device has shared.")
            }

            Section {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Delete all my data", systemImage: "trash")
                }
            } footer: {
                Text("Deletes all of this app's records, and takes back anything you have shared anonymously.")
            }
        }
        .navigationTitle("settings")
        .confirmationDialog("Delete all data?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete everything", role: .destructive) {
                setup.deleteAllData()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Deletes all of this app's records on this device, and takes back anything you shared anonymously. This cannot be undone.")
        }
    }
}

#Preview("Edit Workouts") {
    let container = try! ModelContainer(for: WorkoutDef.self, ExerciseDef.self, WorkoutLog.self, AerobicResult.self, DraftSession.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = container.mainContext
    let store = AppStore(context: context)
    // Seed sample data
    let w1 = WorkoutDef(name: "Upper Body")
    let w2 = WorkoutDef(name: "Leg Day")
    context.insert(w1)
    context.insert(w2)
    try? context.save()
    store.reloadAll()
    return NavigationStack { EditWorkoutsView() }
        .environmentObject(store)
        .modelContainer(container)
}

#Preview("Edit Workout") {
    let container = try! ModelContainer(for: WorkoutDef.self, ExerciseDef.self, WorkoutLog.self, AerobicResult.self, DraftSession.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = container.mainContext
    let store = AppStore(context: context)
    // Seed workout and exercises
    let e1 = ExerciseDef(name: "Bench Press")
    let e2 = ExerciseDef(name: "Pull-up")
    let workout = WorkoutDef(name: "Upper Body", exerciseOrder: [e1.id, e2.id])
    context.insert(e1)
    context.insert(e2)
    context.insert(workout)
    try? context.save()
    store.reloadAll()
    return NavigationStack { EditWorkoutView(workout: workout) }
        .environmentObject(store)
        .modelContainer(container)
}

#Preview("Edit Exercises") {
    let container = try! ModelContainer(for: WorkoutDef.self, ExerciseDef.self, WorkoutLog.self, AerobicResult.self, DraftSession.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = container.mainContext
    let store = AppStore(context: context)
    // Seed sample exercises
    let e1 = ExerciseDef(name: "Squat")
    let e2 = ExerciseDef(name: "Deadlift")
    context.insert(e1)
    context.insert(e2)
    try? context.save()
    store.reloadAll()
    return NavigationStack { ExerciseLibraryView() }
        .environmentObject(store)
        .modelContainer(container)
}

#Preview("Log Exercise") {
    let container = try! ModelContainer(for: WorkoutDef.self, ExerciseDef.self, WorkoutLog.self, AerobicResult.self, DraftSession.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = container.mainContext
    let store = AppStore(context: context)
    let e1 = ExerciseDef(name: "Curl", numberOfSeries: 3)
    let workout = WorkoutDef(name: "Arms", exerciseOrder: [e1.id])
    context.insert(e1)
    context.insert(workout)
    try? context.save()
    store.reloadAll()
    return NavigationStack { LogExerciseView(workout: workout) }
        .environmentObject(store)
        .modelContainer(container)
}

#Preview("Logs") {
    let container = try! ModelContainer(
        for: WorkoutDef.self, ExerciseDef.self, WorkoutLog.self, AerobicResult.self, DraftSession.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext
    let store = AppStore(context: context)
    // Seed workout, exercises, and a log
    let e1 = ExerciseDef(name: "Curl")
    let e2 = ExerciseDef(name: "Press")
    let workout = WorkoutDef(name: "Mixed", exerciseOrder: [e1.id, e2.id])
    let log1 = WorkoutLog(workoutId: workout.id, exerciseId: e1.id,
                          weights: [10, 12, 12], reps: [12, 10, 8])
    let log2 = WorkoutLog(workoutId: workout.id, exerciseId: e2.id,
                          weights: [20, 22, 24], reps: [10, 10, 8])

    context.insert(e1)
    context.insert(e2)
    context.insert(workout)
    context.insert(log1)
    context.insert(log2)
    try? context.save()
    store.reloadAll()

    return NavigationStack { LogsStatsView() }
        .environmentObject(store)
        .modelContainer(container)
}

import UIKit
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

extension URL: @retroactive Identifiable {
    public var id: URL { self }
}

