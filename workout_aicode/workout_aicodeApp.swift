//
//  workout_aicodeApp.swift
//  workout_aicode
//
//  Created by Rob Boer on 3/4/26.
//

import SwiftUI
import SwiftData
import Combine
import UserNotifications

// MARK: - AppSetup
final class AppSetup: ObservableObject {
    @Published private(set) var container: ModelContainer
    @Published private(set) var store: AppStore
    private(set) var containerKey: UUID = UUID()

    /// True when both the normal load AND the V1 recovery path failed.
    /// The App body shows RecoveryView when this is set.
    @Published private(set) var isRecoveryNeeded: Bool = false

    init() {
        #if DEBUG
        // Screenshot demo mode: an in-memory store with sample data, so captures
        // never touch real data. See DemoMode.swift.
        if DemoMode.isEnabled {
            let c = DemoMode.makeContainer()
            container = c
            store = AppStore(context: c.mainContext)
            return
        }
        #endif

        let syncEnabled = UserDefaults.standard.bool(forKey: "iCloudSyncEnabled")

        // Stage 1: normal load (with migration plan).
        if let cs = Self.tryLoad(syncEnabled: syncEnabled) {
            container = cs.0
            store     = cs.1
            return
        }

        // Stage 2: unknown-version fallback — open the old file with the V1
        // schema, convert entries → flat V2 rows, recreate store.
        if let cs = Self.attemptV1Recovery() {
            container = cs.0
            store     = cs.1
            return
        }

        // Stage 3: both paths failed — the data is unreadable.
        // Wipe the corrupt file so the app can at least boot, then show
        // RecoveryView so the user can export what's salvageable and is
        // informed before anything is permanently gone.
        Self.wipeLocalStoreFiles()
        let (c, s) = Self.makeFreshLocalContainer()
        container        = c
        store            = s
        isRecoveryNeeded = true
    }

    // MARK: - Recovery: user-initiated fresh start

    /// Called by RecoveryView when the user taps "Start fresh".
    /// The store was already wiped in init(), so this just resets the flag.
    func startFresh() {
        containerKey     = UUID()
        isRecoveryNeeded = false
    }

    // MARK: - Toggle sync (migrate data between stores)

    /// Guards against the toggle's onChange firing again while a switch is
    /// still in progress.
    private var isReconfiguring = false

    /// Set when iCloud could not be turned on, for Settings to explain.
    @Published var syncFailureMessage: String?

    func reconfigure(syncEnabled: Bool) {
        guard !isReconfiguring else { return }
        isReconfiguring = true

        // Read the old store while it is still valid and the views are still up.
        let snap = Self.snapshot(context: container.mainContext)

        // On the next turn of the runloop, so the update that set the toggle
        // has finished before the store underneath it changes.
        //
        // Swapping used to crash because SwiftUI hashes whatever identifies a
        // row or a navigation entry, and those were model objects — destroyed
        // by the swap. That is fixed at the source (ContentView identifies
        // everything by UUID), so the tree can stay up and the user stays on
        // the screen they were on.
        DispatchQueue.main.async { [self] in
            defer { isReconfiguring = false }

            if let (newContainer, newStore) = Self.tryLoad(syncEnabled: syncEnabled) {
                Self.mergeSnapshot(snap, into: newContainer.mainContext)
                container    = newContainer
                store        = newStore
                containerKey = UUID()
                syncFailureMessage = nil
                return
            }

            // Could not open the requested store. Rebuild a known-good local
            // container rather than keep the old one, which may itself have
            // been invalidated by the failed load.
            UserDefaults.standard.set(false, forKey: "iCloudSyncEnabled")
            if let (fallback, fallbackStore) = Self.tryLoad(syncEnabled: false) {
                Self.mergeSnapshot(snap, into: fallback.mainContext)
                container    = fallback
                store        = fallbackStore
                containerKey = UUID()
            }
            syncFailureMessage = syncEnabled
                ? "iCloud sharing could not be turned on: this device's iCloud copy was written by a version of the app that cannot be read any more. Your data on this device is unaffected."
                : nil
        }
    }

    // MARK: - Delete all data (local + CloudKit)

    func deleteAllData() {
        // Anything shared goes too. "Delete all my data" that left rows in the
        // developer's database would be a promise the app does not keep, and
        // the one deletion a user is most entitled to expect.
        DeveloperDataSync.withdrawEverything()
        let ctx = container.mainContext
        try? ctx.delete(model: WorkoutLog.self)
        try? ctx.delete(model: WorkoutDef.self)
        try? ctx.delete(model: ExerciseDef.self)
        try? ctx.save()
        store.reloadAll()
    }

