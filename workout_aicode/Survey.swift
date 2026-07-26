import SwiftUI
import SwiftData
import Combine

// MARK: - Survey
//
// One short questionnaire, asked once a user has enough experience for their
// answers to mean something: they have logged on 12 separate days AND been
// using the app for 8 weeks — "whichever comes last", so both must be true.
//
// It is raised when they leave the logs/stats screen, not while they are
// reading it. A sheet cannot be presented by a view that is disappearing, so
// the screen only sets a flag here and the main screen presents it.

@MainActor
final class SurveyScheduler: ObservableObject {
    static let shared = SurveyScheduler()

    /// Set when the user leaves logs/stats and is due the survey.
    @Published var pending = false

    private let firstUseKey  = "surveyFirstUseDate"
    private let answeredKey  = "surveyAnsweredAt"
    private let declinedKey  = "surveyDeclinedAt"
    private let declineCount = "surveyDeclineCount"

    /// Thresholds, both of which must be met.
    static let requiredLoggingDays = 12
    static let requiredWeeks = 8
    /// A user who closes the survey without answering is asked again after
    /// this long, at most `maximumAsks` times in total. Being asked forever is
    /// worse than a smaller sample.
    static let reAskAfterDays = 21
    static let maximumAsks = 3

    private let defaults = UserDefaults.standard

    /// Call once at launch so "8 weeks" has a starting point. For someone who
    /// already has history, the earliest log is a truer start than today.
    func noteLaunch(earliestLogDate: Date?) {
        guard defaults.object(forKey: firstUseKey) == nil else { return }
        let start = earliestLogDate ?? Date()
        defaults.set(start.timeIntervalSince1970, forKey: firstUseKey)
    }

    var firstUseDate: Date {
        let t = defaults.double(forKey: firstUseKey)
        return t > 0 ? Date(timeIntervalSince1970: t) : Date()
    }

    /// Distinct calendar days on which anything was logged.
    static func loggingDayCount(_ logs: [WorkoutLog]) -> Int {
        Set(logs.map { Calendar.current.startOfDay(for: $0.date) }).count
    }

    func isDue(logs: [WorkoutLog], now: Date = Date()) -> Bool {
        if defaults.object(forKey: answeredKey) != nil { return false }
        if defaults.integer(forKey: declineCount) >= Self.maximumAsks { return false }

        // Wait out the re-ask interval after a decline.
        if let last = defaults.object(forKey: declinedKey) as? Double {
            let elapsed = now.timeIntervalSince(Date(timeIntervalSince1970: last))
            if elapsed < Double(Self.reAskAfterDays) * 86_400 { return false }
        }

        let days = Self.loggingDayCount(logs)
        let weeks = now.timeIntervalSince(firstUseDate) / (7 * 86_400)
        return days >= Self.requiredLoggingDays && weeks >= Double(Self.requiredWeeks)
    }

    /// Called as the logs/stats screen goes away.
    func noteLeftStatsScreen(logs: [WorkoutLog]) {
        if isDue(logs: logs) { pending = true }
    }

    func markAnswered() {
        defaults.set(Date().timeIntervalSince1970, forKey: answeredKey)
        pending = false
    }

    func markDeclined() {
        defaults.set(Date().timeIntervalSince1970, forKey: declinedKey)
        defaults.set(defaults.integer(forKey: declineCount) + 1, forKey: declineCount)
        pending = false
    }
}

// MARK: - Answers

/// Deliberately small and closed-ended: every field is a fixed scale or a
/// yes/maybe/no, so answers can be compared without touching free text (and
/// without free text becoming a channel for personal information).
struct SurveyAnswers: Codable {
    enum Helpfulness: String, Codable, CaseIterable, Identifiable {
        case notAsked = "not asked"
        case not, aBit, very
        var id: String { rawValue }
        var label: String {
            switch self {
            case .notAsked: return "—"
            case .not:      return "not"
            case .aBit:     return "a bit"
            case .very:     return "very"
            }
        }
    }

    enum Interest: String, Codable, CaseIterable, Identifiable {
        case unanswered, no, maybe, yes
        var id: String { rawValue }
        var label: String {
            switch self {
            case .unanswered: return "—"
            case .no:         return "no"
            case .maybe:      return "maybe"
            case .yes:        return "yes"
            }
        }
    }

    var logsHelpful: Helpfulness = .notAsked
    var graphsHelpful: Helpfulness = .notAsked
    var progressHelpful: Helpfulness = .notAsked
    /// Interest in individualised advice derived from their own data, e.g. how
    /// long to leave before the next workout.
    var wantsAdvancedStats: Interest = .unanswered
    /// Willingness to answer a question after an exercise (fatigue rating,
    /// self-reported result) if it improved that advice.
    var wantsToAnswerQuestions: Interest = .unanswered
    var answeredAt: Date = Date()
}

// MARK: - The sheet

struct SurveyView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SharingKey.consent) private var sharingEnabled = false

    @State private var answers = SurveyAnswers()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("A few quick questions about the logs/stats screen. Your answers guide what gets built next.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("How helpful is each part?") {
                    helpfulnessRow("logs", value: $answers.logsHelpful)
                    helpfulnessRow("graphs", value: $answers.graphsHelpful)
                    helpfulnessRow("progress", value: $answers.progressHelpful)
                }

                Section {
                    interestRow("Show individual advice", value: $answers.wantsAdvancedStats)
                } footer: {
                    Text("Statistics that use your own workout history to estimate things specific to you — for example how long to leave before training a muscle group again.")
                }

                Section {
                    interestRow("Answer a question after an exercise", value: $answers.wantsToAnswerQuestions)
                } footer: {
                    Text("For example rating how hard a set felt, or how you feel a session went. It would take a few seconds, and would make the advice above more accurate.")
                }

                Section {
                    Text(sharingEnabled
                         ? "Your answers will be sent with the anonymous data you already share."
                         : "Sharing anonymous data is off, so your answers stay on this device unless you turn it on in settings.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("A few questions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") {
                        SurveyScheduler.shared.markDeclined()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        answers.answeredAt = Date()
                        DeveloperDataSync.recordSurvey(answers, consent: sharingEnabled)
                        SurveyScheduler.shared.markAnswered()
                        dismiss()
                    }
                }
            }
        }
    }

    private func helpfulnessRow(_ title: String,
                                value: Binding<SurveyAnswers.Helpfulness>) -> some View {
        Picker(title, selection: value) {
            ForEach([SurveyAnswers.Helpfulness.not, .aBit, .very]) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    private func interestRow(_ title: String,
                             value: Binding<SurveyAnswers.Interest>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
            Picker(title, selection: value) {
                ForEach([SurveyAnswers.Interest.no, .maybe, .yes]) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }
}
