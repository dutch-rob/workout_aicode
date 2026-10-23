import SwiftUI
import SwiftData
import EventKit

// MARK: - "Shall I put the next one in your calendar?"
//
// Shown once, at the end of a workout, and only when the user has asked for it
// in settings. The proposed time is this workout's own, rounded up to a
// quarter hour, `daysAhead` days from now — see WorkoutSchedule — and the
// picker is there because a proposal that cannot be argued with is a demand.

struct ScheduleNextWorkoutSheet: View {
    let workoutName: String
    let workoutId: UUID
    let finished: PhoneSessionManager.FinishedWorkout
    var onClose: () -> Void

    @AppStorage(WorkoutScheduleKey.daysAhead) private var daysAhead = WorkoutSchedule.defaultDaysAhead
    @AppStorage(WorkoutScheduleKey.count) private var count = WorkoutSchedule.defaultCount

    @State private var start = Date()
    @State private var asked = false
    @State private var refused = false
    @State private var done: Int? = nil

    private var calendar: WorkoutCalendar { .shared }

    /// The first one is whatever the picker says; the rest follow it at the
    /// same spacing, so moving the first moves the series with it.
    private var starts: [Date] {
        guard count > 1 else { return [start] }
        return [start] + WorkoutSchedule.starts(after: start, daysAhead: daysAhead,
                                                count: count - 1)
    }

    private var duration: TimeInterval {
        WorkoutSchedule.duration(from: finished.startedAt, to: finished.endedAt)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let done {
                    Section {
                        Label(done == 0 ? "Already in your calendar"
                                        : "\(done) added to your calendar",
                              systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } footer: {
                        Text("You can move or delete it in the Calendar app like any other event. The app will not put back one you delete.")
                    }
                } else if refused {
                    Section {
                        Label("No access to your calendar", systemImage: "calendar.badge.exclamationmark")
                            .foregroundStyle(.orange)
                    } footer: {
                        Text("Nothing can be added until SetsRepsWheels is allowed into Calendars, in iOS Settings under Privacy & Security. The switch for this is in the app's own settings too, if you would rather not be asked again.")
                    }
                } else {
                    Section {
                        DatePicker("Next \(workoutName)", selection: $start,
                                   in: Date()...,
                                   displayedComponents: [.date, .hourAndMinute])
                    } footer: {
                        Text(proposalFooter)
                    }

                    if count > 1 {
                        Section("And after that") {
                            ForEach(starts.dropFirst(), id: \.self) { date in
                                Text(date.formatted(date: .abbreviated, time: .shortened))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Section {
                        Button {
                            Task { await put() }
                        } label: {
                            Label("Add to calendar", systemImage: "calendar.badge.plus")
                        }
                    }
                }
            }
            .navigationTitle("Next workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(done == nil ? "Not now" : "Done") { onClose() }
                }
            }
        }
        .onAppear {
            start = WorkoutSchedule.nextStart(after: finished.startedAt, daysAhead: daysAhead)
        }
    }

    private var proposalFooter: String {
        let length = Int(duration / 60)
        return "The time this workout began, rounded up to the quarter hour, \(daysAhead) \(daysAhead == 1 ? "day" : "days") from now. It goes in as a \(length)-minute event — as long as the one you have just done."
    }

    private func put() async {
        asked = true
        guard await calendar.requestAccess() else {
            refused = true
            return
        }
        done = calendar.schedule(workout: workoutName, id: workoutId,
                                 starts: starts, duration: duration)
    }
}

// MARK: - The setting

struct ScheduleSettings: View {
    @AppStorage(WorkoutScheduleKey.enabled) private var enabled = false
    @AppStorage(WorkoutScheduleKey.daysAhead) private var daysAhead = WorkoutSchedule.defaultDaysAhead
    @AppStorage(WorkoutScheduleKey.count) private var count = WorkoutSchedule.defaultCount
    @AppStorage(WorkoutScheduleKey.calendar) private var calendarId = ""

    @State private var calendars: [EKCalendar] = []
    @State private var accessRefused = false

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $enabled) {
                    Label("Offer at the end of a workout", systemImage: "calendar.badge.plus")
                }
                .onChange(of: enabled) { _, on in
                    guard on else { return }
                    Task {
                        accessRefused = !(await WorkoutCalendar.shared.requestAccess())
                        calendars = WorkoutCalendar.shared.writableCalendars
                    }
                }
            } footer: {
                Text(accessRefused
                     ? "SetsRepsWheels is not allowed into Calendars. Turn it on in iOS Settings under Privacy & Security, and nothing can be added until you do."
                     : "When you finish a workout, the app offers to put the next one in your calendar. It never adds anything without being asked, and it only ever touches events it added itself.")
            }

            if enabled {
                Section {
                    Stepper(value: $daysAhead, in: WorkoutSchedule.daysAheadRange) {
                        LabeledContent("Days until the next one",
                                       value: "\(daysAhead)")
                    }
                    Stepper(value: $count, in: WorkoutSchedule.countRange) {
                        LabeledContent("How many to put in",
                                       value: count == 1 ? "just the next" : "\(count)")
                    }
                } footer: {
                    Text(count == 1
                         ? "The proposed day. You can change it on the day itself before adding."
                         : "The next \(count), every \(daysAhead) \(daysAhead == 1 ? "day" : "days"). Scheduling again later moves the ones that have changed and leaves the rest exactly as they are, so an event you have edited by hand keeps your edit.")
                }

                if !calendars.isEmpty {
                    Section {
                        Picker("Calendar", selection: $calendarId) {
                            Text("Default").tag("")
                            ForEach(calendars, id: \.calendarIdentifier) { cal in
                                Text(cal.title).tag(cal.calendarIdentifier)
                            }
                        }
                    } footer: {
                        Text("Which calendar the workouts go in. “Default” is whichever one your phone uses for new events.")
                    }
                }
            }
        }
        .navigationTitle("scheduling")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if WorkoutCalendar.shared.hasAccess {
                calendars = WorkoutCalendar.shared.writableCalendars
            }
        }
    }
}
