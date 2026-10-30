import SwiftUI

// The phone's stamp. The facts it shows are in Shared/BuildStamp.swift.

/// The stamp as it appears at the foot of a screen: quiet, and never in the way
/// of anything. It is a diagnostic, not a feature.
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
        Text(BuildStamp.summary)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }
}
