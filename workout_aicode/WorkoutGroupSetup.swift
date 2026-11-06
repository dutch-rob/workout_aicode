import SwiftUI
import SwiftData

// MARK: - Naming groups, and putting every workout in one
//
// The screen behind the "schedule by group" switch. It is a sheet rather than
// a push because switching grouping on is a job with an end: name the groups,
// assign the workouts, done. The switch does not take until that job is
// finished — see `WorkoutGrouping.canEnable` for why a half-assigned state is
// worse than no grouping at all.
//
// The same screen edits the groups afterwards, reached from the scheduling
// settings. It behaves identically; only the way out differs, which is what
// `isSettingUp` decides.

struct WorkoutGroupSetupView: View {
    /// True when this is the sheet the switch opened, so leaving without
    /// finishing has to put the switch back.
    let isSettingUp: Bool
    var onFinish: (_ enabled: Bool) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: [SortDescriptor(\WorkoutGroupDef.sortIndex)])
    private var groups: [WorkoutGroupDef]
    @Query(sort: [SortDescriptor(\WorkoutDef.sortIndex)])
    private var workouts: [WorkoutDef]

    @State private var newName = ""
    @State private var renaming: WorkoutGroupDef?
    @State private var renameTo = ""

    private var namedWorkouts: [WorkoutDef] {
        WorkoutGroupEditing.groupable(workouts)
    }

    private var unassigned: Int {
        WorkoutGroupEditing.unassigned(among: workouts)
    }

    private var canFinish: Bool {
        WorkoutGrouping.canEnable(groupCount: groups.count, unassignedWorkouts: unassigned)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(groups) { group in
                        Button {
                            renaming = group
                            renameTo = group.name
                        } label: {
                            LabeledContent(group.name) {
                                Text(countIn(group) == 1 ? "1 workout"
                                     : "\(countIn(group)) workouts")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tint(.primary)
                    }
                    .onDelete(perform: deleteGroups)

                    HStack {
                        TextField("New group", text: $newName)
                            .submitLabel(.done)
                            .onSubmit(addGroup)
                        Button("Add", action: addGroup)
                            .disabled(!WorkoutGrouping.nameIsFree(newName,
                                                                  among: groups.map(\.name)))
                    }
                } header: {
                    Text("Groups")
                } footer: {
                    Text("A group is one session done more than one way — the same muscles at a different gym, say. Scheduling puts the group in your calendar, and you pick which of its workouts to do on the day.")
                }

                Section {
                    ForEach(namedWorkouts) { workout in
                        Picker(workout.name, selection: binding(for: workout)) {
                            Text("None").tag(nil as UUID?)
                            ForEach(groups) { group in
                                Text(group.name).tag(group.id as UUID?)
                            }
                        }
                    }
                } header: {
                    Text("Which group each workout is in")
                } footer: {
                    if let blocker = WorkoutGrouping.blocker(groupCount: groups.count,
                                                             unassignedWorkouts: unassigned) {
                        Text(blocker + " Scheduling by group stays off until every workout is in one, so the calendar never has to guess what to call a workout.")
                    } else {
                        Text("Every workout is in a group.")
                    }
                }
            }
            .navigationTitle(isSettingUp ? "Set up groups" : "Groups")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isSettingUp ? "Cancel" : "Done") {
                        // Leaving the set-up sheet early leaves grouping off.
                        // Nothing is undone: the groups made and the workouts
                        // assigned stay, so coming back does not start again.
                        //
                        // Coming back later to EDIT reports what it found, so
                        // deleting the last group, or leaving a workout
                        // without one, switches grouping off rather than
                        // leaving it half-applied.
                        onFinish(isSettingUp ? false : canFinish)
                        dismiss()
                    }
                }
                if isSettingUp {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Turn on") {
                            onFinish(true)
                            dismiss()
                        }
                        .disabled(!canFinish)
                    }
                }
            }
            .alert("Rename group", isPresented: Binding(get: { renaming != nil },
                                                        set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $renameTo)
                Button("Cancel", role: .cancel) { renaming = nil }
                Button("Rename") { commitRename() }
                    .disabled(!renameIsAllowed)
            }
        }
    }

    private var renameIsAllowed: Bool {
        guard let renaming else { return false }
        let others = groups.filter { $0.id != renaming.id }.map(\.name)
        return WorkoutGrouping.nameIsFree(renameTo, among: others)
    }

    private func countIn(_ group: WorkoutGroupDef) -> Int {
        WorkoutGroupEditing.count(in: group, among: workouts)
    }

    // The mutations are shared with the Mac's settings section — see
    // WorkoutGroupEditing, which also holds the comments about why each one
    // refuses what it refuses.
    private func binding(for workout: WorkoutDef) -> Binding<UUID?> {
        Binding(get: { workout.groupId },
                set: { WorkoutGroupEditing.assign(workout, to: $0, in: context) })
    }

    private func addGroup() {
        if WorkoutGroupEditing.add(named: newName, among: groups, in: context) {
            newName = ""
        }
    }

    private func commitRename() {
        guard let group = renaming else { return }
        WorkoutGroupEditing.rename(group, to: renameTo, among: groups, in: context)
        renaming = nil
    }

    private func deleteGroups(_ offsets: IndexSet) {
        WorkoutGroupEditing.delete(offsets.map { groups[$0] }, among: groups,
                                   workouts: workouts, in: context)
    }
}
