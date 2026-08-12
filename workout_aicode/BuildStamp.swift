import SwiftUI

// MARK: - Which build am I looking at?
//
// A byte-identical copy of this file lives in the Watch App target
// ("workout_aicode Watch App/BuildStamp.swift"). The two targets are separate
// synchronized folders and do not share source — the same arrangement as
// WatchSync.swift. Keep them the same.
//
// This exists because the question "is the thing on my wrist the build I just
// made?" had no answer from inside the app, and a round of testing went into
// chasing a bug that may already have been fixed in a build that was never
// installed. Each target stamps itself, so the Watch's line is the Watch's own
// build and not the phone's.

enum BuildStamp {

    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }

    /// When this binary was written, taken from the executable's own file date.
    ///
    /// Swift has no compile-time date, and baking one in would need a build
    /// phase in the project file. The file date is close enough for the job
    /// this does: it moves whenever a new binary is produced, which is exactly
    /// the question being asked. It is not the moment of compilation for a
    /// build that has been through the App Store — re-signing rewrites it —
    /// so read it as "this binary", not as a timestamp to reason from.
    static var builtAt: Date? {
        guard let url = Bundle.main.executableURL,
              let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        else { return nil }
        return values.contentModificationDate
    }

    /// "1.4 (8) · 12 Aug 2026 at 08:14"
    static var summary: String {
        let head = "\(version) (\(build))"
        guard let builtAt else { return head }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "\(head) · \(formatter.string(from: builtAt))"
    }
}

/// The stamp as it appears at the foot of a screen: quiet, and never in the way
/// of anything. It is a diagnostic, not a feature.
struct BuildStampView: View {
    var body: some View {
        Text(BuildStamp.summary)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }
}