    // MARK: - Plain-value snapshots (context-independent)

    private struct ExSnap {
        let id: UUID, name: String, numberOfSeries: Int
        let lowestWeight: Int, highestWeight: Int, weightIncrement: Int
        let movementType: MovementType
    }
    private struct WoSnap {
        let id: UUID, name: String, exerciseOrder: [UUID], sortIndex: Int
    }
    private struct LogSnap {
        let id: UUID, date: Date, workoutId: UUID, exerciseId: UUID
        let weights: [Int], reps: [Int]
    }
    private typealias Snap = ([ExSnap], [WoSnap], [LogSnap])

    private static func snapshot(context: ModelContext) -> Snap {
        let exs  = (try? context.fetch(FetchDescriptor<ExerciseDef>())) ?? []
        let wos  = (try? context.fetch(FetchDescriptor<WorkoutDef>())) ?? []
        let logs = (try? context.fetch(FetchDescriptor<WorkoutLog>())) ?? []
        return (
            exs.map  { ExSnap(id: $0.id, name: $0.name,
                               numberOfSeries: $0.numberOfSeries,
                               lowestWeight: $0.lowestWeight,
                               highestWeight: $0.highestWeight,
                               weightIncrement: $0.weightIncrement,
                               movementType: $0.movementType) },
            wos.map  { WoSnap(id: $0.id, name: $0.name,
                               exerciseOrder: $0.exerciseOrder,
                               sortIndex: $0.sortIndex) },
            logs.map { LogSnap(id: $0.id, date: $0.date,
                                workoutId: $0.workoutId,
                                exerciseId: $0.exerciseId,
                                weights: $0.weights, reps: $0.reps) }
        )
    }

    private static func mergeSnapshot(_ snap: Snap, into ctx: ModelContext) {
        let (exSnaps, woSnaps, logSnaps) = snap

        let destExs = (try? ctx.fetch(FetchDescriptor<ExerciseDef>())) ?? []
        for s in exSnaps {
            if let ex = destExs.first(where: { $0.id == s.id }) {
                if ex.name != s.name { ex.name = s.name }
            } else {
                ctx.insert(ExerciseDef(id: s.id, name: s.name,
                                       numberOfSeries: s.numberOfSeries,
                                       lowestWeight: s.lowestWeight,
                                       highestWeight: s.highestWeight,
                                       weightIncrement: s.weightIncrement,
                                       movementType: s.movementType))
            }
        }

        let destWos = (try? ctx.fetch(FetchDescriptor<WorkoutDef>())) ?? []
        for s in woSnaps {
            if let wo = destWos.first(where: { $0.id == s.id }) {
                if wo.name != s.name { wo.name = s.name }
            } else {
                ctx.insert(WorkoutDef(id: s.id, name: s.name,
                                      exerciseOrder: s.exerciseOrder,
                                      sortIndex: s.sortIndex))
            }
        }

        struct LogSig: Hashable {
            let date: Date, workoutId: UUID, exerciseId: UUID
        }
        let destLogs = (try? ctx.fetch(FetchDescriptor<WorkoutLog>())) ?? []
        let destSigs = Set(destLogs.map {
            LogSig(date: $0.date, workoutId: $0.workoutId, exerciseId: $0.exerciseId)
        })
        for s in logSnaps {
            let sig = LogSig(date: s.date, workoutId: s.workoutId, exerciseId: s.exerciseId)
            if !destSigs.contains(sig) {
                ctx.insert(WorkoutLog(id: s.id, date: s.date,
                                      workoutId: s.workoutId, exerciseId: s.exerciseId,
                                      weights: s.weights, reps: s.reps))
            }
        }
        try? ctx.save()
    }

    // MARK: - Container factory

    static let localStoreURL: URL = {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("local_only.sqlite")
    }()

