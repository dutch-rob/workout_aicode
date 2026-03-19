import SwiftUI
import SwiftData

// MARK: - Edit Workouts Screen
struct EditWorkoutsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\WorkoutDef.name)]) private var workouts: [WorkoutDef]

    @State private var editMode: EditMode = .active
    @State private var dragFrom: Int?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    NavigationLink { EditWorkoutView(workout: WorkoutDef(name: "")) } label: { Text("new") }
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
                        ForEach(workouts) { workout in
                            NavigationLink { EditWorkoutView(workout: workout) } label: {
                                HStack {
                                    Image(systemName: "line.3.horizontal")
                                        .foregroundStyle(.secondary)
                                    Text(workout.name)
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) { confirmDelete(workout) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                        .onMove(perform: move)
                    }
                    .environment(\.editMode, $editMode)
                }
            }
            .padding()
            .navigationTitle("edit workouts")
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var order = workouts
        order.move(fromOffsets: source, toOffset: destination)
        for (idx, w) in order.enumerated() {
            w.exerciseOrder = w.exerciseOrder // no-op; ordering of workouts themselves isn't persisted in this simple model
            // In a future iteration, add an explicit sortIndex to WorkoutDef to persist ordering
            _ = idx
        }
    }

    private func confirmDelete(_ workout: WorkoutDef) {
        // confirmation alert
        let name = workout.name
        let alert = UIAlertController(title: "Delete Workout?", message: "Are you sure you want to delete \(name)?", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in
            context.delete(workout)
        })
        UIApplication.shared.topMostController()?.present(alert, animated: true)
    }
}

// MARK: - Edit Workout Screen
struct EditWorkoutView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query private var allExercises: [ExerciseDef]

    @State var workout: WorkoutDef

    var body: some View {
        Form {
            Section {
                TextField("Workout name", text: Binding(get: { workout.name }, set: { workout.name = $0 }))
            }
            Section(header: Text("Exercises")) {
                Button("new exercise") {
                    // Navigate to new exercise editor
                    // In a NavigationStack context, present editor
                    UIApplication.shared.topMostController()?.present(UIHostingController(rootView: EditExerciseView(exercise: ExerciseDef(name: ""))), animated: true)
                }

                let selectedExercises = workout.exerciseOrder.compactMap { id in allExercises.first(where: { $0.id == id }) }
                ForEach(Array(selectedExercises.enumerated()), id: \.element.id) { idx, ex in
                    Menu {
                        ForEach(allExercises) { choice in
                            Button(choice.name) {
                                workout.exerciseOrder[idx] = choice.id
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "line.3.horizontal")
                            Text(ex.name)
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
        .navigationTitle("edit workout")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    if context.inserted.contains(where: { ($0 as? WorkoutDef)?.id == workout.id }) == false &&
                        context.deleted.contains { ($0 as? WorkoutDef)?.id == workout.id } == false {
                        // ensure the object exists in context
                        context.insert(workout)
                    }
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Exercises List Screen
struct ExercisesView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\ExerciseDef.name)]) private var exercises: [ExerciseDef]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("exercises").font(.largeTitle).bold()
                HStack(spacing: 12) {
                    NavigationLink { EditExerciseView(exercise: ExerciseDef(name: "")) } label: { Text("new") }
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
                        NavigationLink { EditExerciseView(exercise: ex) } label: {
                            Text(ex.name)
                        }
                    }
                }
            }
            .padding()
        }
    }
}

