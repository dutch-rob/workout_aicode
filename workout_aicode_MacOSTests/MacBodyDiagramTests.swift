import Testing
import SwiftUI
import AppKit
@testable import workout_aicode_MacOS

// MARK: - The two halves of the body diagram
//
// Reported from a real Mac, from the workouts screen: the front half of the
// figure was drawn noticeably smaller than the back half beside it, and the
// aerobic heart sat on top of the front figure's foot.
//
// Both came from the same place. The diagram is two figures side by side with
// label columns outside them, and the front half is the wider of the two
// relative to its height — 0.280 against 0.247. Left to itself an HStack
// squeezes two flexible children to the same WIDTH, and at equal widths the
// wider-per-height figure is the shorter one. The heart, meanwhile, was a
// fixed 42 points inside a figure whose width shrank with the window.
//
// Neither is visible in the code, which reads correctly in both cases. What
// follows is the geometry the picker now works out for itself.

@MainActor
@Suite
struct MacBodyDiagramTests {

    /// The width the diagram needs to draw at its full height, with nothing
    /// to spare.
    private func naturalWidth(forHeight height: CGFloat) -> CGFloat {
        MuscleBodyPicker.labelColumnWidth * 2 + MuscleBodyPicker.captionColumnWidth
            + MuscleBodyPicker.figureSizes(width: .infinity, atMost: height).front.width
            + MuscleBodyPicker.figureSizes(width: .infinity, atMost: height).back.width
    }

    @Test func roomToSpareDrawsAtTheHeightAskedFor() {
        #expect(MuscleBodyPicker.heightThatFits(width: 900, atMost: 420) == 420)
        #expect(MuscleBodyPicker.heightThatFits(width: 560, atMost: 420) == 420)
    }

    /// The bug, in one line: at every width both figures come out the same
    /// height. They were never meant to differ — nothing in the drawing says
    /// one body is shorter than the other.
    @Test func bothHalvesAreAlwaysDrawnToOneHeight() {
        for width in stride(from: 180.0, through: 900.0, by: 30.0) {
            let (front, back) = MuscleBodyPicker.figureSizes(width: width, atMost: 420)
            #expect(front.height == back.height, "at \(width) points across")
        }
    }

    /// A column too narrow for the full height gets a shorter diagram rather
    /// than a squeezed one — and it uses the width it has.
    @Test func aNarrowColumnShrinksTheWholeDiagram() {
        let tight = MuscleBodyPicker.heightThatFits(width: 300, atMost: 420)

        #expect(tight < 420)
        #expect(naturalWidth(forHeight: tight) <= 300.5)
        #expect(naturalWidth(forHeight: tight) >= 299.5)
    }

    /// Wider column, bigger bodies. This is what a fixed height cost: a pane
    /// with room to spare drew the same small figures as the narrowest one.
    @Test func aWiderColumnDrawsABiggerBody() {
        let narrow = MuscleBodyPicker.heightThatFits(width: 300, atMost: 420)
        let roomier = MuscleBodyPicker.heightThatFits(width: 400, atMost: 420)

        #expect(roomier > narrow)
    }

    /// There is a floor. A column narrower than the label columns themselves
    /// would otherwise ask for a figure of no height, and take the labels and
    /// the connectors down with it.
    @Test func theDiagramNeverVanishes() {
        #expect(MuscleBodyPicker.heightThatFits(width: 40, atMost: 420) > 0)
        #expect(MuscleBodyPicker.heightThatFits(width: 0, atMost: 420) > 0)
    }

    /// The heart stays in the corner beside the foot at every size. 0.6 of
    /// the figure's width is where it clears the ankle; a heart that does not
    /// shrink with the figure passes 1.0 and sits on the foot, which is what
    /// was reported.
    @Test func theAerobicHeartStaysClearOfTheFootAtEverySize() {
        for height in [180.0, 260.0, 320.0, 420.0, 520.0] {
            let heart = MuscleBodyPicker.aerobicHeart(forHeight: height)
            let figure = MuscleBodyPicker.figureSizes(width: .infinity, atMost: height).front

            #expect((heart.leading + heart.size) / figure.width < 0.6,
                    "the heart reaches too far across a \(height)-point figure")
            #expect(heart.size >= height / 12, "too small to click at \(height)")
        }
    }

    /// What the picker settles on after a layout pass, in a real hosting view
    /// — `ImageRenderer` lays out once and never sees the state arrive.
    @Test func thePickerTakesTheHeightItsColumnAllowsWhenItIsDrawn() {
        let view = MuscleBodyPicker(selection: .constant(nil),
                                    aerobic: .constant(false),
                                    height: 420)
            .frame(width: 300)
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(x: 0, y: 0, width: 300, height: 460)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        host.layoutSubtreeIfNeeded()

        #expect(host.fittingSize.height < 420)
        #expect(host.fittingSize.height > 200)
    }
}
