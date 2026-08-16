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

            LabeledContent {
                TextField("", value: $exercise.lowestWeight, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
            } label: { Text("Lowest weight") }

            LabeledContent {
                TextField("", value: $exercise.highestWeight, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
            } label: { Text("Highest weight") }

            LabeledContent {
                TextField("", value: $exercise.weightIncrement, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
            } label: { Text("Weight increment") }
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
        .onChange(of: exercise.lowestWeight) { _, newValue in
            if newValue < 1 { exercise.lowestWeight = 1 }
            if exercise.highestWeight < newValue { exercise.highestWeight = newValue }
        }
        .onChange(of: exercise.highestWeight) { _, newValue in
            if newValue < 1 { exercise.highestWeight = 1 }
            if newValue < exercise.lowestWeight { exercise.lowestWeight = newValue }
        }
        .onChange(of: exercise.weightIncrement) { _, newValue in
            if newValue < 1 { exercise.weightIncrement = 1 }
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
    @ObservedObject private var restTimer = RestTimer.shared
    @ObservedObject private var aerobic = AerobicCountdown.shared
    /// Every aerobic result, to pre-fill the wheel with what was done last
    /// time — the same courtesy the weight wheels have always paid.
    @Query private var aerobicResults: [AerobicResult]

    @State private var startedAt = Date()
    @State private var currentIndex: Int = 0
    @State private var weights: [[Int]] = []
    @State private var reps: [[Int]] = []

    @State private var loggedIndices: Set<Int> = []
    /// What the wheel is set to, per exercise: how long you mean to go.
    @State private var durations: [Int] = []
    /// What was actually done, per exercise; 0 until a session has run.
    ///
    /// Kept apart from the wheel deliberately. Folding the two together meant
    /// stopping twenty seconds into an eighteen-minute row rewrote the wheel to
    /// "1" — the wheel counts whole minutes and cannot say twenty seconds — so
    /// the number you had chosen was destroyed by the act of measuring it.
    @State private var actualSeconds: [Int] = []
    @State private var showAllLoggedAlert = false
    @State private var dragOffsetX: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    private enum DragDirection { case horizontal, vertical }
    @State private var dragDirection: DragDirection? = nil
    @State private var isPaging: Bool = false

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
                .offset(x: dragOffsetX)
                .padding()
                .modifier(RestSettleAcknowledgement(height: geo.size.height))
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
        .navigationTitle("log exercise")
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: $showAllLoggedAlert) {
            allLoggedSheet
        }
        // Covers the whole screen on purpose: during a rest there is nothing to
        // do here, and a countdown squeezed in beside the wheels is the kind of
        // thing you stop noticing. "skip rest" is the way out.
        .fullScreenCover(isPresented: Binding(
            get: { restTimer.isShowing },
            set: { shown in if !shown, restTimer.isShowing { restTimer.skip() } }
        )) {
            RestCountdownView()
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
        SessionSnapshot(workoutId: workout.id.uuidString,
                        currentIndex: currentIndex,
                        weights: weights,
                        reps: reps,
                        loggedIndices: Array(loggedIndices),
                        startedAt: startedAt.timeIntervalSince1970)
    }

    private func adopt(_ snap: SessionSnapshot) {
        weights       = snap.weights
        reps          = snap.reps
        loggedIndices = Set(snap.loggedIndices)
        startedAt     = Date(timeIntervalSince1970: snap.startedAt)
        ensureBufferShape()
        // Clamp: a stale snapshot may point past the current exercise list.
        currentIndex  = min(max(0, snap.currentIndex),
                            max(0, exerciseIds.count - 1))
    }

    private func startOrAdoptSession() {
        if let snap = handoff.takeAdoptSnapshot(for: workout.id.uuidString) {
            // Opened via handover (the app came forward into an active session).
            adopt(snap)
            handoff.updateLiveSnapshot(currentSnapshot())
        } else {
            // Opened by tapping the workout — become the driver, adopting the
            // other device's state if it was already in this same workout.
            startedAt = Date()
            handoff.enterSession(workoutId: workout.id.uuidString,
                                 current: currentSnapshot()) { snap in adopt(snap) }
        }
    }

    private func pageContent(exercise: ExerciseDef?) -> some View {
        VStack(spacing: 4) {
            buttonRow
            Text(exercise?.name ?? "").font(.title2).bold()
            if let exercise {
                if exercise.kind == .aerobic {
                    aerobicContent(for: exercise)
                } else {
                    Text("weight used").font(.system(size: 18)).frame(maxWidth: .infinity, alignment: .leading)
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
                handoff.finishWorkoutHere(startedAt: startedAt, endedAt: endedAt)
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

            // Quitting early still ends the workout, so it is recorded too
            // (finishWorkoutHere skips it when no set was logged).
            Button("quit") {
                let endedAt = Date()
                onEndSession()
                handoff.leaveSession()
                handoff.finishWorkoutHere(startedAt: startedAt, endedAt: endedAt)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Menu("list") {
                ForEach(exerciseIds.indices, id: \.self) { idx in
                    let exercise = exerciseAt(idx)
                    Button(exercise?.name ?? "") { currentIndex = idx }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    @State private var pickerHeight: CGFloat = 180

    private func weightPickers(for exercise: ExerciseDef) -> some View {
        let weightOptions = Array(stride(from: exercise.lowestWeight, through: exercise.highestWeight, by: exercise.weightIncrement))
        let count = max(1, exercise.numberOfSeries)
        return HStack(spacing: wheelSpacing) {
            ForEach(0..<count, id: \.self) { series in
                Picker("", selection: weightBinding(series: series, defaultValue: exercise.lowestWeight)) {
                    ForEach(weightOptions, id: \.self) { weight in
                        Text("\(weight)").tag(weight)
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

        if currentIndex < actualSeconds.count, actualSeconds[currentIndex] > 0 {
            Text("done: \(AerobicDefaults.label(actualSeconds[currentIndex]))")
                .font(.footnote)
                .bold()
        } else if let done = lastRecorded(for: exercise) {
            Text("last time: \(AerobicDefaults.label(done))")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        Spacer(minLength: 0)
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
            }
        )
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .local)
            .onChanged { value in
                let translation = value.translation
                if dragDirection == nil {
                    let directionSlop: CGFloat = 8
                    if abs(translation.width) > directionSlop || abs(translation.height) > directionSlop {
                        dragDirection = abs(translation.width) > abs(translation.height) ? .horizontal : .vertical
                        isPaging = (dragDirection == .horizontal)
                    }
                }
                dragOffsetX = dragDirection == .horizontal ? translation.width : 0
            }
            .onEnded { value in
                defer {
                    dragDirection = nil
                    isPaging = false
                }
                guard dragDirection == .horizontal else {
                    withAnimation(.easeOut(duration: 0.2)) { dragOffsetX = 0 }
                    return
                }

                let threshold: CGFloat = 80
                let horizontal = value.translation.width

                // Swiping to another exercise is still working, not resting:
                // push the cover out so it does not land mid-swipe.
                if abs(horizontal) >= threshold { restTimer.stillBusy() }

                if horizontal <= -threshold {
                    withAnimation(.easeInOut(duration: 0.22)) { dragOffsetX = -containerWidth }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                        goToNextUnlogged()
                        dragOffsetX = containerWidth
                        withAnimation(.easeInOut(duration: 0.22)) { dragOffsetX = 0 }
                    }
                } else if horizontal >= threshold {
                    withAnimation(.easeInOut(duration: 0.22)) { dragOffsetX = containerWidth }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                        goToPrevUnlogged()
                        dragOffsetX = -containerWidth
                        withAnimation(.easeInOut(duration: 0.22)) { dragOffsetX = 0 }
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.2)) { dragOffsetX = 0 }
                }
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
        weights = exerciseIds.map { exId in last[exId]?.weights ?? [] }
        reps = exerciseIds.map { exId in last[exId]?.reps ?? [] }
        // Pre-filled from the last session of each aerobic exercise, so the
        // wheel opens where it was left, exactly like the weight wheels.
        durations = exerciseIds.map { exId in
            guard let log = last[exId],
                  let result = aerobicResults.first(where: { $0.logId == log.id })
            else { return AerobicDefaults.defaultMinutes * 60 }
            return result.durationSeconds
        }
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
    }

    private func setWeight(_ value: Int, series: Int) {
        ensureSeriesCapacity(&weights[currentIndex], upTo: series, fill: exerciseAt(currentIndex)?.lowestWeight ?? 0)
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
        guard let ex = exerciseAt(currentIndex) else {
            // The exercise was deleted but the workout still references it, so
            // there is nothing to log. Never dead-end the button: treat it as
            // handled and either move on or end the workout.
            loggedIndices.insert(currentIndex)
            if loggedIndices.count >= exerciseIds.count {
                let endedAt = Date()
                onEndSession()
                handoff.leaveSession()
                handoff.finishWorkoutHere(startedAt: startedAt, endedAt: endedAt)
            } else {
                goToNextUnlogged()
            }
            return
        }
        // If this is the last unlogged exercise, log and dismiss immediately
        if loggedIndices.count + 1 >= exerciseIds.count {
            loggedIndices.insert(currentIndex)
            let log = WorkoutLog(workoutId: workout.id,
                                 exerciseId: ex.id,
                                 weights: weights[currentIndex],
                                 reps: reps[currentIndex])
            context.insert(log)
            recordAerobicResult(for: ex, log: log)
            handoff.noteActivity()
            // Pop first, then end the session and record to Health.
            let endedAt = Date()
            onEndSession()
            handoff.leaveSession()
            handoff.finishWorkoutHere(startedAt: startedAt, endedAt: endedAt)
            return
        }
        loggedIndices.insert(currentIndex)
        let log = WorkoutLog(workoutId: workout.id,
                             exerciseId: ex.id,
                             weights: weights[currentIndex],
                             reps: reps[currentIndex])
        context.insert(log)
        recordAerobicResult(for: ex, log: log)
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
        goToNextUnlogged()
        if !wasAerobic {
            restTimer.setFinished(exercise: restName, seconds: restAfter)
        }
    }

    /// Store what an aerobic session measured beside the log that records it.
    /// Nothing is written for a strength exercise, and nothing for an aerobic
    /// one that was never actually run.
    private func recordAerobicResult(for exercise: ExerciseDef, log: WorkoutLog) {
        guard exercise.kind == .aerobic else { return }
        // What was actually done, if a session ran. Otherwise what the wheel
        // says: someone may have used the machine's own timer and only wants
        // it written down, which is no less a record than the rest of this app.
        let measured = currentIndex < actualSeconds.count ? actualSeconds[currentIndex] : 0
        let seconds = measured > 0 ? measured : durationSeconds(at: currentIndex)
        guard seconds > 0 else { return }

        // Heart rate belongs to a session that actually ran, and only to the
        // exercise that ran it. The countdown keeps its readings until the next
        // session starts, so a second aerobic exercise logged straight off the
        // wheel would otherwise inherit the first one's heart rate and claim to
        // have measured something it never did.
        let ranASession = measured > 0
        context.insert(AerobicResult(
            logId: log.id,
            durationSeconds: seconds,
            averageHeartRate: ranASession ? aerobic.averageHeartRate : 0,
            maximumHeartRate: ranASession ? aerobic.maximumHeartRate : 0,
            zoneSeconds: ranASession ? aerobic.zoneSeconds : []))
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

// MARK: - Logs Screen
// MARK: - logs tab
//
// The log list. Import/export lives in ImportExportView; both are tabs of
// LogsStatsView now.

struct LogsListView: View {
    @Query(sort: [SortDescriptor(\WorkoutLog.date, order: .reverse)]) private var logs: [WorkoutLog]
    @Query private var workouts: [WorkoutDef]
    @Query private var exercises: [ExerciseDef]

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

    private func weightsRepsGrid(for log: WorkoutLog, at date: Date) -> some View {
        let previous = previousEntry(for: log.exerciseId, before: date)
        let maxCount = max(log.weights.count, log.reps.count)
        return Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
            GridRow {
                Text("w").font(.headline)
                ForEach(0..<maxCount, id: \.self) { i in
                    let current = i < log.weights.count ? log.weights[i] : 0
                    let prev = previous?.weights.indices.contains(i) == true ? previous!.weights[i] : nil
                    Text("\(current)")
                        .foregroundStyle(colorForWeight(current: current, previous: prev))
                        .font(.headline)
                }
            }
            GridRow {
                Text("r").font(.headline)
                ForEach(0..<maxCount, id: \.self) { i in
                    let current = i < log.reps.count ? log.reps[i] : 0
                    let prevRep = previous?.reps.indices.contains(i) == true ? previous!.reps[i] : nil
                    let currentW = i < log.weights.count ? log.weights[i] : 0
                    let prevW = previous?.weights.indices.contains(i) == true ? previous!.weights[i] : nil
                    Text("\(current)")
                        .foregroundStyle(colorForReps(current: current, previous: prevRep, currentWeight: currentW, previousWeight: prevW))
                        .font(.headline)
                }
            }
        }
    }

    private func previousEntry(for exerciseId: UUID, before date: Date) -> WorkoutLog? {
        // Search older logs (since logs are reverse sorted)
        for log in logs.dropFirst() {
            if log.date < date && log.exerciseId == exerciseId {
                return log
            }
        }
        return nil
    }

    private func colorForWeight(current: Int, previous: Int?) -> Color {
        guard let previous else { return .primary }
        if current > previous { return .green }
        if current < previous { return .red }
        return .primary
    }

    private func colorForReps(current: Int, previous: Int?, currentWeight: Int, previousWeight: Int?) -> Color {
        guard let previous else { return .primary }
        let prevWeight = previousWeight ?? currentWeight
        if current > previous && currentWeight >= prevWeight { return .green }
        if current < previous && currentWeight <= prevWeight { return .red }
        return .primary
    }
}

// MARK: - import/export tab

struct ImportExportView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.modelContext) private var context

    @Query(sort: [SortDescriptor(\WorkoutLog.date, order: .reverse)]) private var logs: [WorkoutLog]
    @Query private var workouts: [WorkoutDef]
    @Query private var exercises: [ExerciseDef]

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
            exportVersion: "logJSON.2",
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
                logs: logs
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
        if version == "logJSON.2" {
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
                }
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

            Section {
                Toggle(isOn: $healthSharingEnabled) {
                    Label("Save workouts to Apple Health", systemImage: "heart.fill")
                }
                .onChange(of: healthSharingEnabled) { _, enabled in
                    if enabled { HealthWorkoutLogger.shared.requestAuthorization() }
                    // Let the Watch know whether to record to Health too.
                    store.reloadAll()
                }
            } footer: {
                Text("When on, a finished workout is saved to Apple Health as a Traditional Strength Training session, with its total duration — including time handed over between iPhone and Apple Watch. Only the workout duration is shared; nothing is read from Health.")
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
            } footer: {
                Text("When on, a rest is counted after every set and after each exercise you log, for as long as that exercise is set to. You can leave the app while it runs: a notification arrives when the rest is over, and an Apple Watch that was nearby when the rest started taps your wrist as well. With this off, the app works exactly as before.")
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
    let container = try! ModelContainer(for: WorkoutDef.self, ExerciseDef.self, WorkoutLog.self, AerobicResult.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
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
    let container = try! ModelContainer(for: WorkoutDef.self, ExerciseDef.self, WorkoutLog.self, AerobicResult.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
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
    let container = try! ModelContainer(for: WorkoutDef.self, ExerciseDef.self, WorkoutLog.self, AerobicResult.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
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
    let container = try! ModelContainer(for: WorkoutDef.self, ExerciseDef.self, WorkoutLog.self, AerobicResult.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
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
        for: WorkoutDef.self, ExerciseDef.self, WorkoutLog.self, AerobicResult.self,
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

