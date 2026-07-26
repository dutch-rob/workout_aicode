import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var handoff = PhoneSessionManager.shared
    @Query(sort: [
        SortDescriptor(\WorkoutDef.sortIndex),
        SortDescriptor(\WorkoutDef.name)
    ]) private var workouts: [WorkoutDef]
    @Query(sort: [SortDescriptor(\ExerciseDef.name)]) private var exercises: [ExerciseDef]

    @State private var pendingNewWorkout: WorkoutDef? = nil
    @State private var pendingNewExercise: ExerciseDef? = nil
    @State private var path: [WorkoutDef] = []
    @ObservedObject private var survey = SurveyScheduler.shared
    @Query(sort: [SortDescriptor(\WorkoutLog.date)]) private var allLogs: [WorkoutLog]
    @AppStorage(SharingKey.consent) private var shareWithDevelopers = false
    @AppStorage(StatsSettingsKey.formula) private var formulaRaw = OneRMFormula.epley.rawValue

    private func uploadSharedDataIfConsented() {
        guard shareWithDevelopers else { return }
        DeveloperDataSync.sync(consent: true, logs: allLogs, exercises: exercises,
                               formula: OneRMFormula(rawValue: formulaRaw) ?? .epley)
    }

    var body: some View {
        NavigationStack(path: $path) {
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

                    NavigationLink(destination: LogsStatsView()) {
                        Text("logs/stats").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(.blue)
                            .frame(maxWidth: .infinity)
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
                                NavigationLink(value: workout) {
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
            .navigationDestination(for: WorkoutDef.self) { workout in
                LogExerciseView(workout: workout, onEndSession: { path.removeAll() })
            }
            .navigationDestination(item: $pendingNewWorkout) { workout in
                EditWorkoutView(workout: workout)
            }
            .navigationDestination(item: $pendingNewExercise) { exercise in
                EditExerciseView(exercise: exercise)
            }
        }
        // Bring the app forward into an active workout that's being handed over.
        .onChange(of: handoff.routeWorkoutId) { _, id in
            guard let id, let workout = workouts.first(where: { $0.id.uuidString == id })
            else { return }
            if path.last?.id != workout.id { path = [workout] }
            handoff.routeWorkoutId = nil
        }
        // Opening / returning to the app checks for an active session elsewhere.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { handoff.onForeground() }
        }
        // Presented here rather than by logs/stats itself — see that view.
        .sheet(isPresented: $survey.pending) { SurveyView() }
        .task {
            survey.noteLaunch(earliestLogDate: allLogs.first?.date)
            uploadSharedDataIfConsented()
        }
        // Workouts logged since the last launch go up on the next one. Uploading
        // as each set is logged would put the network in the middle of a
        // workout; only what is new is sent, so this stays cheap.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { uploadSharedDataIfConsented() }
        }
        // When the workout session ends (finished or quit), pop back to the list.
        // Driven from here (not the log view's dismiss()) so it's reliable with
        // the path-bound NavigationStack.
        .onChange(of: handoff.role) { _, newRole in
            if newRole == .none, !path.isEmpty { path.removeAll() }
        }
        // A workout active on the Watch shows here as a Paused screen; the
        // session only moves over when the user taps "Continue here".
        .overlay {
            if handoff.role == .paused {
                HandoverPausedView(otherDeviceName: "Apple Watch",
                                   onContinue: { handoff.reclaim() },
                                   onDismiss: { handoff.dismissPaused() })
            }
        }
        #if DEBUG
        // Screenshot demo mode — open the requested screen. See DemoMode.swift.
        .overlay {
            switch DemoMode.screen {
            case "logs":     NavigationStack { LogsStatsView() }
            case "graphs":   NavigationStack { StrengthGraphsView() }
            case "progress": NavigationStack { StrengthProgressView() }
            case "info":     NavigationStack { InfoView() }
            case "settings": NavigationStack { SettingsView() }
            default:         EmptyView()
            }
        }
        .task {
            guard DemoMode.screen == "log", path.isEmpty,
                  let w = workouts.first(where: {
                      !$0.name.trimmingCharacters(in: .whitespaces).isEmpty
                  }) else { return }
            path = [w]
        }
        #endif
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
