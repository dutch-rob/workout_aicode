import SwiftUI
import SwiftData
import Combine

// MARK: - The Mac's store
//
// The Mac defaults to iCloud, where the phone defaults to a local file, and
// that difference is deliberate.
//
// On the phone a local store is a complete app: you log workouts, you read them
// back, nothing is missing. A local-only Mac store is a dead end — the Mac does
// not log workouts, so everything defined on it would be invisible to the
// device that does, for ever. Sharing is what makes this app worth opening at
// all, so it starts on and the settings screen says so plainly.
//
// A local store is still offered, for anyone who would rather keep their data
// off iCloud entirely and use the Mac as its home.

enum MacSyncKey {
    static let enabled = "macICloudSyncEnabled"
    /// Whether the choice has been made at least once, so the default can be
    /// "on" without overriding somebody who deliberately turned it off.
    static let asked = "macICloudSyncAsked"
}

@MainActor
final class MacAppSetup: ObservableObject {

    @Published private(set) var container: ModelContainer
    /// Set when the store could not be opened at all, for the shell to explain
    /// rather than showing an empty list that looks like lost data.
    @Published private(set) var failure: String?

    static var syncEnabled: Bool {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: MacSyncKey.asked) else { return true }
        return defaults.bool(forKey: MacSyncKey.enabled)
    }

    static func setSyncEnabled(_ on: Bool) {
        UserDefaults.standard.set(true, forKey: MacSyncKey.asked)
        UserDefaults.standard.set(on, forKey: MacSyncKey.enabled)
    }

    /// Where a local-only store lives, when someone chooses one.
    static let localStoreURL: URL = {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("mac_local_only.sqlite")
    }()

    init() {
        let models: [any PersistentModel.Type] = [
            WorkoutDef.self, ExerciseDef.self, WorkoutLog.self,
            AerobicResult.self, DraftSession.self, AssistedResult.self, LogWeights.self
        ]
        #if DEBUG
        // A screenshot run never touches the real store — see MacDemoData.
        if MacDemoData.isEnabled {
            let demo = try! ModelContainer(
                for: Schema(models),
                configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            container = demo
            MacDemoData.seed(into: demo.mainContext)
            return
        }
        #endif

        let configuration = Self.syncEnabled
            ? ModelConfiguration(cloudKitDatabase: .automatic)
            : ModelConfiguration(url: Self.localStoreURL, cloudKitDatabase: .none)

        // Same migration plan as the phone, because it is the same database.
        // A Mac opening the shared store with a different idea of the schema is
        // how a phone's history would get rewritten from under it.
        do {
            container = try ModelContainer(for: Schema(models),
                                           migrationPlan: WorkoutMigrationPlan.self,
                                           configurations: configuration)
            return
        } catch {
            print("[Mac] store failed with the migration plan: \(error)")
        }
        do {
            container = try ModelContainer(for: Schema(models),
                                           configurations: configuration)
            return
        } catch {
            print("[Mac] store failed without the plan too: \(error)")
        }
        // Last resort: something openable, so the window has a store and the
        // shell can say what went wrong instead of failing to launch.
        // swiftlint:disable:next force_try
        container = try! ModelContainer(
            for: Schema(models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        failure = "Your workouts could not be opened. Nothing has been changed or deleted — this window is showing an empty, temporary store."
    }
}
