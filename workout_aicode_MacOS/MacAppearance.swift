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