// MARK: - Edit Exercise Screen
struct EditExerciseView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State var exercise: ExerciseDef

    var body: some View {
        Form {
            TextField("Exercise name", text: Binding(get: { exercise.name }, set: { exercise.name = $0 }))
            LabeledContent {
                Stepper(value: Binding(get: { exercise.numberOfSeries }, set: { exercise.numberOfSeries = max(0, $0) }), in: 0...200) {
                    Text("\(exercise.numberOfSeries)")
                }
            } label: { Text("Number of series") }
            LabeledContent {
                Stepper(value: Binding(get: { exercise.lowestWeight }, set: { exercise.lowestWeight = max(0, $0) }), in: 0...2000) {
                    Text("\(exercise.lowestWeight)")
                }
            } label: { Text("Lowest weight") }
            LabeledContent {
                Stepper(value: Binding(get: { exercise.highestWeight }, set: { exercise.highestWeight = max(exercise.lowestWeight, $0) }), in: 0...2000) {
                    Text("\(exercise.highestWeight)")
                }
            } label: { Text("Highest weight") }
            LabeledContent {
                Stepper(value: Binding(get: { exercise.weightIncrement }, set: { exercise.weightIncrement = max(1, $0) }), in: 1...200) {
                    Text("\(exercise.weightIncrement)")
                }
            } label: { Text("Weight increment") }
        }
        .navigationTitle("edit exercise")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    context.insert(exercise)
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Log Exercise Screen
struct LogExerciseView: View {
    @Environment(\.modelContext) private var context
    @Query private var allExercises: [ExerciseDef]

    let workout: WorkoutDef

    @State private var currentIndex: Int = 0
    @State private var weights: [[Int]] = []
    @State private var reps: [[Int]] = []

    var body: some View {
        let exercise = exerciseAt(currentIndex)
        VStack(spacing: 16) {
            Text(exercise?.name ?? "").font(.title2).bold()

            Text("weight used").font(.caption).frame(maxWidth: .infinity, alignment: .leading)
            if let exercise = exercise {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(0..<(exercise.numberOfSeries), id: \.self) { series in
                            Picker("", selection: Binding(get: { safeValue(weights, currentIndex, series, default: exercise.lowestWeight) }, set: { setWeight($0, series: series) })) {
                                ForEach(Array(stride(from: exercise.lowestWeight, through: exercise.highestWeight, by: exercise.weightIncrement)), id: \.self) { w in
                                    Text("\(w)").tag(w)
                                }
                            }
                            .pickerStyle(.wheel)
                            .frame(width: 80, height: 120)
                        }
                    }
                }

                Text("repetitions").font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(0..<(exercise.numberOfSeries), id: \.self) { series in
                            Picker("", selection: Binding(get: { safeValue(reps, currentIndex, series, default: 0) }, set: { setRep($0, series: series) })) {
                                ForEach(0...200, id: \.self) { r in Text("\(r)").tag(r) }
                            }
                            .pickerStyle(.wheel)
                            .frame(width: 80, height: 120)
                        }
                    }
                }
            }

            HStack {
                Button("log, next") { logAndNext() }
                    .buttonStyle(.borderedProminent)
                Button("quit") { /* Navigate back */ UIApplication.shared.topMostController()?.dismiss(animated: true) }
                    .buttonStyle(.bordered)
                Menu("list") {
                    ForEach(workout.exerciseOrder.indices, id: \.self) { idx in
                        let ex = exerciseAt(idx)
                        Button(ex?.name ?? "") { currentIndex = idx }
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .onAppear { prepareBuffers() }
        .gesture(DragGesture().onEnded { value in
            if value.translation.width < -40 { goToNextUnlogged() }
            else if value.translation.width > 40 { goToPrevUnlogged() }
        })
    }

    private func exerciseAt(_ index: Int) -> ExerciseDef? {
        guard index >= 0 && index < workout.exerciseOrder.count else { return nil }
        let id = workout.exerciseOrder[index]
        return allExercises.first(where: { $0.id == id })
    }

    private func prepareBuffers() {
        weights = workout.exerciseOrder.map { _ in [] }
        reps = workout.exerciseOrder.map { _ in [] }
        // TODO: load last log defaults
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

    private func logAndNext() {
        guard let ex = exerciseAt(currentIndex) else { return }
        let entry = ExerciseLogEntry(exerciseId: ex.id, weights: weights[currentIndex], reps: reps[currentIndex])
        var log = WorkoutLog(workoutId: workout.id, entries: [entry])
        context.insert(log)
        // TODO: merge entries within same session, set timestamp, export ASCII/iCloud
        goToNextUnlogged()
    }

    private func goToNextUnlogged() {
        let next = (currentIndex + 1) % max(1, workout.exerciseOrder.count)
        currentIndex = next
    }

    private func goToPrevUnlogged() {
        let prev = (currentIndex - 1 + workout.exerciseOrder.count) % max(1, workout.exerciseOrder.count)
        currentIndex = prev
    }
}

// MARK: - Logs Screen
struct LogsView: View {
    @Query(sort: [SortDescriptor(\WorkoutLog.date, order: .reverse)]) private var logs: [WorkoutLog]
    @Query private var workouts: [WorkoutDef]
    @Query private var exercises: [ExerciseDef]

    var body: some View {
        List(logs) { log in
            VStack(alignment: .leading, spacing: 6) {
                Text(log.date.formatted(date: .abbreviated, time: .shortened)).font(.headline)
                Text(workouts.first(where: { $0.id == log.workoutId })?.name ?? "Workout")
                    .font(.subheadline)
                ForEach(log.entries, id: \.self) { entry in
                    let exName = exercises.first(where: { $0.id == entry.exerciseId })?.name ?? "Exercise"
                    Text("\(exName): W \(entry.weights)  R \(entry.reps)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("logs")
    }
}

// MARK: - UIKit helpers
extension UIApplication {
    func topMostController(base: UIViewController? = UIApplication.shared.connectedScenes
        .compactMap { ($0 as? UIWindowScene)?.keyWindow }
        .first?.rootViewController) -> UIViewController? {
        if let nav = base as? UINavigationController { return topMostController(base: nav.visibleViewController) }
        if let tab = base as? UITabBarController, let selected = tab.selectedViewController { return topMostController(base: selected) }
        if let presented = base?.presentedViewController { return topMostController(base: presented) }
        return base
    }
}
