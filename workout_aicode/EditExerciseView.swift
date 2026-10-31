// One exercise's definition: its name, kind, muscles, wheel and rest.

import SwiftUI
import SwiftData

// MARK: - Edit Exercise Screen
struct EditExerciseView: View {
    /// Asked once, the first time any exercise is set to subtract from body
    /// weight — see the alert below.
    static let unitCheckedKey = "bodyWeightUnitChecked"
    @State private var confirmUnit = false

    /// A weight field: typed in the user's unit, stored in grams.
    ///
    /// Nil means an exercise whose weights have not been given a unit yet —
    /// see `WeightHistory`. It reads as zero until the user answers, which is
    /// the one honest thing to show for a number whose meaning is unknown.
    private func weightField(_ keyPath: ReferenceWritableKeyPath<ExerciseDef, Int?>) -> Binding<Double> {
        Binding(
            get: {
                guard let grams = exercise[keyPath: keyPath] else { return 0 }
                return WeightUnit.current.display(grams: grams)
            },
            set: { typed in
                // A field with nothing in it shows 0, and SwiftUI commits what
                // it shows — which turned "no unit yet" into a stored zero,
                // and a stored zero into a wheel with one value on it. Writing
                // the placeholder back is therefore refused: only a number the
                // user actually put there counts.
                let grams = WeightUnit.current.grams(from: max(0, typed))
                guard grams > 0 || exercise[keyPath: keyPath] != nil else { return }
                exercise[keyPath: keyPath] = grams
                // Keep the unit-less fields describing the same wheel, for
                // every device that can only read those.
                exercise.syncLegacyRange()
            }
        )
    }

    @Bindable var exercise: ExerciseDef
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var store: AppStore
    @Query(sort: [SortDescriptor(\ExerciseDef.name)]) private var allExercises: [ExerciseDef]

    /// Everything as it was on arrival, so "quit" can put it back. SwiftData
    /// edits the live object as you type — there is no draft copy to throw
    /// away — so the old values are kept here instead.
    @State private var original: Snapshot? = nil

    private struct Snapshot {
        let name: String
        let sets: Int
        let lowest: Int
        let highest: Int
        let increment: Int
        let primary: MuscleGroup?
        let secondary: [MuscleGroup]
        let restSeconds: Int
        let kind: ExerciseKind
        let activity: AerobicActivity?
        /// True when the exercise was created just before this screen opened,
        /// in which case quitting should remove it rather than restore it.
        let isNew: Bool
    }

