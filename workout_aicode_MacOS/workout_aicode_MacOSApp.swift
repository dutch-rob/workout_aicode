import SwiftUI
import SwiftData

@main
struct workout_aicode_MacOSApp: App {
    @StateObject private var setup = MacAppSetup()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(setup)
                .modelContainer(setup.container)
        }
        .defaultSize(width: 1000, height: 680)
    }
}
