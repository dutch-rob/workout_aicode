import SwiftUI
import SwiftData
import Charts

// MARK: - logs/stats
//
// Four tabs over the same data: the log list, a graph per exercise, the
// exercises ranked by trend, and the import/export tools that used to sit as a
// button row above the list.

enum StatsSettingsKey {
    static let formula   = "oneRMFormula"
    static let window    = "trendWindow"
    static let smoothing = "graphSmoothing"
}

struct LogsStatsView: View {

    enum Tab: String, CaseIterable, Identifiable {
        case logs, graphs, progress, transfer
        var id: String { rawValue }
        var label: String {
            switch self {
            case .logs:     return "logs"
            case .graphs:   return "graphs"
            case .progress: return "progress"
            case .transfer: return "import/export"
            }
        }
    }

    @State private var tab: Tab = .logs
    /// Only needed to judge whether the survey is due when leaving.
    @Query private var logs: [WorkoutLog]

    var body: some View {
        VStack(spacing: 8) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            switch tab {
            case .logs:     LogsListView()
            case .graphs:   StrengthGraphsView()
            case .progress: StrengthProgressView()
            case .transfer: ImportExportView()
            }
        }
        .navigationTitle("logs/stats")
        // The survey is raised on the way out, and presented by ContentView:
        // a view that is being popped cannot present a sheet itself.
        .onDisappear { SurveyScheduler.shared.noteLeftStatsScreen(logs: logs) }
    }
}

// MARK: - Shared statistics loading

/// Reads the user's options and turns stored logs into `ExerciseStats`.
/// Kept in one place so the graphs tab and the progress tab can never disagree
/// about what the numbers are.
struct StatsInputs {
    let formula: OneRMFormula
    let window: Int
    let smoothing: Int

    init(formulaRaw: String, window: Int, smoothing: Int) {
        self.formula = OneRMFormula(rawValue: formulaRaw) ?? .epley
        self.window = max(ExerciseStats.minimumSessions, window)
        self.smoothing = smoothing
    }

    func analyze(logs: [WorkoutLog], exercises: [ExerciseDef]) -> [ExerciseStats] {
        let names = Dictionary(exercises.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        let inputs = logs.map {
            StatsEngine.LogInput(id: $0.id, exerciseId: $0.exerciseId, date: $0.date,
                                 weights: $0.weights, reps: $0.reps)
        }
        return StatsEngine.analyze(logs: inputs, names: names,
                                   formula: formula, window: window, smoothing: smoothing)
    }

    /// Exercises that are still short of the 8 sessions needed, with how many
    /// they have — so the UI can say which graphs are still coming.
    func pending(logs: [WorkoutLog], exercises: [ExerciseDef]) -> [(name: String, count: Int)] {
        let counts = Dictionary(grouping: logs, by: \.exerciseId).mapValues(\.count)
        return exercises
            .compactMap { exercise in
                let n = counts[exercise.id] ?? 0
                guard n > 0, n < ExerciseStats.minimumSessions else { return nil }
                return (name: exercise.name, count: n)
            }
            .sorted { $0.count > $1.count }
    }
}

/// Formats a trend as a percentage per week, the scale people plan in.
func formatTrend(_ perWeek: Double?) -> String {
    guard let perWeek else { return "—" }
    return String(format: "%+.1f%%/week", perWeek * 100)
}

func trendColor(_ perWeek: Double?) -> Color {
    guard let perWeek else { return .secondary }
    if perWeek > 0.002 { return .green }
    if perWeek < -0.002 { return .red }
    return .primary
}

// MARK: - Graphs tab

struct StrengthGraphsView: View {
    @Query(sort: [SortDescriptor(\WorkoutLog.date, order: .forward)]) private var logs: [WorkoutLog]
    @Query private var exercises: [ExerciseDef]

    @AppStorage(StatsSettingsKey.formula)   private var formulaRaw = OneRMFormula.epley.rawValue
    @AppStorage(StatsSettingsKey.window)    private var window = StatsEngine.defaultWindow
    @AppStorage(StatsSettingsKey.smoothing) private var smoothing = StatsEngine.defaultSmoothing

    private var inputs: StatsInputs {
        StatsInputs(formulaRaw: formulaRaw, window: window, smoothing: smoothing)
    }

