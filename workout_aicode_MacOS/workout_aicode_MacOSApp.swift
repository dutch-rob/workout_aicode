import SwiftUI
import SwiftData

@main
struct workout_aicode_MacOSApp: App {
    @StateObject private var setup = MacAppSetup()
    @AppStorage(MacAppearanceKey.textSize) private var textSize = MacTextSize.default.rawValue

    private var size: MacTextSize { MacTextSize(rawValue: textSize) ?? .default }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(setup)
                .modelContainer(setup.container)
                .dynamicTypeSize(size.dynamicTypeSize)
                .remembersItsFrame()
        }
        .defaultSize(width: 1000, height: 680)

        // The Mac way in: the app menu, and ⌘, — which is where every Mac user
        // looks first, and found nothing. The settings are still in the
        // sidebar as well; this is an extra door, not a move.
        Settings {
            MacSettingsView()
                .environmentObject(setup)
                .modelContainer(setup.container)
                .dynamicTypeSize(size.dynamicTypeSize)
                .frame(minWidth: 480, minHeight: 420)
        }
    }
}
