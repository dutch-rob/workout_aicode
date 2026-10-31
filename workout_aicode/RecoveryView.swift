// What is offered after the app closed with a workout still open.

import SwiftUI
import SwiftData

// MARK: - Recovery Screen
//
// Shown when both the normal load AND the V1 schema fallback have failed —
// meaning the on-disk store structure is unrecognisable. By this point
// AppSetup has already wiped the local file so the app can run; this view
// explains what happened, lets the user export whatever is still available
// (the fresh empty store — a valid JSON template), and then continues.

struct RecoveryView: View {
    @EnvironmentObject private var setup: AppSetup
    @EnvironmentObject private var store: AppStore

    @Query private var workouts:  [WorkoutDef]
    @Query private var exercises: [ExerciseDef]
    @Query private var logs:      [WorkoutLog]

    @State private var exportURL: URL?
    @State private var showExportSheet = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.orange)
                    .padding(.top, 32)

                Text("Your data couldn't be loaded")
                    .font(.title2).bold()
                    .multilineTextAlignment(.center)

                Text("""
                     The app found a data file it couldn't read. \
                     This can happen when upgrading from a much earlier version.

                     Your workouts and exercise definitions may have been saved \
                     elsewhere (iCloud, a JSON export). You can export what is \
                     currently available — it may be empty, but it gives you a \
                     valid file to compare against any backup you already have.
                     """)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                // Export button — builds a JSON from the current (fresh) store.
                // Even if empty it provides the correct schema for manual editing.
                Button {
                    buildAndShareExport()
                } label: {
                    Label("Export available data", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .padding(.horizontal)

                NavigationLink(destination: SettingsView()) {
                    Label("Go to Settings", systemImage: "gear")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .padding(.horizontal)

                Divider()

                Button(role: .destructive) {
                    setup.startFresh()
                } label: {
                    Label("Continue with empty app", systemImage: "arrow.forward.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .padding(.horizontal)

                Text("You can import a JSON backup later via the Logs screen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(.bottom, 32)
            }
        }
        .navigationTitle("Data Recovery")
        .sheet(item: $exportURL) { url in
            ShareSheet(activityItems: [url])
                .onDisappear {
                    try? FileManager.default.removeItem(at: url)
                    exportURL = nil
                }
        }
    }

    private func buildAndShareExport() {
        let bundle = Bundle.main
        let envelope = ExportEnvelope(
            exportVersion: "logJSON.2",
            appIdentifier: bundle.bundleIdentifier ?? "",
            appVersion:    bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
            build:         bundle.infoDictionary?["CFBundleVersion"] as? String ?? "",
            exportedAt:    ISO8601DateFormatter().string(from: Date()),
            device: ExportEnvelope.DeviceInfo(
                model:   UIDevice.current.model,
                system:  UIDevice.current.systemName,
                version: UIDevice.current.systemVersion),
            locale:   Locale.current.identifier,
            timeZone: TimeZone.current.identifier,
            counts:   ExportEnvelope.Counts(
                workouts:  workouts.count,
                exercises: exercises.count,
                logs:      logs.count),
            data: ExportEnvelope.AllData(
                workouts:  workouts,
                exercises: exercises,
                logs:      logs)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(envelope) else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("workout-recovery-export.json")
        try? data.write(to: url, options: .atomic)
        exportURL = url
    }
}
