import Foundation
import Combine
import SwiftData
import SwiftUI

// MARK: - Saving, and saying so when it does not work
//
// Every write to the store used to end in `try? context.save()`. That is a
// save whose failure nobody hears: not the user, not the log, not the next
// screen. For an app whose whole job is to remember what you lifted, the worst
// thing it can do is appear to have remembered.
//
// It is not a theoretical failure. A disk with nothing left on it, an iCloud
// store that will not take a write, a model that cannot be encoded — SwiftData
// reports all of these by throwing from `save()`, and `try?` drops them on the
// floor. The set is then on screen, looking logged, and is gone at the next
// launch.
//
// So: one place that saves. It still does not interrupt anything — a save that
// fails in the middle of a workout must not put a dialog between you and the
// next set — but it records what happened and publishes it, and the app's root
// shows it once the user is somewhere they can read it. `doing` is what to
// call the thing that was being saved, in the user's words where a user will
// read it; the file and function come along by themselves for the ones that
// are really only diagnostics.

@MainActor
final class StoreSave: ObservableObject {

    static let shared = StoreSave()
    private init() {}

    struct Failure: Identifiable, Equatable {
        let id = UUID()
        /// What was being saved, as a sentence fragment: "logging a set".
        let doing: String
        let reason: String
        let at: Date

        /// Rebuilt rather than stored so it follows the user's language.
        var message: String {
            "Something went wrong while \(doing), and it may not have been saved. "
            + "If it is missing, it will need doing again.\n\n\(reason)"
        }
    }

    /// The last save that did not work, or nil. Set on the main actor and read
    /// by whatever is showing it.
    @Published private(set) var failure: Failure?

    /// Dismissed by the screen that showed it.
    func clear() { failure = nil }

    /// Saves the context, and remembers it if that fails.
    ///
    /// Returns whether it worked, for the few callers that want to know
    /// before carrying on; most do not and can ignore it.
    @discardableResult
    static func save(_ context: ModelContext, doing: String? = nil,
                     function: StaticString = #function,
                     file: StaticString = #fileID) -> Bool {
        guard context.hasChanges else { return true }
        do {
            try context.save()
            return true
        } catch {
            let what = doing ?? "saving your workouts"
            // Printed as well as published: a TestFlight user cannot hand over
            // a @Published value, and this is the kind of thing that gets
            // reported as "it forgot one".
            print("[save] failed while \(what) — \(file) \(function): \(error)")
            shared.failure = Failure(doing: what,
                                     reason: error.localizedDescription,
                                     at: Date())
            return false
        }
    }
}

// MARK: - Telling the user

extension View {
    /// Shows the last save that did not work, once, wherever this is applied.
    ///
    /// Put it on an app's root so that a failure during a workout is still
    /// there to be read afterwards: nothing interrupts the set in front of
    /// you, but nothing is swallowed either.
    func reportsSaveFailures() -> some View { modifier(SaveFailureAlert()) }
}

private struct SaveFailureAlert: ViewModifier {
    @ObservedObject private var saves = StoreSave.shared

    func body(content: Content) -> some View {
        content.alert("Not saved",
                      isPresented: Binding(get: { saves.failure != nil },
                                           set: { if !$0 { saves.clear() } }),
                      presenting: saves.failure) { _ in
            Button("OK") { saves.clear() }
        } message: { failure in
            Text(failure.message)
        }
    }
}