    /// Open the store for the requested mode. Returns nil if it cannot be
    /// opened at all.
    ///
    /// No side effects: an earlier version wrote `iCloudSyncEnabled` here when
    /// iCloud failed, and since that key drives the Settings toggle it fired
    /// the toggle's onChange again — reconfigure ran re-entrantly, swapping
    /// containers underneath itself, and the objects the views were holding
    /// were destroyed mid-flight. Deciding what to do about a failure belongs
    /// to the caller.
    private static func tryLoad(syncEnabled: Bool) -> (ModelContainer, AppStore)? {
        let config: ModelConfiguration = syncEnabled
            ? ModelConfiguration(cloudKitDatabase: .automatic)
            : ModelConfiguration(url: localStoreURL, cloudKitDatabase: .none)

        do {
            let c = try ModelContainer(
                for: WorkoutDef.self, ExerciseDef.self, WorkoutLog.self, AerobicResult.self,
                migrationPlan: WorkoutMigrationPlan.self,
                configurations: config
            )
            return (c, AppStore(context: c.mainContext))
        } catch {
            print("[ModelContainer] staged load failed (sync=\(syncEnabled)): \(error)")
        }

        // Second chance, without the migration plan.
        //
        // Staged migration refuses a store whose recorded version is not one of
        // the plan's — "Cannot use staged migration with an unknown model
        // version" — which is what an iCloud store written by an older build
        // reports. Every change since V2 is additive, so SwiftData's own
        // inference can open those; this is strictly more forgiving than the
        // plan, not less.
        do {
            let c = try ModelContainer(
                for: WorkoutDef.self, ExerciseDef.self, WorkoutLog.self, AerobicResult.self,
                configurations: config
            )
            print("[ModelContainer] opened without the migration plan (sync=\(syncEnabled))")
            return (c, AppStore(context: c.mainContext))
        } catch {
            print("[ModelContainer] inferred load failed too (sync=\(syncEnabled)): \(error)")
            return nil
        }
    }

    /// A guaranteed-to-succeed fresh local container with NO migration plan.
    /// Only call after wipeLocalStoreFiles() or when the file is known gone.
    private static func makeFreshLocalContainer() -> (ModelContainer, AppStore) {
        // No migration plan — SwiftData creates a brand-new store.
        let config = ModelConfiguration(url: localStoreURL, cloudKitDatabase: .none)
        // swiftlint:disable:next force_try
        let c = try! ModelContainer(for: WorkoutDef.self, ExerciseDef.self, WorkoutLog.self, AerobicResult.self,
                                    configurations: config)
        return (c, AppStore(context: c.mainContext))
    }

    // MARK: - V1 recovery

