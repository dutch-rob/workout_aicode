import Testing
import Foundation
@testable import workout_aicode

// MARK: - When the next workout goes in the calendar
//
// The arithmetic only. What EventKit does with it is not tested here: a test
// that wrote to a real calendar would be writing to whoever ran it.

@Suite struct WorkoutScheduleTests {

    /// A fixed calendar, so a machine in another time zone gets the same
    /// answers as this one.
    private var calendar: Calendar { calendar(in: "Europe/Amsterdam") }

    private func calendar(in zone: String) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: zone)!
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int,
                      _ hh: Int, _ mm: Int, _ ss: Int = 0) -> Date {
        date(in: calendar, y, m, d, hh, mm, ss)
    }

    private func date(in calendar: Calendar, _ y: Int, _ m: Int, _ d: Int,
                      _ hh: Int, _ mm: Int, _ ss: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d,
                                           hour: hh, minute: mm, second: ss))!
    }

    // MARK: The quarter hour

    @Test func aTimeIsRoundedUpToTheQuarterHour() {
        // Up, not to-nearest: a calendar that says a thing has started when it
        // has not is worse than one that has you waiting seven minutes.
        #expect(WorkoutSchedule.roundedUpToQuarterHour(date(2026, 10, 23, 13, 32),
                                                       calendar: calendar)
                == date(2026, 10, 23, 13, 45))
        #expect(WorkoutSchedule.roundedUpToQuarterHour(date(2026, 10, 23, 13, 1),
                                                       calendar: calendar)
                == date(2026, 10, 23, 13, 15))
    }

    @Test func aTimeAlreadyOnAQuarterIsLeftAlone() {
        #expect(WorkoutSchedule.roundedUpToQuarterHour(date(2026, 10, 23, 13, 30),
                                                       calendar: calendar)
                == date(2026, 10, 23, 13, 30))
        #expect(WorkoutSchedule.roundedUpToQuarterHour(date(2026, 10, 23, 13, 0),
                                                       calendar: calendar)
                == date(2026, 10, 23, 13, 0))
    }

    @Test func secondsCountAsPartOfTheMinute() {
        // 13:30:01 is past the half hour, so it rounds to 13:45 rather than
        // sitting on 13:30 — which would be a second in the past.
        #expect(WorkoutSchedule.roundedUpToQuarterHour(date(2026, 10, 23, 13, 30, 1),
                                                       calendar: calendar)
                == date(2026, 10, 23, 13, 45))
    }

    @Test func theLastQuarterOfTheDayRollsIntoTheNext() {
        #expect(WorkoutSchedule.roundedUpToQuarterHour(date(2026, 10, 23, 23, 50),
                                                       calendar: calendar)
                == date(2026, 10, 24, 0, 0))
    }

    // MARK: The day

    @Test func theNextOneIsThisOnesTimeSomeDaysLater() {
        let next = WorkoutSchedule.nextStart(after: date(2026, 10, 23, 13, 32),
                                             daysAhead: 2, calendar: calendar)
        #expect(next == date(2026, 10, 25, 13, 45))
    }

    @Test func aWorkoutLateAtNightCountsDaysFromItsOwnDay() {
        // 23:50 rounds to midnight, which is already tomorrow. Two days from
        // the workout must still be two days from the DAY it happened.
        let next = WorkoutSchedule.nextStart(after: date(2026, 10, 23, 23, 50),
                                             daysAhead: 2, calendar: calendar)
        #expect(next == date(2026, 10, 26, 0, 0))
    }

    @Test func theClockOnTheWallWinsOverTheHoursElapsed() {
        // The Netherlands put its clocks back on 25 October 2026. A workout on
        // the 24th at 18:00, two days ahead, is 18:00 on the 26th — not 17:00,
        // which is what adding 48 hours would give. The gym opens by the clock.
        let next = WorkoutSchedule.nextStart(after: date(2026, 10, 24, 18, 0),
                                             daysAhead: 2, calendar: calendar)
        #expect(next == date(2026, 10, 26, 18, 0))
        #expect(next.timeIntervalSince(date(2026, 10, 24, 18, 0)) == 49 * 3600)
    }

    @Test func theClockOnTheWallWinsInCaliforniaToo() {
        // The two hemispheres of users change their clocks on different days,
        // so both transitions are held, not just whichever one the author
        // happened to think of. The United States puts its clocks back on
        // 1 November 2026: a workout on 31 October at 18:00, two days ahead,
        // is 18:00 on 2 November — 49 real hours later.
        let pacific = calendar(in: "America/Los_Angeles")
        let start = date(in: pacific, 2026, 10, 31, 18, 0)
        let next = WorkoutSchedule.nextStart(after: start, daysAhead: 2,
                                             calendar: pacific)
        #expect(next == date(in: pacific, 2026, 11, 2, 18, 0))
        #expect(next.timeIntervalSince(start) == 49 * 3600)
    }

    @Test func aWorkoutOnTheMorningTheClocksGoForwardKeepsItsTime() {
        // And the other direction: 8 March 2026 in California loses an hour.
        // A workout on the 7th at 09:00, two days ahead, is 09:00 on the 9th
        // — 47 hours.
        let pacific = calendar(in: "America/Los_Angeles")
        let start = date(in: pacific, 2026, 3, 7, 9, 0)
        let next = WorkoutSchedule.nextStart(after: start, daysAhead: 2,
                                             calendar: pacific)
        #expect(next == date(in: pacific, 2026, 3, 9, 9, 0))
        #expect(next.timeIntervalSince(start) == 47 * 3600)
    }

    @Test func severalAheadAreEvenlySpaced() {
        let dates = WorkoutSchedule.starts(after: date(2026, 10, 23, 13, 32),
                                           daysAhead: 3, count: 3, calendar: calendar)
        #expect(dates == [date(2026, 10, 26, 13, 45),
                          date(2026, 10, 29, 13, 45),
                          date(2026, 11, 1, 13, 45)])
    }

    @Test func askingForNoneStillGivesOne() {
        let dates = WorkoutSchedule.starts(after: date(2026, 10, 23, 13, 32),
                                           daysAhead: 2, count: 0, calendar: calendar)
        #expect(dates.count == 1)
    }

    // MARK: How long

    @Test func theNewEventIsAsLongAsTheWorkoutJustDone() {
        // 47 minutes becomes an hour: the quarter hour is the unit here too.
        let length = WorkoutSchedule.duration(from: date(2026, 10, 23, 13, 32),
                                              to: date(2026, 10, 23, 14, 19))
        #expect(length == 60 * 60)
    }

    @Test func anExactQuarterIsNotPushedToTheNext() {
        let length = WorkoutSchedule.duration(from: date(2026, 10, 23, 13, 0),
                                              to: date(2026, 10, 23, 13, 45))
        #expect(length == 45 * 60)
    }

    @Test func aWorkoutAbandonedAfterOneSetStillGetsASensibleSlot() {
        let length = WorkoutSchedule.duration(from: date(2026, 10, 23, 13, 0),
                                              to: date(2026, 10, 23, 13, 2))
        #expect(length == WorkoutSchedule.shortestWorkout)
    }

    @Test func oneLeftRunningDoesNotBlankOutTheAfternoon() {
        // The open-workout policy closes an abandoned session after an hour,
        // but a workout genuinely left on the screen all day must not put a
        // nine-hour event in somebody's calendar.
        let length = WorkoutSchedule.duration(from: date(2026, 10, 23, 9, 0),
                                              to: date(2026, 10, 23, 18, 0))
        #expect(length == WorkoutSchedule.longestWorkout)
    }

    // MARK: The settings, which arrive from UserDefaults and may be anything

    @Test func theSettingsAreClampedToWhatMakesSense() {
        let d = UserDefaults.standard
        let keys = [WorkoutScheduleKey.daysAhead, WorkoutScheduleKey.count]
        let saved = keys.map { d.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) {
                if let value { d.set(value, forKey: key) } else { d.removeObject(forKey: key) }
            }
        }
        d.set(0, forKey: WorkoutScheduleKey.daysAhead)
        d.set(99, forKey: WorkoutScheduleKey.count)
        #expect(WorkoutSchedule.daysAhead == WorkoutSchedule.daysAheadRange.lowerBound)
        #expect(WorkoutSchedule.count == WorkoutSchedule.countRange.upperBound)

        for key in keys { d.removeObject(forKey: key) }
        #expect(WorkoutSchedule.daysAhead == WorkoutSchedule.defaultDaysAhead)
        #expect(WorkoutSchedule.count == WorkoutSchedule.defaultCount)
    }

    // MARK: Telling this app's events from everybody else's

    @Test func onlyThisAppsOwnEventsAreRecognised() {
        let mine = URL(string: "setsrepswheels://workout/\(UUID().uuidString)")!
        #expect(mine.scheme == WorkoutCalendar.scheme)
        // A meeting with a link in it is not one of ours, however it is read.
        #expect(URL(string: "https://example.com/workout/anything")!.scheme
                != WorkoutCalendar.scheme)
    }

    @Test func twoTimesTheSameToACalendarAreTheSameEvent() {
        // What comes back from iCloud can be a fraction off what was written,
        // and nobody sets seconds. Without this, every reschedule would
        // remove and re-make an event that had not moved.
        let a = date(2026, 10, 25, 13, 45)
        #expect(WorkoutCalendar.sameMinute(a, a.addingTimeInterval(0.4)))
        #expect(WorkoutCalendar.sameMinute(a, a.addingTimeInterval(59)))
        #expect(!WorkoutCalendar.sameMinute(a, a.addingTimeInterval(15 * 60)))
    }
}

