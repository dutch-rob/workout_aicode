import Foundation
import EventKit

// MARK: - Putting the next workout in the calendar
//
// Only this file talks to EventKit; when to schedule and for how long is
// WorkoutSchedule's, and is tested there.
//
// Two rules decide the shape of everything below.
//
// FULL ACCESS, not write-only. Write-only is the smaller ask and would be
// enough to ADD an event — but then scheduling twice would leave two, and
// moving a workout would leave the old one behind. Removing what the app put
// there last time means finding it first, and finding anything in a calendar
// needs full access. The app reads nothing else: every search is for events
// it wrote itself, in a window it chose.
//
// THE APP'S OWN EVENTS ARE MARKED, and the mark travels with the event rather
// than being remembered here. `event.url` holds setsrepswheels://workout/<id>,
// which syncs with the event through iCloud, so a second device recognises an
// event this one created — and an event the user made by hand, or one from
// another app, is never touched. Keeping a list of identifiers locally would
// have been the other way, and the second device would not have had it.

@MainActor
final class WorkoutCalendar {
    static let shared = WorkoutCalendar()

    /// Made on first use, not when the app starts.
    ///
    /// Building an EKEventStore talks to the calendar daemons, and on a device
    /// whose calendars are cold that takes long enough to be felt. This type
    /// is a singleton reached from a settings screen's `task`, so an eager one
    /// would have been built on the main actor the moment that screen opened,
    /// with the screen unresponsive until it finished.
    private lazy var store = EKEventStore()

    /// The URL scheme that marks an event as this app's.
    nonisolated static let scheme = "setsrepswheels"

    private init() {}

    // MARK: Permission

    var authorization: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    var hasAccess: Bool { authorization == .fullAccess }

    /// Asks, once. `false` if the user said no, or said no at some point in
    /// the past — iOS does not ask twice, and the app must not pretend it did.
    @discardableResult
    func requestAccess() async -> Bool {
        if hasAccess { return true }
        return (try? await store.requestFullAccessToEvents()) ?? false
    }

    // MARK: Which calendar

    /// The writable calendars, for the picker in settings.
    var writableCalendars: [EKCalendar] {
        guard hasAccess else { return [] }
        return store.calendars(for: .event)
            .filter(\.allowsContentModifications)
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// The one to write to: what the user picked, or the system's own choice
    /// for new events if they have not picked or it has since gone away.
    var chosenCalendar: EKCalendar? {
        let id = UserDefaults.standard.string(forKey: WorkoutScheduleKey.calendar) ?? ""
        if !id.isEmpty, let picked = store.calendar(withIdentifier: id),
           picked.allowsContentModifications {
            return picked
        }
        return store.defaultCalendarForNewEvents
    }

    // MARK: Reading back what this app wrote

    private func isOurs(_ event: EKEvent, workoutId: UUID) -> Bool {
        guard let url = event.url, url.scheme == Self.scheme else { return false }
        return url.lastPathComponent == workoutId.uuidString
    }

    /// This app's own future events for one workout, soonest first.
    ///
    /// One workout's, not all of them: somebody alternating a heavy day and a
    /// light one has both in the calendar, and finishing the heavy one has no
    /// business removing the light one.
    func upcoming(workoutId: UUID, within days: Int = 400,
                  from now: Date = Date()) -> [EKEvent] {
        guard hasAccess else { return [] }
        let end = now.addingTimeInterval(Double(days) * 86_400)
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        return store.events(matching: predicate)
            .filter { isOurs($0, workoutId: workoutId) }
            .sorted { $0.startDate < $1.startDate }
    }

    // MARK: Writing

    /// Puts `starts` in the calendar for this workout, and takes out anything
    /// this app had put there for it that is no longer wanted.
    ///
    /// An event already sitting at a wanted time is LEFT EXACTLY AS IT IS —
    /// not removed and re-made. Its duration may have been edited by hand
    /// since, it may have an alarm on it, somebody may have been invited; a
    /// date that is not changing should not quietly lose any of that.
    @discardableResult
    func schedule(workout name: String, id workoutId: UUID,
                  starts: [Date], duration: TimeInterval,
                  now: Date = Date()) -> Int {
        guard hasAccess, let calendar = chosenCalendar else { return 0 }

        let existing = upcoming(workoutId: workoutId, from: now)
        var wanted = starts.filter { $0 > now }
        var written = 0

        for event in existing {
            if let match = wanted.firstIndex(where: {
                Self.sameMinute($0, event.startDate)
            }) {
                wanted.remove(at: match)      // already there; leave it be
            } else {
                try? store.remove(event, span: .thisEvent, commit: false)
            }
        }

        for start in wanted {
            let event = EKEvent(eventStore: store)
            event.calendar = calendar
            event.title = name.isEmpty ? "Workout" : name
            event.startDate = start
            event.endDate = start.addingTimeInterval(duration)
            event.url = URL(string: "\(Self.scheme)://workout/\(workoutId.uuidString)")
            event.notes = "Added by SetsRepsWheels. Delete it here and the app will not put it back."
            try? store.save(event, span: .thisEvent, commit: false)
            written += 1
        }

        // One commit for the lot: a half-applied reschedule would be a
        // calendar with the old event gone and the new one missing.
        try? store.commit()
        return written
    }

    /// Takes out every future event this app made for a workout — for the
    /// switch in settings being turned off, and for a workout being deleted.
    func removeUpcoming(workoutId: UUID, now: Date = Date()) {
        guard hasAccess else { return }
        for event in upcoming(workoutId: workoutId, from: now) {
            try? store.remove(event, span: .thisEvent, commit: false)
        }
        try? store.commit()
    }

    /// Two dates that a calendar would show as the same time. Seconds are not
    /// a thing anybody sets, and an event that came back from iCloud can be a
    /// fraction off what was written.
    nonisolated static func sameMinute(_ a: Date, _ b: Date) -> Bool {
        abs(a.timeIntervalSince(b)) < 60
    }
}
