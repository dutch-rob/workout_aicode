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
    // Identified by UUID, never by the model object.
    //
    // SwiftUI hashes whatever identifies a row or a navigation entry — and for
    // a SwiftData object that means reading a persisted property. When the
    // store is swapped, those objects are destroyed, and the very next thing
    // SwiftUI does is hash the outgoing ones to work out what to remove:
    //   ForEachState.appendRemove -> Set.insert -> WorkoutDef.hash(into:)
    //   -> WorkoutDef.id.getter -> destroyed backing data -> crash.
    // Plain values cannot fault, so identity is kept in UUIDs and the objects
    // are looked up only where they are about to be drawn.
    @State private var path: [UUID] = []
    @State private var askDefaults = false
    /// Set at launch when there is a history whose unit nobody has stated.
    @State private var askWeightUnit = false
    /// The workout just ended, while the offer to schedule the next one is up.
    @State private var scheduleOffer: PhoneSessionManager.FinishedWorkout? = nil
    /// Once per launch. See the resume in `.task`.
    @State private var triedResume = false

    /// A row on the start screen, as plain values — see `path`.
    private struct WorkoutRow: Identifiable, Hashable {
        let id: UUID
        let name: String
    }

    /// Workouts that have been given a name. A half-created one (the row exists
    /// the moment "new workout" is tapped) should not show on the start screen.
    /// Also kept out of the view body: inline, the type-checker gave up on it.
    private var workoutRows: [WorkoutRow] {
        workouts
            .filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { WorkoutRow(id: $0.id, name: $0.name) }
    }
    @ObservedObject private var survey = SurveyScheduler.shared
    @Query(sort: [SortDescriptor(\WorkoutLog.date)]) private var allLogs: [WorkoutLog]
    @Query private var allLogWeights: [LogWeights]
    @AppStorage(SharingKey.consent) private var shareWithDevelopers = false
    @AppStorage(StatsSettingsKey.formula) private var formulaRaw = OneRMFormula.epley.rawValue

    /// A screenshot run seeds its own data and drives its own navigation.
    private var isDemoRun: Bool {
        #if DEBUG
        return DemoMode.isEnabled
        #else
        return false
        #endif
    }

    /// Converts anything still without a unit, and asks the question when
    /// there is something to convert and no answer yet.
    private func refreshWeightUnitState() {
        guard !isDemoRun else { return }
        WeightHistory.catchUp(in: modelContext)
        askWeightUnit = WeightHistory.shouldAsk(in: modelContext)
    }

    private func uploadSharedDataIfConsented() {
        guard shareWithDevelopers else { return }
        DeveloperDataSync.sync(consent: true, logs: allLogs, exercises: exercises,
                             weightsByLog: LogWeightsIndex.byLogId(allLogWeights),
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
                        .disabled(handoff.isLockedByWatchWorkout)
                    } else {
                        NavigationLink(destination: EditWorkoutsView()) {
                            Text("edit workouts").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(handoff.isLockedByWatchWorkout)
                    }

                    NavigationLink(destination: ExerciseLibraryView()) {
                        Text("exercise library").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(handoff.isLockedByWatchWorkout)
                }

                if workouts.isEmpty {
                    ContentUnavailableView("No workouts", systemImage: "list.bullet", description: Text("Tap 'new workout' to create your first workout"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(workoutRows) { row in
                                NavigationLink(value: row.id) {
                                    Text(row.name)
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                        .bold()
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding()
                                        .background(RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.blue.opacity(
                                                handoff.isLockedByWatchWorkout ? 0.3 : 1.0)))
                                }
                                // A workout is already running on the Watch:
                                // starting another here would be a second
                                // session fighting the first for the same logs.
                                .disabled(handoff.isLockedByWatchWorkout)
                            }
                        }.padding(.top, 4)
                    }
                }
            }
            .padding()
            .navigationDestination(for: UUID.self) { id in
                // Resolved here, where the object is about to be drawn and is
                // therefore valid, rather than being carried around in state.
                if let workout = workouts.first(where: { $0.id == id }) {
                    LogExerciseView(workout: workout, onEndSession: { path.removeAll() })
                }
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
            if path.last != workout.id { path = [workout.id] }
            handoff.routeWorkoutId = nil
        }
        // Opening / returning to the app checks for an active session elsewhere.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                handoff.onForeground()
                // A rest that ran out while the app was away is simply over.
                RestTimer.shared.onForeground()
                AerobicCountdown.shared.onForeground()
            }
        }
        // Presented here rather than by logs/stats itself — see that view.
        .sheet(isPresented: $survey.pending) { SurveyView() }
        // Asked once, on a fresh install, before there is anything to set up.
        .sheet(isPresented: $askDefaults) { ExerciseDefaultsView() }
        .task {
            // Straight back into an interrupted workout. A launch that finds an
            // unfinished session is almost always iOS having killed the app
            // while the phone was in a pocket: the person was on the log
            // screen, and making them find the workout again to get back to it
            // was the complaint. Only on launch — an app that was merely
            // backgrounded comes back where it was without help, and yanking
            // someone out of logs/stats on every return would be its own
            // complaint.
            if !triedResume {
                triedResume = true
                if path.isEmpty, handoff.role != .paused, !isDemoRun {
                    // The answer arrives after the Watch has been asked whether
                    // it is running this workout, so everything is checked
                    // again here: the user may have tapped a workout, or the
                    // Paused screen may have come up, while we waited.
                    handoff.workoutToResume { id in
                        guard let id, path.isEmpty, handoff.role == .none,
                              let workout = workouts.first(where: {
                                  $0.id.uuidString == id
                              }) else { return }
                        path = [workout.id]
                    }
                }
            }
            #if DEBUG
            DeveloperDataSync.sendTestSurveyIfRequested()
            #endif
            askDefaults = ExerciseDefaults.shouldAsk(existingExercises: exercises.count)
            // Somebody with nothing logged has no history to interpret, so
            // they are never asked; their unit follows their region.
            #if DEBUG
            DemoMode.seedLegacyData(into: modelContext)
            DemoMode.importFileIfAsked(into: modelContext)
            #endif
            refreshWeightUnitState()
            survey.noteLaunch(earliestLogDate: allLogs.first?.date)
            uploadSharedDataIfConsented()
            // Finish any withdrawal that did not complete last time.
            DeveloperDataSync.retryWithdrawIfPending()
        }
        // Workouts logged since the last launch go up on the next one. Uploading
        // as each set is logged would put the network in the middle of a
        // workout; only what is new is sent, so this stays cheap.
        // Records arrive over time — from iCloud, from the Watch — and each
        // one needs the unit the user already gave. Checked whenever the data
        // may have moved rather than once at launch, which is the bug this
        // replaces: anything that landed after that instant had no grams, so
        // its wheels were empty and its sets logged as zero.
        .onChange(of: exercises.count) { _, _ in refreshWeightUnitState() }
        .onChange(of: allLogs.count) { _, _ in refreshWeightUnitState() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                refreshWeightUnitState()
                uploadSharedDataIfConsented()
                // This morning's weigh-in rather than last month's, for the
                // machines that take weight off you. Does nothing unless the
                // user asked for Health to be the source.
                Task { await HealthBodyWeight.refresh() }
            }
        }
        // When the workout session ends (finished or quit), pop back to the list.
        // Driven from here (not the log view's dismiss()) so it's reliable with
        // the path-bound NavigationStack.
        .onChange(of: handoff.role) { _, newRole in
            if newRole == .none, !path.isEmpty { path.removeAll() }
        }
        // A workout active on the Watch shows here as a Paused screen; the
        // session only moves over when the user taps "Continue here".
        .sheet(isPresented: $askWeightUnit) {
            WeightUnitPrompt { askWeightUnit = false }
        }
        // Offered after the workout screen has closed, not over it: the last
        // thing somebody does in the gym is put their phone away, and a sheet
        // on top of the log screen is in the way of that.
        .sheet(item: $scheduleOffer) { finished in
            if let workout = workouts.first(where: { $0.id == finished.workoutId }) {
                ScheduleNextWorkoutSheet(workoutName: workout.name,
                                         workoutId: workout.id,
                                         finished: finished) {
                    scheduleOffer = nil
                }
            }
        }
        .onChange(of: handoff.justFinished) { _, finished in
            guard let finished, WorkoutSchedule.isEnabled else {
                handoff.justFinished = nil
                return
            }
            handoff.justFinished = nil
            scheduleOffer = finished
        }
        .overlay {
            if handoff.role == .paused {
                if handoff.remoteAppleWorkout {
                    // Only over a workout screen. On the start screen the
                    // locked buttons say it, and the logs, graphs, progress
                    // and info are all still there to be read — which is the
                    // reason to open the phone mid-workout in the first place.
                    if !path.isEmpty {
                        WatchWorkoutActiveView(onReturn: { path.removeAll() })
                    }
                } else {
                    HandoverPausedView(otherDeviceName: "Apple Watch",
                                       onContinue: { handoff.reclaim() },
                                       onDismiss: { handoff.dismissPaused() })
                }
            }
        }
        #if DEBUG
        // Screenshot demo mode — open the requested screen. See DemoMode.swift.
        .overlay {
            switch DemoMode.screen {
            case "logs":     NavigationStack { LogsStatsView() }
            case "graphs":   NavigationStack { StrengthGraphsView() }
            case "progress": NavigationStack { StrengthProgressView() }
            case "library":  NavigationStack { ExerciseLibraryView() }
            case "art":      NavigationStack { BodyArtProbe() }
            case "info":     NavigationStack { InfoView() }
            case "settings": NavigationStack { SettingsView() }
            default:         EmptyView()
            }
        }
        .task {
            guard DemoMode.screen == "log" || DemoMode.screen == "rest"
                    || DemoMode.screen == "aerobic",
                  path.isEmpty,
                  let w = workouts.first(where: {
                      !$0.name.trimmingCharacters(in: .whitespaces).isEmpty
                  }) else { return }
            path = [w.id]
            if DemoMode.screen == "aerobic" {
                try? await Task.sleep(for: .milliseconds(600))
                AerobicCountdown.shared.showDemoCountdown(
                    exercise: DemoMode.aerobicExercise,
                    remaining: 13 * 60, bpm: 137, total: 20 * 60)
                return
            }
            guard DemoMode.screen == "rest" else { return }
            // After the log screen is on screen, so the countdown covers it
            // rather than being presented from nothing.
            try? await Task.sleep(for: .milliseconds(600))
            RestTimer.shared.showDemoCountdown(exercise: DemoMode.restExercise,
                                               total: DemoMode.restTotal,
                                               remaining: DemoMode.restRemaining)
        }
        #endif
    }
}

#Preview("Home - ContentView") {
    let container = try! ModelContainer(
        for: WorkoutDef.self, ExerciseDef.self, WorkoutLog.self, AerobicResult.self, DraftSession.self,
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
