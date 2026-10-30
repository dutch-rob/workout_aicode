import SwiftUI

// The Watch's stamp. The facts it shows are in Shared/BuildStamp.swift.

/// The stamp as it appears at the foot of a screen: quiet, and never in the way
/// of anything. It is a diagnostic, not a feature.
///
/// Deliberately not the phone's copy of this view — caption2 and centred, and
/// the date on its own line, because the full string does not fit across a
/// watch face at footnote size.
struct BuildStampView: View {
    var body: some View {
        // Hidden during a screenshot run: this is a diagnostic for TestFlight,
        // and a version string in an App Store screenshot is just clutter that
        // goes stale the moment the next build is made.
        #if DEBUG
        if DemoMode.isEnabled { EmptyView() } else { stamp }
        #else
        stamp
        #endif
    }

    @ViewBuilder private var stamp: some View {
        VStack(spacing: 1) {
            Text("\(BuildStamp.version) (\(BuildStamp.build))")
            if let builtAt = BuildStamp.builtAt {
                Text(builtAt, format: .dateTime.day().month().hour().minute())
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
    }
}
