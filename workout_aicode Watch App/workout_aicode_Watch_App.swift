//
//  workout_aicode Watch App
//
//  Created by Rob Boer on 5/7/26.
//

import SwiftUI

// Activating WCSession here (via WatchSessionManager.shared) ensures the
// session is ready before any view appears, and keeps it alive for the
// full app lifetime.

@main
struct workout_aicode_Watch_App_Watch_AppApp: App {
    @StateObject private var sessionManager = WatchSessionManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(sessionManager)
        }
    }
}
