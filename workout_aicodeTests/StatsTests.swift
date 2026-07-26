import Testing
import Foundation
@testable import workout_aicode

// Tests for the strength statistics. The arithmetic here decides what users are
// told about their progress, and a wrong sign or a wrong window is not
// something the UI would make obvious — hence checking the numbers directly.

private func day(_ n: Int) -> Date {
    Date(timeIntervalSince1970: 1_700_000_000).addingTimeInterval(Double(n) * 86_400)
}

// MARK: - 1RM formulas

@Test func epleyMatchesTheFormula() {
    // 100 kg × 10 reps → 100 × (1 + 10/30) = 133.33
    let e = OneRMFormula.epley.estimate(weight: 100, reps: 10)!
    #expect(abs(e - 133.3333) < 0.001)
}

@Test func brzyckiMatchesTheFormula() {
    // 100 / (1.0278 − 0.278) = 133.37
    let b = OneRMFormula.brzycki.estimate(weight: 100, reps: 10)!
    #expect(abs(b - 100 / (1.0278 - 0.0278 * 10)) < 0.001)
}

@Test func lombardiMatchesTheFormula() {
    let l = OneRMFormula.lombardi.estimate(weight: 100, reps: 10)!
    #expect(abs(l - 100 * pow(10, 0.1)) < 0.001)
}

@Test func singleRepIsItsOwnMax() {
    // Epley would otherwise report 103.3 for a set that IS a one-rep max.
    for formula in OneRMFormula.allCases {
        #expect(formula.estimate(weight: 100, reps: 1) == 100)
    }
}

@Test func brzyckiRefusesImpossibleRepCounts() {
    // The denominator hits zero near 37 reps; beyond that the formula would
    // return a negative or absurd "max".
    #expect(OneRMFormula.brzycki.estimate(weight: 100, reps: 40) == nil)
    #expect(OneRMFormula.brzycki.estimate(weight: 100, reps: 20) != nil)
}

@Test func uninformativeSetsYieldNothing() {
    #expect(OneRMFormula.epley.estimate(weight: 0, reps: 10) == nil)
    #expect(OneRMFormula.epley.estimate(weight: 100, reps: 0) == nil)
}

// MARK: - Sessions and hard sets

@Test func bestSetSetsTheMetric() {
    let s = ExerciseSession(id: UUID(), date: day(0),
                            weights: [50, 60, 55], reps: [10, 8, 9],
                            formula: .epley)!
    // 60×8 → 76 is the best of 66.7 / 76 / 71.5
    #expect(abs(s.m1RM - 76) < 0.001)
}

@Test func hardSetsAreTheBestAndThoseWithinFourReps() {
    // Epley, best = 60×8 = 76.0
    //   50×10 = 66.7 → +4 reps: 50×14 = 73.3  → short of 76, not hard
    //   55×9  = 71.5 → +4 reps: 55×13 = 78.8  → reaches 76, hard
    //   30×5  = 35.0 → +4 reps: 30×9  = 39.0  → nowhere near, not hard
    let s = ExerciseSession(id: UUID(), date: day(0),
                            weights: [50, 60, 55, 30], reps: [10, 8, 9, 5],
                            formula: .epley)!
    #expect(s.sets.map(\.isHard) == [false, true, true, false])
    #expect(s.hardSetCount == 2)
}

@Test func tiedBestSetsAreBothHard() {
    let s = ExerciseSession(id: UUID(), date: day(0),
                            weights: [60, 60], reps: [8, 8], formula: .epley)!
    #expect(s.hardSetCount == 2)
}

@Test func sessionWithNoUsableSetIsRejected() {
    #expect(ExerciseSession(id: UUID(), date: day(0),
                            weights: [0, 0], reps: [10, 8], formula: .epley) == nil)
}

// MARK: - Regression

@Test func slopeIsPerDayAndSignedCorrectly() {
    // +1 unit per day, exactly.
    let points = (0..<10).map { (date: day($0), value: 100.0 + Double($0)) }
    let fit = LinearFit(points: points)!
    #expect(abs(fit.slopePerDay - 1.0) < 1e-9)
    #expect(abs(fit.value(at: day(0)) - 100) < 1e-9)
}

@Test func decliningStrengthGivesNegativeTrend() {
    let logs = (0..<10).map {
        StatsEngine.LogInput(id: UUID(), exerciseId: exerciseA, date: day($0 * 7),
                             weights: [100 - $0], reps: [5])
    }
    let stats = StatsEngine.analyze(logs: logs, names: [exerciseA: "Falling"],
                                    formula: .epley, window: 16, smoothing: 1)
    #expect(stats.count == 1)
    #expect(stats[0].trendPerDay! < 0)
}

