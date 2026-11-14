import SwiftUI

// MARK: - What a set already done looks like
//
// One definition for the phone, the Watch and the iPad, because a column that
// means "done" on one of them had better not mean something slightly different
// on another. Which columns get it is `SetProgress`; this is only the look.
//
// BEHIND the wheel, not over it. A tint laid on top dims the numbers, and the
// numbers are the entire point of the screen — a reminder that makes the
// weight harder to read has cost more than it gave. Pale enough to read as a
// background and no more: it has to be noticeable at a glance, in a gym, at
// arm's length, without turning into a traffic light.
//
// YELLOW, and not green, which is the obvious colour for "done" and is taken.
// watchOS draws its own green ring round whichever wheel has the Digital
// Crown, and it starts on the first column — exactly where the first mark
// lands. Green fill beside green ring is two different things in one colour on
// the one screen where the glance has to be quick. Nothing else here is
// yellow: the heart-rate zones come nearest at zone 3, and those are a strip
// across the top row rather than a block behind a wheel.

extension View {

    /// Tints a wheel's column to say its set has been done.
    func setDoneTint(_ done: Bool, cornerRadius: CGFloat = 12) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.yellow.opacity(done ? 0.26 : 0))
                // The mark arrives five seconds after the last touch, by which
                // time the hand has left the wheel — so it should fade in
                // rather than appear, or it reads as something having gone
                // wrong on a screen nobody was touching.
                .animation(.easeInOut(duration: 0.35), value: done)
        }
    }
}
