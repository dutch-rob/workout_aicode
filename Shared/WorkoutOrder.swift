import Foundation
import SwiftUI

// MARK: - The order the workouts are in
//
// A workout's place on the start screen is a number it carries, `sortIndex`,
// and the rule is the whole of it: the number is the position, counted from
// zero, with no gaps. Keeping gaps — 10, 20, 30, so an insert has room — is
// the obvious alternative and is worse here, because the list is short and is
// read far more often than it is reordered, and a list whose numbers have
// drifted apart sorts correctly right up until two of them collide.
//
// It is written down here because both apps do it. The phone drags a row on
// the start screen and the Mac drags one in its sidebar, and a list that came
// back in a different order on the other device would look like the drag had
// not taken.

nonisolated enum WorkoutOrder {

    /// The list as a drag leaves it.
    ///
    /// Generic, and the only reason it is not simply `move(fromOffsets:)` at
    /// the call site is that this is the part worth testing: SwiftUI's own
    /// `toOffset` is the position in the list BEFORE the moved rows are taken
    /// out, which is off by one from what anybody expects when dragging down.
    static func moved<Element>(_ list: [Element],
                               from offsets: IndexSet,
                               to destination: Int) -> [Element] {
        var order = list
        order.move(fromOffsets: offsets, toOffset: destination)
        return order
    }

    /// Writes the positions back. Call it with the list in the order it
    /// should come back in.
    static func renumber(_ ordered: [WorkoutDef]) {
        for (index, workout) in ordered.enumerated() where workout.sortIndex != index {
            workout.sortIndex = index
        }
    }
}
