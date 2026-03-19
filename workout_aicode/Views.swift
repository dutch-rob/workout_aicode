import SwiftUI
import SwiftData

extension Notification.Name {
    static let modelDataDidChange = Notification.Name("ModelDataDidChange")
}

// MARK: - Edit Workouts Screen
struct EditWorkoutsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    // @Query(sort: [SortDescriptor(\WorkoutDef.name)]) private var workouts: [WorkoutDef]
    private var workouts: [WorkoutDef] { store.workouts }

    @State private var editMode: EditMode = .active
    @State private var showDeleteConfirm = false
    @State private var workoutPendingDelete: WorkoutDef?
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Button {
                        let w = WorkoutDef(name: "")
                        // context.insert(w)
                        // try? context.save()
                        // NotificationCenter.default.post(name: .modelDataDidChange, object: nil)
                        store.saveWorkout(w)
                        path.append(w)
                    } label: { Text("new") }
                        .buttonStyle(.borderedProminent)
                    Button("logs") { /* presented via ContentView */ }
                        .buttonStyle(.bordered)
                    Button("end") { dismiss() }
                        .buttonStyle(.bordered)
                }

                if workouts.isEmpty {
                    ContentUnavailableView("No workouts to edit", systemImage: "list.bullet")
                } else {
                    List {
                        Section {
                            ForEach(workouts) { workout in
                                NavigationLink(destination: EditWorkoutView(workout: workout)) {
                                    Text(workout.name)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        workoutPendingDelete = workout
                                        showDeleteConfirm = true
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                            .onMove(perform: move)
                        }
                    }
                    .environment(\.editMode, $editMode)
                }
            }
            .padding()
            .navigationTitle("edit workouts")
            .navigationDestination(for: WorkoutDef.self) { w in
                EditWorkoutView(workout: w)
            }
            .confirmationDialog("Delete Workout?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    // if let w = workoutPendingDelete {
                    //     context.delete(w)
                    //     try? context.save()
                    //     NotificationCenter.default.post(name: .modelDataDidChange, object: nil)
                    // }
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

    private func move(from source: IndexSet, to destination: Int) {
        var order = workouts
        order.move(fromOffsets: source, toOffset: destination)
        store.reorderWorkouts(order)
    }
}

// MARK: - Edit Workout Screen
struct EditWorkoutView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Bindable var workout: WorkoutDef
    @State private var hasInserted = false

    private var isWorkoutValid: Bool {
        !workout.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            Section {
                TextField("Workout name", text: $workout.name)
            }
            Section(header: Text("Exercises")) {
                NavigationLink { EditExerciseView(exercise: ExerciseDef(name: "")) } label: { Text("new exercise") }

                ForEach(workout.exerciseOrder.indices, id: \.self) { idx in
                    let current = allExercises.first(where: { $0.id == workout.exerciseOrder[idx] })
                    Menu {
                        ForEach(allExercises) { choice in
                            Button(choice.name) { workout.exerciseOrder[idx] = choice.id }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "line.3.horizontal")
                            Text(current?.name ?? "Select exercise")
                        }
                    }
                }
                // Empty box at bottom
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
        // .onChange(of: workout.name) { newValue in
        //     let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        //     guard !trimmed.isEmpty, !hasInserted else { return }
        //     do {
        //         let targetID = workout.id
        //         let descriptor = FetchDescriptor<WorkoutDef>(predicate: #Predicate<WorkoutDef> { obj in obj.id == targetID })
        //         let existing = try context.fetch(descriptor)
        //         if existing.isEmpty {
        //             context.insert(workout)
        //         }
        //         hasInserted = true
        //         NotificationCenter.default.post(name: .modelDataDidChange, object: nil)
        //         try? context.save()
        //     } catch {
        //         context.insert(workout)
        //         hasInserted = true
        //         NotificationCenter.default.post(name: .modelDataDidChange, object: nil)
        //         try? context.save()
        //     }
        // }
        // .onDisappear {
        //     guard !hasInserted else { return }
        //     let trimmed = workout.name.trimmingCharacters(in: .whitespacesAndNewlines)
        //     guard !trimmed.isEmpty else { return }
        //     do {
        //         let targetID = workout.id
        //         let descriptor = FetchDescriptor<WorkoutDef>(predicate: #Predicate<WorkoutDef> { obj in obj.id == targetID })
        //         let existing = try context.fetch(descriptor)
        //         if existing.isEmpty {
        //             context.insert(workout)
        //         }
        //         hasInserted = true
        //     } catch {
        //         context.insert(workout)
        //         hasInserted = true
        //     }
        //     try? context.save()
        //     NotificationCenter.default.post(name: .modelDataDidChange, object: nil)
        // }
        .navigationTitle("edit workout")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    // do {
                    //     let targetID = workout.id
                    //     let descriptor = FetchDescriptor<WorkoutDef>(predicate: #Predicate<WorkoutDef> { obj in obj.id == targetID })
                    //     let existing = try context.fetch(descriptor)
                    //     if existing.isEmpty {
                    //         context.insert(workout)
                    //     }
                    //     hasInserted = true
                    //     NotificationCenter.default.post(name: .modelDataDidChange, object: nil)
                    //     try? context.save()
                    //     dismiss()
                    // } catch {
                    //     context.insert(workout)
                    //     hasInserted = true
                    //     NotificationCenter.default.post(name: .modelDataDidChange, object: nil)
                    //     try? context.save()
                    //     dismiss()
                    // }
                    store.saveWorkout(workout)
                    dismiss()
                }
                .disabled(!isWorkoutValid)
            }
        }
    }

    @Query private var allExercises: [ExerciseDef]
}

