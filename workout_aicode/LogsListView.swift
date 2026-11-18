// The logs tab: everything recorded, grouped into the sessions it was done in.

import SwiftUI
import SwiftData

// MARK: - logs tab
//
// The log list. Import/export lives in ImportExportView; both are tabs of
// LogsStatsView.
//
// GROUPED, FOLDED AND SORTED BY THE SAME CODE AS THE MAC. `LogSessions` is in
// Shared and is where the rules live: what counts as one session, what the
// filter matches, which way round the list reads, and how the same logs look
// gathered by exercise instead. This screen used to group them itself, with
// its own copy of the one-hour rule — two answers to "what is a session" that
// nothing kept in step.
//
// WHAT IS NOT SHARED is everything below the grouping: the phone draws a
// session's exercises in two narrow columns with the sets stacked w-over-r,
// because that is what fits, and the Mac draws them out in a wide row because
// it can. Sharing those layouts would mean one of them being wrong.
//
// Tapping an exercise opens THAT ROW for correcting — see EditOneLogView,
// which writes nothing until Save.

struct LogsListView: View {
    @Query(sort: [SortDescriptor(\WorkoutLog.date, order: .reverse)]) private var logs: [WorkoutLog]
    @Query private var workouts: [WorkoutDef]
    @Query private var exercises: [ExerciseDef]
    @Query private var aerobicResults: [AerobicResult]
    @Query private var logWeights: [LogWeights]

    @State private var search = ""
    /// Which way round the log is read, and in what order. Kept per screen
    /// rather than saved: it is a way of looking at something, not a
    /// preference about the app.
    @State private var byExercise = false
    @State private var order = LogSessions.Order.newestFirst
    /// The ids of the sessions or exercises whose rows are folded away.
    @State private var collapsed: Set<String> = []
    /// The row being corrected. A wrapper because `sheet(item:)` wants
    /// something identifiable and a UUID is not it.
    @State private var correcting: LogRowToCorrect?

