import Testing
import Foundation
import SwiftData
@testable import workout_aicode

// MARK: - Narrowing the log list
//
// Reported from the Mac: typing "Assisted chin up" into the field above the
// logs "did not appear to do anything". It was doing something — it kept the
// sessions that contained that exercise — but it listed every other exercise
// in them too, and that exercise is in most sessions. So almost nothing
// disappeared, which is indistinguishable from nothing happening.

@Suite(.serialized)
struct LogFilterTests {

    private let benchId = UUID()
    private let chinUpId = UUID()
    private let squatId = UUID()

    private var names: [UUID: String] {
        [benchId: "Machine bench press",
         chinUpId: "Assisted chin up",
         squatId: "Leg press"]
    }

    private func date(_ d: Int) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c.date(from: DateComponents(year: 2026, month: 10, day: d,
                                           hour: 17, minute: 0))!
    }

    @MainActor private func session(_ day: Int, workout: String,
                                    _ exercises: [UUID]) -> LogSessions.Session {
        let workoutId = UUID()
        return LogSessions.Session(
            id: "\(day)-\(workout)", workoutId: workoutId, workoutName: workout,
            date: date(day),
            logs: exercises.map {
                WorkoutLog(date: date(day), workoutId: workoutId,
                           exerciseId: $0, weights: [100], reps: [10])
            })
    }

    @MainActor private var all: [LogSessions.Session] {
        [session(21, workout: "PF B", [chinUpId, benchId]),
         session(19, workout: "PF B", [benchId, chinUpId, squatId]),
         session(17, workout: "PF A", [squatId, benchId])]
    }

    @MainActor @Test func typingAnExerciseLeavesOnlyThatExercise() {
        let found = LogSessions.matching(all, text: "assisted chin",
                                         exerciseNames: names)
        // The two sessions that have it, and ONLY that exercise in each.
        #expect(found.count == 2)
        #expect(found.allSatisfy { $0.logs.count == 1 })
        #expect(found.allSatisfy { names[$0.logs[0].exerciseId] == "Assisted chin up" })
    }

    @MainActor @Test func halfANameIsEnoughAndCaseDoesNotMatter() {
        #expect(LogSessions.matching(all, text: "CHIN", exerciseNames: names).count == 2)
        #expect(LogSessions.matching(all, text: "  bench  ", exerciseNames: names).count == 3)
    }

    @MainActor @Test func aWorkoutNameKeepsItsSessionWhole() {
        // Asking for a workout is asking for the workout, not for a workout
        // with its contents removed.
        let found = LogSessions.matching(all, text: "PF A", exerciseNames: names)
        #expect(found.count == 1)
        #expect(found[0].logs.count == 2)
    }

    @MainActor @Test func nothingTypedChangesNothing() {
        #expect(LogSessions.matching(all, text: "   ", exerciseNames: names).count == 3)
        #expect(LogSessions.matching(all).count == 3)
    }

    @MainActor @Test func somethingThatIsNotThereMatchesNothing() {
        #expect(LogSessions.matching(all, text: "deadlift", exerciseNames: names).isEmpty)
    }

    @MainActor @Test func aWordInsideAnotherWordIsNotAMatch() {
        // "Machine bench press" contains the letters of "chin": ma-CHIN-e.
        // A raw substring filter answers a search for the chin-up with the
        // bench press, which is how this was found.
        #expect(LogSessions.name("Machine bench press", matches: "chin") == false)
        #expect(LogSessions.name("Assisted chin up", matches: "chin"))
        // And the ordinary cases still behave.
        #expect(LogSessions.name("Machine bench press", matches: "bench"))
        #expect(LogSessions.name("Leg press", matches: "press"))
        #expect(LogSessions.name("Machine bench press", matches: "press"))
        #expect(LogSessions.name("Leg press", matches: "bench") == false)
    }

    @MainActor @Test func typingAWholeNameWorks() {
        // The first thing anybody does, and what was reported: typing the
        // exercise's full name into the field.
        #expect(LogSessions.name("Assisted chin up", matches: "assisted chin up"))
        #expect(LogSessions.name("Assisted chin up", matches: "assisted chin"))
        #expect(LogSessions.name("Machine bench press", matches: "assisted chin") == false)
    }

    // MARK: Dates

    @MainActor @Test func datesAreInclusiveOfBothEnds() {
        // The 17th to the 19th includes everything logged ON the 19th, which
        // is what picking that date on a calendar means — a bound at midnight
        // would silently drop the whole day.
        let found = LogSessions.matching(all, from: date(17), to: date(19))
        #expect(found.count == 2)
        #expect(found.map(\.id).sorted() == ["17-PF A", "19-PF B"])
    }

    @MainActor @Test func aSingleDayIsAValidRange() {
        let found = LogSessions.matching(all, from: date(19), to: date(19))
        #expect(found.count == 1)
        #expect(found[0].id == "19-PF B")
    }

    @MainActor @Test func datesAndTextNarrowTogether() {
        let found = LogSessions.matching(all, text: "chin", exerciseNames: names,
                                         from: date(20), to: date(22))
        #expect(found.count == 1)
        #expect(found.first?.logs.count == 1)
    }

    @MainActor @Test func onlyOneEndOfTheRangeIsEnough() {
        #expect(LogSessions.matching(all, from: date(19)).count == 2)
        #expect(LogSessions.matching(all, to: date(18)).count == 1)
    }
}

