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
/// app's own setting rather than something inherited.
///
/// It used to be handed to `.dynamicTypeSize` at the root of both scenes,
/// which compiles on a Mac and does NOTHING: rendered through `ImageRenderer`,
/// the same `Text` measures 68×16 points at `.xSmall`, at `.xxLarge` and at
/// `.accessibility3` alike, and `@ScaledMetric` is just as inert. The setting
/// was there, it saved, and not a pixel moved — reported from a real Mac,
/// after a restart, which is what sent this looking.
///
/// So the app scales its own text: each style is asked for as a system font
/// at the point size macOS gives that style, times `scale`. Every style still
/// moves together and nothing is hand-sized — a heading stays a heading.
/// What does NOT move is the window chrome AppKit draws for itself: the
/// titles, menus and toolbar.
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

    /// Against `.medium`, which is what the app has always drawn at.
    var scale: CGFloat {
        switch self {
        case .small:      return 0.85
        case .medium:     return 1
        case .large:      return 1.15
        case .extraLarge: return 1.35
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

// MARK: - Text at the chosen size

extension Font {
    /// A text style at the app's chosen size.
    ///
    /// The point size is macOS's own for that style — 13 for the body, 11 for
    /// a caption — so at `.medium` this is exactly the font the app drew
    /// before there was a setting. Rounded to a whole point, because half a
    /// point of difference is not a size anybody asked for and does cost
    /// crispness.
    static func mac(_ style: Font.TextStyle, _ size: MacTextSize) -> Font {
        let base = NSFont.preferredFont(forTextStyle: style.nsTextStyle)
        // Asked of the font rather than listed here, because asking for a
        // system font at a size loses the weight the style carries and a
        // headline that comes back at regular weight stops being one. On this
        // Mac the headline is the only bold style; which ones are is macOS's
        // business, not a table to keep in step with it.
        let weight: Font.Weight =
            base.fontDescriptor.symbolicTraits.contains(.bold) ? .bold : .regular
        return .system(size: (base.pointSize * size.scale).rounded(), weight: weight)
    }
}

private extension Font.TextStyle {
    /// SwiftUI's styles are AppKit's under different names, give or take.
    var nsTextStyle: NSFont.TextStyle {
        switch self {
        case .largeTitle:  return .largeTitle
        case .title:       return .title1
        case .title2:      return .title2
        case .title3:      return .title3
        case .headline:    return .headline
        case .subheadline: return .subheadline
        case .body:        return .body
        case .callout:     return .callout
        case .footnote:    return .footnote
        case .caption:     return .caption1
        case .caption2:    return .caption2
        @unknown default:  return .body
        }
    }
}

private struct MacTextSizeKey: EnvironmentKey {
    /// Read fresh rather than fixed, so a view that somehow sits outside both
    /// scenes still draws at the chosen size instead of the default one.
    static var defaultValue: MacTextSize { .current }
}

extension EnvironmentValues {
    var macTextSize: MacTextSize {
        get { self[MacTextSizeKey.self] }
        set { self[MacTextSizeKey.self] = newValue }
    }
}

extension View {
    /// Put at the root of a scene: sets the default font for everything that
    /// does not ask for a style of its own, and carries the size down to the
    /// ones that do.
    func macTextScaled(_ size: MacTextSize) -> some View {
        environment(\.macTextSize, size)
            .font(.mac(.body, size))
    }

    /// `.macFont(.caption)` where a plain SwiftUI app would say
    /// `.font(.caption)`. The style is the same one; this is the hook that
    /// lets the setting reach it.
    func macFont(_ style: Font.TextStyle) -> some View {
        modifier(MacFont(style: style))
    }
}

private struct MacFont: ViewModifier {
    @Environment(\.macTextSize) private var size
    let style: Font.TextStyle

    func body(content: Content) -> some View {
        content.font(.mac(style, size))
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
    /// `-SRWAppearance dark` or `-SRWAppearance light`, nil to follow the Mac.
    ///
    /// The app has no appearance setting of its own — it takes the one the Mac
    /// is set to, which is right for an app and wrong for a screenshot run.
    /// The set on the store was shot on a dark Mac; a later run on a light one
    /// produced light pictures that could not sit beside them, and nothing in
    /// the script said which it would be. So the run says, rather than the
    /// morning deciding.
    ///
    /// An unrecognised value is nil rather than a guess: a typo should leave
    /// the app alone, not silently shoot the wrong set.
    static func appearanceName(in args: [String] = CommandLine.arguments)
        -> NSAppearance.Name? {
        guard let i = args.firstIndex(of: "-SRWAppearance"), i + 1 < args.count else {
            return nil
        }
        switch args[i + 1].lowercased() {
        case "dark":  return .darkAqua
        case "light": return .aqua
        default:      return nil
        }
    }

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
        if let name = appearanceName() {
            // Asked for on the next pass, not here: this runs from App.init,
            // where NSApp may not exist yet, and an appearance set on nothing
            // is an appearance nobody sees.
            DispatchQueue.main.async { NSApp?.appearance = NSAppearance(named: name) }
        }
        guard let size else { return }
        var elapsed = 0.0
        var settled = 0
        // A main-actor loop rather than a Timer. Every line below is AppKit
        // work that has to be on the main actor, and `Timer`'s block is
        // @Sendable, so it may not hold the two counters the loop runs on —
        // Swift 6 rejects it outright. The bound on `elapsed` is what it
        // always was: give up after thirty seconds rather than spin forever.
        Task { @MainActor in
            while elapsed <= 30 {
                try? await Task.sleep(for: .milliseconds(250))
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
                }) else { continue }

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
                if settled >= 4 { break }
            }
        }
    }
}
#endif
