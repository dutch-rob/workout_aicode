import SwiftUI
import SwiftData

@main
struct workout_aicode_MacOSApp: App {
    @StateObject private var setup = MacAppSetup()

    init() {
        #if DEBUG
        ScreenshotMode.beginIfAsked()
        #endif
    }
    @AppStorage(MacAppearanceKey.textSize) private var textSize = MacTextSize.default.rawValue

    private var size: MacTextSize { MacTextSize(rawValue: textSize) ?? .default }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(setup)
                .modelContainer(setup.container)
                .macTextScaled(size)
                .remembersItsFrameUnlessCapturing()
                // The settings that travel: read what another device wrote,
                // and publish what is changed here. See SettingsMirror.
                .task { SettingsMirror.shared.start(setup.container.mainContext) }
        }
        .defaultSize(width: 1000, height: 680)
        .commands {
            // A Mac app's Help menu is expected to lead somewhere, and this
            // one led nowhere. The guide is already in the app, so Help opens
            // it rather than a separate help book that would be a second copy
            // to keep true.
            CommandGroup(replacing: .help) {
                Button("SetsRepsWheels Help") { MacNavigation.shared.showHelp() }
                    .keyboardShortcut("?", modifiers: .command)
                Divider()
                Button("Import and Export Help") {
                    MacNavigation.shared.showHelp(.importExport)
                }
                Button("Your Data and Privacy") {
                    MacNavigation.shared.showHelp(.privacy)
                }
            }
        }

        // The Mac way in: the app menu, and ⌘, — which is where every Mac user
        // looks first, and found nothing. The settings are still in the
        // sidebar as well; this is an extra door, not a move.
        Settings {
            MacSettingsView()
                .environmentObject(setup)
                .modelContainer(setup.container)
                .macTextScaled(size)
                .frame(minWidth: 480, minHeight: 420)
        }
    }
}

extension View {
    /// A capture must not overwrite the window size somebody actually chose,
    /// so the autosave name is left off entirely on a screenshot run.
    func remembersItsFrameUnlessCapturing() -> some View {
        #if DEBUG
        return Group {
            if ScreenshotMode.size == nil { self.remembersItsFrame() } else { self }
        }
        #else
        return remembersItsFrame()
        #endif
    }
}
