import SwiftUI
import SwiftData

// MARK: - Logs
//
// What was actually done, newest first, grouped into the sessions they were
// done in. The phone shows the same thing in two narrow columns because it has
// to; here there is width for the sets to sit out in a row where they can be
// read across, which is the whole reason to look at a log on a Mac.
//
// Read-only, deliberately. Logging happens on the phone and the Watch, and a
// Mac that could quietly rewrite last Tuesday would make the history a
// different kind of thing.

struct MacLogsView: View {
    @Query(sort: [SortDescriptor(\WorkoutLog.date, order: .reverse)]) private var logs: [WorkoutLog]
    @Query private var workouts: [WorkoutDef]
    @Query private var exercises: [ExerciseDef]
    @Query private var logWeights: [LogWeights]
    @Query private var aerobicResults: [AerobicResult]

    @State private var search = ""
    @State private var limitDates = false
    /// Which way round the log is read, and in what order. Kept per window
    /// rather than saved: it is a way of looking at something, not a
    /// preference about the app.
    @State private var byExercise = false
    @State private var order = LogSessions.Order.newestFirst
    /// The ids of the sessions or exercises whose rows are folded away.
    @State private var collapsed: Set<String> = []
    @State private var from = Calendar.current.date(byAdding: .month, value: -1,
                                                    to: Date()) ?? Date()
    @State private var to = Date()
    @Environment(\.modelContext) private var context
    @State private var editing: LogEditSession?
    @State private var couldNotOpen: String?

