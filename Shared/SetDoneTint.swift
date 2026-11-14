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

extension View {

    /// Tints a wheel's column to say its set has been done.
    func setDoneTint(_ done: Bool, cornerRadius: CGFloat = 12) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.green.opacity(done ? 0.22 : 0))
                // The green arrives five seconds after the last touch, by
                // which time the hand has left the wheel — so it should fade
                // in rather than appear, or it reads as something having gone
                // wrong on a screen nobody was touching.
                .animation(.easeInOut(duration: 0.35), value: done)
        }
    }
}
