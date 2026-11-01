import SwiftUI

// MARK: - Looking at a file before letting it in
//
// Importing is the only screen in this app that can destroy every log at once,
// and this sheet is what stands in front of it.
//
// It replaces a confirmation dialog with five buttons — Validate, Check
// Counts, Replace Data, Merge Data, Cancel. Looking at the file first was
// opt-in, twice: each of the first two put up an alert that had to be
// dismissed before the dialog could be reopened, so the shortest path to
// "Replace Data" was the one that inspected nothing. One of those alerts
// printed its dates with `Date.description(with:)`, a debugging format.
//
// Now the file is read when it is picked and described here, and merge and
// replace are offered underneath that description rather than instead of it.
// The Mac has worked this way from the start — see `MacImportExportView` —
// and the rules underneath are `LogTransfer`'s, shared by both.

/// A file that has been read, and what reading it found. `problem` is nil when
/// the file is good; when it is not, everything else is still shown — being
/// told *what the file claims* is how somebody works out which file they
/// picked — and only the two buttons that would write are taken away.
struct ReviewedFile: Identifiable {
    let id = UUID()
    let name: String
    let envelope: ExportEnvelope
    let preview: LogTransfer.Preview
    let problem: String?
}

struct ImportReviewSheet: View {
    let file: ReviewedFile
    /// What is in the app now, to compare against.
    let here: ExportEnvelope.Counts
    let onMerge: () -> Void
    let onReplace: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var confirmingReplace = false

    private var preview: LogTransfer.Preview { file.preview }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let problem = file.problem {
                        Label(problem, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                    if let written = preview.written {
                        Text("Written \(written.formatted(date: .abbreviated, time: .shortened)) by \(writer).")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Written by \(writer).")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(file.name)
                }

                Section {
                    count("Workouts", preview.workouts, here.workouts)
                    count("Exercises", preview.exercises, here.exercises)
                    count("Logged exercises", preview.logs, here.logs)
                } header: {
                    Text("What it holds")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        if let oldest = preview.oldest, let newest = preview.newest {
                            Text("Covering \(oldest.formatted(date: .abbreviated, time: .omitted)) to \(newest.formatted(date: .abbreviated, time: .omitted)).")
                        } else if preview.logs == 0 {
                            Text("No logged exercises — this file holds workouts and exercises only.")
                        }
                        if !preview.hasWeightsInGrams && preview.logs > 0 {
                            Text("It was written before weights had a unit, so its numbers carry none. They come in as they are and the app asks once what they meant.")
                        }
                    }
                }

                Section {
                    Button("Merge into what I have") {
                        onMerge()
                        dismiss()
                    }
                    Button("Replace everything…", role: .destructive) {
                        confirmingReplace = true
                    }
                } footer: {
                    Text("**Merge** adds what is missing and never overwrites a set you already have. **Replace** throws everything away first. Either way a copy of what you have now is kept, so it can be undone.")
                        .font(.footnote)
                }
                .disabled(file.problem != nil)
            }
            .navigationTitle("Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .confirmationDialog("Replace everything in this app?",
                                isPresented: $confirmingReplace, titleVisibility: .visible) {
                Button("Replace everything", role: .destructive) {
                    onReplace()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your \(LogTransfer.counted(here.logs, "logged exercise")), \(LogTransfer.counted(here.workouts, "workout")) and \(LogTransfer.counted(here.exercises, "exercise")) are deleted and the file's take their place. A copy of what you have now is kept, so this can be undone.")
            }
        }
    }

    /// Which app wrote it, as a person would say it. The device is in here
    /// because a file from the Watch-less Mac and one from a phone look the
    /// same otherwise, and knowing which is which is usually the question.
    private var writer: String {
        let version = file.envelope.appVersion
        let build = file.envelope.build
        let model = file.envelope.device.model
        var text = "SetsRepsWheels"
        if !version.isEmpty { text += " \(version)" }
        if !build.isEmpty { text += " (\(build))" }
        if !model.isEmpty { text += " on \(model)" }
        return text
    }

    private func count(_ label: String, _ inFile: Int, _ inApp: Int) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(inFile)")
                .monospacedDigit()
            Text(inFile == inApp ? "same as here"
                 : (inApp == 0 ? "you have none" : "you have \(inApp)"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
