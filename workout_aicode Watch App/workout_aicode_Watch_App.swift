//
//  workout_aicode Watch App
//
//  Created by Rob Boer on 5/7/26.
//

import SwiftUI
import HealthKit
import WatchKit

// Activating WCSession here (via WatchSessionManager.shared) ensures the
// session is ready before any view appears, and keeps it alive for the
// full app lifetime.

/// Receives a workout the iPhone asked for.
///
/// This is how an aerobic exercise started on the phone reaches the Watch at
/// all. The first attempt used a WatchConnectivity message, which cannot work:
/// those need "two actively running apps", so with the Watch app closed — the
/// ordinary case — the instruction went nowhere, no session was ever created,
/// and nothing was written to Health. `startWatchApp(toHandle:)` on the phone
/// launches this app in the background and delivers the configuration here.
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { @MainActor in
            await WatchAerobicWorkout.shared.start(configuration: workoutConfiguration)
        }
    }
}

@main
struct workout_aicode_Watch_App_Watch_AppApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var delegate
    @StateObject private var sessionManager = WatchSessionManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(sessionManager)
        }
    }
}
