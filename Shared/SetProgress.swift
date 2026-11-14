import Foundation

// MARK: - Which sets have been done, before anything is logged
//
// Three sets of an exercise are three columns of wheels, and somewhere in the
// middle of them it stops being obvious which one you are on. Logging does not
// help: nothing is written down until "log" is pressed, by which time the
// question has been answered the hard way.
//
// So the app guesses, and says so by tinting a column. The guess is
// built on the one thing it already knows — a touch on a wheel, which is what
// starts the rest timer — plus FIVE SECONDS OF QUIET.
//
// The quiet is the whole idea. Arriving at an exercise, people set the wheels
// up: three columns of weights, one after another, in a flurry. None of that
// is a set done, and no amount of looking at WHICH wheels were touched can
// tell it from the real thing. What tells them apart is the pause. Setting up
// is continuous; a set takes time to do.
//
//     a burst   = touches with less than five seconds between them
//     qualifies = the burst's FIRST touch came at least five seconds after
//                 arriving at the exercise, or after the last column was
//                 marked
//
// A qualifying burst that touched the next column along marks that column, and
// nothing else does. Which means the app cannot know a set is done until five
// seconds after the last touch — the burst is not over until then — and the
// mark arrives late by exactly that much. That is a real cost and worth it:
// the alternative is three columns marked while the wheels are still being set
// up, which would be worse than saying nothing at all.
//
// LEFT TO RIGHT, strictly. Only the column immediately right of the last marked
// one can be marked, so a stray touch on the third column while the first is
// still the only marked one does nothing, and does not use up its burst either.
// The columns are the sets in order; a marked third set with an unmarked second
// would be a claim the app has no way to make.
//
// What the mark LOOKS like is `setDoneTint`, deliberately somewhere else: the
// rule has no business knowing a colour, and the colour changed once already.
//
// This holds one exercise's progress and nothing else — no view, no clock of
// its own, no storage — so the rule above is tested (`SetProgressTests`)
// rather than discovered on a wheel in a gym.

nonisolated struct SetProgress: Equatable {

    /// How long the wheels must be left alone before a burst counts as over.
    ///
    /// Short enough that a real set never falls inside it — the set itself
    /// takes longer than this before the hand comes back to the wheel — and
    /// long enough to cover the pauses in setting three columns up.
    static let quiet: TimeInterval = 5

    /// How late the decision may be and still be worth making.
    ///
    /// A burst is decided by a timer set for the moment the quiet runs out,
    /// so in the ordinary way it is decided within milliseconds of it. Long
    /// late means nobody was there to ask — the exercise had been swiped away
    /// from, or the app was in a pocket — and a burst nobody was present for
    /// is dropped rather than guessed at.
    static let latestDecision: TimeInterval = 5

    /// Columns `0..<doneColumns` are done. Never goes down: the app has no
    /// way of noticing a set being un-done.
    private(set) var doneColumns = 0

    /// What the next burst has to be five seconds clear of: arriving at this
    /// exercise, or the moment the last column was marked.
    private var since: Date

    /// The burst in progress, if the wheels have been touched recently.
    private var firstTouch: Date?
    private var lastTouch: Date?
    private var touchedColumns: Set<Int> = []

    init(enteredAt: Date, doneColumns: Int = 0) {
        self.since = enteredAt
        self.doneColumns = max(0, doneColumns)
    }

    /// Arriving at the exercise — the first time, or swiping back to it.
    ///
    /// Coming back is arriving: the wheels get looked over again, and often
    /// adjusted, and that is setting up rather than lifting. Re-arming the
    /// five seconds here is what stops a glance at an old exercise from
    /// marking a set nobody did. What is already marked stays marked.
    mutating func entered(at when: Date) {
        since = when
        forgetBurst()
    }

    /// Swiping away to another exercise. Whatever was half-touched here goes
    /// with it: half a flurry before leaving and half after coming back is two
    /// visits, not one burst, and a burst left open would otherwise be decided
    /// on the way back in — against a five seconds that had not been re-armed
    /// yet. What is already marked stays marked.
    mutating func left() {
        forgetBurst()
    }

    private mutating func forgetBurst() {
        firstTouch = nil
        lastTouch = nil
        touchedColumns = []
    }

    /// A wheel in `column` was touched. Either it continues the open burst or
    /// it starts a new one, which first settles the old.
    mutating func touched(_ column: Int, at when: Date) {
        if let last = lastTouch, when.timeIntervalSince(last) >= Self.quiet {
            settle(at: when)
        }
        if firstTouch == nil {
            firstTouch = when
            touchedColumns = []
        }
        lastTouch = when
        touchedColumns.insert(column)
    }

    /// The wheels have been left alone; decide what the burst meant. True if a
    /// column was marked.
    ///
    /// Safe to call at any time — before the quiet is up it does nothing, so
    /// a timer that fires early or twice cannot invent a set.
    @discardableResult
    mutating func settle(at when: Date) -> Bool {
        guard let first = firstTouch, let last = lastTouch,
              when.timeIntervalSince(last) >= Self.quiet else { return false }

        // Asked far too late to be answered: see `latestDecision`.
        guard when.timeIntervalSince(last) - Self.quiet <= Self.latestDecision else {
            forgetBurst()
            return false
        }

        let qualifies = first.timeIntervalSince(since) >= Self.quiet
        let next = doneColumns
        // `next` is never a real column once every set is marked, so this stops
        // of its own accord without being told how many there are.
        let marked = qualifies && touchedColumns.contains(next)

        forgetBurst()

        if marked {
            doneColumns = next + 1
            // The moment it was marked is when the quiet ran out, not whenever
            // the timer got round to asking. Otherwise a late tick would move
            // the next column's deadline with it, and the rule would depend on
            // how busy the device was.
            since = last.addingTimeInterval(Self.quiet)
        }
        return marked
    }

    /// When there will next be something to decide, for whatever wants to set
    /// a timer. Nil when the wheels are untouched and nothing is pending.
    var decidesAt: Date? { lastTouch?.addingTimeInterval(Self.quiet) }

    /// Whether this column has been done, for the view that tints it.
    func isDone(_ column: Int) -> Bool { column < doneColumns }
}
