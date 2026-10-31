import Foundation

// A BYTE-IDENTICAL COPY of this file lives in the Watch target, which does not
// compile Shared/. Edit the two together: the Watch proposes the next workout
// and the phone writes it, and the two must propose the same thing.
//
// MARK: - When the next workout goes in the calendar
//
// The arithmetic only. Nothing here touches EventKit, so what the app decides
// to put in somebody's calendar can be held still by tests rather than tried
// out on a real one — see WorkoutCalendar for the part that writes.
//
// The offer is made at the END of a workout, which is the moment a person
// actually knows when the next one is: they are standing in the gym having
// just done this one. That is also where the proposed time comes from — the
// time of day this workout began, rounded up to a quarter hour. Somebody who
// trains at 13:32 does not want 13:32 in their calendar.

nonisolated enum WorkoutScheduleKey {
    /// Whether to offer at all, at the end of a workout.
    static let enabled = "scheduleNextWorkout"
    /// How many days from this workout the next one goes.
    static let daysAhead = "scheduleDaysAhead"
    /// How many to put in at once — one, or the next few.
    static let count = "scheduleHowMany"
    /// Which calendar to write to, by identifier. Empty means the one the
    /// system uses for new events.
    static let calendar = "scheduleCalendarId"
}

nonisolated enum WorkoutSchedule {

    static let defaultDaysAhead = 2
    static let defaultCount = 1
    /// More than a fortnight ahead is not a plan, it is a guess.
    static let daysAheadRange = 1...14
    static let countRange = 1...8

    /// The quarter hour is the unit here: it is how people say a time out loud
    /// ("about half two"), and it is what a calendar's own pickers snap to.
    static let quarterHour: TimeInterval = 15 * 60

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: WorkoutScheduleKey.enabled)
    }

    static var daysAhead: Int {
        let stored = UserDefaults.standard.object(forKey: WorkoutScheduleKey.daysAhead) as? Int
        return clamp(stored ?? defaultDaysAhead, to: daysAheadRange)
    }

    static var count: Int {
        let stored = UserDefaults.standard.object(forKey: WorkoutScheduleKey.count) as? Int
        return clamp(stored ?? defaultCount, to: countRange)
    }

    private static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(range.upperBound, max(range.lowerBound, value))
    }

    // MARK: The time

    /// A date rounded UP to the next quarter hour, and left alone if it is
    /// already on one. 13:32 becomes 13:45; 13:30 stays 13:30.
    ///
    /// Up rather than to-nearest because this is a time to BE somewhere. Round
    /// 13:37 down to 13:30 and the calendar says a thing has started that has
    /// not; round it up and the worst case is standing about for seven minutes.
    static func roundedUpToQuarterHour(_ date: Date,
                                       calendar: Calendar = .current) -> Date {
        var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second],
                                            from: date)
        let minute = parts.minute ?? 0
        let second = parts.second ?? 0
        let quarters = (minute * 60 + second + Int(quarterHour) - 1) / Int(quarterHour)
        parts.minute = 0
        parts.second = 0
        guard let hourStart = calendar.date(from: parts) else { return date }
        return hourStart.addingTimeInterval(Double(quarters) * quarterHour)
    }

    /// When the next workout goes: this one's time of day, rounded up to a
    /// quarter hour, `daysAhead` days later.
    ///
    /// The time of day is carried across the day change rather than adding
    /// 48 hours, so a clock change in between does not move the workout an
    /// hour — the gym opens by the clock on the wall.
    static func nextStart(after start: Date, daysAhead: Int,
                          calendar: Calendar = .current) -> Date {
        let rounded = roundedUpToQuarterHour(start, calendar: calendar)
        let time = calendar.dateComponents([.hour, .minute], from: rounded)
        // Against the START of the day, so adding two days to a workout that
        // began at 23:50 lands on the day after tomorrow rather than slipping.
        guard let day = calendar.date(byAdding: .day, value: daysAhead,
                                      to: calendar.startOfDay(for: rounded)),
              let moved = calendar.date(bySettingHour: time.hour ?? 0,
                                        minute: time.minute ?? 0,
                                        second: 0, of: day)
        else { return rounded.addingTimeInterval(Double(daysAhead) * 86_400) }
        return moved
    }

    /// The next few, one every `daysAhead` days.
    static func starts(after start: Date, daysAhead: Int, count: Int,
                       calendar: Calendar = .current) -> [Date] {
        var dates: [Date] = []
        var previous = start
        for _ in 0..<max(1, count) {
            let next = nextStart(after: previous, daysAhead: daysAhead, calendar: calendar)
            dates.append(next)
            previous = next
        }
        return dates
    }

    // MARK: How long

    /// As long as the workout just finished, rounded up to a quarter hour.
    ///
    /// A guess, but the user's own guess: whatever they usually take is what
    /// they just took. Floored at a quarter of an hour so a workout abandoned
    /// after one set does not put a two-minute slot in the calendar, and
    /// capped at three hours so one left running by accident does not blank
    /// out an afternoon.
    static let shortestWorkout: TimeInterval = 15 * 60
    static let longestWorkout: TimeInterval = 3 * 60 * 60

    static func duration(from start: Date, to end: Date) -> TimeInterval {
        let ran = max(0, end.timeIntervalSince(start))
        let quarters = (ran / quarterHour).rounded(.up)
        let rounded = max(quarterHour, quarters * quarterHour)
        return min(longestWorkout, max(shortestWorkout, rounded))
    }
}
