// The screen a workout is actually done on — the wheels, the series, the rest
// wash, the heart rate — and by some way the largest in the app.

import SwiftUI
import SwiftData

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

    /// How far through each exercise's sets the app believes the user is, so a
    /// column can be tinted. By exercise index, like `loggedIndices`.
    /// The rule is `SetProgress`'s and is tested there.
    @State private var setProgress: [Int: SetProgress] = [:]
    @State private var weights: [[Int]] = []
    @State private var reps: [[Int]] = []

    @State private var loggedIndices: Set<Int> = []
    /// The exercise order every array above is indexed against, and `true`
    /// once there is one. The workout can be edited while it is open here —
    /// see `followTheWorkout`.
    @State private var preparedOrder: [UUID] = []
    @State private var didPrepare = false
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
                    arriveAt(currentIndex)
                }
                // A burst of touches is only over once the wheels have been
                // left alone, so the decision has to be taken on a timer
                // rather than on a touch. One sleep per burst, restarted by
                // `id` whenever another touch moves the moment — not a tick
                // every second, which would rebuild this screen throughout a
                // workout for the sake of a question with no new answer.
                .task(id: nextSetDecision) {
                    guard let decision = nextSetDecision else { return }
                    let wait = decision.timeIntervalSinceNow
                    if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                    guard !Task.isCancelled else { return }
                    setProgress[currentIndex]?.settle(at: Date())
                }
                .onChange(of: geo.size.width) { _, newWidth in
                    containerWidth = newWidth
                }
                .onChange(of: geo.size.height) { _, newHeight in
                    pickerHeight = max(160, (newHeight - 220) / 2)
                }
                // Report state to the handover coordinator so the Watch can take
                // over from exactly here. Exercise/log boundaries also checkpoint.
                .onChange(of: currentIndex) { previous, index in
                    setProgress[previous]?.left()
                    arriveAt(index)
                    handoff.updateLiveSnapshot(currentSnapshot()); handoff.checkpoint()
                }
                .onChange(of: weights) { _, _ in handoff.updateLiveSnapshot(currentSnapshot()) }
                .onChange(of: reps) { _, _ in handoff.updateLiveSnapshot(currentSnapshot()) }
                .onChange(of: loggedIndices) { _, _ in
                    handoff.updateLiveSnapshot(currentSnapshot()); handoff.checkpoint()
                }
                // The workout itself, edited elsewhere while it is being
                // logged here — see followTheWorkout.
                .onChange(of: exerciseIds) { _, order in followTheWorkout(order) }
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
            // A cardio session IS the workout happening, so it counts as
            // activity: a workout of nothing but cardio was otherwise treated
            // as a screen somebody opened and closed, and got no offer to
            // schedule the next one.
            handoff.noteActivity()
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
    private func wheelTouchEnded(_ translation: CGSize, column: Int) {
        carriedOn = false
        // A horizontal fling is the page swipe to another exercise, not a set.
        if abs(translation.width) > 40, abs(translation.width) > abs(translation.height) {
            return
        }
        noteWheelTouched(column: column)
        restTimer.setFinished(exercise: exerciseAt(currentIndex)?.name ?? "",
                              seconds: restSecondsForCurrent)
    }

    /// One per column rather than one across the row, which is what tells the
    /// app WHICH set was touched. The rest timer does not care — any wheel
    /// ends a set — but the marked columns do, and working the column out
    /// afterwards from where the finger landed would mean measuring the row
    /// and dividing by the spacing to answer a question the view already knows
    /// the answer to.
    private func wheelTouchGesture(column: Int) -> some Gesture {
        // GLOBAL, not local. A page swipe drags this whole view sideways under
        // the finger — `.offset(x: dragTranslation)` above — so in the view's
        // OWN space the finger has barely moved, and the horizontal fling that
        // the next line throws away measured as nearly nothing. Every swipe
        // between exercises was arriving here as a touch on a wheel. In the
        // screen's space the finger has moved the distance it really moved.
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onEnded { wheelTouchEnded($0.translation, column: column) }
    }

    // MARK: - Which sets have been done

    /// Arriving at an exercise, first time or swiping back to it. Re-arms the
    /// five seconds in which looking the wheels over is not doing a set.
    private func arriveAt(_ index: Int) {
        var progress = setProgress[index] ?? SetProgress(enteredAt: Date())
        progress.entered(at: Date())
        setProgress[index] = progress
    }

    private func noteWheelTouched(column: Int) {
        let now = Date()
        var progress = setProgress[currentIndex] ?? SetProgress(enteredAt: now)
        progress.touched(column, at: now)
        setProgress[currentIndex] = progress
    }

    /// Whether this column of wheels is a set the app believes is done.
    private func setIsDone(_ column: Int) -> Bool {
        setProgress[currentIndex]?.isDone(column) ?? false
    }

    /// When there is next something to decide, for the timer in `body`.
    private var nextSetDecision: Date? { setProgress[currentIndex]?.decidesAt }

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
                               weightsGrams: weights,
                               doneColumns: doneColumnsByExercise())
    }

    /// The marked columns as one count per exercise, for the hand-over. Only
    /// the counts travel: the five-second clock behind them is about a hand on
    /// a wheel on THIS device, and means nothing on the other one.
    private func doneColumnsByExercise() -> [Int] {
        (0..<exerciseIds.count).map { setProgress[$0]?.doneColumns ?? 0 }
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
        // These arrays are the other device's now, so this is the order they
        // are indexed against. A snapshot carries no order of its own.
        preparedOrder = exerciseIds
        didPrepare    = true
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
        // Which sets the other device had marked. Entered NOW, every one of
        // them: picking a device up is arriving, and the first thing anybody
        // does with it is look the wheels over.
        adoptDoneColumns(snap.doneColumns)
    }

    private func adoptDoneColumns(_ counts: [Int]) {
        let now = Date()
        var adopted: [Int: SetProgress] = [:]
        for (index, done) in counts.enumerated() where done > 0 {
            adopted[index] = SetProgress(enteredAt: now, doneColumns: done)
        }
        setProgress = adopted
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
                ForEach(ExerciseListFilter.visible(count: exerciseIds.count,
                                                   logged: loggedIndices,
                                                   current: currentIndex,
                                                   showAll: listShowsAll), id: \.self) { idx in
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
                // Last, under a divider, so it is where a list ends rather
                // than something to read past before reaching the exercises.
                Divider()
                Button {
                    listShowsAll.toggle()
                } label: {
                    Label(ExerciseListFilter.toggleTitle(showAll: listShowsAll),
                          systemImage: listShowsAll
                            ? "line.3.horizontal.decrease.circle" : "list.bullet")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    /// Whether "list" offers the whole workout or only what is left. Per
    /// device and not synced — see `ExerciseListFilter`.
    @AppStorage(ExerciseListFilter.key) private var listShowsAll =
        ExerciseListFilter.showsAllByDefault

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
                .setDoneTint(setIsDone(series))
                .wheelOutline()
                .simultaneousGesture(wheelTouchGesture(column: series))
            }
        }
        .frame(height: pickerHeight)
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
                .setDoneTint(setIsDone(series))
                .wheelOutline()
                .simultaneousGesture(wheelTouchGesture(column: series))
            }
        }
        .frame(height: pickerHeight)
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
    ///
    /// The rule itself is `LoggedSets`, in Shared, because the Watch's log
    /// button has to write exactly the same thing and for a while did not.
    /// What stays here is the only part that is this device's: where the
    /// number of sets comes from, which is a different type on each.
    private func displayed(_ buffer: [[Int]], for exercise: ExerciseDef,
                           default fallback: Int) -> [Int] {
        LoggedSets.displayed(buffer, at: currentIndex,
                             sets: exercise.numberOfSeries, default: fallback)
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
        if !LoggedSets.hasRepetitions(reps) {
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
        weights = exerciseIds.map { freshWeights(for: $0, last: last) }
        reps = exerciseIds.map { last[$0]?.reps ?? [] }
        // Pre-filled from the last session of each aerobic exercise, so the
        // wheel opens where it was left, exactly like the weight wheels.
        durations = exerciseIds.map(freshDuration(for:))
        preparedOrder = exerciseIds
        didPrepare = true
    }

    /// Where one exercise's wheels open: last time's numbers, or nothing.
    private func freshWeights(for exId: UUID, last: [UUID: WorkoutLog]) -> [Int] {
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

    private func freshDuration(for exId: UUID) -> Int {
        AerobicDefaults.lastMinutes(for: exId) * 60
    }

    /// The workout changed while it is open here: an exercise reordered or
    /// taken out on the Mac and brought over by iCloud, or one deleted from
    /// the library, which drops it out of `exerciseIds`. Without this every
    /// array slides up by one and the wheels belong to the wrong exercise —
    /// the Watch had exactly this, reported from a real workout.
    ///
    /// The re-indexing itself is `ExerciseOrderChange`, which is where its
    /// reasoning and its tests are.
    private func followTheWorkout(_ newOrder: [UUID]) {
        guard didPrepare, newOrder != preparedOrder else { return }
        let was = preparedOrder
        let last = store.lastEntries(for: workout)
        weights = ExerciseOrderChange.carry(weights, from: was, to: newOrder) {
            freshWeights(for: $0, last: last)
        }
        reps = ExerciseOrderChange.carry(reps, from: was, to: newOrder) {
            last[$0]?.reps ?? []
        }
        durations = ExerciseOrderChange.carry(durations, from: was, to: newOrder,
                                              fresh: freshDuration(for:))
        // An aerobic session belongs to the exercise it was run for, so it
        // travels with it; an exercise that has just arrived has not run one.
        summaries = ExerciseOrderChange.carry(summaries, from: was, to: newOrder) { _ in nil }
        actualSeconds = ExerciseOrderChange.carry(actualSeconds, from: was, to: newOrder) { _ in 0 }
        loggedIndices = ExerciseOrderChange.carry(loggedIndices, from: was, to: newOrder)
        preparedOrder = newOrder
        currentIndex = ExerciseOrderChange.position(of: currentIndex, from: was, to: newOrder)
        ensureBufferShape()
        // The Watch may take this over at any moment, and what it would be
        // handed is built from these arrays.
        handoff.updateLiveSnapshot(currentSnapshot())
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
