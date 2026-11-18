import SwiftUI
import SwiftData

// MARK: - Correcting one row
//
// What clicking a row on the Logs screen opens: that row, on its own, with the
// cursor in its first weight. The flat table of every row ever logged is still
// there behind the toolbar button, for the jobs that need it — adding a row,
// deleting one, correcting several at once.
//
// NOTHING IS WRITTEN UNTIL "Save", which is what makes this screen as light as
// it is. The big editor cannot work that way: it edits the live records, so it
// has to copy every log before it opens, switch draft mode on, and ask on the
// way out whether the changes were meant. One row's numbers fit in this
// screen's own state, so the way back from a mistake is to close the window —
// there is nothing to restore, because nothing has been changed yet.
//
// That difference is the whole reason this file exists:
//
//                       │ this screen      │ the whole table
//   ───────────────────┼──────────────────┼───────────────────────────────
//   copy of every log  │ none             │ taken before it opens
//   draft mode         │ untouched        │ switched on, asked about on exit
//   written            │ on Save          │ as you type
//   can add or delete  │ no               │ yes
//
// Draft mode is not needed here for a second reason as well as speed: it only
// ever undoes things CREATED while drafting, and this screen creates nothing.
// Correcting a set that was logged last Tuesday was never something leaving
// draft would have put back.

struct MacEditOneLogView: View {
    let logId: UUID

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query private var logs: [WorkoutLog]
    @Query(sort: [SortDescriptor(\WorkoutDef.name)]) private var workouts: [WorkoutDef]
    @Query(sort: [SortDescriptor(\ExerciseDef.name)]) private var exercises: [ExerciseDef]
    @Query private var aerobicResults: [AerobicResult]
    @Query private var assistedResults: [AssistedResult]

    // What is being typed. Read off the log when the screen opens and written
    // back on Save; the log itself is not touched in between.
    @State private var loaded = false
    @State private var date = Date()
    @State private var workoutId = UUID()
    @State private var exerciseId = UUID()
    /// GRAMS, like everything stored. The fields show the user's unit.
    @State private var grams: [Int] = []
    @State private var reps: [Int] = []

    /// Which set's weight has the keyboard. Asked for the moment the screen
    /// appears rather than on the next turn of the run loop — see
    /// `MacEditLogsView.openOnTheRowThatWasClicked` for what that costs.
    @FocusState private var focused: Int?

    private var log: WorkoutLog? {
        logs.first { $0.id == logId && !$0.isDeleted }
    }

    private var exercise: ExerciseDef? {
        exercises.first { $0.id == exerciseId }
    }

    /// A ride has no sets, only a duration, and this screen does not offer to
    /// change it: what it was is what the Watch measured.
    private var aerobicSeconds: Int? {
        aerobicResults.first { !$0.isDeleted && $0.logId == logId }?.durationSeconds
    }

    /// What the machine was carrying, per set, for an assisted exercise. Shown
    /// under the weight it was worked out from, and not typeable, for the same
    /// reason as in the big table.
    private var machineSettings: [Int] {
        assistedResults.first { !$0.isDeleted && $0.logId == logId }?
            .machineSettingsGrams ?? []
    }

