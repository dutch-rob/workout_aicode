import SwiftUI
import SwiftData

// MARK: - The Mac window
//
// A sidebar and a detail pane. The Mac is for defining workouts and exercises
// with a keyboard and for reading back what happened; logging stays on the
// phone and the Watch, which are the things you take to a gym.

struct ContentView: View {
    @EnvironmentObject private var setup: MacAppSetup
    @State private var section: MacSection? = .workouts

    var body: some View {
        NavigationSplitView {
            List(selection: $section) {
                Section("Define") {
                    ForEach(MacSection.defining) { row($0) }
                }
                Section("Review") {
                    ForEach(MacSection.reviewing) { row($0) }
                }
                Section {
                    ForEach(MacSection.app) { row($0) }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
        } detail: {
            detail
                .frame(minWidth: 520, minHeight: 420)
        }
        .toolbar { DraftToolbar() }
    }

    private func row(_ item: MacSection) -> some View {
        Label(item.label, systemImage: item.icon).tag(item)
    }

    @ViewBuilder private var detail: some View {
        if let failure = setup.failure {
            // A store that would not open must never look like an empty one:
            // "no workouts" and "your workouts could not be read" call for very
            // different reactions from whoever is looking at it.
            ContentUnavailableView("Could not open your workouts",
                                   systemImage: "exclamationmark.triangle",
                                   description: Text(failure))
        } else {
            switch section ?? .workouts {
            case .workouts:     MacWorkoutsView()
            case .exercises:    MacExercisesView()
            case .logs:         MacLogsView()
            case .graphs:       MacGraphsView()
            case .progress:     MacProgressView()
            case .settings:     MacSettingsView()
            case .info:         MacInfoView()
            case .importExport: MacComingSoonView(section: .importExport)
            }
        }
    }
}

/// Screens not written yet. Named rather than blank, so it is clear the app is
/// unfinished here rather than that the data is missing.
///
/// Only import/export is left. It is last on purpose: it is the one screen
/// that WRITES, and replace-and-merge deserves more care than a port of the
/// phone's dialog stack.
struct MacComingSoonView: View {
    let section: MacSection

    var body: some View {
        ContentUnavailableView(section.label,
                               systemImage: section.icon,
                               description: Text("Not built yet on the Mac. It is on your iPhone under logs/stats."))
    }
}
