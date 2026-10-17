import SwiftUI

/// The iPhone Duo has two screens, and they are not two devices: the same
/// window is handed a different size when it is folded or opened. Everything
/// here is a decision about *that size*, never about a model name.
///
/// Measured on the simulator (iOS 27.1, iPhone19,4), as the app is given them —
/// that is, inside the safe area:
///
///     folded, cover screen     466 × 678 pt   usable 382 × 644   compact/regular
///     open, landscape          951 × 669 pt   usable 867 × 635   regular/regular
///
/// Both report `userInterfaceIdiom == .phone`. The 84pt band on the trailing
/// edge is the camera and the clock/wifi; it is already excluded from the safe
/// area, so laying out inside it — which every screen in this app does — keeps
/// content clear of both without a special case.
enum FoldLayout {

    /// Open, and on its side: the two-pane layout.
    ///
    /// Height is what tells this apart from an ordinary iPhone in landscape.
    /// Width cannot: a Pro Max lying on its side is 956pt wide and reports a
    /// **regular** horizontal size class, exactly like the open Duo. It is only
    /// 440pt tall, though, where the open Duo is 635. Anything over 600 is a
    /// screen no non-folding iPhone has.
    ///
    /// `idiom == .phone` keeps iPads out of it entirely.
    static func isOpenLandscape(_ size: CGSize) -> Bool {
        #if DEBUG
        // Lets the two-pane layout be seen on an ordinary iPhone, which is a
        // far quicker loop than folding a Duo by hand. The proportions are
        // wrong — two panes on a portrait phone are half the width they would
        // ever really be — so it is for catching breakage, not for judging the
        // layout.
        if ProcessInfo.processInfo.arguments.contains("-SRWForceSplit") {
            return true
        }
        #endif
        return UIDevice.current.userInterfaceIdiom == .phone
            && size.width > size.height
            && size.height >= 600
    }

    /// How much room to leave clear down the fold, in total. The crease is a
    /// physical ridge: a wheel or a row of buttons lying across it is split in
    /// two and awkward to touch. iOS 27.1 says nothing about where the fold
    /// falls — `UIHinge` reports only a status and an angle, and SwiftUI has
    /// nothing at all — so this is ours to decide.
    static let creaseGutter: CGFloat = 24

    /// Where the fold is, in the coordinates a root `GeometryReader` works in.
    ///
    /// NOT the middle of the safe area, which is what the first version of this
    /// used and what put the right-hand pane across the crease. The fold is the
    /// middle of the PHYSICAL screen, and the 84pt camera band sits outside the
    /// safe area on one side only, so the two centres are 42pt apart.
    ///
    /// Splitting here has a pleasant consequence: beyond the fold, inside the
    /// safe area, what is left is 379pt — within a few points of the cover
    /// screen's own 382. The right-hand pane really is the outside screen.
    static func creaseX(width: CGFloat, insets: EdgeInsets) -> CGFloat {
        let full = width + insets.leading + insets.trailing
        return full / 2 - insets.leading
    }

    /// The open screen is traited like an iPad — regular/regular — which would
    /// hand a phone layout iPad spacing and iPad list styling. The brief is
    /// that the right half looks like the cover screen, so phone windows are
    /// held to a compact width whatever the trait collection says. iPads are
    /// left alone: this returns false for them.
    static var usesPhoneLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }
}

/// How wide the camera / clock / wifi band is on the edge of the screen the
/// view is being drawn against — 84pt on the Duo, 0 on every other iPhone,
/// which is what makes it safe to use this unconditionally.
///
/// It is set from the real safe-area inset at the root, and only for the pane
/// that actually touches that edge: in the two-pane layout the left pane's
/// trailing edge is the fold, not the band, so it reads 0.
private struct SensorBandWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var sensorBandWidth: CGFloat {
        get { self[SensorBandWidthKey.self] }
        set { self[SensorBandWidthKey.self] = newValue }
    }
}

extension FoldLayout {
    /// The width of the camera/clock band on the trailing edge, or 0 when the
    /// trailing inset is something else entirely.
    ///
    /// An ordinary iPhone on its side also has a trailing inset — the Dynamic
    /// Island, 59pt of it — but the island sits halfway DOWN that edge, right
    /// where the wheels would go, where the Duo's cluster is at the top. Using
    /// the inset blindly would have pushed the wheels under the island for
    /// anyone who turns their phone sideways. Height tells them apart: no
    /// non-folding iPhone is 600pt tall in landscape.
    static func sensorBand(viewport: CGSize, insets: EdgeInsets) -> CGFloat {
        guard UIDevice.current.userInterfaceIdiom == .phone,
              viewport.height >= 600 else { return 0 }
        return insets.trailing
    }
}

/// The app's root. One pane normally; two when the Duo is open on its side,
/// with the logs on the left and the app proper on the right.
///
/// `main` is the SECOND element of the stack in both cases, and deliberately so.
/// A view that changes position in a `ViewBuilder` is a different view as far as
/// SwiftUI is concerned, and rebuilding `ContentView` here would take the log
/// screen with it — whose `onDisappear` calls `leaveSession()` and ends the
/// workout. Folding the phone mid-set must not do that, so the side pane is
/// inserted BEFORE main and main's position never moves.
struct FoldAwareRoot<Main: View, Side: View>: View {
    private let main: Main
    private let side: Side

    init(@ViewBuilder main: () -> Main, @ViewBuilder side: () -> Side) {
        self.main = main()
        self.side = side()
    }

    var body: some View {
        GeometryReader { geo in
            let split = FoldLayout.isOpenLandscape(geo.size)
            let crease = FoldLayout.creaseX(width: geo.size.width,
                                            insets: geo.safeAreaInsets)
            let gutter = FoldLayout.creaseGutter
            HStack(spacing: 0) {
                if split {
                    side
                        .frame(width: max(0, crease - gutter / 2))
                        .phoneLayout()
                    // The fold itself. No divider: a hairline drawn down the
                    // crease is the one place it cannot be seen.
                    Color.clear.frame(width: gutter)
                }
                main
                    .frame(maxWidth: .infinity)
                    .phoneLayout()
                    // Only this pane touches the band: in the split, the side
                    // pane's trailing edge is the fold.
                    .environment(\.sensorBandWidth,
                                 FoldLayout.sensorBand(viewport: geo.size,
                                                       insets: geo.safeAreaInsets))
            }
        }
    }
}

private extension View {
    /// Phone layout on a phone, untouched anywhere else. The flag is the device
    /// idiom, which does not change while the app runs, so this branch is not a
    /// moving identity.
    @ViewBuilder
    func phoneLayout() -> some View {
        if FoldLayout.usesPhoneLayout {
            environment(\.horizontalSizeClass, .compact)
        } else {
            self
        }
    }
}