    var body: some View {
        let stats = inputs.analyze(logs: logs, exercises: exercises)
        let pending = inputs.pending(logs: logs, exercises: exercises)

        if stats.isEmpty {
            ContentUnavailableView {
                Label("No graphs yet", systemImage: "chart.xyaxis.line")
            } description: {
                Text("A graph appears for an exercise once you have logged it in \(ExerciseStats.minimumSessions) workouts. Keep logging and they will fill in.")
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ForEach(stats) { stat in
                        ExerciseChart(stat: stat)
                    }
                    if !pending.isEmpty {
                        Text(pendingMessage(pending))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
        }
    }

    private func pendingMessage(_ pending: [(name: String, count: Int)]) -> String {
        let names = pending.map { "\($0.name) (\($0.count) of \(ExerciseStats.minimumSessions))" }
        return "More graphs will appear after you have logged these exercises more often: "
             + names.joined(separator: ", ") + "."
    }
}

/// One exercise: the strength metric over time, with its trendline.
struct ExerciseChart: View {
    let stat: ExerciseStats

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(stat.name).font(.headline)
            HStack(spacing: 8) {
                Text(formatTrend(stat.trendPerWeek))
                    .font(.subheadline).bold()
                    .foregroundStyle(trendColor(stat.trendPerWeek))
                Text("· \(stat.sessions.count) of \(stat.totalSessions) workouts")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Chart {
                ForEach(Array(stat.plotPoints.enumerated()), id: \.offset) { _, point in
                    PointMark(x: .value("Date", point.date),
                              y: .value("Best 1RM", point.value))
                        .foregroundStyle(.blue)
                }
                if let fit = stat.fit,
                   let first = stat.sessions.first?.date,
                   let last = stat.sessions.last?.date {
                    // The trendline is the raw regression from the spec — it is
                    // deliberately NOT fitted to the smoothed dots, so smoothing
                    // changes how the dots read but never moves the trend.
                    LineMark(x: .value("Date", first),
                             y: .value("Trend", fit.value(at: first)),
                             series: .value("Series", "trend"))
                        .foregroundStyle(.orange)
                    LineMark(x: .value("Date", last),
                             y: .value("Trend", fit.value(at: last)),
                             series: .value("Series", "trend"))
                        .foregroundStyle(.orange)
                }
            }
            .chartYScale(domain: yDomain)
            .chartYAxis {
                // Plain numbers. The default formatting drops into scientific
                // notation ("4.4E1") on a narrow domain, which is what a
                // plateaued exercise produces.
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(v.formatted(.number.precision(.fractionLength(0))))
                        }
                    }
                }
            }
            .frame(height: 180)
        }
    }

    /// Explicit y range with a margin.
    ///
    /// An exercise held at the same weight and reps for weeks — a plateau, and
    /// common — makes every value identical. Left to itself the chart then gets
    /// a zero-height domain and draws nonsense: axis labels out of order, and
    /// the dots and the trendline at opposite edges despite being equal. So a
    /// flat series is given a band around its value instead.
    private var yDomain: ClosedRange<Double> {
        var values = stat.plotPoints.map(\.value)
        if let fit = stat.fit,
           let first = stat.sessions.first?.date,
           let last = stat.sessions.last?.date {
            values.append(fit.value(at: first))
            values.append(fit.value(at: last))
        }
        guard let low = values.min(), let high = values.max() else { return 0...1 }

        let span = high - low
        let margin = span > 0.001 ? span * 0.15 : max(1, abs(high) * 0.05)
        return (low - margin)...(high + margin)
    }
}

// MARK: - Progress tab

struct StrengthProgressView: View {
    @Query(sort: [SortDescriptor(\WorkoutLog.date, order: .forward)]) private var logs: [WorkoutLog]
    @Query private var exercises: [ExerciseDef]

    @AppStorage(StatsSettingsKey.formula)   private var formulaRaw = OneRMFormula.epley.rawValue
    @AppStorage(StatsSettingsKey.window)    private var window = StatsEngine.defaultWindow
    @AppStorage(StatsSettingsKey.smoothing) private var smoothing = StatsEngine.defaultSmoothing

    var body: some View {
        let inputs = StatsInputs(formulaRaw: formulaRaw, window: window, smoothing: smoothing)
        let stats = inputs.analyze(logs: logs, exercises: exercises)

        if stats.isEmpty {
            ContentUnavailableView {
                Label("Nothing to rank yet", systemImage: "list.number")
            } description: {
                Text("An exercise joins this list once you have logged it in \(ExerciseStats.minimumSessions) workouts.")
            }
        } else {
            List {
                Section {
                    ForEach(stats) { stat in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(stat.name).font(.headline)
                                Text(detail(for: stat))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(formatTrend(stat.trendPerWeek))
                                .font(.subheadline).bold()
                                .foregroundStyle(trendColor(stat.trendPerWeek))
                                .monospacedDigit()
                        }
                    }
                } footer: {
                    Text("Ordered from least to most progress, so whatever needs attention is at the top. The percentage is the trend in your best estimated one-rep max over the last \(min(window, stats.map(\.sessions.count).max() ?? window)) workouts, relative to its average.")
                }
            }
        }
    }

    private func detail(for stat: ExerciseStats) -> String {
        let best = stat.sessions.last?.m1RM ?? 0
        let hard = Double(stat.sessions.map(\.hardSetCount).reduce(0, +)) / Double(stat.sessions.count)
        return String(format: "last best %.0f · %.1f hard sets per workout", best, hard)
    }
}
