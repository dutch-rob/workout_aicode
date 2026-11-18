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
//
// The phone has this screen too, and it is a different screen: a Form in a
// NavigationStack with a decimal keypad, where this is a 430pt panel with a
// Grid of pop-up buttons. What they share is `LogRowDraft` — what gets read
// off a log and what writing it back does to the weights beside it, the
// assisted machine's number and the trailing empty sets. The layout is each
// platform's own; the data is not.

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
    // back on Save; the log itself is not touched in between. See LogRowDraft.
    @State private var loaded = false
    @State private var draft = LogRowDraft.empty

    /// Which set's weight has the keyboard. Asked for the moment the screen
    /// appears rather than on the next turn of the run loop — see
    /// `MacEditLogsView.openOnTheRowThatWasClicked` for what that costs.
    @FocusState private var focused: Int?

    private var log: WorkoutLog? {
        logs.first { $0.id == logId && !$0.isDeleted }
    }

    private var exercise: ExerciseDef? {
        exercises.first { $0.id == draft.exerciseId }
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
                    Picker("", selection: $draft.workoutId) {
                        if !workouts.contains(where: { $0.id == draft.workoutId }) {
                            Text("(missing)").tag(draft.workoutId)
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
                    Picker("", selection: $draft.exerciseId) {
                        if !exercises.contains(where: { $0.id == draft.exerciseId }) {
                            Text("choose…").tag(draft.exerciseId)
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
                    DatePicker("", selection: $draft.date).labelsHidden()
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

            ForEach(draft.grams.indices, id: \.self) { i in
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
                draft.addSet()
                focused = draft.grams.count - 1
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
    /// where the big table trims them too. See LogRowDraft.
    private func weightBinding(_ i: Int) -> Binding<Double> {
        Binding(get: { draft.weight(i, in: unit) },
                set: { draft.setWeight($0, at: i, in: unit) })
    }

    private func repsBinding(_ i: Int) -> Binding<Int> {
        Binding(get: { draft.repetitions(i) },
                set: { draft.setRepetitions($0, at: i) })
    }

    /// Once. `onAppear` runs again when the window comes back to the front,
    /// and re-reading the log then would throw away what had been typed.
    private func load() {
        guard !loaded, let log else { return }
        loaded = true
        draft = LogRowDraft.read(log, in: context)
        focused = draft.grams.isEmpty ? nil : 0
    }

    private func save() {
        guard let log else { return }
        draft.write(to: log, isAerobic: aerobicSeconds != nil, in: context)
        StoreSave.save(context)
        dismiss()
    }
}

/// One row, named so a sheet can be asked for it.
struct LogToCorrect: Identifiable {
    let id: UUID
}