    private var exerciseNames: [UUID: String] {
        Dictionary(exercises.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
    }

    private var workoutNames: [UUID: String] {
        Dictionary(workouts.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
    }

    private var sessions: [LogSessions.Session] {
        LogSessions.matching(LogSessions.group(logs, workoutNames: workoutNames),
                             text: search, exerciseNames: exerciseNames)
    }

    private var orderedSessions: [LogSessions.Session] {
        LogSessions.ordered(sessions, by: order)
    }

    private var histories: [LogSessions.ExerciseHistory] {
        LogSessions.ordered(LogSessions.byExercise(sessions, exerciseNames: exerciseNames),
                            by: order)
    }

    private var groupIds: [String] {
        byExercise ? histories.map(\.id) : orderedSessions.map(\.id)
    }

    private var allCollapsed: Bool {
        let ids = groupIds
        return !ids.isEmpty && ids.allSatisfy { collapsed.contains($0) }
    }

    private func isCollapsed(_ id: String) -> Bool { collapsed.contains(id) }

    private func toggle(_ id: String) {
        if collapsed.contains(id) { collapsed.remove(id) } else { collapsed.insert(id) }
    }

    var body: some View {
        Group {
            if logs.isEmpty {
                ContentUnavailableView("No logs yet", systemImage: "doc.text",
                                       description: Text("Start logging your workouts to see them here."))
            } else {
                VStack(spacing: 0) {
                    controls
                    Divider()
                    list
                }
            }
        }
        .sheet(item: $correcting) { row in
            EditOneLogView(logId: row.id)
        }
    }

    // MARK: The controls

    private var controls: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundStyle(.secondary)
                // "Filter", not "Search": it narrows what is on screen rather
                // than taking you somewhere.
                TextField("Filter by exercise or workout", text: $search)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if !search.isEmpty {
                    Button {
                        search = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .font(.callout)

            HStack(spacing: 10) {
                Picker("", selection: $byExercise) {
                    Text("Workout").tag(false)
                    Text("Exercise").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                // The folded ids are a session's or an exercise's, and they
                // are not each other's: keeping them across the switch would
                // fold nothing and look broken.
                .onChange(of: byExercise) { _, _ in collapsed.removeAll() }

                Spacer(minLength: 0)

                Menu {
                    Picker("", selection: $order) {
                        Text(byExercise ? "Last done, newest" : "Newest first")
                            .tag(LogSessions.Order.newestFirst)
                        Text(byExercise ? "Last done, oldest" : "Oldest first")
                            .tag(LogSessions.Order.oldestFirst)
                        Text("Name, A to Z").tag(LogSessions.Order.nameAZ)
                        Text("Name, Z to A").tag(LogSessions.Order.nameZA)
                    }
                } label: {
                    Label(orderLabel, systemImage: "arrow.up.arrow.down")
                        .font(.caption)
                }

                Button {
                    if allCollapsed { collapsed.removeAll() }
                    else { collapsed = Set(groupIds) }
                } label: {
                    Image(systemName: allCollapsed
                          ? "arrow.down.left.and.arrow.up.right"
                          : "arrow.up.right.and.arrow.down.left")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
                .help(allCollapsed ? "Show everything" : "Fold everything away")
            }

            // Said out loud, because nothing about a row says it can be
            // opened and the Mac learned that the hard way: its own way in
            // went unnoticed until it was asked for as though it did not
            // exist.
            HStack {
                Text(countLine)
                Spacer()
                Text("Tap a row to correct it")
            }
            .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private var orderLabel: String {
        switch order {
        case .newestFirst: return "newest"
        case .oldestFirst: return "oldest"
        case .nameAZ:      return "A–Z"
        case .nameZA:      return "Z–A"
        }
    }

    private var countLine: String {
        let total = LogSessions.group(logs, workoutNames: workoutNames).count
        guard !search.trimmingCharacters(in: .whitespaces).isEmpty else {
            return "\(total) sessions · \(logs.count) logged"
        }
        let rows = sessions.reduce(0) { $0 + $1.logs.count }
        return "\(sessions.count) of \(total) sessions · \(rows) exercises"
    }

    // MARK: The list

    @ViewBuilder private var list: some View {
        if sessions.isEmpty {
            ContentUnavailableView("Nothing matches",
                                   systemImage: "line.3.horizontal.decrease.circle",
                                   description: Text("No workout or exercise called “\(search.trimmingCharacters(in: .whitespaces))”."))
        } else if byExercise {
            exerciseList
        } else {
            workoutList
        }
    }

    // Sections would be the idiom, and were what this screen had first. A
    // folded-away section is a header with no rows, and a List gives every
    // section the same generous gap whether or not anything is in it: folding
    // the lot left twenty-six headers spread down a screen and a half of
    // black. `listSectionSpacing(.compact)` did not touch it. So the headers
    // are rows like any other, and the spacing is this screen's own.
    private var workoutList: some View {
        List {
            ForEach(Array(orderedSessions.enumerated()), id: \.element.id) { index, session in
                header(id: session.id,
                       name: session.workoutName.isEmpty ? "Workout" : session.workoutName,
                       date: session.date,
                       note: nil,
                       count: session.logs.count, noun: "exercises",
                       isFirst: index == 0)
                if !isCollapsed(session.id) {
                    ForEach(session.logs) { log in
                        logRow(name: exerciseNames[log.exerciseId] ?? "(deleted exercise)",
                               log: log)
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    /// The same logs, gathered by exercise. Folded away, an exercise says when
    /// it was last done; opened, it lists every time — which is the question
    /// somebody has standing at a machine wondering whether to add five
    /// pounds.
    /// The same logs, gathered by exercise. Folded away, an exercise says
    /// when it was last done; opened, it lists every time — which is the
    /// question somebody has standing at a machine wondering whether to add
    /// five pounds.
    private var exerciseList: some View {
        List {
            ForEach(Array(histories.enumerated()), id: \.element.id) { index, history in
                header(id: history.id,
                       name: history.name.isEmpty ? "(deleted exercise)" : history.name,
                       date: history.mostRecent?.date,
                       note: history.mostRecent?.workoutName,
                       count: history.entries.count, noun: "times",
                       isFirst: index == 0)
                if !isCollapsed(history.id) {
                    ForEach(history.entries) { entry in
                        logRow(name: entry.workoutName.isEmpty ? "Workout" : entry.workoutName,
                               log: entry.log, showsDate: true)
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    /// The +/− in the left margin, the name, and when. A disclosure triangle
    /// would be the idiom, but these are section headers in a plain List
    /// rather than an outline, and a button is what can actually go there.
    private func header(id: String, name: String, date: Date?,
                        note: String?, count: Int, noun: String,
                        isFirst: Bool) -> some View {
        Button {
            toggle(id)
        } label: {
            VStack(spacing: 6) {
                // The rule above the group, except the first: there the
                // screen's own top edge already does the job, and a rule
                // flush against it read as a stray border.
                if !isFirst {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.8))
                        .frame(height: 2)
                }
                HStack(spacing: 6) {
                    Image(systemName: isCollapsed(id) ? "plus.square" : "minus.square")
                        .foregroundStyle(.secondary)
                    Text(name).font(.headline).foregroundStyle(.blue).italic()
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 0) {
                        if let date {
                            Text(date.formatted(date: .abbreviated, time: .shortened))
                                .font(.subheadline).foregroundStyle(.blue)
                        }
                        // Folded away, the count is the only thing saying how
                        // much is behind the +.
                        if isCollapsed(id) {
                            Text(note.map { "\(count) \(noun) · \($0)" }
                                     ?? "\(count) \(noun)")
                                .font(.caption2).foregroundStyle(.secondary)
                        } else if let note, !note.isEmpty {
                            Text(note).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: isFirst ? 6 : 10, leading: 20,
                                  bottom: 4, trailing: 20))
    }

    /// One logged exercise: its name on the left, its sets on the right. In
    /// the by-exercise list the left column is the workout and the date goes
    /// above the sets, since the name is already the section's.
    private func logRow(name: String, log: WorkoutLog,
                        showsDate: Bool = false) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(name).font(.headline)
                if showsDate {
                    Text(log.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            weightsRepsGrid(for: log, at: log.date)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        // A single tap, not a double: this opens a screen, commits nothing,
        // and the screen it opens can be left without keeping a thing.
        .onTapGesture { correcting = LogRowToCorrect(id: log.id) }
        .listRowSeparator(.hidden)
        // A row's own insets, because the standard ones left a blank line
        // under every exercise: the two numbers rows are about 26pt each and
        // the default padding added 34pt of nothing between one exercise and
        // the next, which read as a third, empty row.
        .listRowInsets(EdgeInsets(top: 2, leading: 20, bottom: 6, trailing: 20))
    }

    /// What a finished aerobic session came to, if this log is one.
    private func aerobicSummary(for log: WorkoutLog) -> AerobicSummary? {
        guard let result = aerobicResults.first(where: { $0.logId == log.id }) else { return nil }
        return AerobicSummary(seconds: result.durationSeconds,
                              averageHeartRate: result.averageHeartRate,
                              maximumHeartRate: result.maximumHeartRate,
                              zoneSeconds: result.zoneSeconds)
    }

    @ViewBuilder
    private func weightsRepsGrid(for log: WorkoutLog, at date: Date) -> some View {
        // A ride has no sets, so the w/r grid rendered two empty rows with
        // nothing in them. Its own numbers instead.
        if let summary = aerobicSummary(for: log) {
            AerobicSummaryView(summary: summary, compact: true)
        } else {
            weightsRepsColumns(for: log, at: date)
        }
    }

    private func weightsRepsColumns(for log: WorkoutLog, at date: Date) -> some View {
        let previous = previousEntry(for: log.exerciseId, before: date)
        // Grams, from beside the log. The unit is only how they are written —
        // no "kg" or "lb" here, where every column is already as narrow as it
        // can be and the unit is the same down the whole screen.
        let byLog = LogWeightsIndex.byLogId(logWeights)
        let grams = byLog[log.id] ?? []
        let previousGrams = previous.flatMap { byLog[$0.id] } ?? []
        let unit = WeightUnit.current
        let maxCount = max(grams.count, log.reps.count)
        return Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
            GridRow {
                Text("w").font(.headline)
                ForEach(0..<maxCount, id: \.self) { i in
                    let current = i < grams.count ? grams[i] : 0
                    let prev = previousGrams.indices.contains(i) ? previousGrams[i] : nil
                    // The reps of the SAME set, both times: the weight's
                    // colour depends on them — see LogComparison.weightColour.
                    let currentR = i < log.reps.count ? log.reps[i] : 0
                    let prevR = previous?.reps.indices.contains(i) == true ? previous!.reps[i] : nil
                    Text(WeightText.string(grams: current, in: unit))
                        .foregroundStyle(colorForWeight(current: current, previous: prev,
                                                        currentReps: currentR, previousReps: prevR,
                                                        exerciseId: log.exerciseId))
                        .font(.headline)
                }
            }
            GridRow {
                Text("r").font(.headline)
                ForEach(0..<maxCount, id: \.self) { i in
                    let current = i < log.reps.count ? log.reps[i] : 0
                    let prevRep = previous?.reps.indices.contains(i) == true ? previous!.reps[i] : nil
                    let currentW = i < grams.count ? grams[i] : 0
                    let prevW = previousGrams.indices.contains(i) ? previousGrams[i] : nil
                    Text("\(current)")
                        .foregroundStyle(colorForReps(current: current, previous: prevRep,
                                                      currentWeight: currentW, previousWeight: prevW,
                                                      exerciseId: log.exerciseId))
                        .font(.headline)
                }
            }
        }
    }

    // The rules themselves live in Shared/StatsPresentation.swift, where the
    // Mac's log screen reads them too. Green and red here are a claim about
    // the user's training, and two devices colouring the same two rows
    // differently would be telling contradictory stories about one workout.

    private func previousEntry(for exerciseId: UUID, before date: Date) -> WorkoutLog? {
        LogComparison.previous(for: exerciseId, before: date, in: logs)
    }

    /// The exercise's own increment, so a difference smaller than half of it
    /// is left uncoloured — see `LogComparison.tolerance`.
    private func increment(for exerciseId: UUID) -> Int? {
        exercises.first(where: { $0.id == exerciseId })?.weightIncrementGrams
    }

    private func colorForWeight(current: Int, previous: Int?,
                                currentReps: Int, previousReps: Int?,
                                exerciseId: UUID) -> Color {
        LogComparison.weightColour(current: current, previous: previous,
                                   currentReps: currentReps, previousReps: previousReps,
                                   increment: increment(for: exerciseId))
    }

    private func colorForReps(current: Int, previous: Int?, currentWeight: Int,
                              previousWeight: Int?, exerciseId: UUID) -> Color {
        LogComparison.repsColour(current: current, previous: previous,
                                 currentWeight: currentWeight, previousWeight: previousWeight,
                                 increment: increment(for: exerciseId))
    }
}