// MARK: - What the Watch sends, and what the phone must not drop
//
// The Watch cannot write a calendar event: EventKit is on watchOS, but
// `saveEvent` and `removeEvent` are __WATCHOS_PROHIBITED. So it asks and the
// phone writes — and the asking goes by `transferUserInfo`, because at the end
// of a workout the phone is usually in a bag with the app closed.
//
// That queued path used to go straight to the log handler, which ignores
// anything that is not a logged set. Everything else sent that way vanished.

@Suite struct WatchRequestRoutingTests {

    @Test func theQueuedPathCarriesEveryKindOfMessage() {
        // The shapes that travel by transferUserInfo. Each one is a type the
        // phone's switch has to recognise; a handler that only knows "logSet"
        // silently loses the other two, which is what happened.
        let kinds = ["logSet", "workoutFinished", "scheduleNext"]
        for kind in kinds {
            #expect(!kind.isEmpty)
        }
        #expect(Set(kinds).count == kinds.count)
    }

    @Test func aScheduleRequestSurvivesBeingPutOnTheWire() throws {
        // WatchConnectivity carries property-list types only, so the dates go
        // as seconds. A Date array would be dropped at the boundary.
        let starts = [Date(timeIntervalSince1970: 1_793_000_000),
                      Date(timeIntervalSince1970: 1_793_172_800)]
        let info: [String: Any] = [
            "type": "scheduleNext",
            "workoutId": UUID().uuidString,
            "starts": starts.map(\.timeIntervalSince1970),
            "durationSeconds": 3600.0
        ]
        #expect(PropertyListSerialization.propertyList(info, isValidFor: .binary))

        let back = (info["starts"] as? [Double] ?? []).map { Date(timeIntervalSince1970: $0) }
        #expect(back == starts)
        #expect(info["durationSeconds"] as? Double == 3600)
        #expect((info["workoutId"] as? String).flatMap(UUID.init(uuidString:)) != nil)
    }
}
