import Testing
import SwiftUI
import AppKit
@testable import workout_aicode_MacOS

// MARK: - The text size setting, which once did nothing
//
// Reported from a real Mac: the setting was there, it saved, it survived a
// restart, and not a pixel moved. It was handed to `.dynamicTypeSize`, which
// compiles on macOS and has no effect — there is no system-wide Dynamic Type
// for it to take part in.
//
// That is a bug no amount of reading the code finds, because the code looks
// right. It needs something that draws the text and measures it, which is what
// these do: `ImageRenderer` on the real view, at the real sizes.

@MainActor
@Suite
struct MacTextSizeTests {

    /// The width of a line of text as this app would draw it at `size`.
    private func width(_ size: MacTextSize, style: Font.TextStyle = .body) -> CGFloat {
        let view = Text("Lats pull down").macFont(style).macTextScaled(size).fixedSize()
        let renderer = ImageRenderer(content: view)
        return renderer.nsImage?.size.width ?? 0
    }

    @Test func theSettingChangesTheTextThatIsDrawn() {
        let small = width(.small)
        let extraLarge = width(.extraLarge)

        // The bug: every one of these came back the same number.
        #expect(small > 0)
        #expect(extraLarge > small)
    }

    @Test func eachStepUpIsBiggerThanTheOneBefore() {
        let widths = MacTextSize.allCases.map { width($0) }

        #expect(widths == widths.sorted())
        #expect(Set(widths).count == MacTextSize.allCases.count)
    }

    /// Turning the setting on must not change what anybody already had.
    @Test func mediumIsExactlyWhatTheAppDrewBefore() {
        let before = ImageRenderer(content: Text("Lats pull down").font(.body).fixedSize())
            .nsImage?.size.width ?? 0

        #expect(width(.medium) == before)
    }

    @Test func mediumScalesByNothingAndTheRestMoveTogether() {
        #expect(MacTextSize.medium.scale == 1)
        #expect(MacTextSize.small.scale < 1)
        #expect(MacTextSize.large.scale > 1)
        #expect(MacTextSize.extraLarge.scale > MacTextSize.large.scale)
    }

    /// Nothing is hand-sized: a heading stays a heading at every size.
    @Test func aHeadingIsStillBiggerThanBodyTextAtEverySize() {
        for size in MacTextSize.allCases {
            #expect(width(size, style: .largeTitle) > width(size, style: .body),
                    "largeTitle collapsed into body at \(size.label)")
            #expect(width(size, style: .body) > width(size, style: .caption2),
                    "body collapsed into caption2 at \(size.label)")
        }
    }

    @Test func anUnsetPreferenceIsTheSizeTheAppAlwaysDrewAt() {
        let defaults = UserDefaults.standard
        let saved = defaults.string(forKey: MacAppearanceKey.textSize)
        defer { defaults.set(saved, forKey: MacAppearanceKey.textSize) }

        defaults.removeObject(forKey: MacAppearanceKey.textSize)
        #expect(MacTextSize.current == .default)
        #expect(MacTextSize.default == .medium)

        defaults.set("extraLarge", forKey: MacAppearanceKey.textSize)
        #expect(MacTextSize.current == .extraLarge)

        // Something the app has never written, from an older or newer build.
        defaults.set("enormous", forKey: MacAppearanceKey.textSize)
        #expect(MacTextSize.current == .default)
    }
}

// MARK: - The appearance a screenshot run is shot in
//
// Reported from a real run: eight dark captures were already on the store,
// the script was run again and produced two light ones. The appearance was
// never the script's to choose — the app followed the Mac, and the Mac had
// been switched since. Nothing in either of them said so.

@Suite
struct ScreenshotAppearanceTests {

    @Test func theRunSaysWhichAppearanceToShootIn() {
        #expect(ScreenshotMode.appearanceName(in: ["app", "-SRWAppearance", "dark"]) == .darkAqua)
        #expect(ScreenshotMode.appearanceName(in: ["app", "-SRWAppearance", "light"]) == .aqua)
    }

    /// Without the flag the app is left alone, which is what every ordinary
    /// launch wants.
    @Test func withoutTheFlagTheAppFollowsTheMac() {
        #expect(ScreenshotMode.appearanceName(in: ["app"]) == nil)
        #expect(ScreenshotMode.appearanceName(in: ["app", "-SRWShot", "1440x900"]) == nil)
    }

    /// A typo must not quietly shoot the other set.
    @Test func anUnknownAppearanceIsNotAGuess() {
        #expect(ScreenshotMode.appearanceName(in: ["app", "-SRWAppearance", "midnight"]) == nil)
        #expect(ScreenshotMode.appearanceName(in: ["app", "-SRWAppearance", ""]) == nil)
    }

    /// The flag last, with nothing after it. Every -SRW flag has to be given a
    /// value — NSUserDefaults reads the launch arguments as pairs, so a bare
    /// one swallows whatever follows — and reading past the end would crash.
    @Test func theFlagWithNothingAfterItIsIgnored() {
        #expect(ScreenshotMode.appearanceName(in: ["app", "-SRWAppearance"]) == nil)
    }

    /// Case is the shell's business, not something to be strict about.
    @Test func theValueIsNotCaseSensitive() {
        #expect(ScreenshotMode.appearanceName(in: ["app", "-SRWAppearance", "Dark"]) == .darkAqua)
        #expect(ScreenshotMode.appearanceName(in: ["app", "-SRWAppearance", "LIGHT"]) == .aqua)
    }
}
