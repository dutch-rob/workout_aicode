import SwiftUI
import SwiftData
import AppKit

// MARK: - Exercises
//
// A list on the left, a form on the right. Numbers are typed rather than
// rolled: a Mac has no touchscreen, and a picker wheel driven by a trackpad is
// worse than a text field at everything a text field does.
//
// Muscle groups are the exception, and they are why this screen matters. They
// are the one field nobody fills in on a phone — fifteen names in a picker,
// once per exercise, standing in a gym — and without them the statistics have
// nothing to group by. Here there is room for the body diagram itself, so a
// whole library can be tagged by pointing at it.

struct MacExercisesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\ExerciseDef.name)]) private var exercises: [ExerciseDef]
    @Query private var drafts: [DraftSession]
    @State private var selection: UUID?

    private var draft: DraftSession? { drafts.first { $0.isActive } }

    private var selected: ExerciseDef? {
        guard let selection else { return nil }
        return exercises.first { $0.id == selection }
    }

    var body: some View {
        HSplitView {
            list
                .frame(minWidth: 220, idealWidth: 260, maxHeight: .infinity)
            Group {
                if let selected {
                    MacExerciseForm(exercise: selected)
                } else {
                    ContentUnavailableView("No exercise selected", systemImage: "hand.point.left")
                }
            }
            // Both halves take the whole height they are given. Without this
            // the split view sized itself to the shorter side, and an empty
            // detail pane left the list floating in the middle of the window
            // with its own scroll bar — the list changing height depending on
            // whether something was selected.
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Exercises")
        .toolbar {
            ToolbarItem {
                Button(action: create) { Label("New exercise", systemImage: "plus") }
                    .help("Add an exercise")
            }
        }
    }

    @ViewBuilder private var list: some View {
        if exercises.isEmpty {
            MacEmptyState(thing: "exercises", onCreate: create)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(selection: $selection) {
                ForEach(exercises) { exercise in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(exercise.name.isEmpty ? "(unnamed)" : exercise.name)
                            Text(subtitle(exercise))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        // Made during the draft in progress: marked so it is
                        // obvious what is at stake when draft ends.
                        if draft?.contains(exercise: exercise.id) == true {
                            Image(systemName: "pencil.and.outline")
                                .foregroundStyle(.orange)
                                .help("Made while drafting")
                        }
                    }
                    .tag(exercise.id)
                }
                .onDelete(perform: delete)
            }
        }
    }

    private func subtitle(_ exercise: ExerciseDef) -> String {
        switch exercise.kind {
        case .aerobic:  return exercise.aerobicActivity?.label ?? "Aerobic"
        case .strength:
            guard let primary = exercise.primaryMuscle else { return "No muscle group yet" }
            let also = exercise.secondaryMuscles.filter { $0 != primary }
            guard !also.isEmpty else { return primary.shortLabel }
            return "\(primary.shortLabel) + \(also.map(\.shortLabel).joined(separator: ", "))"
        }
    }

    private func create() {
        // Through ExerciseDefaults, so a new exercise made here starts on the
        // same sets and weights as one made on the phone rather than on the
        // built-in 0…200 in 5s.
        let exercise = ExerciseDefaults.makeExercise(name: "New exercise")
        context.insert(exercise)
        DraftMode.note(exercise: exercise.id, in: context)
        try? context.save()
        selection = exercise.id
    }

    private func delete(_ offsets: IndexSet) {
        for index in offsets {
            let exercise = exercises[index]
            // Stop offering it back when draft ends, or the count would lie.
            DraftMode.forget(id: exercise.id, in: context)
            context.delete(exercise)
        }
        try? context.save()
    }
}

// MARK: - One exercise

struct MacExerciseForm: View {
    @Bindable var exercise: ExerciseDef

    /// Secondaries as the diagram should draw them. The primary is taken out:
    /// a muscle is one or the other, and showing it in both colours at once
    /// would say the app cannot tell.
    private var alsoWorked: Set<MuscleGroup> {
        Set(exercise.secondaryMuscles).subtracting([exercise.primaryMuscle].compactMap { $0 })
    }

