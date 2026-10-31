// Import and export: writing the whole store out as JSON or TSV, and reading
// one back in — either over the top of what is there, or merged into it.

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

    @State private var exportURL: URL?

    @State private var showImportPicker = false
    @State private var pendingImportURL: URL?
    @State private var showImportActions = false

    // New states for alerts and undo backup
    @State private var showResultAlert: Bool = false
    @State private var resultTitle: String = ""
    @State private var resultMessage: String = ""
    @State private var lastBackupURL: URL? = nil

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
                    if let backupURL = lastBackupURL {
                        replaceData(with: backupURL)
                        lastBackupURL = nil
                    }
                } label: {
                    Text("undo\nimport")
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(lastBackupURL == nil)
            }
            .padding(.horizontal)

            List {
                Section {
                    Text("**export TSV** writes a tab-separated table of every logged set, for a spreadsheet.")
                    Text("**export JSON** writes everything — workouts, exercises and logs — in the app's own format, which is what **import JSON** reads back.")
                    Text("Importing offers to validate the file, count what is in it, replace everything, or merge it with what you have. **undo import** restores the automatic backup taken just before the last replace or merge.")
                } header: {
                    Text("What these do")
                }
                .font(.footnote)
            }
        }
        .sheet(item: $exportURL, onDismiss: { cleanupExport() }) { url in
            ShareSheet(activityItems: [url])
        }
        .fileImporter(isPresented: $showImportPicker, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                pendingImportURL = url
                showImportActions = true
            case .failure(let error):
                resultTitle = "File Error"
                resultMessage = "Failed to pick file: \(error.localizedDescription)"
                showResultAlert = true
            }
        }
        .confirmationDialog("Import JSON", isPresented: $showImportActions, titleVisibility: .visible) {
            Button("Validate") {
                if let url = pendingImportURL {
                    validateImport(at: url)
                }
            }
            Button("Check Counts") {
                if let url = pendingImportURL {
                    checkCounts(at: url)
                }
            }
            Button("Replace Data", role: .destructive) {
                if let url = pendingImportURL {
                    // Backup before replace
                    if let backup = backupCurrentData() {
                        lastBackupURL = backup
                    }
                    replaceData(with: url)
                }
            }
            Button("Merge Data") {
                if let url = pendingImportURL {
                    // Backup before merge
                    if let backup = backupCurrentData() {
                        lastBackupURL = backup
                    }
                    mergeData(with: url)
                }
            }
            Button("Cancel", role: .cancel) {}
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
            logWeights: logWeights,
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

    private func backupCurrentData() -> URL? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        do {
            let jsonData = try encoder.encode(buildExportEnvelope())
            let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("workout-backup.json")
            try jsonData.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            resultTitle = "Backup Failed"
            resultMessage = "Failed to backup current data: \(error.localizedDescription)"
            showResultAlert = true
            return nil
        }
    }

    /// Returns an envelope in the *current* (logJSON.2) flat shape regardless
    /// of whether the source file is logJSON.1 or logJSON.2. Old single-row,
    /// multi-entry logs get expanded into one flat WorkoutLog per entry.
    /// One reader for both apps — see `LogTransfer.load`, which is where the
    /// older formats and what they turn into are described.
    private func loadEnvelope(from url: URL) throws -> ExportEnvelope {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        return try LogTransfer.load(try Data(contentsOf: url))
    }

    private func validateImport(at url: URL) {
        do {
            let envelope = try loadEnvelope(from: url)
            guard envelope.exportVersion.starts(with: "logJSON.") else {
                resultTitle = "Validation Failed"
                resultMessage = "Invalid export version: \(envelope.exportVersion)"
                showResultAlert = true
                return
            }
            // Check required fields presence (non-empty strings)
            guard !envelope.appIdentifier.isEmpty, !envelope.appVersion.isEmpty, !envelope.build.isEmpty else {
                resultTitle = "Validation Failed"
                resultMessage = "Missing app metadata in export"
                showResultAlert = true
                return
            }
            // Check counts consistent with data arrays
            guard envelope.counts.workouts == envelope.data.workouts.count,
                  envelope.counts.exercises == envelope.data.exercises.count,
                  envelope.counts.logs == envelope.data.logs.count else {
                resultTitle = "Validation Failed"
                resultMessage = "Counts mismatch with data arrays"
                showResultAlert = true
                return
            }
            // Check logs are reverse chronological order (each date >= next)
            let logs = envelope.data.logs
            for i in 0..<(logs.count - 1) {
                let current = logs[i].date
                let next = logs[i+1].date
                if current < next {
                    resultTitle = "Validation Failed"
                    resultMessage = "Logs are not in reverse chronological order"
                    showResultAlert = true
                    return
                }
            }
            resultTitle = "Validation Successful"
            resultMessage = "The import file is valid and ready to use."
            showResultAlert = true
        } catch {
            resultTitle = "Validation Failed"
            resultMessage = "Failed to validate import: \(error.localizedDescription)"
            showResultAlert = true
        }
    }

    private func checkCounts(at url: URL) {
        do {
            let envelope = try loadEnvelope(from: url)
            let importedCounts = envelope.counts
            let currentCounts = ExportEnvelope.Counts(
                workouts: workouts.count,
                exercises: exercises.count,
                logs: logs.count
            )
            let importedLogs = envelope.data.logs
            let oldestDate = importedLogs.min(by: { $0.date < $1.date })?.date
            let newestDate = importedLogs.max(by: { $0.date < $1.date })?.date
            
            let workoutDiff = importedCounts.workouts - currentCounts.workouts
            let exerciseDiff = importedCounts.exercises - currentCounts.exercises
            let logDiff = importedCounts.logs - currentCounts.logs
            
            var message = """
            Imported counts:
            - Workouts: \(importedCounts.workouts) (\(workoutDiff >= 0 ? "+" : "")\(workoutDiff) compared to current)
            - Exercises: \(importedCounts.exercises) (\(exerciseDiff >= 0 ? "+" : "")\(exerciseDiff))
            - Logs: \(importedCounts.logs) (\(logDiff >= 0 ? "+" : "")\(logDiff))
            """
            message += "\nImported logs span from \(oldestDate?.description(with: .current) ?? "N/A") to \(newestDate?.description(with: .current) ?? "N/A")"
            
            resultTitle = "Counts Summary"
            resultMessage = message
            showResultAlert = true
        } catch {
            resultTitle = "Counts Check Failed"
            resultMessage = "Failed to check counts: \(error.localizedDescription)"
            showResultAlert = true
        }
    }

    private func replaceData(with url: URL) {
        do {
            let envelope = try loadEnvelope(from: url)
            guard envelope.exportVersion.starts(with: "logJSON.") else {
                resultTitle = "Import Failed"
                resultMessage = "Invalid export version: \(envelope.exportVersion)"
                showResultAlert = true
                return
            }
            // Clear existing data
            let fetchLogs: FetchDescriptor<WorkoutLog> = FetchDescriptor()
            if let existingLogs = try? context.fetch(fetchLogs) {
                for log in existingLogs {
                    context.delete(log)
                }
            }
            let fetchWorkouts: FetchDescriptor<WorkoutDef> = FetchDescriptor()
            if let existingWorkouts = try? context.fetch(fetchWorkouts) {
                for workout in existingWorkouts {
                    context.delete(workout)
                }
            }
            let fetchExercises: FetchDescriptor<ExerciseDef> = FetchDescriptor()
            if let existingExercises = try? context.fetch(fetchExercises) {
                for exercise in existingExercises {
                    context.delete(exercise)
                }
            }
            // The results hang off logs that are about to go, so they go too.
            // Left behind they would be orphans, and would then attach
            // themselves to an imported log that happened to reuse the id.
            if let existing = try? context.fetch(FetchDescriptor<AerobicResult>()) {
                for result in existing { context.delete(result) }
            }
            if let existing = try? context.fetch(FetchDescriptor<AssistedResult>()) {
                for result in existing { context.delete(result) }
            }
            if let existing = try? context.fetch(FetchDescriptor<LogWeights>()) {
                for record in existing { context.delete(record) }
            }
            // Insert imported data
            for exercise in envelope.data.exercises {
                context.insert(exercise)
            }
            for workout in envelope.data.workouts {
                context.insert(workout)
            }
            for log in envelope.data.logs {
                context.insert(log)
            }
            for result in envelope.data.aerobicResults ?? [] {
                context.insert(result)
            }
            for result in envelope.data.assistedResults ?? [] {
                context.insert(result)
            }
            for record in envelope.data.logWeights ?? [] {
                context.insert(record)
            }
            try context.save()
            // Notify store or reload
            NotificationCenter.default.post(name: .modelDataDidChange, object: nil)
            resultTitle = "Import Successful"
            resultMessage = "Data replaced successfully."
            showResultAlert = true
        } catch {
            resultTitle = "Import Failed"
            resultMessage = "Failed to replace data: \(error.localizedDescription)"
            showResultAlert = true
        }
    }

    private func mergeData(with url: URL) {
        struct LogSig: Hashable {
            let date: Date
            let workoutId: UUID
            let exerciseId: UUID
        }
        do {
            let envelope = try loadEnvelope(from: url)
            guard envelope.exportVersion.starts(with: "logJSON.") else {
                resultTitle = "Merge Failed"
                resultMessage = "Invalid export version: \(envelope.exportVersion)"
                showResultAlert = true
                return
            }
            var insertedExercises = 0
            var insertedWorkouts = 0
            var updatedExerciseNames = 0
            var updatedWorkoutNames = 0

            // Insert new exercises only; update names for existing
            for importedEx in envelope.data.exercises {
                if let existingEx = exercises.first(where: { $0.id == importedEx.id }) {
                    if existingEx.name != importedEx.name {
                        existingEx.name = importedEx.name
                        updatedExerciseNames += 1
                    }
                } else {
                    context.insert(importedEx)
                    insertedExercises += 1
                }
            }
            // Insert new workouts only; update names for existing
            for importedWorkout in envelope.data.workouts {
                if let existingWorkout = workouts.first(where: { $0.id == importedWorkout.id }) {
                    if existingWorkout.name != importedWorkout.name {
                        existingWorkout.name = importedWorkout.name
                        updatedWorkoutNames += 1
                    }
                } else {
                    context.insert(importedWorkout)
                    insertedWorkouts += 1
                }
            }
            // Logs: dedupe by (date, workoutId, exerciseId). Same signature with
            // differing weights/reps is treated as a conflict; existing wins.
            let existingByKey: [LogSig: WorkoutLog] = Dictionary(
                uniqueKeysWithValues: logs.map {
                    (LogSig(date: $0.date, workoutId: $0.workoutId, exerciseId: $0.exerciseId), $0)
                }
            )

            var insertedLogs = 0
            var conflictCount = 0
            var importedLogIds: Set<UUID> = []

            for importedLog in envelope.data.logs {
                let key = LogSig(date: importedLog.date,
                                 workoutId: importedLog.workoutId,
                                 exerciseId: importedLog.exerciseId)
                if let existing = existingByKey[key] {
                    if existing.weights != importedLog.weights || existing.reps != importedLog.reps {
                        conflictCount += 1
                        // TODO: present UI to resolve; for now keep existing
                    }
                } else {
                    context.insert(importedLog)
                    insertedLogs += 1
                    importedLogIds.insert(importedLog.id)
                }
            }

            // A result belongs to one log. Where the log was skipped as a
            // duplicate, its result is skipped too: the log that won is the
            // one already here, with whatever results it already had.
            let existingAerobicIds = Set(aerobicResults.map(\.id))
            for result in envelope.data.aerobicResults ?? []
            where importedLogIds.contains(result.logId) && !existingAerobicIds.contains(result.id) {
                context.insert(result)
            }
            let existingAssistedIds = Set(assistedResults.map(\.id))
            for result in envelope.data.assistedResults ?? []
            where importedLogIds.contains(result.logId) && !existingAssistedIds.contains(result.id) {
                context.insert(result)
            }
            let existingWeightIds = Set(logWeights.map(\.id))
            for record in envelope.data.logWeights ?? []
            where importedLogIds.contains(record.logId) && !existingWeightIds.contains(record.id) {
                context.insert(record)
            }
            try context.save()
            NotificationCenter.default.post(name: .modelDataDidChange, object: nil)
            var message = "Data merged successfully.\n"
            message += "Inserted Exercises: \(insertedExercises)\n"
            message += "Inserted Workouts: \(insertedWorkouts)\n"
            message += "Inserted Logs: \(insertedLogs)\n"
            message += "Updated Exercise Names: \(updatedExerciseNames)\n"
            message += "Updated Workout Names: \(updatedWorkoutNames)\n"
            if conflictCount > 0 {
                message += "Conflicts detected in \(conflictCount) log rows; existing kept."
            }
            resultTitle = "Merge Complete"
            resultMessage = message
            showResultAlert = true
        } catch {
            resultTitle = "Merge Failed"
            resultMessage = "Failed to merge data: \(error.localizedDescription)"
            showResultAlert = true
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
