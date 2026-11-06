// Import and export: writing the whole store out as JSON or TSV, and reading
// one back in — either over the top of what is there, or merged into it.
//
// What a file may say, and what replacing and merging mean, are not here:
// they are `LogTransfer`'s, shared with the Mac. This screen used to carry its
// own copies of all four — validate, count, replace, merge — and they had
// drifted from the shared ones, which is how `validateImport` came to crash on
// a file with no logs. What is left here is what a *phone* does with a file:
// which buttons it offers, how it reviews one, and what it says afterwards.

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - import/export tab

struct ImportExportView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.modelContext) private var context

    @Query(sort: [SortDescriptor(\WorkoutLog.date, order: .reverse)]) private var logs: [WorkoutLog]
    @Query private var workouts: [WorkoutDef]
    @Query private var exercises: [ExerciseDef]
    @Query private var aerobicResults: [AerobicResult]
    @Query private var assistedResults: [AssistedResult]
    @Query private var logWeights: [LogWeights]
    @Query private var workoutGroups: [WorkoutGroupDef]

    @State private var exportURL: URL?

    @State private var showImportPicker = false
    /// The file that was picked, already read. Nil until one is.
    @State private var reviewing: ReviewedFile?

    @State private var showResultAlert: Bool = false
    @State private var resultTitle: String = ""
    @State private var resultMessage: String = ""

    /// What the store held just before the last import, to undo it with. In
    /// memory and not on disk: it only has to outlive the import, and a file
    /// in the temporary directory can be swept while the app is away.
    @State private var undo: Data?

    /// What the last import did, and what went wrong with the last one that
    /// did not. Said on the screen it happened on rather than in an alert over
    /// the top of it, which also keeps it out of the way of the sheet closing.
    @State private var outcome: String?
    @State private var problem: String?

    var body: some View {
        VStack {
            HStack(spacing: 8) {
                Button {
                    exportLogs()
                } label: {
                    Text("export\nTSV")
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(logs.isEmpty)

                Button {
                    exportJSON()
                } label: {
                    Text("export\nJSON")
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(logs.isEmpty)

                Button {
                    showImportPicker = true
                } label: {
                    Text("import\nJSON")
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    undoLast()
                } label: {
                    Text("undo\nimport")
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(undo == nil)
            }
            .padding(.horizontal)

            List {
                if let outcome {
                    Section {
                        Label(outcome, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    .font(.footnote)
                }
                if let problem {
                    Section {
                        Label(problem, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                    .font(.footnote)
                }

                Section {
                    Text("**export TSV** writes a tab-separated table of every logged set, for a spreadsheet.")
                    Text("**export JSON** writes everything — workouts, exercises and logs — in the app's own format, which is what **import JSON** reads back.")
                    Text("**import JSON** reads the file and describes it — what it holds, when it was written, how it compares with what you have — before offering to merge or replace. Nothing changes until you choose there. **undo import** puts back the copy taken just before the last one.")
                } header: {
                    Text("What these do")
                }
                .font(.footnote)
            }
            // Away from the export sheet below on purpose: one `.sheet` per
            // view, so the two cannot get in each other's way.
            .sheet(item: $reviewing) { file in
                ImportReviewSheet(
                    file: file,
                    here: ExportEnvelope.Counts(workouts: workouts.count,
                                                exercises: exercises.count,
                                                logs: logs.count),
                    onMerge: { apply(file, replacing: false) },
                    onReplace: { apply(file, replacing: true) })
            }
        }
        .sheet(item: $exportURL, onDismiss: { cleanupExport() }) { url in
            ShareSheet(activityItems: [url])
        }
        .fileImporter(isPresented: $showImportPicker, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            read(result)
        }
        .alert(resultTitle, isPresented: $showResultAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(resultMessage)
        }
    }
    
    private func exportLogs() {
        // Generate TSV content
        let tsv = makeTSV()
        // Write to a temporary file
        let tmpDir = FileManager.default.temporaryDirectory
        let fileURL = tmpDir.appendingPathComponent("workout-logs.tsv")
        do {
            try tsv.data(using: .utf8)?.write(to: fileURL, options: .atomic)
            exportURL = fileURL
        } catch {
            resultTitle = "Export Failed"
            resultMessage = "Failed to write export: \(error.localizedDescription)"
            showResultAlert = true
        }
    }

    private func cleanupExport() {
        if let url = exportURL {
            try? FileManager.default.removeItem(at: url)
        }
        exportURL = nil
    }
    
    /// The same envelope the Mac writes — see `LogTransfer.envelope`. It was
    /// built here once, with its version string as a literal, which is how
    /// the two ends drift.
    private func buildExportEnvelope() -> ExportEnvelope {
        LogTransfer.envelope(
            workouts: workouts, exercises: exercises, logs: logs,
            aerobicResults: aerobicResults, assistedResults: assistedResults,
            logWeights: logWeights, workoutGroups: workoutGroups,
            device: ExportEnvelope.DeviceInfo(model: UIDevice.current.model,
                                              system: UIDevice.current.systemName,
                                              version: UIDevice.current.systemVersion))
    }

    private func exportJSON() {
        do {
            let jsonData = try LogTransfer.encoded(buildExportEnvelope())
            let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("workout-logs.json")
            try jsonData.write(to: fileURL, options: .atomic)
            exportURL = fileURL
        } catch {
            resultTitle = "Export Failed"
            resultMessage = "Failed to export JSON: \(error.localizedDescription)"
            showResultAlert = true
        }
    }

    /// The copy taken before an import, so it can be undone.
    private func backupCurrentData() -> Data? {
        try? LogTransfer.encoded(buildExportEnvelope())
    }

    // MARK: In

    /// Reads a file of any version into the current shape — see
    /// `LogTransfer.load`, which is where the older formats and what they turn
    /// into are described.
    private func loadEnvelope(from url: URL) throws -> ExportEnvelope {
        // A file the user picked is reachable inside the sandbox only while it
        // is being accessed.
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        return try LogTransfer.load(try Data(contentsOf: url))
    }

    /// Reads the picked file and puts the review sheet up.
    ///
    /// A file that cannot be decoded at all gets an alert, because there is
    /// nothing to review. One that decodes but fails `validate` gets the sheet
    /// anyway, with the reason at the top and merge and replace taken away:
    /// seeing what the file claims to hold is how somebody works out which
    /// file they picked by mistake.
    private func read(_ result: Result<[URL], Error>) {
        outcome = nil
        problem = nil
        do {
            guard let url = try result.get().first else { return }
            let envelope = try loadEnvelope(from: url)
            var refusal: String?
            do {
                try LogTransfer.validate(envelope)
            } catch {
                refusal = error.localizedDescription
            }
            reviewing = ReviewedFile(name: url.lastPathComponent,
                                     envelope: envelope,
                                     preview: LogTransfer.preview(envelope),
                                     problem: refusal)
        } catch {
            resultTitle = "Cannot read that file"
            resultMessage = error.localizedDescription
            showResultAlert = true
        }
    }

    private func apply(_ file: ReviewedFile, replacing: Bool) {
        problem = nil
        outcome = nil
        // The copy comes first, and nothing is touched if it cannot be made:
        // the logs are the one thing in this app nobody can reconstruct.
        guard let backup = backupCurrentData() else {
            problem = "Your current data could not be copied, so there would be no way back. Nothing was changed."
            return
        }
        do {
            if replacing {
                try LogTransfer.replace(with: file.envelope, in: context)
                outcome = "Replaced everything with \(file.name)."
            } else {
                outcome = describe(try LogTransfer.merge(file.envelope, into: context))
            }
            undo = backup
            reviewing = nil
            // A pile of history can arrive at once here, and anything in it
            // without a unit needs the answer the user has already given.
            WeightHistory.catchUp(in: context)
            NotificationCenter.default.post(name: .modelDataDidChange, object: nil)
        } catch {
            problem = error.localizedDescription
        }
    }

    private func describe(_ summary: LogTransfer.MergeSummary) -> String {
        var added: [String] = []
        if summary.insertedLogs > 0 {
            added.append(LogTransfer.counted(summary.insertedLogs, "logged exercise"))
        }
        if summary.insertedWorkouts > 0 {
            added.append(LogTransfer.counted(summary.insertedWorkouts, "workout"))
        }
        if summary.insertedExercises > 0 {
            added.append(LogTransfer.counted(summary.insertedExercises, "exercise"))
        }
        var text = added.isEmpty
            ? "Nothing new — everything in that file was already here."
            : "Added " + added.joined(separator: ", ") + "."
        let renamed = summary.renamedWorkouts + summary.renamedExercises
        if renamed > 0 { text += " Renamed \(renamed)." }
        if summary.conflicts > 0 {
            text += summary.conflicts == 1
                ? " 1 row differed from what you already had; yours was kept."
                : " \(summary.conflicts) rows differed from what you already had; yours were kept."
        }
        return text
    }

    private func undoLast() {
        guard let backup = undo else { return }
        problem = nil
        outcome = nil
        do {
            try LogTransfer.replace(with: try LogTransfer.load(backup), in: context)
            undo = nil
            outcome = "Put back the way it was before the last import."
            WeightHistory.catchUp(in: context)
            NotificationCenter.default.post(name: .modelDataDidChange, object: nil)
        } catch {
            problem = "Could not undo. \(error.localizedDescription)"
        }
    }

    /// The same spreadsheet the Mac writes — see `LogTransfer.tsv`.
    ///
    /// This used to be its own, and was still logTSV.1: the raw numbers off
    /// each log with no column saying what unit they were in, which is the
    /// exact problem units were added to solve. It also quoted a name
    /// containing a comma and not one containing a tab, in a file whose
    /// columns are separated by tabs.
    private func makeTSV() -> String {
        LogTransfer.tsv(logs: logs, workouts: workouts, exercises: exercises,
                        weightsByLog: LogWeightsIndex.byLogId(logWeights),
                        unit: .current)
    }

}
