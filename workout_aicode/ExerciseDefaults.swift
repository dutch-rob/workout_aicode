import SwiftUI

// MARK: - Asking for the numbers a new exercise starts with
//
// The values themselves, and everything that reads them, live in
// Shared/NewExerciseDefaults.swift — the Mac creates exercises too, and two
// copies of "what does a new exercise start with" would answer differently on
// the two devices. What stays here is the question: a first-run form with a
// number pad, which is an iOS shape.

// MARK: - The question

struct ExerciseDefaultsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage(ExerciseDefaultsKey.sets) private var sets = ExerciseDefaults.sets
    @AppStorage(ExerciseDefaultsKey.lowest) private var lowest = ExerciseDefaults.lowest
    @AppStorage(ExerciseDefaultsKey.highest) private var highest = ExerciseDefaults.highest
    @AppStorage(ExerciseDefaultsKey.increment) private var increment = ExerciseDefaults.increment
    @AppStorage(RestTimerKey.enabled) private var restTimerOn = false
    @AppStorage(RestTimerKey.defaultSeconds) private var restSeconds = RestTimerDefaults.seconds

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("These are the starting numbers for every exercise you add. You can change any exercise afterwards, and change these again in settings.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("Sets") {
                    Stepper(value: $sets, in: 1...10) {
                        LabeledContent("Number of sets", value: "\(sets)")
                    }
                }

                Section {
                    LabeledContent("Lowest weight") {
                        TextField("", value: $lowest, format: .number)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Highest weight") {
                        TextField("", value: $highest, format: .number)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Weight increment") {
                        TextField("", value: $increment, format: .number)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("Weights")
                } footer: {
                    Text("The wheels show weights from the lowest to the highest, in steps of the increment. Match the increment to your gym — often 5, or 2.5 for dumbbells. Halves and quarters are allowed.")
                }

                Section {
                    Toggle("Rest timer", isOn: $restTimerOn)
                        .onChange(of: restTimerOn) { _, on in
                            if on { RestTimerDefaults.requestNotificationPermission() }
                        }
                    if restTimerOn {
                        RestSecondsPicker(title: "Rest between sets", seconds: $restSeconds)
                    }
                } footer: {
                    Text("Counts your rest after every set and between exercises. You can put the phone away while it runs — it buzzes when the rest is over. Each exercise can be given its own rest afterwards, and the whole thing can be switched off again in settings.")
                }
            }
            .navigationTitle("Your usual numbers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if highest < lowest { highest = lowest }
                        if increment < 0.25 { increment = 0.25 }
                        ExerciseDefaults.markAsked()
                        dismiss()
                    }
                }
            }
            .interactiveDismissDisabled()
        }
    }
}

/// The same numbers, reachable from settings afterwards — the first-run
/// question promises as much, and a promise the settings screen does not keep
/// is worse than not making it.
struct ExerciseDefaultsSettings: View {
    @AppStorage(ExerciseDefaultsKey.sets) private var sets = ExerciseDefaults.sets
    @AppStorage(ExerciseDefaultsKey.lowest) private var lowest = ExerciseDefaults.lowest
    @AppStorage(ExerciseDefaultsKey.highest) private var highest = ExerciseDefaults.highest
    @AppStorage(ExerciseDefaultsKey.increment) private var increment = ExerciseDefaults.increment
    @AppStorage(RestTimerKey.defaultSeconds) private var restSeconds = RestTimerDefaults.seconds

    var body: some View {
        Form {
            Section("Sets") {
                Stepper(value: $sets, in: 1...10) {
                    LabeledContent("Number of sets", value: "\(sets)")
                }
            }
            Section {
                LabeledContent("Lowest weight") {
                    TextField("", value: $lowest, format: .number)
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                }
                LabeledContent("Highest weight") {
                    TextField("", value: $highest, format: .number)
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                }
                LabeledContent("Weight increment") {
                    TextField("", value: $increment, format: .number)
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                }
            } header: {
                Text("Weights")
            } footer: {
                Text("Only affects exercises you add from now on.")
            }
            Section {
                RestSecondsPicker(title: "Rest between sets", seconds: $restSeconds)
            } header: {
                Text("Rest timer")
            } footer: {
                Text("Only affects exercises you add from now on. Change an existing exercise on its own screen.")
            }
        }
        .navigationTitle("new exercise numbers")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            if highest < lowest { highest = lowest }
            if increment < 0.25 { increment = 0.25 }
        }
    }
}
