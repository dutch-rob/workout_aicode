//
//  workout_aicodeApp.swift
//  workout_aicode
//
//  Created by Rob Boer on 3/4/26.
//

import SwiftUI
import SwiftData

@main
struct workout_aicodeApp: App {
    let sharedModelContainer: ModelContainer
    @StateObject private var store: AppStore

    init() {
        let syncEnabled = UserDefaults.standard.bool(forKey: "iCloudSyncEnabled")
        do {
            let config = syncEnabled
                ? ModelConfiguration(cloudKitDatabase: .automatic)
                : ModelConfiguration()
            let container = try ModelContainer(
                for: WorkoutDef.self, ExerciseDef.self, WorkoutLog.self,
                configurations: config
            )
            self.sharedModelContainer = container
            _store = StateObject(wrappedValue: AppStore(context: container.mainContext))
        } catch {
            if syncEnabled {
                // CloudKit not available (entitlements/container not set up) — fall back to local
                UserDefaults.standard.set(false, forKey: "iCloudSyncEnabled")
                let container = try! ModelContainer(
                    for: WorkoutDef.self, ExerciseDef.self, WorkoutLog.self,
                    configurations: ModelConfiguration()
                )
                self.sharedModelContainer = container
                _store = StateObject(wrappedValue: AppStore(context: container.mainContext))
            } else {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
        .modelContainer(sharedModelContainer)
    }
}
