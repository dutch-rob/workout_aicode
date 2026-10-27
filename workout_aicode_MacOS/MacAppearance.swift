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

/// Finds the app's own window and sizes it for a capture.
///
/// It does NOT tell the script which window it found, and that omission is
/// the point. It used to write the window id to a path the script passed in,
/// which stopped working the day the app was sandboxed: a sandboxed app may
/// write to its container and to files the user picked in a panel, and the
/// script's temp file is neither. The write was a `try?`, so it failed in
/// silence — every screen reported "the app never reported a window" while
/// the window was in fact up, correctly sized, and on screen. Hours went into
/// bisecting the sample data, which had nothing to do with it.
///
/// So the app no longer reports anything. The script asks the window server
/// which window belongs to this process (tools/srw-window-id.swift) and waits
/// for one the size it asked for, which is a better ready signal anyway: it
/// says the window exists AND has been resized, where the id file only ever
/// said the app had got as far as writing a file.
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

    /// What the WINDOW SERVER thinks this window's size is.
    ///
    /// Not the same as `NSWindow.frame`, and the difference is the whole
    /// reason this exists: a frame set to exactly 1440×900 is reported by the
    /// window server as 1412×882, because the frame includes a shadow margin
    /// the window server does not count. `screencapture -l` photographs what
    /// the window server has, so this is the number that ends up being the
    /// size of the picture — and the Mac App Store accepts only four sizes.
    ///
    /// Reading our own window needs no Screen Recording permission.
    private static func serverSize(of window: NSWindow) -> CGSize? {
        let id = CGWindowID(window.windowNumber)
        guard let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], id)
                as? [[String: Any]],
              let bounds = list.first?[kCGWindowBounds as String] as? [String: Any],
              let w = bounds["Width"] as? Double, let h = bounds["Height"] as? Double
        else { return nil }
        return CGSize(width: w, height: h)
    }

    /// Starts watching for the window. Safe to call before the run loop runs.
    ///
    /// Through `NSApp.windows` rather than a view's `window` property: an
    /// earlier attempt hung an NSViewRepresentable in the root view and waited
    /// for `view.window`, which never arrived on a seeded store. AppKit knows
    /// what windows the app has however SwiftUI arrived at them.
    static func beginIfAsked() {
        guard let size else { return }
        var elapsed = 0.0
        var settled = 0
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { timer in
            elapsed += 0.25
            // The real window: titled, visible, and the biggest of them.
            // Taking the first visible window with a content view picked a
            // 500×500 offscreen shell SwiftUI keeps beside the main one, so
            // the shell was resized and the window that was actually
            // photographed kept whatever size it remembered.
            let candidates = NSApp.windows.filter {
                $0.isVisible && $0.contentView != nil && $0.styleMask.contains(.titled)
            }
            guard let window = candidates.max(by: {
                $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height
            }) else {
                if elapsed > 30 { timer.invalidate() }
                return
            }

            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)

            // Close the loop on the window server's idea of the size rather
            // than setting the frame once and hoping. Two things made a single
            // resize wrong: the shadow margin above, and SwiftUI restoring the
            // frame it remembers shortly after the window first appears.
            let measured = serverSize(of: window) ?? window.frame.size
            let offBy = CGSize(width: size.width - measured.width,
                               height: size.height - measured.height)
            if abs(offBy.width) < 0.5 && abs(offBy.height) < 0.5 {
                settled += 1
                // Whatever SwiftUI focused on opening draws a blue ring, and
                // a focused number field draws its value selected. Neither
                // belongs in a picture of the app sitting still.
                window.makeFirstResponder(nil)
            } else {
                settled = 0
                var frame = window.frame
                frame.size.width += offBy.width
                frame.size.height += offBy.height
                if let visible = (window.screen ?? NSScreen.main)?.visibleFrame {
                    frame.origin.x = visible.midX - frame.width / 2
                    frame.origin.y = visible.midY - frame.height / 2
                }
                window.setFrame(frame, display: true)
            }
            // Stop only once the size has HELD for a second, so a late
            // restore gets corrected rather than winning.
            if settled >= 4 || elapsed > 30 { timer.invalidate() }
        }
    }
}
#endif
