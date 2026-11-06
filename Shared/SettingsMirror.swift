import Foundation
import SwiftData
import Combine
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - When the mirror runs
//
// `SyncedSettings.sync` is the rule; this is the thing that calls it. Three
// moments, and all three are needed:
//
//   • At launch, once the store is open — to take what another device wrote
//     while this one was closed.
//   • When anything in UserDefaults changes — which is how a setting being
//     changed in a view reaches the record, without a single view having to
//     know this file exists. Coalesced, because a Stepper being held down
//     fires this on every step.
//   • When the app comes back to the front — iCloud delivers while the app is
//     away, and the view that shows a setting will not ask again by itself.
//
// Deliberately NOT a fourth: there is no observer of the store. A change
// arriving from CloudKit mid-session updates the record, and this device picks
// it up the next time it comes forward. The alternative is watching
// NSPersistentStoreRemoteChange across two platforms to save somebody looking
// at a settings screen they have open while editing it on another device.

@MainActor
final class SettingsMirror: ObservableObject {
    static let shared = SettingsMirror()

    private var context: ModelContext?
    private var watching: [AnyCancellable] = []
    /// Guards against running inside itself. It does NOT stop the echo —
    /// adopting writes UserDefaults, which fires the notification again 400 ms
    /// later. That echo is harmless because `sync` is idempotent: by then the
    /// defaults match the record, so the second run finds nothing to do and
    /// writes nothing. One wasted comparison, against a flag that would have
    /// to be unset on a timer to be any better.
    private var running = false

    /// Run after this device has taken values another device wrote.
    ///
    /// The phone sets this to `reloadAll`, and has to: the Watch is told what
    /// it needs in the payload the phone builds, so a zone tint or a wheel
    /// count set on the Mac would reach the phone and stop there. Nothing to
    /// do on the Mac, which has no Watch to tell.
    var didAdopt: (() -> Void)?

    private init() {}

    /// Starts mirroring against `context`, and runs once immediately.
    func start(_ context: ModelContext) {
        self.context = context
        watching.removeAll()
        run()
        NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(400), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.run() }
            .store(in: &watching)
        // Coming back to the front. Subscribed here rather than from a
        // scenePhase in each app, so the two platforms cannot end up with one
        // of them doing it and the other not.
        for name in Self.cameForward {
            NotificationCenter.default.publisher(for: name)
                .sink { [weak self] _ in self?.run() }
                .store(in: &watching)
        }
    }

    private static var cameForward: [Notification.Name] {
        #if os(iOS)
        return [UIApplication.willEnterForegroundNotification]
        #elseif os(macOS)
        return [NSApplication.didBecomeActiveNotification]
        #else
        return []
        #endif
    }

    /// For anything that knows it has reason to look again.
    func refresh() { run() }

    private func run() {
        guard !running, let context else { return }
        running = true
        defer { running = false }
        if SyncedSettings.sync(in: context) == .adopted { didAdopt?() }
    }
}
