import SwiftUI
import SwiftData

// MARK: - Draft, in the toolbar
//
// A mode you can forget you are in wants to be visible, so the marker sits in
// the window's toolbar the whole time draft is on rather than only in Settings.
// The switch itself lives in Settings; this is the reminder and the way out.

struct DraftToolbar: ToolbarContent {
    @Environment(\.modelContext) private var context
    @Query private var sessions: [DraftSession]
    @State private var askingToEnd = false

    private var active: DraftSession? { sessions.first { $0.isActive } }

    var body: some ToolbarContent {
        ToolbarItem(placement: .status) {
            if let active {
                Button {
                    askingToEnd = true
                } label: {
                    Label("Draft — \(active.summary)", systemImage: "pencil.and.outline")
                        .foregroundStyle(.orange)
                }
                .help("You are in draft. Click to finish and decide what to keep.")
                .confirmationDialog("Finish draft?",
                                    isPresented: $askingToEnd, titleVisibility: .visible) {
                    Button("Keep \(active.summary)") {
                        DraftMode.keepAll(in: context)
                    }
                    Button("Discard \(active.summary)", role: .destructive) {
                        DraftMode.discardAll(in: context)
                    }
                    Button("Stay in draft", role: .cancel) { }
                } message: {
                    // Naming what is at stake, rather than a bare yes/no: the
                    // app cannot tell playing from building, so the person
                    // deciding needs to see the count.
                    Text(active.isEmpty
                         ? "You have not made anything yet, so there is nothing to keep or discard."
                         : "You made \(active.summary) while drafting. Anything you changed that already existed is kept either way.")
                }
            }
        }
    }
}
