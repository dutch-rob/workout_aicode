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

    private var isWorkoutValid: Bool {
        !workout.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Buttons row under title
            HStack(spacing: 12) {
                Button {
                    let exercise = ExerciseDef(name: "")
                    store.saveExercise(exercise)
                    workout.exerciseOrder.append(exercise.id)
                    pendingNewExercise = exercise
                } label: {
                    Text("new exercise").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                if workout.exerciseOrder.count >= 2 {
                    NavigationLink {
                        ReorderExercisesView(workout: workout)
                    } label: {
                        Text("reorder exercises").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }

            Form {
                Section(header: Text("Workout name")) {
                    TextField("Workout name", text: $workout.name)
                }
                Section(header: Text("Exercises")) {
                    ForEach(workout.exerciseOrder.indices, id: \.self) { idx in
                        let current = allExercises.first(where: { $0.id == workout.exerciseOrder[idx] })
                        HStack(spacing: 12) {
                            DeleteCircleButton { workout.exerciseOrder.remove(at: idx) }

                            Menu {
                                ForEach(allExercises) { choice in
                                    Button(choice.name) { workout.exerciseOrder[idx] = choice.id }
                                }
                            } label: {
                                HStack {
                                    Text(current?.name ?? "Select exercise")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }

                    if !allExercises.isEmpty {
                        Menu {
                            ForEach(allExercises) { choice in
                                Button(choice.name) {
                                    workout.exerciseOrder.append(choice.id)
                                }
                            }
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle")
                                Text("Add exercise")
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .navigationTitle("edit workout")
        .navigationDestination(item: $pendingNewExercise) { exercise in
            EditExerciseView(exercise: exercise)
        }
        .toolbar { }
    }

    @Query private var allExercises: [ExerciseDef]
}

// MARK: - Reorder Exercises Screen
struct ReorderExercisesView: View {
    @EnvironmentObject private var store: AppStore
    @Bindable var workout: WorkoutDef
    @State private var editMode: EditMode = .active

    var body: some View {
        List {
            ForEach(workout.exerciseOrder.indices, id: \.self) { idx in
                let name = exerciseName(for: workout.exerciseOrder[idx])
                Text(name)
            }
            .onMove { indices, newOffset in
                var order = workout.exerciseOrder
                order.move(fromOffsets: indices, toOffset: newOffset)
                workout.exerciseOrder = order
            }
        }
        .environment(\.editMode, $editMode)
        .navigationTitle("reorder")
    }

    @Query private var allExercises: [ExerciseDef]
    private func exerciseName(for id: UUID) -> String {
        return allExercises.name(for: id)
    }
}


// MARK: - Edit Exercises Screen
struct EditExercisesView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    
    @State private var showDeleteConfirm = false
    @State private var exercisePendingDelete: ExerciseDef?
    @State private var editMode: EditMode = .inactive
    @State private var pendingNewExercise: ExerciseDef? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    let exercise = ExerciseDef(name: "")
                    store.saveExercise(exercise)
                    pendingNewExercise = exercise
                } label: {
                    Text("new exercise").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            if store.exercises.isEmpty {
                ContentUnavailableView("No exercises to edit", systemImage: "list.bullet")
            } else {
                List {
                    Section {
                        ForEach(store.exercises) { exercise in
                            HStack(spacing: 12) {
                                if editMode == .active {
                                    // Reorder mode: show title; system shows drag handles
                                    Text(exercise.name)
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                } else {
                                    // Normal mode: make the whole row a NavigationLink to edit
                                    NavigationLink(destination: EditExerciseView(exercise: exercise)) {
                                        HStack(spacing: 12) {
                                            // Place a red delete button on the left to mimic reorder screen placement
                                            DeleteCircleButton {
                                                exercisePendingDelete = exercise
                                                showDeleteConfirm = true
                                            }

                                            Text(exercise.name)
                                                .lineLimit(1)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                    }
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    exercisePendingDelete = exercise
                                    showDeleteConfirm = true
                                } label: { Label("Delete", systemImage: "trash") }
                            }
                        }
                        .onDelete { indexSet in
                            for idx in indexSet {
                                let exercise = store.exercises[idx]
                                exercisePendingDelete = exercise
                                showDeleteConfirm = true
                            }
                        }
                    }
                }
                .environment(\.editMode, $editMode)
            }
        }
        .padding()
        .navigationTitle("edit exercises")
        .navigationDestination(item: $pendingNewExercise) { exercise in
            EditExerciseView(exercise: exercise)
        }
        .onAppear { store.reloadAll() }
        .confirmationDialog("Delete Exercise?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let exercise = exercisePendingDelete {
                    store.deleteExercise(exercise)
                }
                exercisePendingDelete = nil
            }
            Button("Cancel", role: .cancel) { exercisePendingDelete = nil }
        } message: {
            Text("Are you sure you want to delete this exercise?")
        }
    }
}

// MARK: - Edit Exercise Screen
struct EditExerciseView: View {
    @Bindable var exercise: ExerciseDef

    var body: some View {
        Form {
            TextField("Exercise name", text: $exercise.name)

            LabeledContent {
                Stepper(value: $exercise.numberOfSeries, in: 1...10) {
                    Text("\(exercise.numberOfSeries)")
                }
            } label: { Text("Number of series") }

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
    }
}

// MARK: - Log Exercise Screen
struct LogExerciseView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allExercises: [ExerciseDef]

    let workout: WorkoutDef

    @State private var currentIndex: Int = 0
    @State private var weights: [[Int]] = []
    @State private var reps: [[Int]] = []

    @State private var loggedIndices: Set<Int> = []
    @State private var showAllLoggedAlert = false
    @State private var dragOffsetX: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    private enum DragDirection { case horizontal, vertical }
    @State private var dragDirection: DragDirection? = nil
    @State private var isPaging: Bool = false

    private var isLastUnlogged: Bool {
        let total = workout.exerciseOrder.count
        // If after adding currentIndex, loggedIndices count would equal total, means last unlogged
        return loggedIndices.count == total - 1 && !loggedIndices.contains(currentIndex)
    }

    var body: some View {
        let exercise = exerciseAt(currentIndex)
        GeometryReader { geo in
            let width = geo.size.width
            VStack(spacing: 4) {
                buttonRow
                Text(exercise?.name ?? "").font(.title2).bold()
                if let exercise {
                    Text("weight used").font(.system(size: 18)).frame(maxWidth: .infinity, alignment: .leading)
                    weightPickers(for: exercise)
                    Text("repetitions").font(.system(size: 18)).frame(maxWidth: .infinity, alignment: .leading)
                    repsPickers(for: exercise)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .contentShape(Rectangle())
            .offset(x: dragOffsetX)
            .padding()
            .onAppear {
                containerWidth = width
                pickerHeight = max(160, (geo.size.height - 220) / 2)
                prepareBuffers()
            }
            .onChange(of: geo.size.width) { _, newWidth in
                containerWidth = newWidth
            }
            .onChange(of: geo.size.height) { _, newHeight in
                pickerHeight = max(160, (newHeight - 220) / 2)
            }
            .simultaneousGesture(dragGesture)
        }
        .navigationTitle("log exercise")
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: $showAllLoggedAlert) {
            VStack(spacing: 20) {
                Text("All exercises logged")
                    .font(.title2)
                    .bold()
                Button {
                    dismiss()
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

            Button("quit") { dismiss() }
                .buttonStyle(.bordered)
                .controlSize(.large)

            Menu("list") {
                ForEach(workout.exerciseOrder.indices, id: \.self) { idx in
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
        return VStack(spacing: 0) {
            Divider()
            GeometryReader { proxy in
                let count = max(1, exercise.numberOfSeries)
                HStack(spacing: 0) {
                    ForEach(0..<count, id: \.self) { series in
                        Picker("", selection: weightBinding(series: series, defaultValue: exercise.lowestWeight)) {
                            ForEach(weightOptions, id: \.self) { weight in
                                Text("\(weight)").tag(weight)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(width: proxy.size.width / CGFloat(count), height: pickerHeight)
                    }
                }
            }
            .frame(height: pickerHeight)
            Divider()
        }
    }

    private func repsPickers(for exercise: ExerciseDef) -> some View {
        VStack(spacing: 0) {
            Divider()
            GeometryReader { proxy in
                let count = max(1, exercise.numberOfSeries)
                HStack(spacing: 0) {
                    ForEach(0..<count, id: \.self) { series in
                        Picker("", selection: repsBinding(series: series)) {
                            ForEach(0...200, id: \.self) { reps in Text("\(reps)").tag(reps) }
                        }
                        .pickerStyle(.wheel)
                        .frame(width: proxy.size.width / CGFloat(count), height: pickerHeight)
                    }
                }
            }
            .frame(height: pickerHeight)
            Divider()
        }
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
        guard index >= 0 && index < workout.exerciseOrder.count else { return nil }
        let id = workout.exerciseOrder[index]
        return allExercises.first(where: { $0.id == id })
    }

    private func prepareBuffers() {
        let last = store.lastEntries(for: workout)
        weights = workout.exerciseOrder.map { exId in last[exId]?.weights ?? [] }
        reps = workout.exerciseOrder.map { exId in last[exId]?.reps ?? [] }
    }

    private func setWeight(_ value: Int, series: Int) {
        ensureSeriesCapacity(&weights[currentIndex], upTo: series, fill: exerciseAt(currentIndex)?.lowestWeight ?? 0)
        weights[currentIndex][series] = value
    }

    private func setRep(_ value: Int, series: Int) {
        ensureSeriesCapacity(&reps[currentIndex], upTo: series, fill: 0)
        reps[currentIndex][series] = value
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
        guard let ex = exerciseAt(currentIndex) else { return }
        // If this is the last unlogged exercise, log and dismiss immediately
        if loggedIndices.count + 1 >= workout.exerciseOrder.count {
            loggedIndices.insert(currentIndex)
            let log = WorkoutLog(workoutId: workout.id,
                                 exerciseId: ex.id,
                                 weights: weights[currentIndex],
                                 reps: reps[currentIndex])
            context.insert(log)
            dismiss()
            return
        }
        loggedIndices.insert(currentIndex)
        let log = WorkoutLog(workoutId: workout.id,
                             exerciseId: ex.id,
                             weights: weights[currentIndex],
                             reps: reps[currentIndex])
        context.insert(log)

        guard loggedIndices.count < workout.exerciseOrder.count else {
            // All logged, present an alert
            showAllLoggedAlert = true
            return
        }

        goToNextUnlogged()
    }

    private func goToNextUnlogged() {
        let count = max(1, workout.exerciseOrder.count)
        var next = (currentIndex + 1) % count
        while loggedIndices.contains(next) && loggedIndices.count < count {
            next = (next + 1) % count
        }
        currentIndex = next
    }

    private func goToPrevUnlogged() {
        let count = max(1, workout.exerciseOrder.count)
        var prev = (currentIndex - 1 + count) % count
        while loggedIndices.contains(prev) && loggedIndices.count < count {
            prev = (prev - 1 + count) % count
        }
        currentIndex = prev
    }
}

// MARK: - Logs Screen
struct LogsView: View {
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
        Group {
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
                .padding(.bottom, 8)

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
        }
        .navigationTitle("logs")
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

    struct CompactRow: Identifiable {
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

struct SettingsView: View {
    @AppStorage("iCloudSyncEnabled") private var iCloudSyncEnabled = false
    @EnvironmentObject private var setup: AppSetup
    @State private var showDeleteConfirm = false

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $iCloudSyncEnabled) {
                    Label("Share data among your iPhones/iPads", systemImage: "icloud")
                }
            } footer: {
                Text("Syncs your workouts, exercises, and logs across all your iPhones and iPads signed into the same iCloud account and that have this option turned on. Changes take effect immediately.")
            }

            Section {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Delete all my data", systemImage: "trash")
                }
            } footer: {
                Text("Deletes all of this app's records.")
            }
        }
        .navigationTitle("settings")
        .confirmationDialog("Delete all data?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete everything", role: .destructive) {
                setup.deleteAllData()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Deletes all of this app's records. This cannot be undone.")
        }
    }
}

#Preview("Edit Workouts") {
    let container = try! ModelContainer(for: WorkoutDef.self, ExerciseDef.self, WorkoutLog.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
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
    let container = try! ModelContainer(for: WorkoutDef.self, ExerciseDef.self, WorkoutLog.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
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
    let container = try! ModelContainer(for: WorkoutDef.self, ExerciseDef.self, WorkoutLog.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = container.mainContext
    let store = AppStore(context: context)
    // Seed sample exercises
    let e1 = ExerciseDef(name: "Squat")
    let e2 = ExerciseDef(name: "Deadlift")
    context.insert(e1)
    context.insert(e2)
    try? context.save()
    store.reloadAll()
    return NavigationStack { EditExercisesView() }
        .environmentObject(store)
        .modelContainer(container)
}

#Preview("Log Exercise") {
    let container = try! ModelContainer(for: WorkoutDef.self, ExerciseDef.self, WorkoutLog.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
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
        for: WorkoutDef.self, ExerciseDef.self, WorkoutLog.self,
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

    return NavigationStack { LogsView() }
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

