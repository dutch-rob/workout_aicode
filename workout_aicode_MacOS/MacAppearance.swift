import SwiftUI
import AppKit

// MARK: - How big, and where
//
// Two things a Mac app is expected to get right and this one did not: text
// that can be made bigger, and a window that comes back the size you left it.

enum MacAppearanceKey {
    static let textSize = "macTextSize"
}

/// How large the app draws its text.
///
/// macOS has no system-wide Dynamic Type the way iOS does, so the size is the
/// app's own setting rather than something inherited. The cases are SwiftUI's,
/// which means every text style scales together and nothing has to be
/// hand-sized: a heading stays a heading.
enum MacTextSize: String, CaseIterable, Identifiable {
    case small, medium, large, extraLarge

    var id: String { rawValue }

    var label: String {
        switch self {
        case .small:      return "Small"
        case .medium:     return "Medium"
        case .large:      return "Large"
        case .extraLarge: return "Extra large"
        }
    }

    var dynamicTypeSize: DynamicTypeSize {
        switch self {
        case .small:      return .small
        case .medium:     return .medium
        case .large:      return .large
        case .extraLarge: return .xxLarge
        }
    }

    /// What the app used before this was a choice, so turning the setting on
    /// changes nothing until it is moved.
    static let `default` = MacTextSize.medium

    static var current: MacTextSize {
        MacTextSize(rawValue: UserDefaults.standard.string(forKey: MacAppearanceKey.textSize) ?? "")
            ?? .default
    }
}

// MARK: - Remembering the window

/// Gives the window a frame autosave name, which is how AppKit remembers a
/// size and position across launches.
///
/// SwiftUI's `defaultSize` only says how big a NEW window starts; it has
/// nothing to say about the one you resized last week. Reaching for the
/// NSWindow is the supported way to ask for that, and the name is what the
/// saved frame is filed under.
struct RemembersItsFrame: NSViewRepresentable {
    let name: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            // Set once. Assigning the name again on every redraw makes AppKit
            // re-read the saved frame and the window jumps while being dragged.
            if window.frameAutosaveName != name {
                window.setFrameAutosaveName(name)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

extension View {
    func remembersItsFrame(_ name: String = "SetsRepsWheelsMainWindow") -> some View {
        background(RemembersItsFrame(name: name))
    }
}

#if DEBUG
// MARK: - Sizing itself for a screenshot

/// Finds the app's own window, sizes it, and reports its id.
///
/// Through `NSApp.windows` rather than through a view's `window` property.
/// The first attempt hung an NSViewRepresentable in the background of the
/// root view and waited for `view.window` to become non-nil — which it does
/// for an ordinary launch and, for reasons that were not worth any more
/// bisecting, never did when the app opened on a seeded in-memory store. The
/// view was built (its `makeNSView` ran) and simply never joined a window.
///
/// AppKit knows what windows the app has regardless of how SwiftUI arrived at
/// them, so this asks AppKit.
enum ScreenshotMode {
    /// `-SRWShot <width>x<height>`
    static var size: CGSize? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "-SRWShot"), i + 1 < args.count else { return nil }
        let parts = args[i + 1].lowercased().split(separator: "x")
        guard parts.count == 2, let w = Double(parts[0]), let h = Double(parts[1]),
              w > 200, h > 200 else { return nil }
        return CGSize(width: w, height: h)
    }

    /// `-SRWShotId <path>` — where to write the window id for the script.
    static var windowIdPath: String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "-SRWShotId"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    /// Starts watching for the window. Safe to call before the run loop runs.
    static func beginIfAsked() {
        guard windowIdPath != nil || size != nil else { return }
        let size = self.size
        var elapsed = 0.0
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { timer in
            elapsed += 0.25
            // A real window with content, not a panel or an offscreen shell.
            guard let window = NSApp.windows.first(where: {
                $0.isVisible && $0.contentView != nil && $0.frame.width > 200
            }) else {
                if elapsed > 30 { timer.invalidate() }
                return
            }
            timer.invalidate()
            if let size { window.setContentSize(size) }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            if let path = windowIdPath {
                try? "\(window.windowNumber)".write(toFile: path, atomically: true,
                                                    encoding: .utf8)
            }
        }
    }
}
#endif
