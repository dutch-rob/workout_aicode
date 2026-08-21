import SwiftUI
import SwiftData

// MARK: - Exercises
//
// A table on the left, a form on the right. Numbers are typed rather than
// rolled: a Mac has no touchscreen, and a picker wheel driven by a trackpad is
// worse than a text field at everything a text field does.

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
                .frame(minWidth: 220, idealWidth: 260)
            Group {
                if let selected {
                    MacExerciseForm(exercise: selected)
                } else {
                    ContentUnavailableView("No exercise selected", systemImage: "hand.point.left")
                }
            }
            .frame(minWidth: 320)
        }
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
        case .strength: return exercise.primaryMuscle?.label ?? "No muscle group yet"
        }
    }

    private func create() {
        let exercise = ExerciseDef(name: "New exercise")
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

struct MacExerciseForm: View {
    @Bindable var exercise: ExerciseDef

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
                Section("Muscle groups") {
                    Picker("Primary", selection: Binding(
                        get: { exercise.primaryMuscle },
                        set: { exercise.primaryMuscle = $0 })) {
                        Text("Choose…").tag(MuscleGroup?.none)
                        ForEach(MuscleGroup.allCases) {
                            Text($0.label).tag(MuscleGroup?.some($0))
                        }
                    }
                }
            }

            Section("Rest after a set") {
                Picker("Rest", selection: $exercise.restSeconds) {
                    ForEach(Array(stride(from: 15, through: 300, by: 15)), id: \.self) {
                        Text(String(format: "%d:%02d", $0 / 60, $0 % 60)).tag($0)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(.top, 4)
    }
}
