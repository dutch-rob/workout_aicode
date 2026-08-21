import SwiftUI

// MARK: - What the sidebar offers
//
// Grouped rather than a flat list of eight. Defining things and looking at what
// happened are different errands, and the two housekeeping screens belong with
// neither — a flat list would put "Import/export" next to "Workouts" and make
// the reader sort them out every time.

enum MacSection: String, CaseIterable, Identifiable, Hashable {
    case workouts, exercises
    case logs, graphs, progress, importExport
    case settings, info

    var id: String { rawValue }

    var label: String {
        switch self {
        case .workouts:     return "Workouts"
        case .exercises:    return "Exercises"
        case .logs:         return "Logs"
        case .graphs:       return "Graphs"
        case .progress:     return "Progress"
        case .importExport: return "Import / export"
        case .settings:     return "Settings"
        case .info:         return "Info"
        }
    }

    var icon: String {
        switch self {
        case .workouts:     return "list.bullet.rectangle"
        case .exercises:    return "dumbbell"
        case .logs:         return "calendar"
        case .graphs:       return "chart.xyaxis.line"
        case .progress:     return "chart.bar"
        case .importExport: return "arrow.up.arrow.down.circle"
        case .settings:     return "gearshape"
        case .info:         return "info.circle"
        }
    }

    static let defining: [MacSection] = [.workouts, .exercises]
    static let reviewing: [MacSection] = [.logs, .graphs, .progress, .importExport]
    static let app: [MacSection] = [.settings, .info]
}