    private var unusedMuscles: [MuscleGroup] {
        MuscleGroup.displayOrder.filter {
            $0 != exercise.primaryMuscle && !alsoWorked.contains($0)
        }
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $exercise.name)
                Picker("Kind", selection: Binding(
                    get: { exercise.kind }, set: { exercise.kind = $0 })) {
                    ForEach(ExerciseKind.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            if exercise.kind == .aerobic {
                Section("Activity") {
                    Picker("Activity", selection: Binding(
                        get: { exercise.aerobicActivity },
                        set: { exercise.aerobicActivity = $0 })) {
                        Text("Choose…").tag(AerobicActivity?.none)
                        ForEach(AerobicActivity.allCases) {
                            Text($0.label).tag(AerobicActivity?.some($0))
                        }
                    }
                }
            } else {
                Section("Numbers") {
                    // Typed, not rolled. Steppers alongside so the keyboard is
                    // not the only way in.
                    LabeledContent("Sets") {
                        Stepper(value: $exercise.numberOfSeries, in: 1...10) {
                            TextField("", value: $exercise.numberOfSeries, format: .number)
                                .frame(width: 60)
                        }
                    }
                    LabeledContent("Lowest weight") {
                        TextField("", value: $exercise.lowestWeight, format: .number)
                            .frame(width: 80)
                    }
                    LabeledContent("Highest weight") {
                        TextField("", value: $exercise.highestWeight, format: .number)
                            .frame(width: 80)
                    }
                    LabeledContent("Increment") {
                        TextField("", value: $exercise.weightIncrement, format: .number)
                            .frame(width: 80)
                    }
                }

                muscleSection
            }

            Section("Rest after a set") {
                Picker("Rest", selection: $exercise.restSeconds) {
                    ForEach(ExerciseDefaults.restChoices, id: \.self) {
                        Text(ExerciseDefaults.restLabel($0)).tag($0)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(.top, 4)
    }

    // MARK: Muscle groups

    private var muscleSection: some View {
        Section {
            MuscleBodyPicker(selection: Binding(
                                get: { exercise.primaryMuscle },
                                set: { exercise.primaryMuscle = $0 }),
                             secondary: alsoWorked,
                             // No aerobic button: this is not a filter, and
                             // "aerobic instead" is not an answer to "which
                             // muscles does this work".
                             aerobic: nil,
                             height: 340,
                             onPick: pick)
                .frame(maxWidth: .infinity)

            chips
        } header: {
            Text("Muscle groups")
        } footer: {
            Text("Click a muscle, or its label, to make it the one this exercise mainly works. Option-click to mark it as also worked — those show in a paler blue. Up to \(MuscleGroup.maximumSecondary) can be also-worked.")
        }
    }

    /// The written answer under the drawing.
    ///
    /// The diagram alone would be a picture you have to interpret; these say it
    /// in words, and give a way in for anyone who would rather not hunt for
    /// "rear delts" on a small figure — or who cannot use a mouse well enough
    /// to option-click.
    @ViewBuilder private var chips: some View {
        FlowLayout(spacing: 6, lineSpacing: 6) {
            if let primary = exercise.primaryMuscle {
                chip(primary.shortLabel, tint: .blue, filled: true) {
                    exercise.primaryMuscle = nil
                }
            } else {
                Text("No muscle group yet")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.vertical, 3)
            }

            ForEach(MuscleGroup.displayOrder.filter { alsoWorked.contains($0) }) { group in
                chip(group.shortLabel, tint: .blue, filled: false) {
                    setSecondary(exercise.secondaryMuscles.filter { $0 != group })
                }
            }

            if alsoWorked.count < MuscleGroup.maximumSecondary {
                Menu("＋ also worked") {
                    ForEach(unusedMuscles) { group in
                        Button(group.label) {
                            setSecondary(exercise.secondaryMuscles + [group])
                        }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chip(_ text: String, tint: Color, filled: Bool,
                      remove: @escaping () -> Void) -> some View {
        HStack(spacing: 3) {
            Text(text).font(.caption)
            Button(action: remove) {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
            .help("Remove")
        }
        .foregroundStyle(filled ? Color.white : Color.primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(filled ? tint : tint.opacity(0.28)))
    }

    // MARK: Clicking a muscle

    /// A plain click sets the primary; Option adds or removes an also-worked.
    ///
    /// The modifier is read from AppKit at the moment of the click rather than
    /// carried through the picker: the picker is shared with the phone, where
    /// there is no such thing as a held key, and teaching it about modifiers
    /// would put a Mac idea into a file the phone compiles.
    private func pick(_ group: MuscleGroup) {
        if NSEvent.modifierFlags.contains(.option) {
            if alsoWorked.contains(group) {
                setSecondary(exercise.secondaryMuscles.filter { $0 != group })
            } else if alsoWorked.count < MuscleGroup.maximumSecondary {
                setSecondary(exercise.secondaryMuscles + [group])
            }
            return
        }
        let wasPrimary = exercise.primaryMuscle == group
        exercise.primaryMuscle = wasPrimary ? nil : group
        // Promoting a muscle that was already listed as also-worked takes it
        // out of that list, so it is never claimed twice.
        if !wasPrimary { setSecondary(exercise.secondaryMuscles.filter { $0 != group }) }
    }

    private func setSecondary(_ groups: [MuscleGroup]) {
        exercise.secondaryMuscles = Array(groups.prefix(MuscleGroup.maximumSecondary))
    }
}
