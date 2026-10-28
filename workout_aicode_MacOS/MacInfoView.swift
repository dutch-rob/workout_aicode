import SwiftUI
import Combine

/// Where the app is, for the Help menu and for anything else that needs to
/// put a particular screen in front of someone.
@MainActor
final class MacNavigation: ObservableObject {
    static let shared = MacNavigation()
    @Published var section: MacSection? = .workouts
    /// Which part of the guide to open on, when Help asks for it.
    @Published var helpTopic: MacInfoTopic? = nil

    private init() {
        #if DEBUG
        // Screenshot runs say which screen to open, the same way the iPhone's
        // do — see tools/make-mac-screenshots.sh.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "-SRWScreen"), i + 1 < args.count,
           let asked = MacSection(rawValue: args[i + 1]) {
            section = asked
            if asked == .info, let t = args.firstIndex(of: "-SRWTopic"), t + 1 < args.count {
                helpTopic = MacInfoTopic(rawValue: args[t + 1])
            }
        }
        #endif
    }

    func showHelp(_ topic: MacInfoTopic = .theMacApp) {
        helpTopic = topic
        section = .info
    }
}

enum MacInfoTopic: String, CaseIterable, Identifiable, Hashable {
    case theMacApp, workouts, exercises, logs, graphsAndProgress
    case importExport, settings, privacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .theMacApp:         return "The Mac app"
        case .workouts:          return "Workouts"
        case .exercises:         return "Exercises"
        case .logs:              return "Logs"
        case .graphsAndProgress: return "Graphs and progress"
        case .importExport:      return "Import and export"
        case .settings:          return "Settings"
        case .privacy:           return "Your data and privacy"
        }
    }

    var icon: String {
        switch self {
        case .theMacApp:         return "macbook"
        case .workouts:          return "list.bullet.rectangle"
        case .exercises:         return "dumbbell"
        case .logs:              return "calendar"
        case .graphsAndProgress: return "chart.xyaxis.line"
        case .importExport:      return "arrow.up.arrow.down.circle"
        case .settings:          return "gearshape"
        case .privacy:           return "lock"
        }
    }

    /// Paragraphs. Plain strings rather than one long blob, so the layout can
    /// space them and nothing has to be re-flowed by hand.
    var paragraphs: [String] {
        switch self {
        case .theMacApp:
            return [
                "This is the desk half of the app. Define your workouts and exercises here with a keyboard, and read back what you have done; the logging itself happens on your iPhone and Apple Watch, which are the things you take to a gym.",
                "Everything you see here is the same data as on your phone. It travels through your own iCloud account, so what you define here appears there, and what you log there appears here — usually within seconds of both being awake.",
                "Unlike the iPhone app, which keeps to itself until you say otherwise, this one shares by default. A Mac that kept its workouts to itself could never get them to the device you actually train with."
            ]
        case .workouts:
            return [
                "A workout is a named list of exercises in the order you do them — “PF A”, “Upper body”, whatever you call it. Your phone shows these on its start screen, and tapping one begins logging.",
                "Choose a workout on the left to edit it. Drag to reorder; the order here is the order the wheels come up in at the gym.",
                "The panel on the right adds exercises. It offers the ones you have already defined, and a ready-made catalogue for anything you have not — building a workout is exactly when you notice a lift you have not set up yet. Open “Find by muscle” to pick from the body instead of from a list, which is easier when you know the muscle but not the name you gave it."
            ]
        case .exercises:
            return [
                "An exercise carries its own numbers: how many sets you normally do, the lowest and highest weight on its wheel, and the step between them. Match the step to the machine — often 5, or 2.5 for dumbbells. Halves and quarters are allowed.",
                "The body picture is a filter: click a muscle to see what works it, or the heart for cardio. Click an exercise to open it.",
                "“Subtracted from body weight” is for machines that take weight off you, such as an assisted chin-up. The wheel then means what is set ON the machine, and the app records what you actually lifted: your body weight less that."
            ]
        case .logs:
            return [
                "Every set you have logged, newest first. The field at the top narrows the list to what you type — part of an exercise name, or a workout name — and matches by word, so “chin” finds the chin-up and not the bench press.",
                "Tick “Dates” to narrow to a period. Both ends are included.",
                "Read it either way round. “By workout” groups each session together, which answers what you did on a day. “By exercise” gathers every time you did one lift, newest first, which answers what you did last time and whether to add weight. Either way the +/− in the left margin folds a group away, and the column headings sort — click the one already in use to turn it round.",
                "“Edit logs” corrects a row, adds one, or deletes one. It takes a copy of everything first, so it can all be put back."
            ]
        case .graphsAndProgress:
            return [
                "Graphs show one chart per exercise: what you lifted, and a trend line through it. The trend needs a few sessions before it says anything.",
                "Progress ranks your exercises by how they are moving, so what has stalled is visible without reading every chart.",
                "Both work from an estimated one-rep max, so a set of 8 and a set of 12 can be compared. Which formula is used is a setting."
            ]
        case .importExport:
            return [
                "Export JSON writes everything — workouts, exercises, every logged set and the weights beside them. It is the app's own format and is what Import reads back. Keep one somewhere safe: it is the only copy of your logs that does not depend on iCloud.",
                "Export spreadsheet writes one row per set, with the weight in the unit you read and a column saying which, for a spreadsheet or anything else that eats tab-separated text.",
                "Import reads a file and describes it first — what it holds, when it was written, how it compares with what is here. Nothing changes until you choose. Merge adds what is missing and never overwrites a set you already have; where the two disagree about the same set, yours is kept and you are told how often. Replace throws everything away first. Either way a copy of what you had is kept, and “Undo the last import” puts it back."
            ]
        case .settings:
            return [
                "Settings are in the sidebar and in the app menu (⌘,).",
                "Text size applies to this app only. macOS has no system-wide setting for it the way an iPhone does, and screens differ enough that the same size is small on one and large on another.",
                "The weight unit decides how weights are read out. Nothing is recalculated when you switch: weights are stored in a form that has no unit, so switching re-presents everything you have ever logged in the other one.",
                "The numbers a new exercise starts with are kept per device, so what you set here applies to exercises made here."
            ]
        case .privacy:
            return [
                "Your workouts, exercises and logs live in your own iCloud account. There is no other account, no server of ours, and nothing to sign up for.",
                "This app reads nothing else on your Mac. Import and export touch exactly the file you pick in the panel and nothing around it.",
                "Sharing anonymous data with the developer is off unless you turn it on, and it is a setting on the iPhone. Turning it off deletes what was shared."
            ]
        }
    }
}

