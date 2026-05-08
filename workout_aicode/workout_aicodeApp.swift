//
//  workout_aicodeApp.swift
//  workout_aicode
//
//  Created by Rob Boer on 3/4/26.
//

import SwiftUI
import SwiftData
import Combine

// MARK: - AppSetup
final class AppSetup: ObservableObject {
    @Published private(set) var container: ModelContainer
    @Published private(set) var store: AppStore
    private(set) var containerKey: UUID = UUID()

    init() {
        let syncEnabled = UserDefaults.standard.bool(forKey: "iCloudSyncEnabled")
        (container, store) = Self.makeContainer(syncEnabled: syncEnabled)
    }

    // MARK: - Toggle sync (migrate data between stores)

    func reconfigure(syncEnabled: Bool) {
        let snap = Self.snapshot(context: container.mainContext)
        let (newContainer, newStore) = Self.makeContainer(syncEnabled: syncEnabled)
        Self.mergeSnapshot(snap, into: newContainer.mainContext)
        container    = newContainer
        store        = newStore
        containerKey = UUID()
    }

    // MARK: - Delete all data (local + CloudKit)

    func deleteAllData() {
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
            exs.map  { ExSnap(id: $0.id, name: $0.name, numberOfSeries: $0.numberOfSeries,
                               lowestWeight: $0.lowestWeight, highestWeight: $0.highestWeight,
                               weightIncrement: $0.weightIncrement) },
            wos.map  { WoSnap(id: $0.id, name: $0.name, exerciseOrder: $0.exerciseOrder,
                               sortIndex: $0.sortIndex) },
            logs.map { LogSnap(id: $0.id, date: $0.date, workoutId: $0.workoutId,
                                exerciseId: $0.exerciseId,
                                weights: $0.weights, reps: $0.reps) }
        )
    }

    // MARK: - Merge (mirrors the import mergeData logic)

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
                                       weightIncrement: s.weightIncrement))
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
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("local_only.sqlite")
    }()

    private static func makeContainer(syncEnabled: Bool) -> (ModelContainer, AppStore) {
        do {
            let config: ModelConfiguration = syncEnabled
                ? ModelConfiguration(cloudKitDatabase: .automatic)
                : ModelConfiguration(url: localStoreURL, cloudKitDatabase: .none)
            let c = try ModelContainer(
                for: WorkoutDef.self, ExerciseDef.self, WorkoutLog.self,
                migrationPlan: WorkoutMigrationPlan.self,
                configurations: config
            )
            return (c, AppStore(context: c.mainContext))
        } catch {
            if syncEnabled {
                UserDefaults.standard.set(false, forKey: "iCloudSyncEnabled")
                return makeContainer(syncEnabled: false)
            } else {
                fatalError("Could not create ModelContainer: \(error)")
            }
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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .id(setup.containerKey)
                .environmentObject(setup.store)
                .environmentObject(setup)
                .modelContainer(setup.container)
                .onChange(of: iCloudSyncEnabled) { _, newValue in
                    setup.reconfigure(syncEnabled: newValue)
                }
        }
    }
}
