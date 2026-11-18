import SwiftUI
import SwiftData

// MARK: - Edit logs
//
// The flat table the log list is not: one row per logged exercise, with the
// workout and the exercise as dropdowns, the date typeable, and the sets in
// weight/reps pairs across the row. An empty row at the bottom adds one.
//
// It opens as a sheet rather than as a sidebar section, and that is deliberate.
// The rules about draft mode are all about entering and leaving this screen, so
// leaving has to be one thing the user does on purpose — not something that can
// happen by clicking "Graphs" in the sidebar while half a row is typed.
//
// This is the screen for the jobs that need the whole log at once: adding a
// row, deleting one, correcting several. Correcting ONE row does not come here
// — clicking it on the Logs screen opens MacEditOneLogView, which holds one
// row's numbers in its own state, writes on Save, and therefore needs none of
// the copying, drafting and asking below. This screen briefly opened scrolled
// to a clicked row instead; that is what the one-row screen replaced.

/// Everything that has to be remembered from the moment the screen opened.
struct LogEditSession: Identifiable {
    let id = UUID()
    /// Whether draft was already on. Decides what leaving does when nothing
    /// was changed: a draft the user started stays, one this screen started
    /// goes.
    let wasInDraft: Bool
    let snapshot: LogSnapshot
}

