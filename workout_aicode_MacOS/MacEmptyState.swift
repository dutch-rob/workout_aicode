import SwiftUI
import SwiftData

// MARK: - Nothing here yet
//
// Two very different reasons a Mac window can be empty, and telling them apart
// is the whole job of this file:
//
//   • iCloud sharing is off, here or on the phone — the data exists, this
//     window simply cannot see it, and no amount of waiting will help;
//   • there is genuinely nothing yet, because nothing has been made.
//
// Saying "no workouts" in the first case would be a lie that sends someone
// looking for data they have not lost.

struct MacEmptyState: View {
    let thing: String
    /// What to say and offer when the store is local by choice.
    var onCreate: (() -> Void)?

    var body: some View {
        if MacAppSetup.syncEnabled {
            ContentUnavailableView {
                Label("No \(thing) yet", systemImage: "tray")
            } description: {
                Text("Anything you define here syncs to your iPhone and Apple Watch through your iCloud account.\n\nIf you already have \(thing) on your iPhone and they are not here, turn on “Share data among your iPhones/iPads” in the iPhone app's settings — until that is on, the iPhone keeps its data to itself.")
            } actions: {
                if let onCreate {
                    Button("New \(thing.dropLast())", action: onCreate)
                }
            }
        } else {
            ContentUnavailableView {
                Label("No \(thing) yet", systemImage: "icloud.slash")
            } description: {
                Text("This Mac is set to keep its data to itself, so nothing here reaches your iPhone or Apple Watch. Turn on iCloud in Settings to share.")
            } actions: {
                if let onCreate {
                    Button("New \(thing.dropLast())", action: onCreate)
                }
            }
        }
    }
}