// MARK: - Exercises List Screen
struct ExercisesView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    // @Query(sort: [SortDescriptor(\ExerciseDef.name)]) private var exercises: [ExerciseDef]
    private var exercises: [ExerciseDef] { store.exercises }
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            VStack(alignment: .leading, spacing: 12) {
                Text("exercises").font(.largeTitle).bold()
                HStack(spacing: 12) {
                    Button {
                        let ex = ExerciseDef(name: "")
                        // context.insert(ex)
                        // try? context.save()
                        // NotificationCenter.default.post(name: .modelDataDidChange, object: nil)
                        store.saveExercise(ex)
                        path.append(ex)
                    } label: { Text("new") }
                        .buttonStyle(.borderedProminent)
                    Button("edit") { /* could present edit mode in future */ }
                        .buttonStyle(.bordered)
                    Button("logs") { /* open logs */ }
                        .buttonStyle(.bordered)
                }
                if exercises.isEmpty {
                    ContentUnavailableView("No exercises", systemImage: "dumbbell")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(exercises) { ex in
                        NavigationLink(value: ex) {
                            Text(ex.name)
                        }
                    }
                }
            }
            .padding()
            .navigationDestination(for: ExerciseDef.self) { ex in
                EditExerciseView(exercise: ex)
            }
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
        // .onChange(of: exercise.name) { newValue in
        //     let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        //     guard !trimmed.isEmpty, !hasInserted else { return }
        //     do {
        //         let targetID = exercise.id
        //         let descriptor = FetchDescriptor<ExerciseDef>(predicate: #Predicate<ExerciseDef> { obj in obj.id == targetID })
        //         let existing = try context.fetch(descriptor)
        //         if existing.isEmpty {
        //             context.insert(exercise)
        //         }
        //         hasInserted = true
        //         NotificationCenter.default.post(name: .modelDataDidChange, object: nil)
        //         try? context.save()
        //     } catch {
        //         context.insert(exercise)
        //         hasInserted = true
        //         NotificationCenter.default.post(name: .modelDataDidChange, object: nil)
        //         try? context.save()
        //     }
        // }
        .onChange(of: exercise.lowestWeight) { newValue in
            if exercise.highestWeight < newValue { exercise.highestWeight = newValue }
        }
        .onChange(of: exercise.highestWeight) { newValue in
            if newValue < exercise.lowestWeight { exercise.lowestWeight = newValue }
        }
        .onChange(of: exercise.weightIncrement) { newValue in
            if newValue < 1 { exercise.weightIncrement = 1 }
        }
        .navigationTitle("edit exercise")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    // do {
                    //     let targetID = exercise.id
                    //     let descriptor = FetchDescriptor<ExerciseDef>(predicate: #Predicate<ExerciseDef> { obj in obj.id == targetID })
                    //     let existing = try context.fetch(descriptor)
                    //     if existing.isEmpty {
                    //         context.insert(exercise)
                    //     }
                    //     hasInserted = true
                    //     NotificationCenter.default.post(name: .modelDataDidChange, object: nil)
                    //     try? context.save()
                    //     dismiss()
                    // } catch {
                    //     context.insert(exercise)
                    //     hasInserted = true
                    //     NotificationCenter.default.post(name: .modelDataDidChange, object: nil)
                    //     try? context.save()
                    //     dismiss()
                    // }
                    store.saveExercise(exercise)
                    dismiss()
                }
                .disabled(!isExerciseValid)
            }
        }
        // .onDisappear {
        //     guard !hasInserted else { return }
        //     let trimmed = exercise.name.trimmingCharacters(in: .whitespacesAndNewlines)
        //     guard !trimmed.isEmpty else { return }
        //     do {
        //         let targetID = exercise.id
        //         let descriptor = FetchDescriptor<ExerciseDef>(predicate: #Predicate<ExerciseDef> { obj in obj.id == targetID })
        //         let existing = try context.fetch(descriptor)
        //         if existing.isEmpty {
        //             context.insert(exercise)
        //         }
        //         hasInserted = true
        //     } catch {
        //         context.insert(exercise)
        //         hasInserted = true
        //     }
        //     try? context.save()
        //     NotificationCenter.default.post(name: .modelDataDidChange, object: nil)
        // }
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

    var body: some View {
        let exercise = exerciseAt(currentIndex)
        VStack(spacing: 16) {
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
                }
                .frame(height: 260)
            }

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
        }
        .padding()
        .navigationBarBackButtonHidden(true)
        //.navigationTitle(exercise?.name ?? "Exercise")
        //.navigationBarTitleDisplayMode(.inline)
        .onAppear { prepareBuffers() }
        .gesture(DragGesture().onEnded { value in
            if value.translation.width < -40 { goToNextUnlogged() }
            else if value.translation.width > 40 { goToPrevUnlogged() }
        })
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
        // TODO: merge entries within same session, set timestamp, export ASCII/iCloud

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

    var body: some View {
        List {
            Section {
                if let url = store.exportLogs() {
                    ShareLink(item: url) {
                        Text("Export")
                    }
                }
            }
            Section {
                ForEach(logs) { log in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(log.date.formatted(date: .abbreviated, time: .shortened)).font(.headline)
                        Text(workouts.first(where: { $0.id == log.workoutId })?.name ?? "Workout")
                            .font(.subheadline)
                        ForEach(log.entries, id: \.self) { entry in
                            let exName = exercises.first(where: { $0.id == entry.exerciseId })?.name ?? "Exercise"
                            let weightsText = entry.weights.map(String.init).joined(separator: ", ")
                            let repsText = entry.reps.map(String.init).joined(separator: ", ")
                            Text("\(exName): W \(weightsText)  R \(repsText)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("logs")
    }
}

