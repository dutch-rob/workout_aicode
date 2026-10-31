// Settings, and the zone-tint preview that belongs to one of them: the band
// is chosen here against a sample rather than on the wrist.

import SwiftUI
import SwiftData

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
    // MARK: Heart rate zones, typed in by hand
    //
    // Only offered to a Watch that cannot read them from Health itself. From
    // watchOS 27 HealthKit hands over whatever the Workout app is using, which
    // is better than anything that can be typed here — but that needs a Series
    // 9 or later, so an older Watch would otherwise be stuck with an estimate
    // from resting rate and age that quietly disagrees with the wrist.
    //
    // A Watch that has never said which watchOS it is on (`watchOSMajor` is 0)
    // is offered the fields: a setting nobody needs is a smaller harm than one
    // the user cannot reach.

    private var enteredZoneNumbers: [Int] {
        zoneText.compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }

    private var typedZoneBoundaries: [Int] {
        WatchPreferences.validBoundaries(enteredZoneNumbers)
    }

    private var zoneTextIsEmpty: Bool {
        zoneText.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private var zoneBoundariesState: String {
        if zoneTextIsEmpty {
            return "Not set. Your Watch works the zones out from your resting heart rate and your age."
        }
        if typedZoneBoundaries.isEmpty {
            return "All four are needed, each higher than the one before. Until then your Watch works them out."
        }
        return "In use on your Watch."
    }

    private var zoneBoundariesExplanation: String {
        let known = handoff.watchOSMajor
        let watch = known > 0
            ? "your Watch is on watchOS \(known), which has no way to hand them over"
            : "an older Watch has no way to hand them over"
        return "From watchOS 27 the app reads your zones straight out of Health, the same ones the Workout app uses — but that needs an Apple Watch Series 9 or later, and " + watch + ". Open Health › Browse › Heart › Heart Rate Zones and copy in the four numbers each zone starts at. Zone 1 has no bottom and zone 5 no top, so there are four, not six."
    }

    private func loadZoneText() {
        let stored = WatchPreferences.parseBoundaries(zoneBoundariesText)
        guard !stored.isEmpty else { return }
        zoneText = stored.map(String.init)
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
    @AppStorage(WatchPreferences.zoneBoundariesKey) private var zoneBoundariesText = ""
    /// The four thresholds as typed, so a half-finished set of numbers can sit
    /// on screen without being saved or acted on. Only a complete, valid four
    /// reaches `zoneBoundariesText` and the Watch.
    @State private var zoneText: [String] = ["", "", "", ""]

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

            if showsWatchSettings {
                Section {
                    if handoff.watchOSMajor >= WatchSystemVersion.firstWithZoneConfiguration {
                        LabeledContent("Zone boundaries") {
                            Text("From Apple Health").foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(0..<4, id: \.self) { index in
                            LabeledContent {
                                TextField("—", text: $zoneText[index])
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                            } label: {
                                Text("Zone \(index + 2) starts at")
                            }
                        }
                        Text(zoneBoundariesState)
                            .font(.footnote)
                            .foregroundStyle(typedZoneBoundaries.isEmpty && !zoneTextIsEmpty
                                             ? .orange : .secondary)
                        if !zoneTextIsEmpty {
                            Button("Work them out for me instead") {
                                zoneText = ["", "", "", ""]
                            }
                        }
                    }
                } header: {
                    Text("Heart rate zones")
                } footer: {
                    Text(zoneBoundariesExplanation)
                }
                .onAppear { loadZoneText() }
                .onChange(of: zoneText) { _, _ in
                    zoneBoundariesText = WatchPreferences.boundariesText(enteredZoneNumbers)
                    store.reloadAll()
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
    StoreSave.save(context)
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
    StoreSave.save(context)
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
    StoreSave.save(context)
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
    StoreSave.save(context)
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
    StoreSave.save(context)
    store.reloadAll()

    return NavigationStack { LogsStatsView() }
        .environmentObject(store)
        .modelContainer(container)
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