@Test func flatHistoryHasZeroSlope() {
    let logs = (0..<10).map {
        StatsEngine.LogInput(id: UUID(), exerciseId: exerciseA, date: day($0 * 7),
                             weights: [100], reps: [5])
    }
    let stats = StatsEngine.analyze(logs: logs, names: [exerciseA: "Flat"],
                                    formula: .epley, window: 16, smoothing: 1)
    #expect(abs(stats[0].trendPerDay!) < 1e-12)
}

@Test func trendIsSlopeOverMean() {
    let logs = (0..<10).map {
        StatsEngine.LogInput(id: UUID(), exerciseId: exerciseA, date: day($0),
                             weights: [100 + $0], reps: [1])
    }
    let stats = StatsEngine.analyze(logs: logs, names: [exerciseA: "Rising"],
                                    formula: .epley, window: 16, smoothing: 1)
    let s = stats[0]
    let mean = s.sessions.map(\.m1RM).reduce(0, +) / Double(s.sessions.count)
    #expect(abs(s.trendPerDay! - s.fit!.slopePerDay / mean) < 1e-12)
}

// MARK: - Eligibility and windowing

@Test func fewerThanEightSessionsAreNotReported() {
    let logs = (0..<7).map {
        StatsEngine.LogInput(id: UUID(), exerciseId: exerciseA, date: day($0 * 7),
                             weights: [100], reps: [5])
    }
    let stats = StatsEngine.analyze(logs: logs, names: [exerciseA: "Sparse"],
                                    formula: .epley, window: 16, smoothing: 1)
    #expect(stats.isEmpty)
}

@Test func exactlyEightSessionsQualify() {
    let logs = (0..<8).map {
        StatsEngine.LogInput(id: UUID(), exerciseId: exerciseA, date: day($0 * 7),
                             weights: [100], reps: [5])
    }
    let stats = StatsEngine.analyze(logs: logs, names: [exerciseA: "Just enough"],
                                    formula: .epley, window: 16, smoothing: 1)
    #expect(stats.count == 1)
}

@Test func onlyTheMostRecentWindowIsUsed() {
    // 30 sessions, window 16 → the oldest 14 are ignored, and the 16 kept are
    // the most recent ones.
    let logs = (0..<30).map {
        StatsEngine.LogInput(id: UUID(), exerciseId: exerciseA, date: day($0 * 7),
                             weights: [100], reps: [5])
    }
    let stats = StatsEngine.analyze(logs: logs, names: [exerciseA: "Long"],
                                    formula: .epley, window: 16, smoothing: 1)
    #expect(stats[0].sessions.count == 16)
    #expect(stats[0].totalSessions == 30)
    #expect(stats[0].sessions.first!.date == day(14 * 7))
}

// MARK: - Smoothing

@Test func movingAverageCentresOnTheMiddleDate() {
    let points = [(date: day(0), value: 1.0),
                  (date: day(2), value: 2.0),
                  (date: day(10), value: 3.0)]
    let smoothed = StatsEngine.movingAverage(points, width: 3)
    #expect(smoothed.count == 1)
    #expect(smoothed[0].date == day(2))          // middle date, not the mean date
    #expect(abs(smoothed[0].value - 2.0) < 1e-12)
}

@Test func smoothingWidthOneChangesNothing() {
    let points = (0..<5).map { (date: day($0), value: Double($0)) }
    #expect(StatsEngine.movingAverage(points, width: 1).count == 5)
}

@Test func tooFewPointsToSmoothAreLeftAlone() {
    let points = (0..<3).map { (date: day($0), value: Double($0)) }
    #expect(StatsEngine.movingAverage(points, width: 5).count == 3)
}

// MARK: - Ordering

@Test func progressListRunsWorstToBest() {
    let rising = (0..<10).map {
        StatsEngine.LogInput(id: UUID(), exerciseId: exerciseA, date: day($0 * 7),
                             weights: [100 + $0 * 2], reps: [5])
    }
    let falling = (0..<10).map {
        StatsEngine.LogInput(id: UUID(), exerciseId: exerciseB, date: day($0 * 7),
                             weights: [100 - $0], reps: [5])
    }
    let stats = StatsEngine.analyze(logs: rising + falling,
                                    names: [exerciseA: "Rising", exerciseB: "Falling"],
                                    formula: .epley, window: 16, smoothing: 1)
    #expect(stats.map(\.name) == ["Falling", "Rising"])
}

private let exerciseA = UUID()
private let exerciseB = UUID()
