// Which window belongs to a running process, and how big is it.
//
// `screencapture -l<id>` photographs one window and nothing else, which is
// the only safe way to shoot an app: a region capture takes whatever happens
// to be at those coordinates, and once took a picture of a browser.
//
// Getting the id used to be the app's job — it wrote the number to a file the
// script passed in. Sandboxing ended that silently (see ScreenshotMode), so
// the script asks the window server instead. Window ids, owners, pids and
// bounds need no permission; only reading pixels does.
//
// Usage:  srw-window-id <pid>     ->  "<window-id> <width> <height>" or nothing
import CoreGraphics
import Foundation

guard let pid = Int(CommandLine.arguments.dropFirst().first ?? "") else {
    FileHandle.standardError.write(Data("usage: srw-window-id <pid>\n".utf8))
    exit(2)
}

let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []

// Layer 0 is an ordinary document window: not the menu bar, not a tooltip,
// not one of the offscreen shells AppKit keeps around. Biggest wins, because
// a sheet or a popover over the window would otherwise be picked.
let mine = windows.compactMap { window -> (id: Int, w: Int, h: Int)? in
    guard window[kCGWindowOwnerPID as String] as? Int == pid,
          window[kCGWindowLayer as String] as? Int == 0,
          window[kCGWindowIsOnscreen as String] as? Bool == true,
          let id = window[kCGWindowNumber as String] as? Int,
          let bounds = window[kCGWindowBounds as String] as? [String: Any],
          let w = bounds["Width"] as? Int, let h = bounds["Height"] as? Int,
          w > 200, h > 200
    else { return nil }
    return (id, w, h)
}

guard let best = mine.max(by: { $0.w * $0.h < $1.w * $1.h }) else { exit(1) }
print("\(best.id) \(best.w) \(best.h)")
