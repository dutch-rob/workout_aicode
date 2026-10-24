import SwiftUI
import WatchKit

// MARK: - WatchLogExerciseView
//
// The Watch equivalent of the phone's LogExerciseView, shrunk to one screen.
//
// To fit the Watch, only ONE row of picker wheels is shown at a time — either
// the repetitions row or the weights row — toggled by a button. The row that is
// NOT being edited is shown compactly as labels:
//   • reps wheels visible   → selected weights shown as labels
//   • weights wheels visible → selected reps shown as labels
// Entering the screen (and moving to a new exercise) starts on the reps row.
//
// The same actions as the phone are offered: "log, next" / "log, end", "quit",
// and a "list" menu to jump between exercises. Logging a set sends it to the
// iPhone, which stores it. The current time is shown by watchOS in the status bar.

struct WatchLogExerciseView: View {
    @ObservedObject private var session = WatchSessionManager.shared
    @Environment(\.dismiss) private var dismiss

    let workout: SyncWorkout
    /// Clears the navigation path in ContentView — deterministic pop.
    var onEndSession: () -> Void = {}

    private enum Mode { case reps, weights }

    @State private var mode: Mode = .reps
    /// Two rows of wheels — weights and repetitions on screen together, with
    /// no toggle between them — when the phone says so. See `WatchPreferences`.
    private var twoRows: Bool { session.wheelRows == 2 }
    @State private var currentIndex: Int = 0
    @State private var weights: [[Int]] = []
    @State private var reps: [[Int]] = []
    @State private var loggedIndices: Set<Int> = []
    @State private var didPrepare = false
    @State private var showExerciseList = false
    @State private var startedAt = Date()
    @State private var dragOffsetX: CGFloat = 0
    @State private var isHorizontalDrag: Bool? = nil
    /// Minutes chosen per exercise, for the aerobic ones.
    @State private var durations: [Int] = []

    // MARK: - Body

