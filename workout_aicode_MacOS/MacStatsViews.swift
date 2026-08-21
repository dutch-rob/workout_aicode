import SwiftUI
import SwiftData
import Charts

// MARK: - Graphs and progress
//
// The same two screens the phone has, over the same numbers: StatsInputs and
// StatsEngine do the work, and nothing here recomputes anything. What the Mac
// adds is width — the graphs sit two to a row instead of one, and the progress
// list can afford a column of detail rather than a caption.
//
// The options that decide what the numbers mean — which 1RM formula, how many
// sessions, how much smoothing — are in Settings, and read from the same
// UserDefaults keys the phone writes. They are per-device, like every other
// setting here; the footer in Settings says so.

// MARK: - Graphs

struct MacGraphsView: View {
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

        Group {
            if stats.isEmpty {
                ContentUnavailableView {
                    Label("No graphs yet", systemImage: "chart.xyaxis.line")
                } description: {
                    Text(emptyMessage(pending))
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 380), spacing: 20)],
                              alignment: .leading, spacing: 24) {
                        ForEach(stats) { stat in
                            MacExerciseChart(stat: stat)
                        }
                    }
                    .padding(16)

                    if !pending.isEmpty {
                        Text(pendingMessage(pending))
                            .font(.footnote).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 20)
                    }
                }
            }
        }
        .navigationTitle("Graphs")
        .toolbar { StatsOptionsMenu() }
    }

    /// An empty screen has two quite different causes, and saying the wrong one
    /// sends someone looking for a problem they do not have.
    private func emptyMessage(_ pending: [(name: String, count: Int)]) -> String {
        if logs.isEmpty {
            return "Nothing has been logged yet. Graphs are drawn from what you log on your iPhone and Apple Watch, and appear here once an exercise has \(ExerciseStats.minimumSessions) workouts behind it."
        }
        if pending.isEmpty {
            return "A graph appears for an exercise once you have logged it in \(ExerciseStats.minimumSessions) workouts."
        }
        return "Not yet: " + pendingMessage(pending)
    }

    private func pendingMessage(_ pending: [(name: String, count: Int)]) -> String {
        let names = pending.map { "\($0.name) (\($0.count) of \(ExerciseStats.minimumSessions))" }
        return "More graphs will appear after you have logged these exercises more often: "
             + names.joined(separator: ", ") + "."
    }
}

/// One exercise: the strength metric over time, with its trendline.
struct MacExerciseChart: View {
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
                    // The trendline is the raw regression — deliberately NOT
                    // fitted to the smoothed dots, so smoothing changes how the
                    // dots read but never moves the trend.
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
            .frame(height: 200)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
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

// MARK: - Progress

struct MacProgressView: View {
    @Query(sort: [SortDescriptor(\WorkoutLog.date, order: .forward)]) private var logs: [WorkoutLog]
    @Query private var exercises: [ExerciseDef]

    @AppStorage(StatsSettingsKey.formula)   private var formulaRaw = OneRMFormula.epley.rawValue
    @AppStorage(StatsSettingsKey.window)    private var window = StatsEngine.defaultWindow
    @AppStorage(StatsSettingsKey.smoothing) private var smoothing = StatsEngine.defaultSmoothing

    var body: some View {
        let inputs = StatsInputs(formulaRaw: formulaRaw, window: window, smoothing: smoothing)
        let stats = inputs.analyze(logs: logs, exercises: exercises)

        Group {
            if stats.isEmpty {
                ContentUnavailableView {
                    Label("Nothing to rank yet", systemImage: "list.number")
                } description: {
                    Text("An exercise joins this list once you have logged it in \(ExerciseStats.minimumSessions) workouts.")
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Table(stats) {
                        TableColumn("Exercise") { stat in
                            Text(stat.name)
                        }
                        TableColumn("Trend") { stat in
                            Text(formatTrend(stat.trendPerWeek))
                                .bold()
                                .foregroundStyle(trendColor(stat.trendPerWeek))
                                .monospacedDigit()
                        }
                        .width(110)
                        TableColumn("Last best") { stat in
                            Text(stat.sessions.last.map { String(format: "%.0f", $0.m1RM) } ?? "—")
                                .monospacedDigit()
                        }
                        .width(80)
                        TableColumn("Hard sets / workout") { stat in
                            Text(String(format: "%.1f", hardSets(stat)))
                                .monospacedDigit()
                        }
                        .width(140)
                        TableColumn("Workouts") { stat in
                            Text("\(stat.sessions.count) of \(stat.totalSessions)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .width(100)
                    }

                    Divider()
                    Text(footnote(stats))
                        .font(.footnote).foregroundStyle(.secondary)
                        .padding(12)
                }
            }
        }
        .navigationTitle("Progress")
        .toolbar { StatsOptionsMenu() }
    }

    private func hardSets(_ stat: ExerciseStats) -> Double {
        guard !stat.sessions.isEmpty else { return 0 }
        return Double(stat.sessions.map(\.hardSetCount).reduce(0, +)) / Double(stat.sessions.count)
    }

    private func footnote(_ stats: [ExerciseStats]) -> String {
        let used = min(window, stats.map(\.sessions.count).max() ?? window)
        return "Ordered from least to most progress, so whatever needs attention is at the top. The percentage is the trend in your best estimated one-rep max over the last \(used) workouts, relative to its average."
    }
}

// MARK: - The options, where the numbers are being read
//
// Also in Settings, but a toolbar menu here as well: changing the smoothing to
// see what a graph does under it is a thing you do WHILE looking at the graph,
// and a round trip through another screen to try each value would make nobody
// try any of them.

struct StatsOptionsMenu: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItem {
            Menu {
                MacStatsOptions()
                    .frame(width: 260)
            } label: {
                Label("Options", systemImage: "slider.horizontal.3")
            }
            .help("How these numbers are worked out")
        }
    }
}

/// The three options themselves, shared by the toolbar menu and Settings so
/// there is one description of each rather than two that drift.
struct MacStatsOptions: View {
    @AppStorage(StatsSettingsKey.formula)   private var formulaRaw = OneRMFormula.epley.rawValue
    @AppStorage(StatsSettingsKey.window)    private var window = StatsEngine.defaultWindow
    @AppStorage(StatsSettingsKey.smoothing) private var smoothing = StatsEngine.defaultSmoothing

    private var formula: OneRMFormula { OneRMFormula(rawValue: formulaRaw) ?? .epley }

    var body: some View {
        Picker("One-rep max formula", selection: $formulaRaw) {
            ForEach(OneRMFormula.allCases) { f in
                Text("\(f.label) — \(f.formulaText)").tag(f.rawValue)
            }
        }
        Picker("Sessions in the trend", selection: $window) {
            ForEach([8, 12, 16, 24, 32, 52], id: \.self) { n in
                Text("\(n)").tag(n)
            }
        }
        Picker("Smoothing", selection: $smoothing) {
            ForEach(StatsEngine.smoothingChoices, id: \.self) { n in
                Text(n == 1 ? "None" : "\(n) sessions").tag(n)
            }
        }
    }
}