    private var trimmedName: String {
        exercise.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Another exercise already using this name.
    private var duplicateName: String? {
        guard !trimmedName.isEmpty else { return nil }
        return allExercises.first {
            $0.id != exercise.id && $0.name.lowercased() == trimmedName.lowercased()
        }?.name
    }

    /// A name, and then whatever that kind of exercise cannot do without.
    ///
    /// A strength exercise needs a primary muscle: without one it cannot be
    /// found by the muscle-group filter, is left out of any grouping by muscle,
    /// and would be a blank in shared data. An aerobic one needs an activity
    /// instead, because that is what the Apple workout is started as — a rest
    /// timer can fall back on a default, but "which workout is this" cannot.
    private var canSave: Bool {
        guard !trimmedName.isEmpty, duplicateName == nil else { return false }
        switch exercise.kind {
        case .strength: return exercise.primaryMuscle != nil
        case .aerobic:  return exercise.aerobicActivity != nil
        }
    }

    var body: some View {
        Form {
            TextField("Exercise name", text: $exercise.name)
            if let clash = duplicateName {
                Text("You already have an exercise called “\(clash)”. Give this one a different name — two exercises with the same name cannot be told apart in your logs or graphs.")
                    .font(.footnote)
                    .foregroundStyle(.red)
            } else if trimmedName.isEmpty {
                Text("An exercise needs a name before it can be saved.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if exercise.kind == .strength, exercise.primaryMuscle == nil {
                Text("Choose a primary muscle group below before saving.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if exercise.kind == .aerobic, exercise.aerobicActivity == nil {
                Text("Choose which activity this is before saving.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Picker("Kind", selection: Binding(
                get: { exercise.kind },
                set: { exercise.kind = $0 }
            )) {
                ForEach(ExerciseKind.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            if exercise.kind == .aerobic {
                Picker(selection: Binding(
                    get: { exercise.aerobicActivity },
                    set: { exercise.aerobicActivity = $0 }
                )) {
                    Text("Choose…").tag(AerobicActivity?.none)
                    ForEach(AerobicActivity.allCases) {
                        Text($0.label).tag(AerobicActivity?.some($0))
                    }
                } label: {
                    Text("Activity")
                }
            }

            if exercise.kind == .strength {
            LabeledContent {
                Stepper(value: $exercise.numberOfSeries, in: 1...10) {
                    Text("\(exercise.numberOfSeries)")
                }
                // The stored property is still numberOfSeries — renaming it
                // would break existing databases and exports for a word.
            } label: { Text("Number of sets") }

            // In the user's unit, with the unit written beside it — this is
            // the one screen where a weight is typed rather than rolled, and
            // the one place the question "kilograms or pounds?" actually
            // arises. The wheels, logs and graphs are left unlabelled: the
            // unit is the same down the whole screen and the space is not.
            LabeledContent {
                HStack(spacing: 4) {
                    TextField("", value: weightField(\.lowestWeightGrams), format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                    Text(WeightUnit.current.label).foregroundStyle(.secondary)
                }
            } label: { Text("Lowest weight") }

            LabeledContent {
                HStack(spacing: 4) {
                    TextField("", value: weightField(\.highestWeightGrams), format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                    Text(WeightUnit.current.label).foregroundStyle(.secondary)
                }
            } label: { Text("Highest weight") }

            LabeledContent {
                HStack(spacing: 4) {
                    TextField("", value: weightField(\.weightIncrementGrams), format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                    Text(WeightUnit.current.label).foregroundStyle(.secondary)
                }
            } label: { Text("Weight increment") }

            Toggle(isOn: $exercise.subtractsFromBodyWeight) {
                Text("Subtracted from body weight")
            }
            .onChange(of: exercise.subtractsFromBodyWeight) { _, on in
                // The first exercise to use body weight is the first time the
                // unit actually matters for arithmetic rather than for
                // reading: body weight in one unit against a machine in the
                // other is what logged a set at zero.
                if on, !UserDefaults.standard.bool(forKey: Self.unitCheckedKey) {
                    confirmUnit = true
                }
            }
            .alert("Weights in \(WeightUnit.current.label)?", isPresented: $confirmUnit) {
                Button("Yes, \(WeightUnit.current.label)") {
                    UserDefaults.standard.set(true, forKey: Self.unitCheckedKey)
                }
                Button("No, switch to \(WeightUnit.current == .kilograms ? "lb" : "kg")") {
                    let other: WeightUnit = WeightUnit.current == .kilograms ? .pounds : .kilograms
                    UserDefaults.standard.set(other.rawValue, forKey: WeightUnit.key)
                    UserDefaults.standard.set(true, forKey: Self.unitCheckedKey)
                }
            } message: {
                Text("This exercise works out what you lifted from your body weight, so the two have to be in the same units. Your weights are currently shown in \(WeightUnit.current.label).")
            }
            if exercise.subtractsFromBodyWeight {
                Text("For machines that take weight off you instead of adding it, such as an assisted chin-up or dip. The wheels show what you set on the machine; what is logged is what you lifted — your body weight less that setting — so the graphs and trends read the right way round. Your body weight comes from Settings.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            }

            // Shown whether or not the timer is switched on, so the value is
            // already right if it is turned on later — and so the setting is
            // discoverable from the place it applies to.
            Section {
                RestSecondsPicker(title: "Rest after a set", seconds: $exercise.restSeconds)
            } footer: {
                if RestTimerDefaults.isEnabled {
                    Text("How long the rest timer counts after each set of this exercise, and after logging it.")
                } else {
                    Text("Used when you switch the rest timer on in settings.")
                }
            }

            // NOTE: the "Movement type" picker used to live here. It only fed the
            // Watch's motion-based rep counter, which no longer exists, so the
            // control did nothing while promising a feature. `movementType` stays
            // on the model so existing data and JSON exports keep working.

            if exercise.kind == .strength {
                MuscleGroupSection(exercise: exercise)
            }

            WorkoutMembershipSection(exercise: exercise)
        }
        .onChange(of: exercise.lowestWeightGrams) { _, newValue in
            guard let newValue else { return }
            if (exercise.highestWeightGrams ?? 0) < newValue {
                exercise.highestWeightGrams = newValue
            }
            exercise.syncLegacyRange()
        }
        .onChange(of: exercise.highestWeightGrams) { _, newValue in
            guard let newValue, let lowest = exercise.lowestWeightGrams else { return }
            if newValue < lowest { exercise.lowestWeightGrams = newValue }
            exercise.syncLegacyRange()
        }
        .navigationTitle("edit exercise")
        .navigationBarBackButtonHidden(true)
        .toolbar {
            // Replaces the back chevron. Leaving by the chevron used to save
            // whatever was on screen, including a nameless exercise that then
            // sat in the list as "(unnamed)".
            ToolbarItem(placement: .topBarLeading) {
                Button("quit", role: .cancel) { revertAndLeave() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("save") { dismiss() }
                    .disabled(!canSave)
                    .bold()
            }
        }
        .onAppear {
            guard original == nil else { return }
            original = Snapshot(name: exercise.name,
                                sets: exercise.numberOfSeries,
                                lowest: exercise.lowestWeight,
                                highest: exercise.highestWeight,
                                increment: exercise.weightIncrement,
                                primary: exercise.primaryMuscle,
                                secondary: exercise.secondaryMuscles,
                                restSeconds: exercise.restSeconds,
                                kind: exercise.kind,
                                activity: exercise.aerobicActivity,
                                isNew: exercise.name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    /// Undo everything done on this screen, then leave.
    private func revertAndLeave() {
        if let o = original {
            if o.isNew {
                // Created for this screen and never named: it should not linger.
                store.deleteExercise(exercise)
            } else {
                exercise.name = o.name
                exercise.numberOfSeries = o.sets
                exercise.lowestWeight = o.lowest
                exercise.highestWeight = o.highest
                exercise.weightIncrement = o.increment
                exercise.primaryMuscle = o.primary
                exercise.secondaryMuscles = o.secondary
                exercise.restSeconds = o.restSeconds
                exercise.kind = o.kind
                exercise.aerobicActivity = o.activity
                StoreSave.save(context)
            }
        }
        dismiss()
    }
}
