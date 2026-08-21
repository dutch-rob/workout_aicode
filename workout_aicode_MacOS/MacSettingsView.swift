import SwiftUI
import SwiftData

struct MacSettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var drafts: [DraftSession]
    @State private var syncOn = MacAppSetup.syncEnabled
    @State private var askingToEnd = false

    private var draft: DraftSession? { drafts.first { $0.isActive } }

    var body: some View {
        Form {
            Section {
                Toggle("Share data through iCloud", isOn: $syncOn)
                    .onChange(of: syncOn) { _, on in
                        MacAppSetup.setSyncEnabled(on)
                    }
            } footer: {
                Text("On by default on the Mac, unlike the iPhone. This app does not log workouts — the iPhone and Watch do — so a Mac keeping its data to itself could never get what you define here to the device you train with.\n\nChanging this takes effect when you next open the app. Your iPhone has its own switch, and both must be on for the two to see each other.")
            }

            Section {
                Toggle("Draft", isOn: Binding(
                    get: { draft != nil },
                    set: { on in
                        if on {
                            DraftMode.start(in: context)
                        } else if draft?.isEmpty == false {
                            askingToEnd = true          // ask before anything goes
                        } else {
                            DraftMode.keepAll(in: context)
                        }
                    }))
            } footer: {
                Text("While draft is on, anything you make is marked, and the toolbar says so. Turning it off asks whether to keep what you made or throw it away — it never decides for you. Changes to things that already existed are yours to keep either way.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .confirmationDialog("Finish draft?", isPresented: $askingToEnd, titleVisibility: .visible) {
            if let draft {
                Button("Keep \(draft.summary)") { DraftMode.keepAll(in: context) }
                Button("Discard \(draft.summary)", role: .destructive) {
                    DraftMode.discardAll(in: context)
                }
            }
            Button("Stay in draft", role: .cancel) { }
        } message: {
            Text(draft.map { "You made \($0.summary) while drafting." } ?? "")
        }
    }
}
