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
    @State private var currentIndex: Int = 0
    @State private var weights: [[Int]] = []
    @State private var reps: [[Int]] = []
    @State private var loggedIndices: Set<Int> = []
    @State private var didPrepare = false
    @State private var showExerciseList = false
    @State private var startedAt = Date()
    @State private var dragOffsetX: CGFloat = 0
    @State private var isHorizontalDrag: Bool? = nil

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
            .onDisappear { session.leaveSession() }
            // Reloaded state after reclaiming the session in place.
            .onChange(of: session.adoptSnapshot) { _, _ in
                if let snap = session.takeAdoptSnapshot(for: workout.id) { adopt(snap) }
            }
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

    private func currentPage(for exercise: SyncExercise) -> some View {
        VStack(spacing: 2) {
            exerciseTitle(exercise)
            HStack(spacing: 2) {
                rowLabel
                pickerRow(for: exercise)
            }
            .frame(height: wheelHeight())
            otherMetricLabels(for: exercise, index: currentIndex)
        }
    }

    /// While swiping, the incoming page is just the exercise title and empty
    /// wheel outlines — the real values arrive with the wheels once it lands.
    /// Keeps the drag cheap and the transition clean.
    @ViewBuilder
    private func neighbourPage(index: Int) -> some View {
        if isHorizontalDrag == true, index != currentIndex, let ex = exerciseAt(index) {
            VStack(spacing: 2) {
                exerciseTitle(ex)
                HStack(spacing: 2) {
                    rowLabel
                    HStack(spacing: 2) {
                        ForEach(0..<max(1, ex.numberOfSeries), id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Color.gray.opacity(0.55), lineWidth: 1)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .frame(height: wheelHeight())
                // Reserve the value row's height so nothing shifts on landing.
                Text(" ")
                    .font(.caption).bold()
                    .frame(maxWidth: .infinity)
            }
            .allowsHitTesting(false)
        } else {
            Color.clear
        }
    }

    private func exerciseTitle(_ exercise: SyncExercise) -> some View {
        Text(exercise.name)
            .font(.caption).bold()
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rowLabel: some View {
        Text(mode == .reps ? "reps" : "weight")
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
                HStack(spacing: 0) {
                    Button {
                        withAnimation { mode = (mode == .reps ? .weights : .reps) }
                    } label: {
                        Label(mode == .reps ? "weights" : "reps",
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
    private func wheelHeight() -> CGFloat {
        max(60, stripHeight - 50)
    }

    /// Toggle width — left-aligned and capped so it clears the clock top-right.
    private var toggleWidth: CGFloat {
        WKInterfaceDevice.current().screenBounds.width * 0.58
    }

    // MARK: - Handover helpers

    private func currentSnapshot() -> SessionSnapshot {
        SessionSnapshot(workoutId: workout.id,
                        currentIndex: currentIndex,
                        weights: weights,
                        reps: reps,
                        loggedIndices: Array(loggedIndices),
                        startedAt: startedAt.timeIntervalSince1970)
    }

    private func adopt(_ snap: SessionSnapshot) {
        weights = snap.weights
        reps = snap.reps
        loggedIndices = Set(snap.loggedIndices)
        startedAt = Date(timeIntervalSince1970: snap.startedAt)
        setIndex(snap.currentIndex)
    }

    private func startOrAdoptSession() {
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

    // MARK: - Picker row (reps OR weights)

    private func pickerRow(for exercise: SyncExercise) -> some View {
        let count = max(1, exercise.numberOfSeries)
        return HStack(spacing: 2) {
            ForEach(0..<count, id: \.self) { series in
                Group {
                    if mode == .reps {
                        Picker("", selection: repsBinding(series: series)) {
                            ForEach(0...200, id: \.self) { Text("\($0)").tag($0) }
                        }
                    } else {
                        Picker("", selection: weightBinding(series: series,
                                                            defaultValue: exercise.lowestWeight)) {
                            ForEach(weightOptions(for: exercise), id: \.self) {
                                Text("\($0)").tag($0)
                            }
                        }
                    }
                }
                .labelsHidden()
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
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
                ? safeValue(weights, index, series, default: exercise.lowestWeight)
                : safeValue(reps, index, series, default: 0)
        }
        return HStack(spacing: 2) {
            // Reserve the vertical row-label column so values align with wheels.
            Color.clear.frame(width: rowLabelWidth, height: 1)
            ForEach(0..<count, id: \.self) { series in
                Text("\(prefix)\(values[series])")
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
            Button {
                logAndNext(exercise)
            } label: {
                Text(isLastUnlogged ? "end" : "log").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.mini)

            Button("quit") {
                let endedAt = Date()
                onEndSession()
                session.leaveSession()
                session.finishWorkout(startedAt: startedAt, endedAt: endedAt)
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
                Button(exerciseAt(idx)?.name ?? "") { setIndex(idx) }
            }
        }
    }

    // MARK: - Logging

    private var isLastUnlogged: Bool {
        let total = workout.exerciseOrder.count
        return loggedIndices.count == total - 1 && !loggedIndices.contains(currentIndex)
    }

    private func logAndNext(_ exercise: SyncExercise) {
        session.logSet(workoutId: workout.id,
                       exerciseId: exercise.id,
                       weights: weights[safe: currentIndex] ?? [],
                       reps: reps[safe: currentIndex] ?? [])
        loggedIndices.insert(currentIndex)

        if loggedIndices.count >= workout.exerciseOrder.count {
            // Whole workout logged — end the session (pops back to the list, see
            // ContentView) and report it so the phone records it to Health.
            let endedAt = Date()
            onEndSession()
            session.leaveSession()
            session.finishWorkout(startedAt: startedAt, endedAt: endedAt)
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

    // MARK: - Buffers & value access

    private func exerciseAt(_ index: Int) -> SyncExercise? {
        guard index >= 0 && index < workout.exerciseOrder.count else { return nil }
        return session.exercise(id: workout.exerciseOrder[index])
    }

    private func prepareBuffers() {
        weights = workout.exerciseOrder.map { exId in
            session.lastEntry(workoutId: workout.id, exerciseId: exId)?.weights ?? []
        }
        reps = workout.exerciseOrder.map { exId in
            session.lastEntry(workoutId: workout.id, exerciseId: exId)?.reps ?? []
        }
    }

    private func setIndex(_ index: Int) {
        guard index >= 0 && index < workout.exerciseOrder.count else { return }
        currentIndex = index
    }

    private func weightOptions(for exercise: SyncExercise) -> [Int] {
        let increment = max(1, exercise.weightIncrement)
        guard exercise.highestWeight >= exercise.lowestWeight else { return [exercise.lowestWeight] }
        return Array(stride(from: exercise.lowestWeight,
                            through: exercise.highestWeight,
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
                               fill: exerciseAt(currentIndex)?.lowestWeight ?? 0)
                weights[currentIndex][series] = newValue
            }
        )
    }

    private func repsBinding(series: Int) -> Binding<Int> {
        Binding<Int>(
            get: { safeValue(reps, currentIndex, series, default: 0) },
            set: { newValue in
                guard currentIndex < reps.count else { return }
                ensureCapacity(&reps[currentIndex], upTo: series, fill: 0)
                reps[currentIndex][series] = newValue
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