struct MacEditLogsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let session: LogEditSession

    @Query(sort: [SortDescriptor(\WorkoutLog.date, order: .reverse)]) private var logs: [WorkoutLog]
    @Query(sort: [SortDescriptor(\WorkoutDef.name)]) private var workouts: [WorkoutDef]
    @Query(sort: [SortDescriptor(\ExerciseDef.name)]) private var exercises: [ExerciseDef]
    @Query private var aerobicResults: [AerobicResult]
    @Query private var assistedResults: [AssistedResult]
    @Query private var logWeights: [LogWeights]

    @State private var leaving = false
    @State private var failure: String?

    // The row at the bottom, before it becomes a log.
    @State private var newWorkout: UUID?
    @State private var newExercise: UUID?
    @State private var newDate = Date()
    @State private var newWeights: [Int] = [0, 0, 0]
    @State private var newReps: [Int] = [0, 0, 0]

    /// One row as plain values.
    ///
    /// The table draws from these, never from the model objects, and that is
    /// what stopped it crashing on delete. SwiftData tears a deleted object's
    /// backing data away immediately; SwiftUI then redraws, and the row for the
    /// row just removed read `weights` off the detached object:
    ///
    ///   "This backing data was detached from a context without resolving
    ///    attribute faults ... \WorkoutLog.weights"
    ///
    /// The same lesson as the phone's start screen, in a different costume:
    /// hold identities, and look the object up only where it is about to be
    /// written to. A value cannot fault.
    private struct Row: Identifiable {
        let id: UUID
        let workoutId: UUID
        let exerciseId: UUID
        let date: Date
        let weights: [Int]
        let reps: [Int]
        /// Set for an aerobic row, which has a duration instead of sets.
        let aerobicSeconds: Int?
        /// What was set on the machine, per set, for an assisted exercise —
        /// the number the weight column was worked out from. Empty otherwise.
        let machineSettings: [Int]
    }

    private var rows: [Row] {
        let durations = Dictionary(aerobicResults.filter { !$0.isDeleted }
                                        .map { ($0.logId, $0.durationSeconds) },
                                   uniquingKeysWith: { a, _ in a })
        let machines = Dictionary(assistedResults.filter { !$0.isDeleted }
                                        .compactMap { result -> (UUID, [Int])? in
                                            guard let grams = result.machineSettingsGrams
                                            else { return nil }
                                            return (result.logId, grams)
                                        },
                                  uniquingKeysWith: { a, _ in a })
        let weightsByLog = LogWeightsIndex.byLogId(logWeights)
        return logs.filter { !$0.isDeleted }.map {
            Row(id: $0.id, workoutId: $0.workoutId, exerciseId: $0.exerciseId,
                date: $0.date, weights: weightsByLog[$0.id] ?? [], reps: $0.reps,
                aerobicSeconds: durations[$0.id],
                machineSettings: machines[$0.id] ?? [])
        }
    }

    /// The live record behind a row, when one is about to be changed. Nil once
    /// it has been deleted, so an edit arriving late is dropped rather than
    /// crashing.
    private func record(_ id: UUID) -> WorkoutLog? {
        logs.first { $0.id == id && !$0.isDeleted }
    }

    /// The rows, and how many weight/reps pairs wide the table is: at least
    /// three, so there is somewhere to type, and one spare past the longest row
    /// so a set can always be added without a control for adding columns.
    ///
    /// WORKED OUT ONCE PER REDRAW, and handed down, which is the whole reason
    /// this type exists. Both were computed properties, and the width asked
    /// `rows` for the longest row — so drawing the table rebuilt the whole
    /// table once per row, dictionaries and all, to find out how wide it was.
    /// That is quadratic in the number of logs and it happens again on every
    /// keystroke: measured at 0.13ms a rebuild, a few hundred logs is a few
    /// hundred milliseconds of it per redraw, for an answer that cannot change
    /// between one row and the next.
    ///
    /// It was NOT what made the editor slow to open — that is the sheet
    /// arriving, see `openOnTheRowThatWasClicked` — and measuring said so
    /// before this was written down as a fix for it.
    private struct Layout {
        let rows: [Row]
        let setColumns: Int
    }

    private var layout: Layout {
        let rows = self.rows
        let longest = rows.map { max($0.weights.count, $0.reps.count) }.max() ?? 0
        return Layout(rows: rows, setColumns: min(12, max(3, longest + 1)))
    }

    private var changed: Bool { LogEditing.hasChanged(from: session.snapshot, in: context) }

    var body: some View {
        let layout = self.layout
        return VStack(spacing: 0) {
            header
            Divider()
            table(layout)
            Divider()
            footer(layout)
        }
        .frame(minWidth: 900, idealWidth: 1100, minHeight: 560, idealHeight: 700)
        .confirmationDialog("Leave the log editor?", isPresented: $leaving,
                            titleVisibility: .visible) {
            Button("Keep the changes and leave draft") { keepAndLeave() }
            Button("Discard the changes made here", role: .destructive) { discardAndLeave() }
            Button("Continue in draft", role: .cancel) { }
        } message: {
            Text("You changed the log. Keeping puts the changes in for good and ends draft. Discarding puts the log back exactly as it was when you opened this screen — it does not touch anything else you made while drafting.")
        }
        .alert("Could not put the log back",
               isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK", role: .cancel) { failure = nil }
        } message: {
            Text(failure ?? "")
        }
    }

    // MARK: Chrome

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Edit logs").macFont(.title3).bold()
                Text("Changes are draft changes until you say otherwise.")
                    .macFont(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Label("Draft", systemImage: "pencil.and.outline")
                .foregroundStyle(.orange)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(Color.orange.opacity(0.15)))
        }
        .padding(12)
    }

    private func footer(_ layout: Layout) -> some View {
        HStack {
            Text("\(layout.rows.count) rows")
                .macFont(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Done") { finish() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }

    // MARK: The table

    private func table(_ layout: Layout) -> some View {
        ScrollView([.vertical, .horizontal]) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(layout.rows) { row in
                        self.row(row, layout.setColumns)
                        Divider()
                    }
                    newRow(layout.setColumns)
                } header: {
                    columnTitles(layout.setColumns)
                }
            }
            .padding(.horizontal, 12)
        }
    }

    private func columnTitles(_ setColumns: Int) -> some View {
        HStack(spacing: 8) {
            Text("Workout").frame(width: 160, alignment: .leading)
            Text("Exercise").frame(width: 190, alignment: .leading)
            Text("Date and time").frame(width: 180, alignment: .leading)
            ForEach(0..<setColumns, id: \.self) { i in
                Text("w/r \(i + 1)").frame(width: 74, alignment: .leading)
            }
            Text("").frame(width: 26)
        }
        .macFont(.caption).bold()
        .foregroundStyle(.secondary)
        .padding(.vertical, 6)
        .background(.regularMaterial)
    }

    private func row(_ row: Row, _ setColumns: Int) -> some View {
        HStack(spacing: 8) {
            workoutPicker(selection: Binding(get: { row.workoutId },
                                             set: { record(row.id)?.workoutId = $0 }))
            exercisePicker(selection: Binding(get: { row.exerciseId },
                                              set: { record(row.id)?.exerciseId = $0 }))
            DatePicker("", selection: Binding(get: { row.date },
                                              set: { record(row.id)?.date = $0 }))
                .labelsHidden()
                .frame(width: 180)

            if let seconds = row.aerobicSeconds {
                // A ride has no sets. Showing empty weight boxes would invite
                // someone to type a number into a row that has no use for one.
                Text("aerobic · \(minutesSeconds(seconds))")
                    .macFont(.callout).foregroundStyle(.secondary)
                    .frame(width: CGFloat(setColumns) * 82, alignment: .leading)
            } else {
                ForEach(0..<setColumns, id: \.self) { i in
                    setPair(weight: weightBinding(row, i), reps: repsBinding(row, i),
                            machine: i < row.machineSettings.count ? row.machineSettings[i] : nil)
                }
            }

            Button {
                delete(row.id)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Remove this row")
            .frame(width: 26)
        }
        .padding(.vertical, 3)
    }

    private func newRow(_ setColumns: Int) -> some View {
        HStack(spacing: 8) {
            workoutPicker(selection: Binding(get: { newWorkout ?? workouts.first?.id ?? UUID() },
                                             set: { newWorkout = $0 }))
            exercisePicker(selection: Binding(get: { newExercise ?? UUID() },
                                              set: { newExercise = $0 }))
            DatePicker("", selection: $newDate).labelsHidden().frame(width: 180)

            ForEach(0..<setColumns, id: \.self) { i in
                setPair(weight: newWeightBinding(i), reps: newRepsBinding(i))
            }

            Button {
                add()
            } label: {
                Image(systemName: "plus.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(canAdd ? Color.accentColor : .secondary)
            .disabled(!canAdd)
            .help(canAdd ? "Add this row" : "Choose an exercise first")
            .frame(width: 26)
        }
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.06))
    }

    // MARK: Cells

    private func workoutPicker(selection: Binding<UUID>) -> some View {
        Picker("", selection: selection) {
            // A log whose workout was deleted still has to show something, or
            // the picker would silently pick the first workout in the list and
            // move the row into it.
            if !workouts.contains(where: { $0.id == selection.wrappedValue }) {
                Text("(missing)").tag(selection.wrappedValue)
            }
            ForEach(workouts) { Text($0.name.isEmpty ? "(unnamed)" : $0.name).tag($0.id) }
        }
        .labelsHidden()
        .frame(width: 160)
    }

    private func exercisePicker(selection: Binding<UUID>) -> some View {
        Picker("", selection: selection) {
            if !exercises.contains(where: { $0.id == selection.wrappedValue }) {
                Text("choose…").tag(selection.wrappedValue)
            }
            ForEach(exercises) { Text($0.name.isEmpty ? "(unnamed)" : $0.name).tag($0.id) }
        }
        .labelsHidden()
        .frame(width: 190)
    }

    private func setPair(weight: Binding<Double>, reps: Binding<Int>,
                         machine: Int? = nil) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 2) {
                TextField("", value: weight, format: .number)
                    .frame(width: 34)
                TextField("", value: reps, format: .number)
                    .frame(width: 34)
            }
            .multilineTextAlignment(.trailing)
            // What the machine was carrying, for an assisted set. Not editable:
            // the weight above is what was lifted, and this follows it — typing
            // here would be two ways to say the same thing, which is how the
            // two come to disagree.
            if let machine {
                Text("machine \(WeightText.string(grams: machine, in: WeightUnit.current))")
                    .macFont(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .monospacedDigit()
        .frame(width: 74, alignment: .leading)
    }

    /// Reads the row's own copy, writes to the record behind it — which may be
    /// gone by the time a field commits, hence the lookup on every write.
    /// Reads and writes in the user's unit; what is stored is grams.
    private func weightBinding(_ row: Row, _ i: Int) -> Binding<Double> {
        let unit = WeightUnit.current
        return Binding(
            get: {
                let grams = i < row.weights.count ? row.weights[i] : 0
                return unit.display(grams: grams)
            },
            set: { value in
                guard let log = record(row.id) else { return }
                LogEditing.setGrams(unit.grams(from: max(0, value)), at: i,
                                    for: log, in: context)
                // On an assisted machine this column is the weight lifted;
                // the machine's own number is kept in step with it.
                LogEditing.realignAssisted(log: log, set: i, in: context)
            })
    }

    private func repsBinding(_ row: Row, _ i: Int) -> Binding<Int> {
        Binding(get: { i < row.reps.count ? row.reps[i] : 0 },
                set: { value in
                    guard let log = record(row.id) else { return }
                    LogEditing.extend(log, toSets: i + 1, in: context)
                    log.reps[i] = value
                })
    }

    /// The bottom row is not a log yet, so its cells write to state rather
    /// than to a record. Both arrays grow together, for the same reason a
    /// log's do.
    /// The row being typed at the bottom. `newWeights` holds GRAMS, like
    /// everything stored; the cell shows and takes the user's unit.
    private func newWeightBinding(_ i: Int) -> Binding<Double> {
        let unit = WeightUnit.current
        return Binding(
            get: {
                unit.display(grams: i < newWeights.count ? newWeights[i] : 0)
            },
            set: { value in
                growNewRow(to: i + 1)
                newWeights[i] = unit.grams(from: max(0, value))
            })
    }

    private func newRepsBinding(_ i: Int) -> Binding<Int> {
        Binding(get: { i < newReps.count ? newReps[i] : 0 },
                set: { value in growNewRow(to: i + 1); newReps[i] = value })
    }

    private func growNewRow(to count: Int) {
        while newWeights.count < count { newWeights.append(0) }
        while newReps.count < count { newReps.append(0) }
    }

    // MARK: Adding and removing

    private var canAdd: Bool {
        newExercise != nil && exercises.contains { $0.id == newExercise }
    }

    private func add() {
        guard let exerciseId = newExercise else { return }
        let workoutId = newWorkout ?? workouts.first?.id ?? UUID()
        var weights = newWeights, reps = newReps
        while let w = weights.last, let r = reps.last, w == 0, r == 0 {
            weights.removeLast(); reps.removeLast()
        }
        // The weights go beside the log, in grams, with the original unit-less
        // numbers in the log's own field for whatever has yet to update — see
        // WeightHistory.legacyNumbers.
        let legacyUnit = WeightHistory.statedUnit ?? .current
        let definition = exercises.first { $0.id == exerciseId }
        let log = WorkoutLog(date: newDate, workoutId: workoutId,
                             exerciseId: exerciseId,
                             weights: WeightHistory.legacyNumbers(
                                for: weights, of: definition, in: legacyUnit),
                             reps: reps)
        context.insert(log)
        context.insert(LogWeights(logId: log.id, grams: weights))
        DraftMode.note(log: log.id, in: context)
        StoreSave.save(context)

        newExercise = nil
        newWeights = [0, 0, 0]
        newReps = [0, 0, 0]
    }

    private func delete(_ id: UUID) {
        guard let log = record(id) else { return }
        for result in aerobicResults where !result.isDeleted && result.logId == id {
            context.delete(result)
        }
        DraftMode.forget(id: id, in: context)
        context.delete(log)
        // Saved at once, so the query that feeds this table stops handing back
        // a row whose record has gone.
        StoreSave.save(context)
    }

    // MARK: Leaving

    private func finish() {
        for log in logs where !log.isDeleted {
            LogEditing.trimEmptyTrailingSets(log, in: context)
        }
        StoreSave.save(context)

        if changed {
            leaving = true               // ask; the dialog's buttons do the rest
        } else if session.wasInDraft {
            dismiss()                    // their draft, still theirs
        } else {
            DraftMode.keepAll(in: context)   // this screen started it; nothing was made
            dismiss()
        }
    }

    private func keepAndLeave() {
        DraftMode.keepAll(in: context)
        dismiss()
    }

    private func discardAndLeave() {
        do {
            try LogEditing.restore(session.snapshot, in: context)
            if !session.wasInDraft { DraftMode.keepAll(in: context) }
            dismiss()
        } catch {
            // Never close on a failed restore: the user asked for their log
            // back and has not got it, and closing would hide that.
            failure = error.localizedDescription
        }
    }
}
