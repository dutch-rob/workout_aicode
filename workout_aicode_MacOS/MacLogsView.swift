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
    @Query private var aerobicResults: [AerobicResult]

    @State private var search = ""
    @Environment(\.modelContext) private var context
    @State private var editing: LogEditSession?
    @State private var couldNotOpen: String?

    private var exerciseNames: [UUID: String] {
        Dictionary(exercises.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
    }

    private var workoutNames: [UUID: String] {
        Dictionary(workouts.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
    }

    /// Filtering keeps whole sessions: a session with a matching exercise in it
    /// stays, with its other exercises alongside. Dropping those would show a
    /// squat next to nothing and lose what it was done among.
    private var sessions: [LogSessions.Session] {
        let all = LogSessions.group(logs, workoutNames: workoutNames)
        let needle = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return all }
        return all.filter { session in
            session.workoutName.lowercased().contains(needle)
                || session.logs.contains {
                    (exerciseNames[$0.exerciseId] ?? "").lowercased().contains(needle)
                }
        }
    }

    var body: some View {
        Group {
            if logs.isEmpty {
                MacEmptyState(thing: "logs")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    HStack {
                        TextField("Search an exercise or a workout", text: $search)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 320)
                        Spacer()
                        Text(countLine)
                            .font(.caption).foregroundStyle(.secondary)
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
        let n = sessions.count
        let total = LogSessions.group(logs, workoutNames: workoutNames).count
        if n == total { return "\(total) sessions · \(logs.count) exercises logged" }
        return "\(n) of \(total) sessions"
    }

    @ViewBuilder private var list: some View {
        if sessions.isEmpty {
            ContentUnavailableView("Nothing matches",
                                   systemImage: "magnifyingglass",
                                   description: Text("No workout or exercise called “\(search)”."))
        } else {
            List {
                ForEach(sessions) { session in
                    Section {
                        ForEach(session.logs) { log in
                            row(log)
                        }
                    } header: {
                        HStack {
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
        let count = max(log.weights.count, log.reps.count)
        // Half of this is the difference worth colouring — see
        // LogComparison.tolerance. It matters for the assisted machines, whose
        // logged weight moves with the user's body weight.
        let incrementForLog = exercises.first(where: { $0.id == log.exerciseId })?.weightIncrement
        return HStack(spacing: 10) {
            ForEach(0..<count, id: \.self) { i in
                let weight = i < log.weights.count ? log.weights[i] : 0
                let reps = i < log.reps.count ? log.reps[i] : 0
                let previousWeight = previous?.weights.indices.contains(i) == true
                    ? previous!.weights[i] : nil
                let previousReps = previous?.reps.indices.contains(i) == true
                    ? previous!.reps[i] : nil
                VStack(spacing: 0) {
                    Text("\(weight)")
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