    private var exerciseNames: [UUID: String] {
        Dictionary(exercises.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
    }

    private var workoutNames: [UUID: String] {
        Dictionary(workouts.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
    }

    /// See `LogSessions.matching` for what the typing does and why.
    private var sessions: [LogSessions.Session] {
        LogSessions.matching(LogSessions.group(logs, workoutNames: workoutNames),
                             text: search,
                             exerciseNames: exerciseNames,
                             from: limitDates ? from : nil,
                             to: limitDates ? to : nil)
    }

    private var histories: [LogSessions.ExerciseHistory] {
        LogSessions.ordered(LogSessions.byExercise(sessions, exerciseNames: exerciseNames),
                            by: order)
    }

    private var orderedSessions: [LogSessions.Session] {
        LogSessions.ordered(sessions, by: order)
    }

    private func isCollapsed(_ id: String) -> Bool { collapsed.contains(id) }

    private func toggleCollapsed(_ id: String) {
        if collapsed.contains(id) { collapsed.remove(id) } else { collapsed.insert(id) }
    }

    private var isFiltering: Bool {
        !search.trimmingCharacters(in: .whitespaces).isEmpty || limitDates
    }

    var body: some View {
        Group {
            if logs.isEmpty {
                MacEmptyState(thing: "logs")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    VStack(spacing: 6) {
                        HStack {
                            // "Filter", not "Search": it narrows what is on
                            // screen rather than taking you somewhere.
                            TextField("Filter by exercise or workout", text: $search)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 320)
                            if !search.isEmpty {
                                Button {
                                    search = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                                .help("Clear the filter")
                            }
                            Spacer()
                            Text(countLine)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 8) {
                            Picker("", selection: $byExercise) {
                                Text("By workout").tag(false)
                                Text("By exercise").tag(true)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .fixedSize()
                            .onChange(of: byExercise) { _, _ in collapsed.removeAll() }

                            Divider().frame(height: 16)

                            Button(allCollapsed ? "Expand all" : "Collapse all") {
                                if allCollapsed { collapsed.removeAll() }
                                else { collapsed = Set(allGroupIds) }
                            }
                            .buttonStyle(.link)

                            Divider().frame(height: 16)

                            Toggle("Dates", isOn: $limitDates)
                            if limitDates {
                                DatePicker("from", selection: $from,
                                           displayedComponents: .date)
                                DatePicker("to", selection: $to,
                                           displayedComponents: .date)
                                    .onChange(of: to) { _, newValue in
                                        if newValue < from { from = newValue }
                                    }
                                    .onChange(of: from) { _, newValue in
                                        if newValue > to { to = newValue }
                                    }
                            }
                            Spacer()
                        }
                        .font(.callout)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    Divider()
                    list
                }
            }
        }
        .navigationTitle("Logs")
        .toolbar {
            ToolbarItem {
                Button(action: openEditor) {
                    Label("Edit logs", systemImage: "square.and.pencil")
                        // With its words, not just the pencil. A macOS toolbar
                        // shows icon-only by default, and an unlabelled icon is
                        // a feature nobody finds: this one went unnoticed until
                        // it was asked for as though it did not exist.
                        .labelStyle(.titleAndIcon)
                }
                .help("Correct a logged row, add one, or delete one")
            }
        }
        .sheet(item: $editing) { session in
            MacEditLogsView(session: session)
        }
        .alert("Could not open the log editor",
               isPresented: Binding(get: { couldNotOpen != nil },
                                    set: { if !$0 { couldNotOpen = nil } })) {
            Button("OK", role: .cancel) { couldNotOpen = nil }
        } message: {
            Text(couldNotOpen ?? "")
        }
    }

    /// The copy is taken BEFORE the screen opens, and the screen does not open
    /// without one. An editor with no way back is not a thing to offer for the
    /// only records in this app that cannot be re-made.
    private func openEditor() {
        let wasInDraft = DraftMode.isOn(in: context)
        do {
            let snapshot = try LogEditing.snapshot(in: context)
            DraftMode.start(in: context)
            editing = LogEditSession(wasInDraft: wasInDraft, snapshot: snapshot)
        } catch {
            couldNotOpen = "Your logs could not be copied, so there would be no way to undo an edit. \(error.localizedDescription)"
        }
    }

    private var countLine: String {
        let shown = sessions
        let total = LogSessions.group(logs, workoutNames: workoutNames).count
        guard isFiltering else {
            return "\(total) sessions · \(logs.count) exercises logged"
        }
        // Rows as well as sessions, because the filter now reduces both and a
        // count of sessions alone would not say how much is being shown.
        let rows = shown.reduce(0) { $0 + $1.logs.count }
        return "\(shown.count) of \(total) sessions · \(rows) exercises"
    }

    private var emptyDescription: String {
        let typed = search.trimmingCharacters(in: .whitespaces)
        switch (typed.isEmpty, limitDates) {
        case (true, true):  return "Nothing was logged between those dates."
        case (false, true): return "No workout or exercise called “\(typed)” between those dates."
        default:            return "No workout or exercise called “\(typed)”."
        }
    }

    private var allGroupIds: [String] {
        byExercise ? histories.map(\.id) : orderedSessions.map(\.id)
    }

    private var allCollapsed: Bool {
        let ids = allGroupIds
        return !ids.isEmpty && ids.allSatisfy { collapsed.contains($0) }
    }

    /// Clickable column titles. The one in use says which way it is sorted,
    /// and clicking it again turns it round.
    private var headings: some View {
        HStack(spacing: 16) {
            heading(byExercise ? "Exercise" : "Workout", active: !order.isByDate) {
                order = order.clickingName()
            }
            .frame(width: 232, alignment: .leading)

            heading(byExercise ? "Last logged" : "Date", active: order.isByDate) {
                order = order.clickingDate()
            }
            Spacer(minLength: 0)
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private func heading(_ title: String, active: Bool,
                         _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text(title)
                    .foregroundStyle(active ? .primary : .secondary)
                if active {
                    Image(systemName: order == .newestFirst || order == .nameZA
                          ? "chevron.down" : "chevron.up")
                        .font(.caption2)
                }
            }
        }
        .buttonStyle(.plain)
        .help("Sort by \(title.lowercased())")
    }

    /// The +/− in the left margin. A disclosure triangle would be the macOS
    /// idiom, but these are section headers in a plain List rather than an
    /// outline, and a button is what can actually be put there.
    private func foldButton(_ id: String) -> some View {
        Button {
            toggleCollapsed(id)
        } label: {
            Image(systemName: isCollapsed(id) ? "plus.square" : "minus.square")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help(isCollapsed(id) ? "Show the exercises" : "Hide the exercises")
    }

    @ViewBuilder private var list: some View {
        if sessions.isEmpty {
            ContentUnavailableView("Nothing matches",
                                   systemImage: "line.3.horizontal.decrease.circle",
                                   description: Text(emptyDescription))
        } else {
            VStack(spacing: 0) {
                headings
                Divider()
                if byExercise { exerciseList } else { workoutList }
            }
        }
    }

    private var workoutList: some View {
        List {
            ForEach(orderedSessions) { session in
                Section {
                    if !isCollapsed(session.id) {
                        ForEach(session.logs) { log in
                            row(log)
                        }
                    }
                } header: {
                    HStack(spacing: 6) {
                        foldButton(session.id)
                        Text(session.workoutName.isEmpty ? "Workout" : session.workoutName)
                            .font(.headline).foregroundStyle(.blue)
                        Spacer()
                        Text(session.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.subheadline).foregroundStyle(.blue)
                    }
                }
            }
        }
    }

    /// The same logs, gathered by exercise. Collapsed, an exercise says when
    /// it was last done and where; opened, it lists every time.
    private var exerciseList: some View {
        List {
            ForEach(histories) { history in
                Section {
                    if !isCollapsed(history.id) {
                        ForEach(history.entries) { entry in
                            HStack(alignment: .top, spacing: 16) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(entry.date.formatted(date: .abbreviated,
                                                              time: .shortened))
                                    Text(entry.workoutName.isEmpty ? "Workout"
                                                                   : entry.workoutName)
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                .frame(width: 200, alignment: .leading)
                                if let result = aerobicResult(for: entry.log) {
                                    aerobicLine(result)
                                } else {
                                    sets(entry.log)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                } header: {
                    HStack(spacing: 6) {
                        foldButton(history.id)
                        Text(history.name.isEmpty ? "(deleted exercise)" : history.name)
                            .font(.headline).foregroundStyle(.blue)
                        Spacer()
                        if let last = history.mostRecent {
                            Text(last.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.subheadline).foregroundStyle(.blue)
                            if !last.workoutName.isEmpty {
                                Text("· \(last.workoutName)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func row(_ log: WorkoutLog) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(exerciseNames[log.exerciseId] ?? "(deleted exercise)")
                .frame(width: 200, alignment: .leading)
            if let result = aerobicResult(for: log) {
                aerobicLine(result)
            } else {
                sets(log)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    /// One column per set: the weight over the reps, coloured against the last
    /// time this exercise was done.
    private func sets(_ log: WorkoutLog) -> some View {
        let previous = LogComparison.previous(for: log.exerciseId, before: log.date, in: logs)
        // Grams, from beside the log, written in the user's unit.
        let byLog = LogWeightsIndex.byLogId(logWeights)
        let grams = byLog[log.id] ?? []
        let previousGrams = previous.flatMap { byLog[$0.id] } ?? []
        let unit = WeightUnit.current
        let count = max(grams.count, log.reps.count)
        // Half of this is the difference worth colouring — see
        // LogComparison.tolerance. It matters for the assisted machines, whose
        // logged weight moves with the user's body weight.
        let incrementForLog = exercises.first(where: { $0.id == log.exerciseId })?.weightIncrementGrams
        return HStack(spacing: 10) {
            ForEach(0..<count, id: \.self) { i in
                let weight = i < grams.count ? grams[i] : 0
                let reps = i < log.reps.count ? log.reps[i] : 0
                let previousWeight = previousGrams.indices.contains(i)
                    ? previousGrams[i] : nil
                let previousReps = previous?.reps.indices.contains(i) == true
                    ? previous!.reps[i] : nil
                VStack(spacing: 0) {
                    Text(WeightText.string(grams: weight, in: unit))
                        .foregroundStyle(LogComparison.weightColour(current: weight,
                                                                    previous: previousWeight,
                                                                    increment: incrementForLog))
                    Text("\(reps)")
                        .font(.caption)
                        .foregroundStyle(LogComparison.repsColour(current: reps,
                                                                  previous: previousReps,
                                                                  currentWeight: weight,
                                                                  previousWeight: previousWeight,
                                                                  increment: incrementForLog))
                }
                .monospacedDigit()
                .frame(minWidth: 26)
            }
        }
        // Said once at the head of the row rather than on every set.
        .overlay(alignment: .leading) {
            Text("w\nr")
                .font(.caption2).foregroundStyle(.secondary)
                .offset(x: -14)
        }
    }

    /// Straight from the stored row. The phone wraps this in an AerobicSummary
    /// because it also has a live session to describe; here there is only ever
    /// the record of a finished one.
    private func aerobicResult(for log: WorkoutLog) -> AerobicResult? {
        aerobicResults.first { $0.logId == log.id }
    }

    /// An aerobic session has no sets, so the w/r columns would be two empty
    /// rows. Its own numbers instead.
    private func aerobicLine(_ result: AerobicResult) -> some View {
        HStack(spacing: 12) {
            Label(minutesSeconds(result.durationSeconds), systemImage: "clock")
            // Zero means no Watch, or Health access refused — a normal outcome,
            // and "0 avg" would read as a measurement rather than its absence.
            if result.averageHeartRate > 0 {
                Label("\(result.averageHeartRate) avg", systemImage: "heart.fill")
                    .foregroundStyle(.red)
                Text("max \(result.maximumHeartRate)")
                if !result.zoneSeconds.isEmpty {
                    Text(zoneLine(result.zoneSeconds)).foregroundStyle(.secondary)
                }
            } else {
                Text("no heart rate").foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .monospacedDigit()
    }

    /// "Z1 2:10 · Z2 8:40" — only the zones actually spent in, because five
    /// entries of which three are 0:00 is mostly noise.
    private func zoneLine(_ seconds: [Int]) -> String {
        seconds.enumerated()
            .filter { $0.element > 0 }
            .map { "Z\($0.offset + 1) \(minutesSeconds($0.element))" }
            .joined(separator: " · ")
    }
}