struct MacInfoView: View {
    @ObservedObject private var navigation = MacNavigation.shared
    @State private var topic: MacInfoTopic = .theMacApp

    var body: some View {
        // Contents on the left, the topic on the right — the shape macOS uses
        // for anything with sections to move between, and the one the rest of
        // this window already has. A page of anchors to scroll between is the
        // web's answer to this, not the Mac's.
        HStack(spacing: 0) {
            List(MacInfoTopic.allCases, selection: Binding(
                get: { topic }, set: { topic = $0 ?? .theMacApp })) { item in
                Label(item.title, systemImage: item.icon).tag(item)
            }
            .listStyle(.sidebar)
            // Wide enough for "Your data and privacy", which was clipped.
            .frame(width: 250)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(topic.title).macFont(.title2).bold()
                    ForEach(Array(topic.paragraphs.enumerated()), id: \.offset) { _, text in
                        Text(.init(text))
                    }
                    if topic == .theMacApp {
                        Divider()
                        Text("The full guide, including the Apple Watch and the rest timer, is on the iPhone under info.")
                            .macFont(.footnote).foregroundStyle(.secondary)
                        BuildStampView()
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: 620, alignment: .leading)
                .padding(28)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Info")
        .onAppear { if let asked = navigation.helpTopic { topic = asked; navigation.helpTopic = nil } }
        .onChange(of: navigation.helpTopic) { _, asked in
            if let asked { topic = asked; navigation.helpTopic = nil }
        }
    }
}

/// The Mac's own build stamp — same reasoning as the phone's and the Watch's.
struct BuildStampView: View {
    var body: some View {
        Text(summary).macFont(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
    }

    private var summary: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
