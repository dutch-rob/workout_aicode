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

/// Puts the window at a known place and size for a capture run.
///
/// So that taking screenshots needs ONE permission instead of two. Driving the
/// window from a script means System Events, which means Accessibility, which
/// is a second grant to a second app and a second trip through System
/// Settings — for the sole purpose of setting a rectangle the app can set
/// itself.
///
/// The autosave name is deliberately NOT set here: a screenshot run must not
/// overwrite the window size the user actually chose.
struct ScreenshotFrame: NSViewRepresentable {
    let origin: CGPoint
    let size: CGSize

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        Self.whenAttached(to: view) { window in
            window.setContentSize(size)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            // Its own window id, written where the script can read it.
            //
            // The first attempt positioned the window and captured that
            // rectangle of the SCREEN, which was wrong twice over. AppKit
            // measures from the bottom-left and `screencapture -R` from the
            // top-left, so the window and the capture were at opposite ends of
            // the display — the result was a picture of the desktop with
            // somebody's browser in it. And a region shot takes whatever
            // happens to be there, which for screenshots of an app is both
            // useless and a way to photograph a private window by accident.
            //
            // `screencapture -l<id>` takes the window and nothing else: no
            // desktop, no coordinates to get wrong, nothing behind it.
            if let path = ScreenshotMode.windowIdPath {
                try? "\(window.windowNumber)".write(toFile: path, atomically: true,
                                                    encoding: .utf8)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    /// Runs `body` once the view actually has a window, rather than once.
    ///
    /// A single hop to the main queue is not enough and the screenshots said
    /// so: five of eight screens never reported a window, while the two
    /// lightest did. `makeNSView` is called while the hierarchy is still being
    /// put together, so `view.window` is often nil on the next turn of the run
    /// loop — and the heavier a screen is to build, the more reliably nil it
    /// is. Asking once and giving up silently turned that into "the app never
    /// reported a window", which looked like a permissions problem and was
    /// nothing of the sort.
    private static func whenAttached(to view: NSView, _ body: @escaping (NSWindow) -> Void) {
        func attempt(_ remaining: Int) {
            if let window = view.window {
                body(window)
            } else if remaining > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    attempt(remaining - 1)
                }
            }
        }
        // Ten seconds of trying. A window that has not appeared by then is not
        // going to.
        DispatchQueue.main.async { attempt(100) }
    }
}

enum ScreenshotMode {
    /// Unused now that the window reports its id — kept at zero so nothing
    /// depends on a position again.
    static let origin = CGPoint.zero

    /// `-SRWShotId <path>` — where to write the window id for the script.
    static var windowIdPath: String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "-SRWShotId"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static var size: CGSize? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "-SRWShot"), i + 1 < args.count else { return nil }
        let parts = args[i + 1].lowercased().split(separator: "x")
        guard parts.count == 2, let w = Double(parts[0]), let h = Double(parts[1]),
              w > 200, h > 200 else { return nil }
        return CGSize(width: w, height: h)
    }
}
#endif
