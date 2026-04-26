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
    @State private var navigateToNewWorkout: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    let w = WorkoutDef(name: "")
                    store.saveWorkout(w)
                    pendingNewWorkout = w
                    navigateToNewWorkout = true }

                label: {
                    Text("new workout")
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button {
                    editMode = (editMode == .active ? .inactive : .active)
                }
                label: {
                    Text(editMode == .active ? "end reorder" : "reorder workouts")
                    .frame(maxWidth: .infinity)}

                .buttonStyle(.bordered)
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
                                let w = store.workouts[idx]
                                workoutPendingDelete = w
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
        .navigationDestination(isPresented: $navigateToNewWorkout) {
            if let w = pendingNewWorkout {
                EditWorkoutView(workout: w)
            } else {
                EmptyView()
            }
        }
        .confirmationDialog("Delete Workout?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let w = workoutPendingDelete {
                    store.deleteWorkout(w)
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
    @State private var navigateToNewExercise: Bool = false

    private var isWorkoutValid: Bool {
        !workout.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Buttons row under title
            HStack(spacing: 12) {
                Button {
                    let ex = ExerciseDef(name: "")
                    store.saveExercise(ex)
                    // Append to this workout's exercise order as last
                    workout.exerciseOrder.append(ex.id)
                    pendingNewExercise = ex
                    navigateToNewExercise = true
                }
                label: {
                    Text("new exercise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                NavigationLink {
                    ReorderExercisesView(workout: workout)
                }
                label: {
                    Text("reorder exercises")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

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

                    // Add exercise row at the bottom
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
        .navigationTitle("edit workout")
        .navigationDestination(isPresented: $navigateToNewExercise) {
            if let ex = pendingNewExercise {
                EditExerciseView(exercise: ex)
            } else {
                EmptyView()
            }
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
    @State private var navigateToNewExercise: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    let ex = ExerciseDef(name: "")
                    store.saveExercise(ex)
                    pendingNewExercise = ex
                    navigateToNewExercise = true
                    
                } label: { Text("new exercise")
                    .frame(maxWidth: .infinity)}
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
                                let ex = store.exercises[idx]
                                exercisePendingDelete = ex
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
        .navigationDestination(isPresented: $navigateToNewExercise) {
            if let ex = pendingNewExercise {
                EditExerciseView(exercise: ex)
            } else {
                EmptyView()
            }
        }
        .onAppear { store.reloadAll() }
        .confirmationDialog("Delete Exercise?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let ex = exercisePendingDelete {
                    store.deleteExercise(ex)
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
    @EnvironmentObject private var store: AppStore
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Bindable var exercise: ExerciseDef
    @State private var hasInserted = false

    private var isExerciseValid: Bool {
        let nameOK = !exercise.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let incrementOK = exercise.weightIncrement >= 1
        let rangeOK = exercise.lowestWeight <= exercise.highestWeight
        return nameOK && incrementOK && rangeOK
    }

    var body: some View {
        Form {
            TextField("Exercise name", text: $exercise.name)
            LabeledContent {
                Stepper(value: $exercise.numberOfSeries, in: 0...200) {
                    Text("\(exercise.numberOfSeries)")
                }
            } label: { Text("Number of series") }
            LabeledContent {
                Stepper(value: $exercise.lowestWeight, in: 0...2000) {
                    Text("\(exercise.lowestWeight)")
                }
            } label: { Text("Lowest weight") }
            LabeledContent {
                Stepper(value: $exercise.highestWeight, in: 0...2000) {
                    Text("\(exercise.highestWeight)")
                }
            } label: { Text("Highest weight") }
            LabeledContent {
                Stepper(value: $exercise.weightIncrement, in: 1...200) {
                    Text("\(exercise.weightIncrement)")
                }
            } label: { Text("Weight increment") }
        }
        .onChange(of: exercise.lowestWeight) { _, newValue in
            if exercise.highestWeight < newValue { exercise.highestWeight = newValue }
        }
        .onChange(of: exercise.highestWeight) { _, newValue in
            if newValue < exercise.lowestWeight { exercise.lowestWeight = newValue }
        }
        .onChange(of: exercise.weightIncrement) { _, newValue in
            if newValue < 1 { exercise.weightIncrement = 1 }
        }
        .navigationTitle("edit exercise")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    store.saveExercise(exercise)
                    dismiss()
                }
                .disabled(!isExerciseValid)
            }
        }
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

    var body: some View {
        let exercise = exerciseAt(currentIndex)
        GeometryReader { geo in
            let width = geo.size.width
            VStack(spacing: 16) {
                
                HStack {
                    Button("log, next") { logAndNext() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    Button("quit") { dismiss() }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    Menu("list") {
                        ForEach(workout.exerciseOrder.indices, id: \.self) { idx in
                            let ex = exerciseAt(idx)
                            Button(ex?.name ?? "") { currentIndex = idx }
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }

                Text(exercise?.name ?? "").font(.title2).bold()

                Text("weight used").font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                if let exercise = exercise {
                    let weightOptions = Array(stride(from: exercise.lowestWeight, through: exercise.highestWeight, by: exercise.weightIncrement))
                    GeometryReader { proxy in
                        let totalWidth = proxy.size.width - 16
                        let count = max(1, exercise.numberOfSeries)
                        let column = max(100, totalWidth / CGFloat(count))
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(0..<count, id: \.self) { series in
                                    Picker("", selection: weightBinding(series: series, defaultValue: exercise.lowestWeight)) {
                                        ForEach(weightOptions, id: \.self) { w in
                                            Text("\(w)").tag(w)
                                        }
                                    }
                                    .pickerStyle(.wheel)
                                    .frame(width: column, height: max(240, proxy.size.height * 0.4))
                                }
                            }
                        }
                        .scrollDisabled(isPaging)
                    }
                    .frame(height: 260)

                    Text("repetitions").font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                    GeometryReader { proxy in
                        let totalWidth = proxy.size.width - 16
                        let count = max(1, exercise.numberOfSeries)
                        let column = max(100, totalWidth / CGFloat(count))
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(0..<count, id: \.self) { series in
                                    Picker("", selection: repsBinding(series: series)) {
                                        ForEach(0...200, id: \.self) { r in Text("\(r)").tag(r) }
                                    }
                                    .pickerStyle(.wheel)
                                    .frame(width: column, height: max(240, proxy.size.height * 0.4))
                                }
                            }
                        }
                        .scrollDisabled(isPaging)
                    }
                    .frame(height: 260)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .contentShape(Rectangle())
            .offset(x: dragOffsetX)
            .padding()
            .onAppear {
                containerWidth = width
                prepareBuffers()
            }
            .onChange(of: geo.size.width) { _, newW in
                containerWidth = newW
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 10, coordinateSpace: .local)
                    .onChanged { value in
                        let t = value.translation
                        if dragDirection == nil {
                            let slop: CGFloat = 8
                            if abs(t.width) > slop || abs(t.height) > slop {
                                dragDirection = abs(t.width) > abs(t.height) ? .horizontal : .vertical
                                isPaging = (dragDirection == .horizontal)
                            }
                        }
                        if dragDirection == .horizontal {
                            dragOffsetX = t.width
                        } else {
                            // vertical or undecided: keep the page in place so pickers can scroll
                            dragOffsetX = 0
                        }
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
                            withAnimation(.easeInOut(duration: 0.22)) {
                                dragOffsetX = -containerWidth
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                                goToNextUnlogged()
                                dragOffsetX = containerWidth
                                withAnimation(.easeInOut(duration: 0.22)) {
                                    dragOffsetX = 0
                                }
                            }
                        } else if horizontal >= threshold {
                            withAnimation(.easeInOut(duration: 0.22)) {
                                dragOffsetX = containerWidth
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                                goToPrevUnlogged()
                                dragOffsetX = -containerWidth
                                withAnimation(.easeInOut(duration: 0.22)) {
                                    dragOffsetX = 0
                                }
                            }
                        } else {
                            withAnimation(.easeOut(duration: 0.2)) { dragOffsetX = 0 }
                        }
                    }
            )
        }
        .navigationTitle("log exercise")
        .navigationBarBackButtonHidden(true)
        .alert("All exercises logged", isPresented: $showAllLoggedAlert) {
            Button("View only", role: .cancel) { /* stay on current */ }
            Button("Overwrite") { loggedIndices.remove(currentIndex) }
            Button("Done") { dismiss() }
        } message: {
            Text("You have logged all exercises. What would you like to do?")
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
        loggedIndices.insert(currentIndex)
        let entry = ExerciseLogEntry(exerciseId: ex.id, weights: weights[currentIndex], reps: reps[currentIndex])
        let log = WorkoutLog(workoutId: workout.id, entries: [entry])
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

    @Query(sort: [SortDescriptor(\WorkoutLog.date, order: .reverse)]) private var logs: [WorkoutLog]
    @Query private var workouts: [WorkoutDef]
    @Query private var exercises: [ExerciseDef]
    
    @State private var exportURL: URL?

    var body: some View {
        Group {
            if logs.isEmpty {
                ContentUnavailableView("No logs yet", systemImage: "doc.text", description: Text("Start logging your workouts to see them here."))
            } else {
                List(compactRows()) { row in
                    VStack(spacing: 2) {
                        // Single separator above content
                        Rectangle()
                            .fill(Color.secondary.opacity(1.0))
                            .frame(height: row.isWorkout ? 3 : 1)
                        // Row content
                        HStack(alignment: .center, spacing: 8) {
                            // Column 1
                            Group {
                                if row.isWorkout {
                                    Text(row.left)
                                        .font(.headline)
                                        .foregroundStyle(.blue)
                                        .italic()
                                } else {
                                    Text(row.left)
                                        .font(.headline)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            // Column 2
                            row.rightView
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.bottom, 0)

//                        // Single separator below content
//                        Rectangle()
//                            .fill(Color.secondary.opacity(0.5))
//                            .frame(height: row.isWorkout ? 2 : 1)
                    }
                    .listStyle(.plain)
                    .listRowSeparator(.hidden)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("export") {
                    exportLogs()
                }
                .disabled(logs.isEmpty)
            }
        }
        .navigationTitle("logs")
        .sheet(item: $exportURL, onDismiss: { cleanupExport() }) { url in
            ShareSheet(activityItems: [url])
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
            print("Failed to write export: \(error)")
        }
    }

    private func cleanupExport() {
        if let url = exportURL {
            try? FileManager.default.removeItem(at: url)
        }
        exportURL = nil
    }

    private func makeTSV() -> String {
        // Header
        var lines: [String] = ["date\ttime\tworkout\texercise\tset\tweight\treps\tlog output version: log.1"]
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone.current
        dateFormatter.dateFormat = "yyyy-MM-dd\tHH:mm"
        // Logs are reverse sorted; export newest first is fine
        for log in logs {
            let workoutName = workouts.first(where: { $0.id == log.workoutId })?.name ?? "Workout"
            for entry in log.entries {
                let exerciseName = exercises.first(where: { $0.id == entry.exerciseId })?.name ?? "Exercise"
                let count = max(entry.weights.count, entry.reps.count)
                for i in 0..<count {
                    let w = i < entry.weights.count ? entry.weights[i] : 0
                    let r = i < entry.reps.count ? entry.reps[i] : 0
                    let dateStr = dateFormatter.string(from: log.date)
                    // Escape commas by wrapping fields in quotes if needed
                    let wq = quoteIfNeeded(workoutName)
                    let eq = quoteIfNeeded(exerciseName)
                    lines.append("\(dateStr)\t\(wq)\t\(eq)\t\(i+1)\t\(w)\t\(r)")
                }
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
        let rightView: AnyView
        let timestamp: Date
        let workoutId: UUID?
        let exerciseId: UUID?
    }

    private func compactRows() -> [CompactRow] {
        // Build rows in reverse chronological order (logs are already reverse sorted)
        var rows: [CompactRow] = []
        var lastExerciseTimestamp: Date? = nil
        for log in logs {
            let workoutName = workouts.first(where: { $0.id == log.workoutId })?.name ?? "Workout"
            var addedWorkoutForThisLog = false
            for entry in log.entries {
                // Determine if we need to include a workout row based on gap with previous exercise row
                let shouldIncludeWorkoutRow: Bool
                if let prevTs = lastExerciseTimestamp {
                    // Previous row is more recent; include workout row if gap >= 1 hour
                    shouldIncludeWorkoutRow = prevTs.timeIntervalSince(log.date) >= 3600
                } else {
                    // First exercise encountered -> include workout row
                    shouldIncludeWorkoutRow = true
                }
                if shouldIncludeWorkoutRow && !addedWorkoutForThisLog {
                    let right = Text(log.date.formatted(date: .abbreviated, time: .shortened)).font(.headline).foregroundStyle(.blue)
                    rows.append(CompactRow(id: "w-\(log.id.uuidString)-first", isWorkout: true, left: workoutName, rightView: AnyView(right), timestamp: log.date, workoutId: log.workoutId, exerciseId: nil))
                    addedWorkoutForThisLog = true
                }
                // Append exercise row
                let exName = exercises.first(where: { $0.id == entry.exerciseId })?.name ?? "Exercise"
                let right = AnyView(weightsRepsGrid(for: entry, at: log.date))
                rows.append(CompactRow(id: "e-\(log.id.uuidString)-\(entry.exerciseId.uuidString)", isWorkout: false, left: exName, rightView: right, timestamp: log.date, workoutId: log.workoutId, exerciseId: entry.exerciseId))
                // Update last exercise timestamp after adding the exercise row
                lastExerciseTimestamp = log.date
            }
        }
        return rows
    }

    private func weightsRepsGrid(for entry: ExerciseLogEntry, at date: Date) -> some View {
        let previous = previousEntry(for: entry.exerciseId, before: date)
        let maxCount = max(entry.weights.count, entry.reps.count)
        return AnyView(
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
                GridRow {
                    Text("w").font(.headline)
                    ForEach(0..<maxCount, id: \.self) { i in
                        let current = i < entry.weights.count ? entry.weights[i] : 0
                        let prev = previous?.weights.indices.contains(i) == true ? previous!.weights[i] : nil
                        Text("\(current)")
                            .foregroundStyle(colorForWeight(current: current, previous: prev))
                            .font(.headline)
                    }
                }
                GridRow {
                    Text("r").font(.headline)
                    ForEach(0..<maxCount, id: \.self) { i in
                        let current = i < entry.reps.count ? entry.reps[i] : 0
                        let prevRep = previous?.reps.indices.contains(i) == true ? previous!.reps[i] : nil
                        let currentW = i < entry.weights.count ? entry.weights[i] : 0
                        let prevW = previous?.weights.indices.contains(i) == true ? previous!.weights[i] : nil
                        Text("\(current)")
                            .foregroundStyle(colorForReps(current: current, previous: prevRep, currentWeight: currentW, previousWeight: prevW))
                            .font(.headline)
                    }
                }
            }
        )
    }

    private func previousEntry(for exerciseId: UUID, before date: Date) -> ExerciseLogEntry? {
        // Search older logs (since logs are reverse sorted)
        for log in logs.dropFirst() {
            if log.date < date {
                if let entry = log.entries.first(where: { $0.exerciseId == exerciseId }) {
                    return entry
                }
            }
        }
        return nil
    }

    private func colorForWeight(current: Int, previous: Int?) -> Color {
        guard let previous = previous else { return .primary }
        if current > previous { return .green }
        if current < previous { return .red }
        return .primary
    }

    private func colorForReps(current: Int, previous: Int?, currentWeight: Int, previousWeight: Int?) -> Color {
        guard let previous = previous else { return .primary }
        // If reps larger and weight same or larger -> green
        if current > previous, (previousWeight == nil || currentWeight >= (previousWeight ?? currentWeight)) { return .green }
        // If reps smaller and weight same or smaller -> green per spec
        if current < previous, (previousWeight == nil || currentWeight <= (previousWeight ?? currentWeight)) { return .red }
        return .primary
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
    let logEntry1 = ExerciseLogEntry(exerciseId: e1.id, weights: [10, 12, 12], reps: [12, 10, 8])
    let logEntry2 = ExerciseLogEntry(exerciseId: e2.id, weights: [20, 22, 24], reps: [10, 10, 8])
    let log = WorkoutLog(workoutId: workout.id, entries: [logEntry1, logEntry2])

    context.insert(e1)
    context.insert(e2)
    context.insert(workout)
    context.insert(log)
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

extension URL: Identifiable {
    public var id: URL { self }
}

