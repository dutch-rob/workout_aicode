import Foundation

// MARK: - What the "list" menu offers during a workout
//
// The list is how you jump between the exercises of the workout you are in.
// Part way through, most of it is behind you, and on a watch face the ones
// still to do can be off the bottom of a dialog you have to scroll.
//
// So the list can be narrowed to what is left. The rule is here rather than in
// either screen because both apps show the same list and must narrow it the
// same way — the phone in a Menu, the Watch in a confirmation dialog.
//
// The setting is NOT synced between the devices. It is a view preference, and
// the toggle has to work on the wrist in the middle of a set, where a round
// trip to a phone in a locker would either fail or arrive late and undo what
// the user just chose.

nonisolated enum ExerciseListFilter {

    /// `UserDefaults` key, the same on both devices so each remembers its own
    /// answer under a name the other would recognise.
    static let key = "exerciseListShowsAll"

    /// Everything, which is what the list did before it could be narrowed.
    /// A setting that changes what a screen shows should start by changing
    /// nothing.
    static let showsAllByDefault = true

    /// The positions the list offers, in order.
    ///
    /// Two things are always in it, however narrow it gets:
    ///
    /// * **Where you are.** A logged exercise you are standing on stays
    ///   listed, so the list can still answer "which one is this?".
    /// * **Something.** Narrowing to nothing would leave a menu with no rows
    ///   in it, which reads as broken rather than as finished, so a workout
    ///   with everything logged falls back to the full list.
    static func visible(count: Int, logged: Set<Int>, current: Int,
                        showAll: Bool) -> [Int] {
        let all = Array(0..<max(0, count))
        guard !showAll else { return all }
        // Asked of what is UNLOGGED, not of what would be shown: where you are
        // is kept below whether it is logged or not, so a list that keeps it
        // is never empty, and a fully logged workout would narrow to the one
        // exercise you happen to be standing on.
        let unlogged = all.filter { !logged.contains($0) }
        guard !unlogged.isEmpty else { return all }
        return all.filter { !logged.contains($0) || $0 == current }
    }

    /// What the button at the bottom of the list says. It names what tapping
    /// it does, not the state it is in.
    static func toggleTitle(showAll: Bool) -> String {
        showAll ? "only what's left" : "show all"
    }
}
