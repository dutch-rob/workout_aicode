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
        do {
            let configuration = ModelConfiguration()
            let container = try ModelContainer(
                for: WorkoutDef.self, ExerciseDef.self, WorkoutLog.self,
                configurations: configuration
            )
            self.sharedModelContainer = container
            _store = StateObject(wrappedValue: AppStore(context: container.mainContext))
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
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
