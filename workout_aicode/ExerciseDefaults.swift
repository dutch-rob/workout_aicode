import SwiftUI

// MARK: - Default numbers for a new exercise
//
// Sets, weight range and increment are the same for most of a person's
// exercises and depend on their gym: a rack of dumbbells going up in 2 kg
// steps, or a machine stack in 5s. Asking once beats correcting every exercise.
//
// These are only the starting values — every exercise can still be changed
// individually on its own screen.

enum ExerciseDefaultsKey {
    static let sets = "defaultNumberOfSets"
    static let lowest = "defaultLowestWeight"
    static let highest = "defaultHighestWeight"
    static let increment = "defaultWeightIncrement"
    /// Set once the question has been asked, so it is never asked again.
    static let asked = "exerciseDefaultsAsked"
}

enum ExerciseDefaults {
    /// What the app used before this was configurable, and what the question
    /// itself starts from.
    static let sets = 3
    static let lowest = 0
    static let highest = 200
    static let increment = 5

    static var current: (sets: Int, lowest: Int, highest: Int, increment: Int) {
        let d = UserDefaults.standard
        return (d.object(forKey: ExerciseDefaultsKey.sets) as? Int ?? sets,
                d.object(forKey: ExerciseDefaultsKey.lowest) as? Int ?? lowest,
                d.object(forKey: ExerciseDefaultsKey.highest) as? Int ?? highest,
                d.object(forKey: ExerciseDefaultsKey.increment) as? Int ?? increment)
    }

    /// A new exercise, with whatever the user chose.
    static func makeExercise(name: String = "",
                             primary: MuscleGroup? = nil,
                             secondary: [MuscleGroup] = [],
                             libraryKey: String? = nil) -> ExerciseDef {
        let d = current
        return ExerciseDef(name: name,
                           numberOfSeries: d.sets,
                           lowestWeight: d.lowest,
                           highestWeight: d.highest,
                           weightIncrement: d.increment,
                           primaryMuscle: primary,
                           secondaryMuscles: secondary,
                           libraryKey: libraryKey)
    }

    /// Only for someone who has not been asked yet. An existing user updating
    /// the app already has exercises set up the way they want, and a popup
    /// offering to change "the defaults" would read as a threat to them.
    static func shouldAsk(existingExercises: Int) -> Bool {
        !UserDefaults.standard.bool(forKey: ExerciseDefaultsKey.asked)
            && existingExercises == 0
    }

    static func markAsked() {
        UserDefaults.standard.set(true, forKey: ExerciseDefaultsKey.asked)
    }
}

// MARK: - The question

struct ExerciseDefaultsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage(ExerciseDefaultsKey.sets) private var sets = ExerciseDefaults.sets
    @AppStorage(ExerciseDefaultsKey.lowest) private var lowest = ExerciseDefaults.lowest
    @AppStorage(ExerciseDefaultsKey.highest) private var highest = ExerciseDefaults.highest
    @AppStorage(ExerciseDefaultsKey.increment) private var increment = ExerciseDefaults.increment

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
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Highest weight") {
                        TextField("", value: $highest, format: .number)
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Weight increment") {
                        TextField("", value: $increment, format: .number)
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("Weights")
                } footer: {
                    Text("The wheels show weights from the lowest to the highest, in steps of the increment. Match the increment to your gym — often 5, or 2 for dumbbells.")
                }
            }
            .navigationTitle("Your usual numbers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if highest < lowest { highest = lowest }
                        if increment < 1 { increment = 1 }
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
                        .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                }
                LabeledContent("Highest weight") {
                    TextField("", value: $highest, format: .number)
                        .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                }
                LabeledContent("Weight increment") {
                    TextField("", value: $increment, format: .number)
                        .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                }
            } header: {
                Text("Weights")
            } footer: {
                Text("Only affects exercises you add from now on.")
            }
        }
        .navigationTitle("new exercise numbers")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            if highest < lowest { highest = lowest }
            if increment < 1 { increment = 1 }
        }
    }
}
