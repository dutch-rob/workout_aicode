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
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.setFrame(NSRect(origin: origin, size: size), display: true)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

enum ScreenshotMode {
    /// `-SRWShot <width>x<height>` — and the capture region the script uses
    /// is this origin and size, which is why both are fixed here.
    static let origin = CGPoint(x: 60, y: 60)

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
