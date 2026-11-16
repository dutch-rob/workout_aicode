// The logs tab: everything recorded, newest first, with the filters over it.

import SwiftUI
import SwiftData

// MARK: - Logs Screen
// MARK: - logs tab
//
// The log list. Import/export lives in ImportExportView; both are tabs of
// LogsStatsView now.

struct LogsListView: View {
    @Query(sort: [SortDescriptor(\WorkoutLog.date, order: .reverse)]) private var logs: [WorkoutLog]
    @Query private var workouts: [WorkoutDef]
    @Query private var exercises: [ExerciseDef]
    @Query private var aerobicResults: [AerobicResult]
    @Query private var logWeights: [LogWeights]

    var body: some View {
        if logs.isEmpty {
            ContentUnavailableView("No logs yet", systemImage: "doc.text", description: Text("Start logging your workouts to see them here."))
        } else {
            let rows = compactRows()
            List(rows) { row in
                VStack(spacing: 4) {
                    // Every row carries the rule above it, except the first:
                    // there the card's own top edge already does the job, and
                    // a rule drawn flush against it read as a stray border.
                    if row.id != rows.first?.id {
                        Rectangle()
                            .fill(Color.secondary.opacity(1.0))
                            .frame(height: row.isWorkout ? 3 : 1)
                    }
                    HStack(alignment: .center, spacing: 8) {
                        Group {
                            if row.isWorkout {
                                Text(row.left).font(.headline).foregroundStyle(.blue).italic()
                            } else {
                                Text(row.left).font(.headline)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Group {
                            if row.isWorkout {
                                Text(row.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.headline).foregroundStyle(.blue)
                            } else if let log = row.log {
                                weightsRepsGrid(for: log, at: row.date)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .listRowSeparator(.hidden)
                // A row's own insets, because the standard ones left a blank
                // line under every exercise: the two numbers rows are about
                // 26pt each and the default padding added 34pt of nothing
                // between one exercise and the next, which read as a third,
                // empty row. The rule above each row is drawn here rather
                // than by the list, so the top inset is the rule's own.
                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 8, trailing: 20))
            }
            // The grey above the first rule matched neither the grey beside
            // the list nor anything else. With the 8pt the shell already puts
            // under the tab picker, this makes it the same 20pt as the sides.
            .contentMargins(.top, 12, for: .scrollContent)
        }
    }

    private struct CompactRow: Identifiable {
        let id: String
        let isWorkout: Bool
        let left: String
        let date: Date
        let log: WorkoutLog?
        let workoutId: UUID?
        let exerciseId: UUID?
    }

    private func compactRows() -> [CompactRow] {
        let maxWorkoutPauze: TimeInterval = 3600 // seconds
        var rows: [CompactRow] = []
        var lastExerciseDate: Date? = nil
        var lastWorkoutId: UUID? = nil
        for log in logs {
            let workoutName = workouts.first(where: { $0.id == log.workoutId })?.name ?? "Workout"
            // Insert a workout-header row when more than maxWorkoutPauze has
            // elapsed since the previous logged exercise OR the workout id
            // changed (so adjacent same-workout exercises group together).
            let shouldInsertHeader: Bool = {
                guard let last = lastExerciseDate else { return true }
                if last.timeIntervalSince(log.date) >= maxWorkoutPauze { return true }
                if lastWorkoutId != log.workoutId { return true }
                return false
            }()
            if shouldInsertHeader {
                rows.append(CompactRow(
                    id: "w-\(log.id.uuidString)",
                    isWorkout: true,
                    left: workoutName,
                    date: log.date,
                    log: nil,
                    workoutId: log.workoutId,
                    exerciseId: nil
                ))
            }
            let exerciseName = exercises.first(where: { $0.id == log.exerciseId })?.name ?? "Exercise"
            rows.append(CompactRow(
                id: "e-\(log.id.uuidString)",
                isWorkout: false,
                left: exerciseName,
                date: log.date,
                log: log,
                workoutId: log.workoutId,
                exerciseId: log.exerciseId
            ))
            lastExerciseDate = log.date
            lastWorkoutId = log.workoutId
        }
        return rows
    }

    /// What a finished aerobic session came to, if this log is one.
    private func aerobicSummary(for log: WorkoutLog) -> AerobicSummary? {
        guard let result = aerobicResults.first(where: { $0.logId == log.id }) else { return nil }
        return AerobicSummary(seconds: result.durationSeconds,
                              averageHeartRate: result.averageHeartRate,
                              maximumHeartRate: result.maximumHeartRate,
                              zoneSeconds: result.zoneSeconds)
    }

    @ViewBuilder
    private func weightsRepsGrid(for log: WorkoutLog, at date: Date) -> some View {
        // A ride has no sets, so the w/r grid rendered two empty rows with
        // nothing in them. Its own numbers instead.
        if let summary = aerobicSummary(for: log) {
            AerobicSummaryView(summary: summary, compact: true)
        } else {
            weightsRepsColumns(for: log, at: date)
        }
    }

    private func weightsRepsColumns(for log: WorkoutLog, at date: Date) -> some View {
        let previous = previousEntry(for: log.exerciseId, before: date)
        // Grams, from beside the log. The unit is only how they are written —
        // no "kg" or "lb" here, where every column is already as narrow as it
        // can be and the unit is the same down the whole screen.
        let byLog = LogWeightsIndex.byLogId(logWeights)
        let grams = byLog[log.id] ?? []
        let previousGrams = previous.flatMap { byLog[$0.id] } ?? []
        let unit = WeightUnit.current
        let maxCount = max(grams.count, log.reps.count)
        return Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
            GridRow {
                Text("w").font(.headline)
                ForEach(0..<maxCount, id: \.self) { i in
                    let current = i < grams.count ? grams[i] : 0
                    let prev = previousGrams.indices.contains(i) ? previousGrams[i] : nil
                    // The reps of the SAME set, both times: the weight's
                    // colour depends on them — see LogComparison.weightColour.
                    let currentR = i < log.reps.count ? log.reps[i] : 0
                    let prevR = previous?.reps.indices.contains(i) == true ? previous!.reps[i] : nil
                    Text(WeightText.string(grams: current, in: unit))
                        .foregroundStyle(colorForWeight(current: current, previous: prev,
                                                        currentReps: currentR, previousReps: prevR,
                                                        exerciseId: log.exerciseId))
                        .font(.headline)
                }
            }
            GridRow {
                Text("r").font(.headline)
                ForEach(0..<maxCount, id: \.self) { i in
                    let current = i < log.reps.count ? log.reps[i] : 0
                    let prevRep = previous?.reps.indices.contains(i) == true ? previous!.reps[i] : nil
                    let currentW = i < grams.count ? grams[i] : 0
                    let prevW = previousGrams.indices.contains(i) ? previousGrams[i] : nil
                    Text("\(current)")
                        .foregroundStyle(colorForReps(current: current, previous: prevRep,
                                                      currentWeight: currentW, previousWeight: prevW,
                                                      exerciseId: log.exerciseId))
                        .font(.headline)
                }
            }
        }
    }

    // The rules themselves live in Shared/StatsPresentation.swift, where the
    // Mac's log screen reads them too. Green and red here are a claim about
    // the user's training, and two devices colouring the same two rows
    // differently would be telling contradictory stories about one workout.

    private func previousEntry(for exerciseId: UUID, before date: Date) -> WorkoutLog? {
        LogComparison.previous(for: exerciseId, before: date, in: logs)
    }

    /// The exercise's own increment, so a difference smaller than half of it
    /// is left uncoloured — see `LogComparison.tolerance`.
    private func increment(for exerciseId: UUID) -> Int? {
        exercises.first(where: { $0.id == exerciseId })?.weightIncrementGrams
    }

    private func colorForWeight(current: Int, previous: Int?,
                                currentReps: Int, previousReps: Int?,
                                exerciseId: UUID) -> Color {
        LogComparison.weightColour(current: current, previous: previous,
                                   currentReps: currentReps, previousReps: previousReps,
                                   increment: increment(for: exerciseId))
    }

    private func colorForReps(current: Int, previous: Int?, currentWeight: Int,
                              previousWeight: Int?, exerciseId: UUID) -> Color {
        LogComparison.repsColour(current: current, previous: previous,
                                 currentWeight: currentWeight, previousWeight: previousWeight,
                                 increment: increment(for: exerciseId))
    }
}