    var body: some View {
        mainContent
            // No back chevron: "quit" does the same job, and hiding it lets the
            // toggle sit on the clock's row instead of below it.
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                if !didPrepare {
                    prepareBuffers()
                    startOrAdoptSession()
                    didPrepare = true
                }
            }
            // Report live state so the phone can take over from exactly here.
            .onChange(of: currentIndex) { _, _ in
                mode = .reps   // each new exercise starts on the reps row
                session.updateLiveSnapshot(currentSnapshot()); session.checkpoint()
            }
            .onChange(of: weights) { _, _ in session.updateLiveSnapshot(currentSnapshot()) }
            .onChange(of: reps) { _, _ in session.updateLiveSnapshot(currentSnapshot()) }
            .onChange(of: loggedIndices) { _, _ in
                session.updateLiveSnapshot(currentSnapshot()); session.checkpoint()
            }
            // Cancelling here, not just on quit: leaving this screen by any
            // route ends the workout, and a rest that outlived it went on to
            // buzz for a set the user had already walked away from.
            .onDisappear { session.leaveSession(); WatchRestTimer.shared.cancel() }
            // Reloaded state after reclaiming the session in place.
            .onChange(of: session.adoptSnapshot) { _, _ in
                if let snap = session.takeAdoptSnapshot(for: workout.id) { adopt(snap) }
            }
            // The phone's switch, flipped while this workout is already under
            // way — see watchModeChanged.
            .onChange(of: session.workoutMode) { _, mode in watchModeChanged(to: mode) }
            // Swipe left/right to move between exercises without logging, as on
            // the phone. Simultaneous so the wheels keep their own scrolling.
            .simultaneousGesture(exerciseSwipeGesture)
    }

    /// Horizontal swipe → next / previous unlogged exercise (no logging).
    /// The direction is locked on first movement so a vertical drag keeps
    /// scrolling the wheels; a horizontal one drags the middle section along.
    private var exerciseSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged { value in
                if isHorizontalDrag == nil {
                    let dx = abs(value.translation.width)
                    let dy = abs(value.translation.height)
                    if dx > 6 || dy > 6 { isHorizontalDrag = dx > dy }
                }
                if isHorizontalDrag == true { dragOffsetX = value.translation.width }
            }
            .onEnded { value in
                guard isHorizontalDrag == true else { isHorizontalDrag = nil; return }
                let width = WKInterfaceDevice.current().screenBounds.width
                let dx = value.translation.width
                if dx <= -swipeThreshold {
                    settle(to: -width, landingOn: nextUnloggedIndex)
                } else if dx >= swipeThreshold {
                    settle(to: width, landingOn: prevUnloggedIndex)
                } else {
                    // Not far enough — spring back.
                    withAnimation(.easeOut(duration: 0.15)) { dragOffsetX = 0 }
                    isHorizontalDrag = nil
                }
            }
    }

    /// Finish the swipe: glide the strip a full page, then make that page the
    /// current one and re-centre. Because the neighbour is already on screen the
    /// swap is invisible — no flash, no second animation.
    private func settle(to offset: CGFloat, landingOn index: Int) {
        withAnimation(.easeInOut(duration: 0.2)) { dragOffsetX = offset }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.21) {
            currentIndex = index
            dragOffsetX = 0
            isHorizontalDrag = nil
        }
    }

    private var swipeThreshold: CGFloat {
        max(30, WKInterfaceDevice.current().screenBounds.width * 0.25)
    }

    // MARK: - Swipe pages
    //
    // A 3-wide strip (previous · current · next) laid out inside a screen-width
    // frame, so the middle page is what you see. Dragging moves the whole strip,
    // which brings the neighbouring exercise in as the current one leaves.
    // The neighbours are lightweight previews (static value boxes rather than
    // live wheels) — three sets of watchOS wheel Pickers would stutter — and are
    // only built while an actual horizontal drag is in progress.

    private func swipePages(current: SyncExercise) -> some View {
        let w = WKInterfaceDevice.current().screenBounds.width
        return HStack(spacing: 0) {
            neighbourPage(index: prevUnloggedIndex).frame(width: w)
            currentPage(for: current).frame(width: w)
            neighbourPage(index: nextUnloggedIndex).frame(width: w)
        }
        .frame(width: w, height: stripHeight)   // strip overflows width, centred on `current`
        .offset(x: dragOffsetX)
    }

    @ViewBuilder
    private func currentPage(for exercise: SyncExercise) -> some View {
        if exercise.isAerobic {
            aerobicPage(for: exercise)
        } else if twoRows {
            // Nothing but the wheels: the name is up on the clock's row, and
            // the w/r values under the wheels said what the other row now
            // says for itself.
            VStack(spacing: 2) {
                wheelRow(for: exercise, metric: .weights)
                wheelRow(for: exercise, metric: .reps)
            }
            .overlay(alignment: .topTrailing) { WatchRestOverlay() }
        } else {
            VStack(spacing: 2) {
                exerciseTitle(exercise, showRest: true)
                HStack(spacing: 2) {
                    rowLabel(mode)
                    pickerRow(for: exercise)
                }
                .frame(height: wheelHeight())
                otherMetricLabels(for: exercise, index: currentIndex)
            }
        }
    }

    /// The exercise name on the clock's row, with the rest beside it, over a
    /// band that runs the full width of the screen.
    private func topNameRow(_ exercise: SyncExercise?) -> some View {
        HStack(spacing: 4) {
            Text(exercise?.name ?? "")
                .font(.caption).bold()
                .lineLimit(1)
                .truncationMode(.tail)
            // The rest's seconds are NOT here: this row shares its width with
            // the clock, and the counter sat on top of the exercise name.
            // They are over the wheels instead — see WatchRestOverlay.
            Spacer(minLength: 0)
        }
        .frame(width: toggleWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { WatchZoneRowBackground() }
    }

    private func wheelRow(for exercise: SyncExercise, metric: Mode) -> some View {
        HStack(spacing: 2) {
            rowLabel(metric)
            pickerRow(for: exercise, metric: metric)
        }
        .frame(height: wheelHeight(rows: 2))
    }

    // MARK: - Aerobic
    //
    // One wheel of minutes and a start button, the same shape as the phone's.
    // Without this the Watch showed weight and repetition wheels for a rowing
    // machine, which is not something anyone can answer.

    private func aerobicPage(for exercise: SyncExercise) -> some View {
        VStack(spacing: 2) {
            exerciseTitle(exercise)
            Picker("", selection: minutesBinding()) {
                ForEach(1...120, id: \.self) { Text("\($0)").tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            .frame(height: wheelHeight())

            Text("minutes").font(.caption2).foregroundStyle(.secondary)
        }
    }

    /// Whether an aerobic session has already been run for this exercise, so
    /// the button can stop offering to start another and offer to log instead.
    ///
    /// For THIS exercise. It used to ignore the index it was given and ask
    /// whether any session at all had finished, which left the second cardio
    /// exercise of a workout with no start button — reported from a real
    /// workout that began with the elliptical and could not then start the
    /// indoor cycle.
    private func hasRun(_ index: Int) -> Bool {
        guard let name = exerciseAt(index)?.name else { return false }
        return WatchAerobicWorkout.shared.hasFinishedSession(for: name)
    }

    private func durationSeconds(at index: Int) -> Int {
        guard index < durations.count, durations[index] > 0 else { return 20 * 60 }
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

    /// While swiping, the incoming page is just the exercise title and empty
    /// wheel outlines — the real values arrive with the wheels once it lands.
    /// Keeps the drag cheap and the transition clean.
    @ViewBuilder
    private func neighbourPage(index: Int) -> some View {
        if isHorizontalDrag == true, index != currentIndex, let ex = exerciseAt(index) {
            VStack(spacing: 2) {
                if twoRows {
                    emptyWheelRow(for: ex, metric: .weights)
                    emptyWheelRow(for: ex, metric: .reps)
                } else {
                    exerciseTitle(ex)
                    HStack(spacing: 2) {
                        rowLabel(mode)
                        emptyWheels(for: ex)
                    }
                    .frame(height: wheelHeight())
                    // Reserve the value row's height so nothing shifts on landing.
                    Text(" ")
                        .font(.caption).bold()
                        .frame(maxWidth: .infinity)
                }
            }
            .allowsHitTesting(false)
        } else {
            Color.clear
        }
    }

    private func emptyWheels(for exercise: SyncExercise) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<max(1, exercise.numberOfSeries), id: \.self) { _ in
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.gray.opacity(0.55), lineWidth: 1)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func emptyWheelRow(for exercise: SyncExercise, metric: Mode) -> some View {
        HStack(spacing: 2) {
            rowLabel(metric)
            emptyWheels(for: exercise)
        }
        .frame(height: wheelHeight(rows: 2))
    }

    private func exerciseTitle(_ exercise: SyncExercise, showRest: Bool = false) -> some View {
        HStack(spacing: 4) {
            Text(exercise.name)
                .font(.caption).bold()
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            // The rest's seconds sit beside the name, as they sit beside
            // "log exercise" on the phone. Only on the page in view, never on
            // the neighbour sliding in during a swipe.
            if showRest { WatchRestCounter() }
        }
        // In Apple-workout mode this row carries the heart rate zone. It draws
        // nothing in the other mode, or before the first reading arrives.
        .background { WatchZoneRowBackground() }
    }

    private func rowLabel(_ metric: Mode) -> some View {
        // "machine" for the ones that take weight off you: the wheel is what
        // you set on the machine, not what you lift.
        let assisted = exerciseAt(currentIndex)?.subtractsFromBodyWeight == true
        return Text(metric == .reps ? "reps" : (assisted ? "machine" : "weight"))
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize()
            .rotationEffect(.degrees(-90))
            .frame(width: rowLabelWidth)
    }

    /// Index of the next / previous exercise a swipe would land on.
    private var nextUnloggedIndex: Int {
        let count = max(1, workout.exerciseOrder.count)
        var next = (currentIndex + 1) % count
        while loggedIndices.contains(next) && loggedIndices.count < count {
            next = (next + 1) % count
        }
        return next
    }

    private var prevUnloggedIndex: Int {
        let count = max(1, workout.exerciseOrder.count)
        var prev = (currentIndex - 1 + count) % count
        while loggedIndices.contains(prev) && loggedIndices.count < count {
            prev = (prev - 1 + count) % count
        }
        return prev
    }

    private var mainContent: some View {
        let exercise = exerciseAt(currentIndex)
        return VStack(spacing: 2) {
                // Toggle sits on the clock's row, left-aligned and width-capped so
                // it never runs under the time (which is top-right).
                // No reps/weights toggle for an aerobic exercise: it switches
                // between two things it does not have, and it was sitting on
                // top of the exercise name.
                if exercise?.isAerobic != true {
                    if twoRows {
                        // With both rows on screen there is nothing to toggle,
                        // so the name takes that row — which is the clock's
                        // row, hence the same width cap the toggle had. The
                        // band behind it is NOT capped: it runs the full width,
                        // under the clock, where there is nothing else to show.
                        topNameRow(exercise)
                    } else {
                        HStack(spacing: 0) {
                            Button {
                                withAnimation { mode = (mode == .reps ? .weights : .reps) }
                            } label: {
                                Label(mode == .reps
                                  ? (exercise?.subtractsFromBodyWeight == true ? "machine" : "weights")
                                  : "reps",
                                      systemImage: "arrow.left.arrow.right")
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            .frame(width: toggleWidth)
                            Spacer(minLength: 0)
                        }
                    }
                }

                if let exercise {
                    // Three side-by-side pages (prev · current · next) so a swipe
                    // drags the new exercise in as the old one leaves.
                    swipePages(current: exercise)

                    actionButtons(for: exercise)
                } else {
                    Spacer()
                    Text("No exercises in this workout")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 3)
        .padding(.top, 6)
        // Enough room for button text descenders (the "g" in "log" was clipped).
        .padding(.bottom, 6)
        // Draw into the status strip so the toggle shares the clock's row.
        .ignoresSafeArea(.container, edges: .top)
    }

    /// Width of the vertical row label; the value row reserves the same width so
    /// the numbers line up with the wheel columns.
    private let rowLabelWidth: CGFloat = 13
    /// Height for the wheel row. Sized from the real screen height, NOT the
    /// height the layout offers — watchOS hands the content area more height
    /// than is actually visible, so sizing from that pushes the buttons off the
    /// bottom. `chromeAndStatus` is the status strip plus the toggle, title,
    /// value row, buttons and spacing.
    /// Height of the whole swipe strip (title + wheels + value row). PINNED so a
    /// neighbouring page can never resize it mid-drag — that was what pushed the
    /// buttons down during a swipe and let them jump back at the end.
    private var stripHeight: CGFloat {
        // The toggle row, button row and paddings are a roughly FIXED height on
        // every watch, so subtract them rather than taking a proportion — that
        // keeps the buttons at the bottom and gives the rest to the wheels.
        max(110, WKInterfaceDevice.current().screenBounds.height - 80)
    }

    /// Wheels take the strip minus the title and value rows. Reserve enough for
    /// BOTH rows at full size — if this is too tight the value text silently
    /// shrinks (minimumScaleFactor) instead of the wheels giving way.
    private func wheelHeight(rows: Int = 1) -> CGFloat {
        // Two rows divide the whole strip between them: with the name moved
        // to the clock's row and the w/r values gone, there is nothing else
        // inside it to reserve height for.
        if rows == 2 { return max(44, (stripHeight - 4) / 2) }
        return max(60, stripHeight - 50)
    }

    /// Toggle width — left-aligned and capped so it clears the clock top-right.
    private var toggleWidth: CGFloat {
        WKInterfaceDevice.current().screenBounds.width * 0.58
    }

    // MARK: - Handover helpers

    private func currentSnapshot() -> SessionSnapshot {
        // Both numbers, so the phone can take this over whichever build it is
        // on — see "Two numbers for every weight" in WatchSync.swift.
        let legacy = weights.enumerated().map { index, row in
            session.legacyWeights(row, exerciseId: workout.exerciseOrder.indices.contains(index)
                                  ? workout.exerciseOrder[index] : "")
        }
        return SessionSnapshot(workoutId: workout.id,
                               currentIndex: currentIndex,
                               weights: legacy,
                               reps: reps,
                               loggedIndices: Array(loggedIndices),
                               startedAt: startedAt.timeIntervalSince1970,
                               weightsGrams: weights)
    }

    private func adopt(_ snap: SessionSnapshot) {
        weights = snap.grams(for: workout.exerciseOrder.map { session.exercise(id: $0) },
                             in: session.weightUnit)
        reps = snap.reps
        loggedIndices = Set(snap.loggedIndices)
        startedAt = Date(timeIntervalSince1970: snap.startedAt)
        setIndex(snap.currentIndex)
        // Taken over mid-rest: carry on with it from where it is. Only if the
        // phone says the timer is on — a Watch never invents a rest.
        if session.restTimerEnabled, let rest = snap.pendingRest() {
            WatchRestTimer.shared.resume(endsAt: rest.endsAt, total: rest.total, exercise: "")
        }
    }

    private func startOrAdoptSession() {
        defer { startAppleWorkoutIfChosen() }
        if let snap = session.takeAdoptSnapshot(for: workout.id) {
            // Opened via handover — continue exactly where the phone left off.
            adopt(snap)
            session.updateLiveSnapshot(currentSnapshot())
        } else {
            // Opened by tapping the workout — become the driver, adopting the
            // phone's state if it was already in this same workout.
            startedAt = Date()
            session.enterSession(workoutId: workout.id,
                                 current: currentSnapshot()) { snap in adopt(snap) }
        }
    }

    /// In Apple-workout mode the whole workout is a real HKWorkoutSession.
    ///
    /// `startedAt` is the start of the WORKOUT: when this screen was reached by
    /// hand-over from the phone it is the phone's start, and the session is
    /// back-dated to it so Health records the whole thing rather than the part
    /// done at the machine. Only the heart rate is missing from the earlier
    /// stretch, which is unavoidable — nothing was on the wrist for it.
    private func startAppleWorkoutIfChosen() {
        guard session.workoutMode == .appleWorkout else { return }
        let start = startedAt
        Task { await WatchStrengthWorkout.shared.start(workoutStartedAt: start) }
    }

    /// The setting is on the phone, and it can be changed while the workout is
    /// already running — which is exactly what one user did, mid-workout,
    /// then found no heart-rate zones behind the exercise names. The other
    /// settings in the same payload (two rows of wheels) had plainly arrived,
    /// so the answer "it will be right next time" was not good enough.
    ///
    /// The session is back-dated to the start of the workout either way, so
    /// switching it on part-way records the whole thing — minus the heart rate
    /// for the stretch before the wrist was asked, which nothing can recover.
    private func watchModeChanged(to mode: WatchWorkoutMode) {
        guard mode == .appleWorkout else { return }
        startAppleWorkoutIfChosen()
    }

    // MARK: - Picker row (reps OR weights)

    private func pickerRow(for exercise: SyncExercise,
                           metric: Mode? = nil) -> some View {
        let count = max(1, exercise.numberOfSeries)
        let metric = metric ?? mode
        return HStack(spacing: 2) {
            ForEach(0..<count, id: \.self) { series in
                Group {
                    if metric == .reps {
                        Picker("", selection: repsBinding(series: series)) {
                            ForEach(0...200, id: \.self) { Text("\($0)").tag($0) }
                        }
                    } else {
                        Picker("", selection: weightBinding(series: series,
                                                            defaultValue: exercise.lowestGrams)) {
                            ForEach(weightOptions(for: exercise), id: \.self) { grams in
                                Text(WeightText.string(grams: grams, in: session.weightUnit))
                                    .tag(grams)
                            }
                        }
                    }
                }
                .labelsHidden()
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .simultaneousGesture(wheelTouchGesture)
    }

    /// A touch on a wheel ends a set, as it does on the phone.
    ///
    /// The Watch used to start the rest only when a wheel came to rest on a
    /// DIFFERENT number, so repeating the previous set — the common case —
    /// started nothing, and the wheel had to be wiggled off its value and back
    /// to fake a change. A touch is the honest signal: the user has just
    /// lifted, and has reached for the wheel.
    ///
    /// Simultaneous, so the wheels still scroll and the page swipe between
    /// exercises still works; a horizontal fling is that swipe, not a set.
    private var wheelTouchGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onEnded { value in
                if abs(value.translation.width) > 40,
                   abs(value.translation.width) > abs(value.translation.height) {
                    return
                }
                noteSetFinished()
            }
    }

    // MARK: - The other metric, shown as labels

    /// The metric NOT in the wheels, shown one value per column so each sits
    /// directly under its wheel. Prefixed "w"/"r" so no separate label is needed.
    private func otherMetricLabels(for exercise: SyncExercise, index: Int) -> some View {
        let count = max(1, exercise.numberOfSeries)
        let prefix = mode == .reps ? "w" : "r"
        let values: [Int] = (0..<count).map { series in
            mode == .reps
                ? safeValue(weights, index, series, default: exercise.lowestGrams)
                : safeValue(reps, index, series, default: 0)
        }
        let unit = session.weightUnit
        return HStack(spacing: 2) {
            // Reserve the vertical row-label column so values align with wheels.
            Color.clear.frame(width: rowLabelWidth, height: 1)
            ForEach(0..<count, id: \.self) { series in
                Text(mode == .reps
                     ? "\(prefix)\(WeightText.string(grams: values[series], in: unit))"
                     : "\(prefix)\(values[series])")
                    // Same size as the exercise title. Readability comes from the
                    // bright white + bold — .secondary was the real problem, not
                    // the size. (watchOS .footnote/.caption2 render alike, so a
                    // style bump alone does nothing; hence matching .caption here.)
                    .font(.caption).bold()
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Action buttons (mirror the phone's exercise screen)

    private func actionButtons(for exercise: SyncExercise) -> some View {
        HStack(spacing: 3) {
            // For cardio the first button starts the session, and only becomes
            // "log" once one has been run. A fourth button stacked above this
            // row is what overlapped it — the watch has room for three.
            if exercise.isAerobic, !hasRun(currentIndex) {
                Button {
                    let seconds = max(60, durationSeconds(at: currentIndex))
                    Task {
                        await WatchAerobicWorkout.shared.startHere(
                            activityRaw: exercise.aerobicActivityRaw,
                            exercise: exercise.name,
                            seconds: seconds)
                    }
                } label: {
                    Text("start").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
            } else {
            Button {
                logAndNext(exercise)
            } label: {
                Text(isLastUnlogged ? "end" : "log").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.mini)
            }

            Button("quit") {
                let endedAt = Date()
                onEndSession()
                session.leaveSession()
                session.finishWorkout(startedAt: startedAt, endedAt: endedAt,
                                  workoutId: workout.id)
            }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .frame(maxWidth: .infinity)

            Button("list") { showExerciseList = true }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .frame(maxWidth: .infinity)
        }
        .confirmationDialog("Exercises", isPresented: $showExerciseList, titleVisibility: .visible) {
            ForEach(workout.exerciseOrder.indices, id: \.self) { idx in
                // The tick is part of the title here: a watchOS confirmation
                // dialog takes plain buttons, with nowhere to hang an icon.
                // Same meaning as the phone's checkmark, and the row stays
                // tappable — a logged exercise can still be gone back to.
                let name = exerciseAt(idx)?.name ?? ""
                Button(loggedIndices.contains(idx) ? "✓ \(name)" : name) { setIndex(idx) }
            }
        }
    }

    // MARK: - Logging

    private var isLastUnlogged: Bool {
        let total = workout.exerciseOrder.count
        return loggedIndices.count == total - 1 && !loggedIndices.contains(currentIndex)
    }

    private func logAndNext(_ exercise: SyncExercise) {
        // An aerobic exercise reports what the session measured instead of
        // sets; a strength one sends zero duration and nothing to go with it.
        // Only this exercise's own session, and only for an aerobic one —
        // taking it unconditionally threw away a finished session whenever a
        // strength exercise happened to be logged first.
        let measured = exercise.isAerobic
            ? WatchAerobicWorkout.shared.takeLastSummary(for: exercise.name)
            : nil
        session.logSet(workoutId: workout.id,
                       exerciseId: exercise.id,
                       weights: weights[safe: currentIndex] ?? [],
                       reps: reps[safe: currentIndex] ?? [],
                       aerobic: exercise.isAerobic ? (measured
                            ?? WatchAerobicWorkout.Summary(
                                durationSeconds: durationSeconds(at: currentIndex),
                                averageHeartRate: 0, maximumHeartRate: 0,
                                zoneSeconds: [])) : nil)
        loggedIndices.insert(currentIndex)

        if loggedIndices.count >= workout.exerciseOrder.count {
            // Whole workout logged — end the session (pops back to the list, see
            // ContentView) and report it so the phone records it to Health.
            // No rest: there is nothing left to rest for.
            let endedAt = Date()
            onEndSession()
            session.leaveSession()
            session.finishWorkout(startedAt: startedAt, endedAt: endedAt,
                                  workoutId: workout.id)
            return
        }
        // Read before moving on — goToNextUnlogged changes what currentIndex
        // points at, and the rest belongs to the exercise just finished.
        let restAfter = exercise.restSeconds
        let restName = exercise.name
        slideToNextUnlogged()
        startRest(exercise: restName, seconds: restAfter)
    }

    // MARK: - Rest timer
    //
    // Only when the phone says the feature is on. A Watch that has not heard
    // from the phone leaves it off rather than guessing.

    private func noteSetFinished() {
        startRest(exercise: exerciseAt(currentIndex)?.name ?? "",
                  seconds: exerciseAt(currentIndex)?.restSeconds ?? SyncDefaults.restSeconds)
    }

    private func startRest(exercise: String, seconds: Int) {
        guard session.restTimerEnabled else { return }
        WatchRestTimer.shared.setFinished(exercise: exercise, seconds: seconds)
    }

    /// Logging moves to the next exercise the way a swipe does: the one just
    /// finished leaves to the left while the next comes in from the right.
    ///
    /// The index used to change on the spot, so the screen simply became a
    /// different exercise — easy to miss mid-workout, and the phone has slid
    /// since the carousel was built. The machinery is already here; it only
    /// needed asking. `isHorizontalDrag` is set because the neighbouring pages
    /// are built only while a drag is in progress, and `settle` clears it.
    private func slideToNextUnlogged() {
        let next = nextUnloggedIndex
        guard next != currentIndex else { goToNextUnlogged(); return }
        isHorizontalDrag = true
        settle(to: -WKInterfaceDevice.current().screenBounds.width, landingOn: next)
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

    // MARK: - Buffers & value access

    private func exerciseAt(_ index: Int) -> SyncExercise? {
        guard index >= 0 && index < workout.exerciseOrder.count else { return nil }
        return session.exercise(id: workout.exerciseOrder[index])
    }

    private func prepareBuffers() {
        weights = workout.exerciseOrder.map { exId in
            session.lastWeightsGrams(workoutId: workout.id, exerciseId: exId)
        }
        reps = workout.exerciseOrder.map { exId in
            session.lastEntry(workoutId: workout.id, exerciseId: exId)?.reps ?? []
        }
        // Where the last session of this exercise left the wheel, not a flat
        // twenty minutes for everything.
        durations = workout.exerciseOrder.map { exId in
            let last = session.lastEntry(workoutId: workout.id, exerciseId: exId)?.durationSeconds ?? 0
            return last > 0 ? last : 20 * 60
        }
    }

    private func setIndex(_ index: Int) {
        guard index >= 0 && index < workout.exerciseOrder.count else { return }
        currentIndex = index
    }

    /// In GRAMS, like the phone's. The Watch is sent the range in grams and
    /// sends back whatever the wheel landed on; the unit is only how the
    /// number is written, and arrives with the definitions.
    private func weightOptions(for exercise: SyncExercise) -> [Int] {
        let increment = max(1, exercise.incrementGrams)
        guard exercise.highestGrams >= exercise.lowestGrams else { return [exercise.lowestGrams] }
        return Array(stride(from: exercise.lowestGrams,
                            through: exercise.highestGrams,
                            by: increment))
    }

    private func ensureCapacity(_ arr: inout [Int], upTo index: Int, fill: Int) {
        while arr.count <= index { arr.append(fill) }
    }

    private func safeValue(_ matrix: [[Int]], _ exIndex: Int, _ series: Int, default def: Int) -> Int {
        guard exIndex < matrix.count, series < matrix[exIndex].count else { return def }
        return matrix[exIndex][series]
    }

    private func weightBinding(series: Int, defaultValue: Int) -> Binding<Int> {
        Binding<Int>(
            get: { safeValue(weights, currentIndex, series, default: defaultValue) },
            set: { newValue in
                guard currentIndex < weights.count else { return }
                ensureCapacity(&weights[currentIndex], upTo: series,
                               fill: exerciseAt(currentIndex)?.lowestGrams ?? 0)
                guard weights[currentIndex][series] != newValue else { return }
                weights[currentIndex][series] = newValue
                noteSetFinished()
            }
        )
    }

    private func repsBinding(series: Int) -> Binding<Int> {
        Binding<Int>(
            get: { safeValue(reps, currentIndex, series, default: 0) },
            set: { newValue in
                guard currentIndex < reps.count else { return }
                ensureCapacity(&reps[currentIndex], upTo: series, fill: 0)
                guard reps[currentIndex][series] != newValue else { return }
                reps[currentIndex][series] = newValue
                noteSetFinished()
            }
        )
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Paused overlay (Watch)
//
// Shown when a workout is active on the iPhone. Tapping "Continue here" pulls
// the session onto the Watch; "Not now" dismisses to browse normally.
struct WatchPausedView: View {
    let onContinue: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Image(systemName: "iphone.gen3")
                    .font(.system(size: 26))
                    .foregroundStyle(.tint)
                Text("Active on iPhone")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                // The phone's rest, if one is running: this is the screen most
                // likely to be up while deciding whether to switch to the wrist,
                // and "Continue here" carries the rest over as it stands.
                WatchRestCounter()
                Button("Continue here", action: onContinue)
                    .buttonStyle(.borderedProminent)
                Button("Not now", action: onDismiss)
                    .buttonStyle(.bordered)
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
        .background(Color.black.ignoresSafeArea())
    }
}
