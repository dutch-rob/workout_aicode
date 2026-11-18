import SwiftUI
import SwiftData

// MARK: - Correcting one logged row, on the phone
//
// What tapping a row on the logs tab opens. The Mac has the same screen, and
// the two share `LogRowDraft` — what is read off the log, and what writing it
// back does to the weights beside it, the assisted machine's own number and
// the trailing empty sets. Everything below is the phone's own: a Form in a
// NavigationStack, with a keypad rather than a pop-up panel.
//
// NOTHING IS WRITTEN UNTIL "Save". There is no copy of the log kept anywhere,
// no draft mode switched on and no question asked on the way out, because the
// way back from a mistake is "Cancel" — the log has not been touched yet.
// (The Mac's OTHER editor, the flat table of every row ever logged, does need
// all three, because it writes as you type. The phone does not have that one.)
//
// THE NUMBERS ARE TYPED HERE, not rolled. Logging uses wheels, which are right
// for a number you are choosing at a machine between sets; this is a number
// you already know and are putting right, and a keypad is three taps where a
// wheel is a hunt. Same reasoning as the weights on EditExerciseView.

struct EditOneLogView: View {
    let logId: UUID

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query private var logs: [WorkoutLog]
    @Query(sort: [SortDescriptor(\WorkoutDef.name)]) private var workouts: [WorkoutDef]
    @Query(sort: [SortDescriptor(\ExerciseDef.name)]) private var exercises: [ExerciseDef]
    @Query private var aerobicResults: [AerobicResult]
    @Query private var assistedResults: [AssistedResult]

    @State private var loaded = false
    @State private var draft = LogRowDraft.empty
    /// Which field has the keyboard, so there can be a way to put it away: a
    /// number pad has no return key, and without this the only way back from
    /// it is to hit Save or Cancel.
    @FocusState private var typing: Bool

    private var log: WorkoutLog? {
        logs.first { $0.id == logId && !$0.isDeleted }
    }

    /// A ride has no sets, only a duration, and this screen does not offer to
    /// change it: what it was is what the Watch measured.
    private var aerobicSeconds: Int? {
        aerobicResults.first { !$0.isDeleted && $0.logId == logId }?.durationSeconds
    }

    /// What the machine was carrying, per set, for an assisted exercise. Shown
    /// under the weight it was worked out from, and not typeable: the log
    /// holds what was LIFTED, and the machine's number follows from that and
    /// the body weight recorded with the set — see LogEditing.realignAssisted.
    private var machineSettings: [Int] {
        assistedResults.first { !$0.isDeleted && $0.logId == logId }?
            .machineSettingsGrams ?? []
    }

    private var unit: WeightUnit { .current }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Workout", selection: $draft.workoutId) {
                        if !workouts.contains(where: { $0.id == draft.workoutId }) {
                            Text("(missing)").tag(draft.workoutId)
                        }
                        ForEach(workouts) {
                            Text($0.name.isEmpty ? "(unnamed)" : $0.name).tag($0.id)
                        }
                    }
                    Picker("Exercise", selection: $draft.exerciseId) {
                        if !exercises.contains(where: { $0.id == draft.exerciseId }) {
                            Text("choose…").tag(draft.exerciseId)
                        }
                        ForEach(exercises) {
                            Text($0.name.isEmpty ? "(unnamed)" : $0.name).tag($0.id)
                        }
                    }
                    DatePicker("When", selection: $draft.date)
                } footer: {
                    Text("Nothing is changed until you save.")
                }

                if let aerobicSeconds {
                    Section {
                        LabeledContent("Duration", value: minutesSeconds(aerobicSeconds))
                    } footer: {
                        Text("A ride's time and heart rate are what the Watch measured, so they are not edited here.")
                    }
                } else {
                    sets
                }
            }
            .navigationTitle("Correct this row")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(log == nil)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { typing = false }
                }
            }
            .onAppear(perform: load)
        }
    }

    @ViewBuilder private var sets: some View {
        Section {
            ForEach(draft.grams.indices, id: \.self) { i in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 10) {
                        Text("Set \(i + 1)")
                            .foregroundStyle(.secondary)
                            .frame(width: 54, alignment: .leading)
                        TextField("", value: weightBinding(i), format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .focused($typing)
                        Text(unit.label).foregroundStyle(.secondary)
                        TextField("", value: repsBinding(i), format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .focused($typing)
                        Text("reps").foregroundStyle(.secondary)
                    }
                    if i < machineSettings.count {
                        Text("machine \(WeightText.string(grams: machineSettings[i], in: unit))")
                            .font(.caption2).foregroundStyle(.secondary)
                            .padding(.leading, 64)
                    }
                }
            }
            Button {
                draft.addSet()
            } label: {
                Label("One more set", systemImage: "plus.circle")
            }
        } header: {
            Text("Sets")
        } footer: {
            // Said out loud, because it is the one thing somebody might come
            // here to do and cannot. A row appears by being logged; taking one
            // away is the Mac's flat table, which is the only editor that can.
            Text("A set left empty at the end is dropped when you save. Deleting a whole row is on the Mac.")
        }
    }

    // MARK: Reading and writing

    private func weightBinding(_ i: Int) -> Binding<Double> {
        Binding(get: { draft.weight(i, in: unit) },
                set: { draft.setWeight($0, at: i, in: unit) })
    }

    private func repsBinding(_ i: Int) -> Binding<Int> {
        Binding(get: { draft.repetitions(i) },
                set: { draft.setRepetitions($0, at: i) })
    }

    /// Once. `onAppear` runs again when the sheet comes back to the front, and
    /// re-reading the log then would throw away what had been typed.
    private func load() {
        guard !loaded, let log else { return }
        loaded = true
        draft = LogRowDraft.read(log, in: context)
    }

    private func save() {
        guard let log else { return }
        draft.write(to: log, isAerobic: aerobicSeconds != nil, in: context)
        StoreSave.save(context)
        dismiss()
    }
}

/// One row, named so a sheet can be asked for it. The Mac has its own of
/// these; a UUID on its own is not Identifiable.
struct LogRowToCorrect: Identifiable {
    let id: UUID
}
