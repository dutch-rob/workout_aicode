import SwiftUI
import SwiftData

// MARK: - Workout groups, on the Mac
//
// The same job as the iPhone's set-up sheet (`WorkoutGroupSetupView`): name
// the groups, and put every workout in one. The mutations are the shared ones
// in `WorkoutGroupEditing`, so the two screens cannot drift apart.
//
// Two things are deliberately different here.
//
// There is no switch. On the iPhone, grouping is a per-device preference in
// UserDefaults, which nothing syncs — so a switch here could never reach the
// phone that does the scheduling, and would be a control that appears to do
// something and does not. The groups themselves are in the store and DO cross,
// so what this screen is for is making them; the phone offers the switch once
// they arrive. `MacWorkoutDetail` reads grouping the same data-driven way.
//
// And deleting a group asks first. The iPhone deletes on a swipe, which nobody
// does by accident; here it is a button next to a row.

struct MacWorkoutGroups: View {
    @Environment(\.modelContext) private var context

    @Query(sort: [SortDescriptor(\WorkoutGroupDef.sortIndex)])
    private var groups: [WorkoutGroupDef]
    @Query(sort: [SortDescriptor(\WorkoutDef.sortIndex)])
    private var workouts: [WorkoutDef]

    @State private var newName = ""
    @State private var renaming: WorkoutGroupDef?
    @State private var renameTo = ""
    @State private var deleting: WorkoutGroupDef?

    private var namedWorkouts: [WorkoutDef] { WorkoutGroupEditing.groupable(workouts) }
    private var unassigned: Int { WorkoutGroupEditing.unassigned(among: workouts) }

    var body: some View {
        Group {
            Section {
                ForEach(groups) { group in
                    LabeledContent(group.name) {
                        HStack(spacing: 12) {
                            Text(WorkoutGroupEditing.count(in: group, among: workouts) == 1
                                 ? "1 workout"
                                 : "\(WorkoutGroupEditing.count(in: group, among: workouts)) workouts")
                                .foregroundStyle(.secondary)
                            Button("Rename") {
                                renameTo = group.name
                                renaming = group
                            }
                            Button {
                                deleting = group
                            } label: {
                                Image(systemName: "trash")
                            }
                            .help("Remove this group")
                        }
                    }
                }

                HStack {
                    TextField("New group", text: $newName)
                        .onSubmit(addGroup)
                    Button("Add", action: addGroup)
                        .disabled(!WorkoutGrouping.nameIsFree(newName, among: groups.map(\.name)))
                }
            } header: {
                Text("Workout groups")
            } footer: {
                Text("A group is one session done more than one way — the same muscles at a different gym, say. Scheduling puts the group in your calendar, and you pick which of its workouts to do on the day.\n\nGroups travel through iCloud, so a group made here is the one your iPhone schedules by. The switch that turns scheduling by group on is on the iPhone, with the calendar: this app has no calendar of its own.")
            }

            if !groups.isEmpty {
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
                            .foregroundStyle(.orange)
                    } else {
                        Text("Every workout is in a group.")
                    }
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
        .confirmationDialog("Remove this group?", isPresented: Binding(get: { deleting != nil },
                                                                      set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            if let deleting {
                Button("Remove \(deleting.name)", role: .destructive) { commitDelete() }
            }
            Button("Keep it", role: .cancel) { self.deleting = nil }
        } message: {
            Text(deleting.map { group in
                let count = WorkoutGroupEditing.count(in: group, among: workouts)
                return count == 0
                    ? "No workout is in it."
                    : (count == 1 ? "The 1 workout in it goes back to having no group."
                                  : "The \(count) workouts in it go back to having no group.")
            } ?? "")
        }
    }

    private var renameIsAllowed: Bool {
        guard let renaming else { return false }
        return WorkoutGrouping.nameIsFree(renameTo,
                                          among: groups.filter { $0.id != renaming.id }.map(\.name))
    }

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

    private func commitDelete() {
        guard let group = deleting else { return }
        WorkoutGroupEditing.delete([group], among: groups, workouts: workouts, in: context)
        deleting = nil
    }
}
