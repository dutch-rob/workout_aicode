import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Import and export, on one screen
//
// The phone spreads this across a button row, a confirmation dialog and a
// string of alerts, because a phone has no room to show a file and a question
// at the same time. A Mac does. So a chosen file is READ first and described
// — what it holds, when it was written, how it compares with what is here —
// and only then are replace and merge offered, next to the description rather
// than after it.
//
// The rules themselves are LogTransfer's, shared with the rest of the app.

struct MacImportExportView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\WorkoutLog.date, order: .reverse)]) private var logs: [WorkoutLog]
    @Query private var workouts: [WorkoutDef]
    @Query private var exercises: [ExerciseDef]
    @Query private var aerobicResults: [AerobicResult]
    @Query private var assistedResults: [AssistedResult]
    @Query private var logWeights: [LogWeights]

    @State private var chosen: ChosenFile?
    @State private var problem: String?
    @State private var outcome: String?
    @State private var undo: Data?
    @State private var importing = false
    @State private var confirmingReplace = false

    private struct ChosenFile {
        let name: String
        let envelope: ExportEnvelope
        let preview: LogTransfer.Preview
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                exportSection
                Divider()
                importSection
                if let outcome {
                    Label(outcome, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                if let problem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
            .padding(20)
            .frame(maxWidth: 680, alignment: .leading)
        }
        .navigationTitle("Import / export")
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.json],
                      allowsMultipleSelection: false) { result in
            read(result)
        }
        .confirmationDialog("Replace everything in this app?",
                            isPresented: $confirmingReplace, titleVisibility: .visible) {
            Button("Replace everything", role: .destructive) { apply(replacing: true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your \(logs.count) logged exercises, \(workouts.count) workouts and \(exercises.count) exercises are deleted and the file's take their place. A copy of what you have now is kept so this can be undone.")
        }
    }

    // MARK: Out

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Export").font(.headline)
            HStack(spacing: 10) {
                Button("Export JSON…") { exportJSON() }
                    .disabled(logs.isEmpty && workouts.isEmpty && exercises.isEmpty)
                Button("Export spreadsheet (TSV)…") { exportTSV() }
                    .disabled(logs.isEmpty)
            }
            Text("JSON holds everything — workouts, exercises, every logged set and the weights beside them — and is what **Import** reads back. The spreadsheet is one row per set, with the weight written in \(WeightUnit.current.label) and a column saying so.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private func envelope() -> ExportEnvelope {
        let bundle = Bundle.main
        return ExportEnvelope(
            exportVersion: LogTransfer.currentVersion,
            appIdentifier: bundle.bundleIdentifier ?? "",
            appVersion: bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
            build: bundle.infoDictionary?["CFBundleVersion"] as? String ?? "",
            exportedAt: ISO8601DateFormatter().string(from: Date()),
            device: ExportEnvelope.DeviceInfo(model: "Mac", system: "macOS",
                                              version: ProcessInfo.processInfo
                                                  .operatingSystemVersionString),
            locale: Locale.current.identifier,
            timeZone: TimeZone.current.identifier,
            counts: ExportEnvelope.Counts(workouts: workouts.count,
                                          exercises: exercises.count,
                                          logs: logs.count),
            data: ExportEnvelope.AllData(workouts: workouts, exercises: exercises,
                                         logs: logs,
                                         aerobicResults: aerobicResults,
                                         assistedResults: assistedResults,
                                         logWeights: logWeights))
    }

    private func encodedData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        return try encoder.encode(envelope())
    }

    private func exportJSON() {
        save(suggested: "workout-logs.json", type: .json) { try encodedData() }
    }

    private func exportTSV() {
        let text = LogTransfer.tsv(logs: logs, workouts: workouts, exercises: exercises,
                                   weightsByLog: LogWeightsIndex.byLogId(logWeights),
                                   unit: .current)
        save(suggested: "workout-logs.tsv", type: .tabSeparatedText) {
            Data(text.utf8)
        }
    }

    /// A save panel, which is also what grants a sandboxed app the right to
    /// write the file: the user picking it IS the permission.
    private func save(suggested: String, type: UTType, body: () throws -> Data) {
        problem = nil
        outcome = nil
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggested
        panel.allowedContentTypes = [type]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try body().write(to: url, options: .atomic)
            outcome = "Written to \(url.lastPathComponent)."
        } catch {
            problem = "Could not write the file. \(error.localizedDescription)"
        }
    }

    // MARK: In

    private var importSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Import").font(.headline)
            HStack(spacing: 10) {
                Button("Choose a file…") { importing = true }
                if undo != nil {
                    Button("Undo the last import") { undoLast() }
                }
            }

            if let chosen {
                fileCard(chosen)
            } else {
                Text("Pick a JSON file exported by this app, on any of your devices. Nothing changes until you say so: the file is read and described first.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func fileCard(_ file: ChosenFile) -> some View {
        let p = file.preview
        return VStack(alignment: .leading, spacing: 8) {
            Text(file.name).font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 3) {
                line("Workouts", "\(p.workouts)", p.workouts - workouts.count)
                line("Exercises", "\(p.exercises)", p.exercises - exercises.count)
                line("Logged exercises", "\(p.logs)", p.logs - logs.count)
            }
            .font(.callout)

            if let oldest = p.oldest, let newest = p.newest {
                Text("Covering \(oldest.formatted(date: .abbreviated, time: .omitted)) to \(newest.formatted(date: .abbreviated, time: .omitted)).")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if !p.hasWeightsInGrams {
                Label("This file was written before weights had a unit, so its numbers carry none. They are imported as they are and the app asks once what they meant.",
                      systemImage: "info.circle")
                    .font(.callout).foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button("Merge into what I have") { apply(replacing: false) }
                Button("Replace everything…", role: .destructive) { confirmingReplace = true }
                Spacer()
                Button("Forget this file") { chosen = nil }
                    .buttonStyle(.link)
            }
            .padding(.top, 2)

            Text("**Merge** adds what is missing and never overwrites a set you already have. **Replace** throws everything away first. Either way a copy of what you have now is kept, so it can be undone.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }

    private func line(_ label: String, _ value: String, _ difference: Int) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value)
            Text(difference == 0 ? "same as here"
                 : (difference > 0 ? "+\(difference)" : "\(difference)"))
                .foregroundStyle(.secondary)
        }
    }

    private func read(_ result: Result<[URL], Error>) {
        problem = nil
        outcome = nil
        chosen = nil
        do {
            guard let url = try result.get().first else { return }
            // A file the user picked is reachable inside the sandbox only
            // while it is being accessed.
            let opened = url.startAccessingSecurityScopedResource()
            defer { if opened { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            let envelope = try LogTransfer.load(data)
            try LogTransfer.validate(envelope)
            chosen = ChosenFile(name: url.lastPathComponent, envelope: envelope,
                                preview: LogTransfer.preview(envelope))
        } catch {
            problem = error.localizedDescription
        }
    }

    private func apply(replacing: Bool) {
        guard let file = chosen else { return }
        problem = nil
        // The copy comes first, and nothing is touched if it cannot be made:
        // the logs are the one thing in this app nobody can reconstruct.
        guard let backup = try? encodedData() else {
            problem = "Your current data could not be copied, so there would be no way back. Nothing was changed."
            return
        }
        do {
            if replacing {
                try LogTransfer.replace(with: file.envelope, in: context)
                outcome = "Replaced with \(file.name)."
            } else {
                let summary = try LogTransfer.merge(file.envelope, into: context)
                outcome = describe(summary)
            }
            undo = backup
            chosen = nil
            WeightHistory.catchUp(in: context)
        } catch {
            problem = error.localizedDescription
        }
    }

    private func describe(_ s: LogTransfer.MergeSummary) -> String {
        var parts: [String] = []
        if s.insertedLogs > 0 { parts.append("\(s.insertedLogs) logged exercises") }
        if s.insertedWorkouts > 0 { parts.append("\(s.insertedWorkouts) workouts") }
        if s.insertedExercises > 0 { parts.append("\(s.insertedExercises) exercises") }
        var text = parts.isEmpty ? "Nothing new — everything in that file was already here."
                                 : "Added " + parts.joined(separator: ", ") + "."
        let renamed = s.renamedWorkouts + s.renamedExercises
        if renamed > 0 { text += " Renamed \(renamed)." }
        if s.conflicts > 0 {
            text += " \(s.conflicts) rows differed from what you already had; yours were kept."
        }
        return text
    }

    private func undoLast() {
        guard let backup = undo else { return }
        problem = nil
        do {
            let envelope = try LogTransfer.load(backup)
            try LogTransfer.replace(with: envelope, in: context)
            undo = nil
            outcome = "Put back the way it was before the last import."
        } catch {
            problem = "Could not undo. \(error.localizedDescription)"
        }
    }
}