    private var unit: WeightUnit { .current }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("Workout").gridColumnAlignment(.trailing)
                    Picker("", selection: $workoutId) {
                        if !workouts.contains(where: { $0.id == workoutId }) {
                            Text("(missing)").tag(workoutId)
                        }
                        ForEach(workouts) {
                            Text($0.name.isEmpty ? "(unnamed)" : $0.name).tag($0.id)
                        }
                    }
                    .labelsHidden()
                    // The button is narrower than the column and would
                    // otherwise be centred in it, out of line with the row
                    // above and the row below.
                    .frame(width: 220, alignment: .leading)
                }
                GridRow {
                    Text("Exercise")
                    Picker("", selection: $exerciseId) {
                        if !exercises.contains(where: { $0.id == exerciseId }) {
                            Text("choose…").tag(exerciseId)
                        }
                        ForEach(exercises) {
                            Text($0.name.isEmpty ? "(unnamed)" : $0.name).tag($0.id)
                        }
                    }
                    .labelsHidden()
                    // The button is narrower than the column and would
                    // otherwise be centred in it, out of line with the row
                    // above and the row below.
                    .frame(width: 220, alignment: .leading)
                }
                GridRow {
                    Text("When")
                    DatePicker("", selection: $date).labelsHidden()
                }
            }
            .macFont(.callout)

            Divider()

            if let aerobicSeconds {
                Label("aerobic · \(minutesSeconds(aerobicSeconds))", systemImage: "bicycle")
                    .macFont(.callout)
                    .foregroundStyle(.secondary)
            } else {
                sets
            }

            Divider()
            buttons
        }
        .padding(18)
        .frame(width: 430)
        .onAppear(perform: load)
    }

    // MARK: The parts

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Correct this row").macFont(.title3).bold()
            Text("Nothing is changed until you save.")
                .macFont(.caption).foregroundStyle(.secondary)
        }
    }

    private var sets: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("").frame(width: 46, alignment: .leading)
                Text(unit.label).frame(width: 62, alignment: .leading)
                Text("reps").frame(width: 62, alignment: .leading)
            }
            .macFont(.caption).foregroundStyle(.secondary)

            ForEach(grams.indices, id: \.self) { i in
                HStack(spacing: 8) {
                    Text("Set \(i + 1)")
                        .macFont(.callout).foregroundStyle(.secondary)
                        .frame(width: 46, alignment: .leading)
                    TextField("", value: weightBinding(i), format: .number)
                        .frame(width: 62)
                        .focused($focused, equals: i)
                    TextField("", value: repsBinding(i), format: .number)
                        .frame(width: 62)
                    if i < machineSettings.count {
                        Text("machine \(WeightText.string(grams: machineSettings[i], in: unit))")
                            .macFont(.caption2).foregroundStyle(.secondary)
                    }
                }
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
            }

            Button {
                grams.append(grams.last ?? 0)
                reps.append(0)
                focused = grams.count - 1
            } label: {
                Label("One more set", systemImage: "plus.circle")
            }
            .buttonStyle(.plain)
            .macFont(.caption)
            .foregroundStyle(Color.accentColor)
            .padding(.top, 2)
        }
    }

    private var buttons: some View {
        HStack {
            // Said out loud, because the one thing this screen cannot do is
            // the thing somebody might come here to do.
            Text("Adding and deleting rows is in Edit logs.")
                .macFont(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Save") { save() }
                .keyboardShortcut(.defaultAction)
                .disabled(log == nil)
        }
    }

    // MARK: Reading and writing

    /// Reads in the user's unit, keeps grams. A set at no weight is still a
    /// set, so nothing is dropped here — the trailing empties go on Save,
    /// where the big table trims them too.
    private func weightBinding(_ i: Int) -> Binding<Double> {
        Binding(get: { unit.display(grams: i < grams.count ? grams[i] : 0) },
                set: { value in
                    guard i < grams.count else { return }
                    grams[i] = unit.grams(from: max(0, value))
                })
    }

    private func repsBinding(_ i: Int) -> Binding<Int> {
        Binding(get: { i < reps.count ? reps[i] : 0 },
                set: { value in
                    guard i < reps.count else { return }
                    reps[i] = max(0, value)
                })
    }

    /// Once. `onAppear` runs again when the window comes back to the front,
    /// and re-reading the log then would throw away what had been typed.
    private func load() {
        guard !loaded, let log else { return }
        loaded = true
        date = log.date
        workoutId = log.workoutId
        exerciseId = log.exerciseId
        let stored = LogEditing.grams(for: log, in: context)
        let count = max(stored.count, log.reps.count)
        grams = (0..<count).map { $0 < stored.count ? stored[$0] : 0 }
        reps = (0..<count).map { $0 < log.reps.count ? log.reps[$0] : 0 }
        focused = grams.isEmpty ? nil : 0
    }

    private func save() {
        guard let log else { return }
        log.date = date
        log.workoutId = workoutId
        log.exerciseId = exerciseId

        if aerobicSeconds == nil {
            LogEditing.extend(log, toSets: grams.count, in: context)
            for i in grams.indices {
                LogEditing.setGrams(grams[i], at: i, for: log, in: context)
                // On an assisted machine the weight here is what was lifted;
                // the machine's own number follows it.
                LogEditing.realignAssisted(log: log, set: i, in: context)
                log.reps[i] = i < reps.count ? reps[i] : 0
            }
            // A set with nothing in it at the end of a row is a column the
            // table would keep offering for ever.
            LogEditing.trimEmptyTrailingSets(log, in: context)
        }

        StoreSave.save(context)
        dismiss()
    }
}

/// One row, named so a sheet can be asked for it.
struct LogToCorrect: Identifiable {
    let id: UUID
}
