import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [
        SortDescriptor(\WorkoutDef.sortIndex),
        SortDescriptor(\WorkoutDef.name)
    ]) private var workouts: [WorkoutDef]
    @Query(sort: [SortDescriptor(\ExerciseDef.name)]) private var exercises: [ExerciseDef]

    @State private var pendingNewWorkout: WorkoutDef? = nil
    @State private var pendingNewExercise: ExerciseDef? = nil

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("workouts")
                    .font(.largeTitle).bold()
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 12) {
                    NavigationLink(destination: InfoView()) {
                        Label {
                            Text("info")
                        } icon: {
                            ZStack {
                                Circle().fill(Color.blue)
                                Image(systemName: "info")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            .frame(width: 20, height: 20)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    NavigationLink(destination: LogsView()) {
                        Text("logs").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                HStack(spacing: 12) {
                    if workouts.isEmpty {
                        Button {
                            let workout = WorkoutDef(name: "")
                            modelContext.insert(workout)
                            pendingNewWorkout = workout
                        } label: {
                            Text("new workout").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    } else {
                        NavigationLink(destination: EditWorkoutsView()) {
                            Text("edit workouts").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }

                    if exercises.isEmpty {
                        Button {
                            let exercise = ExerciseDef(name: "")
                            modelContext.insert(exercise)
                            pendingNewExercise = exercise
                        } label: {
                            Text("new exercise").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    } else {
                        NavigationLink(destination: EditExercisesView()) {
                            Text("edit exercises").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }

                if workouts.isEmpty {
                    ContentUnavailableView("No workouts", systemImage: "list.bullet", description: Text("Tap 'new workout' to create your first workout"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(workouts.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }, id: \.self) { workout in
                                NavigationLink(destination: LogExerciseView(workout: workout)) {
                                    Text(workout.name)
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                        .bold()
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding()
                                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.blue.opacity(1.0)))
                                }
                            }
                        }.padding(.top, 4)
                    }
                }
            }
            .padding()
            .navigationDestination(item: $pendingNewWorkout) { workout in
                EditWorkoutView(workout: workout)
            }
            .navigationDestination(item: $pendingNewExercise) { exercise in
                EditExerciseView(exercise: exercise)
            }
        }
    }
}

#Preview("Home - ContentView") {
    let container = try! ModelContainer(
        for: WorkoutDef.self, ExerciseDef.self, WorkoutLog.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext
    let store = AppStore(context: context)
    let e1 = ExerciseDef(name: "Bench Press")
    let e2 = ExerciseDef(name: "Squat")
    let w1 = WorkoutDef(name: "Upper Body", exerciseOrder: [e1.id])
    let w2 = WorkoutDef(name: "Leg Day", exerciseOrder: [e2.id])

    context.insert(e1)
    context.insert(e2)
    context.insert(w1)
    context.insert(w2)
    try? context.save()
    store.reloadAll()

    return ContentView()
        .environmentObject(store)
        .modelContainer(container)
}
