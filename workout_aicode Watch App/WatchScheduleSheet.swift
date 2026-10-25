import SwiftUI

// MARK: - "Next one?" on the wrist
//
// Shown when a workout ends on the Watch, if the user asked for it on the
// phone. The Watch proposes; the PHONE writes the event, because watchOS will
// not let anything else happen: EventKit is there, but `saveEvent` and
// `removeEvent` are __WATCHOS_PROHIBITED. Reading a calendar on the wrist is
// allowed, writing one is not.
//
// So the question is asked here and the answer is sent over, which is better
// than it sounds — there is nothing to go and do on the phone afterwards. The
// request is queued, so it arrives whether or not the phone is awake, in a
// pocket, or out of range at the time.

struct WatchScheduleSheet: View {
    let finished: WatchSessionManager.FinishedWorkout
    var onClose: () -> Void

    @ObservedObject private var session = WatchSessionManager.shared
    @State private var sent = false

    /// The same arithmetic the phone would do, from the same file — see the
    /// byte-identical copy note in WorkoutSchedule.swift.
    private var starts: [Date] {
        WorkoutSchedule.starts(after: finished.startedAt,
                               daysAhead: session.scheduleDaysAhead,
                               count: session.scheduleCount)
    }

    private var duration: TimeInterval {
        WorkoutSchedule.duration(from: finished.startedAt, to: finished.endedAt)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if sent {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2).foregroundStyle(.green)
                    Text("Sent to your iPhone")
                        .font(.caption).bold()
                    Text("It goes in your calendar there, next time the two are in range. Nothing to do on the phone.")
                        .font(.caption2).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Done") { onClose() }
                        .buttonStyle(.borderedProminent)
                } else {
                    Text("Next \(finished.name)?")
                        .font(.caption).bold()
                        .multilineTextAlignment(.center)
                    ForEach(starts, id: \.self) { date in
                        Text(date.formatted(.dateTime.weekday(.abbreviated)
                                              .day().month(.abbreviated)
                                              .hour().minute()))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        session.requestSchedule(workoutId: finished.workoutId,
                                                starts: starts,
                                                duration: duration)
                        sent = true
                    } label: {
                        Label("Add", systemImage: "calendar.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Not now") { onClose() }
                        .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, 4)
        }
    }
}