    /// When the migration plan says "unknown model version", the store was
    /// likely written by a build that predates the versioned schema. We copy
    /// it to /tmp and try to open the COPY with the V1 model (entries-array
    /// WorkoutLog) and no migration plan. If that works we convert the data
    /// in memory, wipe the original file, create a fresh V2 store, and import
    /// everything. The original /tmp copy is deleted on return regardless.
    ///
    /// Returns nil when even the V1 schema doesn't match the on-disk structure.
    private static func attemptV1Recovery() -> (ModelContainer, AppStore)? {
        // ── Step 1: copy store files to /tmp ─────────────────────────────
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("srw_v1_recovery", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmpDir,
                                                  withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let srcDir  = localStoreURL.deletingLastPathComponent()
        let srcStem = localStoreURL.deletingPathExtension().lastPathComponent
        let tmpURL  = tmpDir.appendingPathComponent("v1_copy.sqlite")

        do {
            let contents = try FileManager.default
                .contentsOfDirectory(at: srcDir, includingPropertiesForKeys: nil)
            for f in contents where f.lastPathComponent.hasPrefix(srcStem) {
                let suffix  = String(f.lastPathComponent.dropFirst(srcStem.count))
                let dstName = "v1_copy\(suffix)"
                try FileManager.default.copyItem(at: f,
                                                  to: tmpDir.appendingPathComponent(dstName))
            }
        } catch {
            print("[V1Recovery] copy failed: \(error)")
            return nil
        }

        // ── Step 2: open copy with V1 WorkoutLog schema, no migration plan ──
        let v1Container: ModelContainer
        do {
            let v1Config = ModelConfiguration(url: tmpURL, cloudKitDatabase: .none)
            // The frozen V1 ExerciseDef, not the live one: the store being
            // opened here predates the muscle-group columns, and asking for a
            // model that declares them would not match what is on disk.
            v1Container  = try ModelContainer(
                for: WorkoutDef.self, WorkoutLogSchemaV1.ExerciseDef.self,
                    WorkoutLogSchemaV1.WorkoutLog.self,
                configurations: v1Config
            )
        } catch {
            print("[V1Recovery] V1 schema load failed: \(error)")
            return nil
        }

        // ── Step 3: read all records ──────────────────────────────────────
        let v1Ctx  = v1Container.mainContext
        let exs    = (try? v1Ctx.fetch(FetchDescriptor<WorkoutLogSchemaV1.ExerciseDef>())) ?? []
        let wos    = (try? v1Ctx.fetch(FetchDescriptor<WorkoutDef>())) ?? []
        let v1Logs = (try? v1Ctx.fetch(
            FetchDescriptor<WorkoutLogSchemaV1.WorkoutLog>())) ?? []

        // Flatten V1 entries → V2 flat log rows (same logic as migration plan)
        let v2Logs: [WorkoutLog] = v1Logs.flatMap { v1 in
            v1.entries.enumerated().map { idx, entry in
                WorkoutLog(id:         idx == 0 ? v1.id : UUID(),
                           date:       v1.date,
                           workoutId:  v1.workoutId,
                           exerciseId: entry.exerciseId,
                           weights:    entry.weights,
                           reps:       entry.reps)
            }
        }

        print("[V1Recovery] recovered \(wos.count) workouts, " +
              "\(exs.count) exercises, \(v2Logs.count) log rows from V1 store")

        // ── Step 4: wipe original store, create clean V2 store ───────────
        wipeLocalStoreFiles()
        guard let (v2Container, v2Store) = tryLoad(syncEnabled: false) else {
            print("[V1Recovery] could not create V2 store after wipe")
            return nil
        }

        // ── Step 5: import recovered data ────────────────────────────────
        let ctx = v2Container.mainContext
        for e in exs {
            // Do NOT read e.movementType — the old store doesn't have that
            // column, so SwiftData leaves it as NULL and crashes on the cast
            // from Optional<Any> to the non-optional MovementType enum.
            // All pre-movementType exercises default to .none.
            ctx.insert(ExerciseDef(id: e.id, name: e.name,
                                   numberOfSeries: e.numberOfSeries,
                                   lowestWeight: e.lowestWeight,
                                   highestWeight: e.highestWeight,
                                   weightIncrement: e.weightIncrement,
                                   movementType: .none,
                                   // Same reasoning for the muscle-group
                                   // columns: absent from a V1 store, so they
                                   // start unset and the user can fill them in.
                                   primaryMuscle: nil,
                                   secondaryMuscles: [],
                                   libraryKey: nil))
        }
        for w in wos {
            ctx.insert(WorkoutDef(id: w.id, name: w.name,
                                  exerciseOrder: w.exerciseOrder,
                                  sortIndex: w.sortIndex))
        }
        for l in v2Logs { ctx.insert(l) }
        try? ctx.save()
        v2Store.reloadAll()

        return (v2Container, v2Store)
    }

    /// Removes local_only.sqlite plus WAL / SHM / journal sidecars.
    static func wipeLocalStoreFiles() {
        let folder = localStoreURL.deletingLastPathComponent()
        let stem   = localStoreURL.deletingPathExtension().lastPathComponent
        guard let contents = try? FileManager.default
            .contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        else { return }
        for f in contents where f.lastPathComponent.hasPrefix(stem) {
            try? FileManager.default.removeItem(at: f)
        }
    }
}

// MARK: - App entry point
@main
struct workout_aicodeApp: App {
    @StateObject private var setup = AppSetup()
    @AppStorage("iCloudSyncEnabled") private var iCloudSyncEnabled = false
    // Activating WCSession here keeps it live for the app's full lifetime.
    @StateObject private var watchSession = PhoneSessionManager.shared

    init() {
        // Must be in place before the app finishes launching, or an end-of-rest
        // notification arriving with the app in front shows nothing at all.
        UNUserNotificationCenter.current().delegate = RestTimerNotificationDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            Group {
            if setup.isRecoveryNeeded {
                // Both the normal load and V1 recovery failed.
                // Show a full-screen explanation with export + fresh-start options.
                NavigationStack {
                    RecoveryView()
                }
                .environmentObject(setup)
                .environmentObject(setup.store)
                .modelContainer(setup.container)
            } else {
                // Deliberately NOT .id(containerKey): rebuilding the tree on a
                // store swap threw the user out of Settings and back to the
                // start screen, which reads as a crash. The container and store
                // are published, so @Query re-runs against the new one on its
                // own, and nothing in this tree is identified by a model object
                // any more.
                ContentView()
                    .environmentObject(setup.store)
                    .environmentObject(setup)
                    .modelContainer(setup.container)
                    .task(id: setup.containerKey) {
                        // Give the Watch connectivity layer the current store so
                        // it can push definitions and insert logs from the Watch.
                        PhoneSessionManager.shared.attach(store: setup.store)
                    }
            }
            }
            // Outside the Group on purpose: attached to ContentView it would be
            // torn down by the very swap it starts.
            .onChange(of: iCloudSyncEnabled) { _, newValue in
                setup.reconfigure(syncEnabled: newValue)
            }
        }
    }
}