// MARK: - Reading the log the other way round
//
// The Mac can gather the same logs by exercise instead of by session: what
// somebody wants while standing at a machine, wondering what they did last
// time and whether to add weight.

@Suite(.serialized)
struct ExerciseGroupingTests {

    private let benchId = UUID()
    private let chinUpId = UUID()

    private var names: [UUID: String] { [benchId: "Bench press", chinUpId: "Assisted chin up"] }

    private func date(_ d: Int) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c.date(from: DateComponents(year: 2026, month: 10, day: d, hour: 17))!
    }

    @MainActor private func session(_ day: Int, _ workout: String,
                                    _ ids: [UUID]) -> LogSessions.Session {
        let workoutId = UUID()
        return LogSessions.Session(
            id: "\(day)", workoutId: workoutId, workoutName: workout, date: date(day),
            logs: ids.map {
                WorkoutLog(date: date(day), workoutId: workoutId, exerciseId: $0,
                           weights: [100], reps: [10])
            })
    }

    @MainActor private var all: [LogSessions.Session] {
        [session(21, "PF B", [chinUpId]),
         session(19, "PF B", [benchId, chinUpId]),
         session(17, "PF A", [benchId])]
    }

    @MainActor @Test func everyTimeAnExerciseWasDoneIsGatheredUnderIt() {
        let histories = LogSessions.byExercise(all, exerciseNames: names)
        #expect(histories.count == 2)

        let chin = try? #require(histories.first { $0.name == "Assisted chin up" })
        #expect(chin?.entries.count == 2)
        // Newest first, like the rest of the app's log reading.
        #expect(chin?.entries.first?.date == date(21))
        #expect(chin?.entries.last?.date == date(19))
    }

    @MainActor @Test func anExerciseCarriesTheWorkoutItWasDoneIn() {
        let histories = LogSessions.byExercise(all, exerciseNames: names)
        let bench = histories.first { $0.name == "Bench press" }
        #expect(bench?.mostRecent?.workoutName == "PF B")
        #expect(bench?.entries.last?.workoutName == "PF A")
    }

    @MainActor @Test func exercisesComeInTheOrderTheyWereLastDone() {
        let histories = LogSessions.byExercise(all, exerciseNames: names)
        // The chin-up was done on the 21st, the bench on the 19th.
        #expect(histories.map(\.name) == ["Assisted chin up", "Bench press"])
    }

    // MARK: Ordering

    @MainActor @Test func clickingAHeadingTurnsItRound() {
        var order = LogSessions.Order.newestFirst
        order = order.clickingDate()
        #expect(order == .oldestFirst)
        order = order.clickingDate()
        #expect(order == .newestFirst)
        // Clicking the OTHER heading starts at its own natural end rather than
        // inheriting the direction of the one before it.
        order = order.clickingName()
        #expect(order == .nameAZ)
        order = order.clickingName()
        #expect(order == .nameZA)
    }

    @MainActor @Test func sessionsSortBothWaysByDateAndByName() {
        #expect(LogSessions.ordered(all, by: .newestFirst).map(\.id) == ["21", "19", "17"])
        #expect(LogSessions.ordered(all, by: .oldestFirst).map(\.id) == ["17", "19", "21"])
        let az = LogSessions.ordered(all, by: .nameAZ).map(\.workoutName)
        #expect(az.first == "PF A")
        #expect(LogSessions.ordered(all, by: .nameZA).map(\.workoutName).first == "PF B")
    }

    @MainActor @Test func exercisesSortBothWaysToo() {
        let histories = LogSessions.byExercise(all, exerciseNames: names)
        #expect(LogSessions.ordered(histories, by: .nameAZ).map(\.name)
                == ["Assisted chin up", "Bench press"])
        #expect(LogSessions.ordered(histories, by: .nameZA).map(\.name)
                == ["Bench press", "Assisted chin up"])
        #expect(LogSessions.ordered(histories, by: .oldestFirst).map(\.name)
                == ["Bench press", "Assisted chin up"])
    }

    @MainActor @Test func theFilterAndTheGroupingWorkTogether() {
        // Narrow first, then turn inside out: one filter, two ways of looking
        // at what it leaves.
        let narrowed = LogSessions.matching(all, text: "chin", exerciseNames: names)
        let histories = LogSessions.byExercise(narrowed, exerciseNames: names)
        #expect(histories.count == 1)
        #expect(histories[0].entries.count == 2)
    }
}
