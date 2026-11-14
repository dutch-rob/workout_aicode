import Foundation
import Combine
import WatchConnectivity
import HealthKit

// MARK: - PhoneSessionManager
//
// iOS side of WatchConnectivity.
//
//   • Push workout / exercise definitions to the Watch and answer its pulls.
//   • Receive completed sets logged on the Watch and store them.
//   • Coordinate a single-driver "handover" session. At most one device drives
//     an in-progress workout; the other, if it knows a session is active, shows
//     a Paused screen offering "Continue here".
//
// Handover is TAP-ONLY: merely opening / glancing at the other device never
// moves the session. Foregrounding only *asks* whether the other device is
// driving ("queryDriver") and, if so, shows the Paused screen. The session is
// only handed over when the user taps "Continue here" ("takeOver").
//
// Messages (WCSession sendMessage):
//   • "queryDriver" (reply): "are you driving? give me your snapshot" — no side
//     effects on the responder.
//   • "takeOver" (reply): "I'm taking the session now" — the current driver
//     replies its snapshot and flips itself to Paused.
//   • "driverActive" (carries snapshot): a device just became the driver, so an
//     already-open counterpart flips to Paused immediately.
//   • "sessionEnded": the driver quit/finished; the other returns home.
// The driver also stashes its snapshot in the application context so takeover
// still works when the other app is asleep.

enum HandoverRole { case none, driving, paused }

final class PhoneSessionManager: NSObject, ObservableObject {

    static let shared = PhoneSessionManager()

    @Published private(set) var isWatchReachable = false

    /// Whether there is a Watch app to measure anything at all. Distinct from
    /// reachable: an installed Watch app that happens to be asleep will still
    /// wake for a workout, whereas no Watch app means no heart rate, ever.
    var hasWatchApp: Bool {
        guard WCSession.isSupported() else { return false }
        let session = WCSession.default
        return session.activationState == .activated && session.isWatchAppInstalled
    }

    /// Whether a Watch app is installed to show Watch settings for at all.
    /// Published, unlike `hasWatchApp`, so a screen can be built from it and
    /// redraw when a Watch is paired or unpaired while the app is open.
    @Published private(set) var watchAppInstalled = false

    /// Major watchOS version of the paired Watch, 0 until one has said. See
    /// `WatchSystemVersion`; published so the settings screen follows it
    /// without being reopened.
    @Published private(set) var watchOSMajor = WatchSystemVersion.major

    /// Role of THIS device in the shared workout session.
    @Published private(set) var role: HandoverRole = .none
    /// When set, ContentView should navigate into this workout. Cleared on consume.
    @Published var routeWorkoutId: String? = nil
    /// Snapshot the log view should load (adopt) when it appears / while open.
    @Published private(set) var adoptSnapshot: SessionSnapshot? = nil

    weak var store: AppStore?

    private var liveSnapshot: SessionSnapshot?
    private var remoteSnapshot: SessionSnapshot?
    /// True after the user dismissed the Paused screen ("Not now"); suppresses
    /// re-prompting until the remote session changes or ends.
    private var snoozed = false

    private var lastPayloadData: Data?
    /// Details of a running aerobic session, for a Watch app that has not been
    /// launched yet to pick up when it is.
    private var aerobicContext: [String: Any]?

    // MARK: - Apple Health: open-workout tracking
    //
    // The phone tracks the in-progress workout (start + last activity) and, if it
    // is left un-ended, auto-finalizes it after an hour of inactivity — assuming
    // it ended at the last logged set (so a forgotten workout isn't hours long).

    private struct OpenWorkout: Codable { var startedAt: Date; var lastActivityAt: Date }
    private let openWorkoutKey = "openHealthWorkout"
    /// When a forgotten workout counts as over, and how long an interrupted
    /// session stays resumable — one rule, in OpenWorkoutPolicy, because a
    /// session the app will still resume is one it has not declared finished.
    private var autoEndAfter: TimeInterval { OpenWorkoutPolicy.idleLimit }

    private var openWorkout: OpenWorkout? {
        get {
            guard let d = UserDefaults.standard.data(forKey: openWorkoutKey) else { return nil }
            return try? JSONDecoder().decode(OpenWorkout.self, from: d)
        }
        set {
            if let v = newValue, let d = try? JSONEncoder().encode(v) {
                UserDefaults.standard.set(d, forKey: openWorkoutKey)
            } else {
                UserDefaults.standard.removeObject(forKey: openWorkoutKey)
            }
        }
    }

    private var healthEnabled: Bool { UserDefaults.standard.bool(forKey: "healthSharingEnabled") }

    // MARK: - Carrying on after the app is killed
    //
    // iOS suspends an app the moment the screen locks, and reclaims suspended
    // apps whenever it wants the memory. A phone in a gym pocket for ten
    // minutes is exactly that case, and there is no way to prevent it: the
    // background modes that keep an app alive are for navigation, audio and
    // workouts-on-a-Watch, and claiming one under a false pretext is both a
    // lie to the user about their battery and an App Store rejection.
    //
    // So the app stops trying to stay alive and learns to come back instead.
    // The live session — which workout, which exercise, what is dialled into
    // every wheel, what has been logged, when it started — is written down as
    // it changes. Reopening the workout picks it up.
    //
    // Written to UserDefaults rather than to the database on purpose: this is
    // the state of one device's screen, not a fact about the user's training,
    // and it must never sync to the phone's other devices as though it were.

    private struct UnfinishedSession: Codable {
        var snapshot: SessionSnapshot
        /// Last touched, which is what decides whether it is still today's
        /// workout or yesterday's leftovers.
        var savedAt: Date
    }
    private let unfinishedSessionKey = "unfinishedSession"

    private var unfinishedSession: UnfinishedSession? {
        get {
            guard let d = UserDefaults.standard.data(forKey: unfinishedSessionKey) else { return nil }
            return try? JSONDecoder().decode(UnfinishedSession.self, from: d)
        }
        set {
            if let v = newValue, let d = try? JSONEncoder().encode(v) {
                UserDefaults.standard.set(d, forKey: unfinishedSessionKey)
            } else {
                UserDefaults.standard.removeObject(forKey: unfinishedSessionKey)
            }
        }
    }

    /// The session to carry on with when this workout is opened again, or nil
    /// if there is none, it is a different workout, or it has gone cold.
    func resumableSession(for workoutId: String) -> SessionSnapshot? {
        guard let saved = unfinishedSession, saved.snapshot.workoutId == workoutId else { return nil }
        // Measured from the last LOGGED exercise — the same moment, and the
        // same hour, that decides when a forgotten workout is written to
        // Health. It used to be measured from the last wheel touch, which
        // could only ever be later, so the two limits agreed in practice but
        // were two clocks. One clock means one rule to explain: a workout the
        // app still picks up is one it has not yet reported as finished.
        guard let open = openWorkout,
              OpenWorkoutPolicy.isResumable(lastActivityAt: open.lastActivityAt, now: Date())
        else {
            unfinishedSession = nil
            return nil
        }
        return saved.snapshot
    }

    func forgetUnfinishedSession() { unfinishedSession = nil }

    /// A snapshot as it should leave this device: with the rest as it stands
    /// right now and the moment it was sent.
    ///
    /// Stamped here, on the way out, rather than whenever the log screen
    /// happens to record one. A rest skipped a second ago has not changed any
    /// wheel, so the last recorded snapshot still says it is running — and the
    /// Watch would carry on with a rest the user had just ended.
    private func outgoing(_ snap: SessionSnapshot) -> SessionSnapshot {
        var s = snap
        let rest = RestTimer.shared
        s.restEndsAt = rest.endsAt?.timeIntervalSince1970
        s.restTotal = rest.endsAt == nil ? nil : rest.totalSeconds
        s.updatedAt = Date().timeIntervalSince1970
        return s
    }

    /// What to tell the Watch about the workout in progress on this phone.
    ///
    /// Either the live one, or — when iOS has reclaimed the app since — the
    /// unfinished session it wrote down. That second case is the ordinary one:
    /// the phone went into a pocket, the app was killed, and the Watch is
    /// opened. The phone app is then woken in the background to answer, knows
    /// nothing live, and used to say "not driving". So the Watch showed its
    /// workout list instead of offering to carry on.
    private var sessionToOffer: SessionSnapshot? {
        if role == .driving, let snap = liveSnapshot { return outgoing(snap) }
        guard role == .none, let saved = unfinishedSession,
              resumableSession(for: saved.snapshot.workoutId) != nil else { return nil }
        return outgoing(saved.snapshot)
    }

    /// The workout to open straight into when the app launches, if one was
    /// interrupted and is still inside the idle limit — and only once the Watch
    /// has said it is not running that workout right now.
    ///
    /// Asking matters. This used to be a plain synchronous answer, and the
    /// caller guarded it with `role != .paused`, which is never true at launch:
    /// the Watch is asked over WatchConnectivity and the reply arrives later.
    /// So opening the phone during a Watch workout — to look at the logs, say —
    /// navigated into the log screen, which enters the session, which
    /// broadcasts `driverActive`, which left the Watch showing Paused. The user
    /// had taken the workout off their wrist without being asked, and declining
    /// afterwards was too late to give it back.
    ///
    /// When the Watch is driving, the Paused screen is raised instead, which is
    /// the hand-over the user can accept or decline — the one that was always
    /// meant to be the only way across.
    ///
    /// Settles the auto-end first, so a workout that has already gone cold is
    /// written to Health and forgotten rather than reopened.
    func workoutToResume(_ completion: @escaping (String?) -> Void) {
        checkAutoEnd()
        guard let saved = unfinishedSession,
              resumableSession(for: saved.snapshot.workoutId) != nil else {
            completion(nil); return
        }
        let id = saved.snapshot.workoutId
        let session = WCSession.default
        // Out of range: no Watch to take anything from, so carry on as before.
        guard session.activationState == .activated, session.isReachable else {
            completion(id); return
        }
        queryDriver { [weak self] isDriving, snap in
            guard let self else { completion(nil); return }
            guard isDriving else { completion(id); return }
            self.remoteSnapshot = snap
            if self.role == .none, !self.snoozed { self.role = .paused }
            completion(nil)
        }
    }

    /// A workout began (on either device). Finalizes any stale prior one first.
    func noteWorkoutStarted(at date: Date) {
        guard !watchIsTheHealthWriter else { forgetOpenWorkout(); return }
        if let w = openWorkout, abs(w.startedAt.timeIntervalSince(date)) < 1 { return }
        finalizeAbandonedOpenWorkout()
        openWorkout = OpenWorkout(startedAt: date, lastActivityAt: date)
    }

    /// A set was logged (on either device) — extend the workout's activity time.
    func noteActivity(at date: Date = Date()) {
        guard !watchIsTheHealthWriter else { forgetOpenWorkout(); return }
        if var w = openWorkout {
            if date > w.lastActivityAt { w.lastActivityAt = date; openWorkout = w }
        } else {
            openWorkout = OpenWorkout(startedAt: date, lastActivityAt: date)
        }
    }

    /// In Apple-workout mode a workout on the Watch is written to Health BY the
    /// Watch, as the session it ran. The phone must then not keep an open
    /// workout of its own for it: the hour-later auto-end would write the same
    /// workout a second time, and the user would find it twice in Fitness.
    ///
    /// Only while the Watch has it. A workout driven here is still the phone's
    /// to record, which is what the Health switch means in this mode.
    private var watchIsTheHealthWriter: Bool {
        WatchWorkoutMode.current == .appleWorkout && role != .driving
    }

    /// Drop the open workout without writing it anywhere.
    private func forgetOpenWorkout() {
        openWorkout = nil
    }

    /// The workout ended on THIS (phone) device — either by finishing every
    /// exercise or by quitting early. Both count as a workout, so both are saved
    /// (as long as at least one set was actually logged).
    func finishWorkoutHere(startedAt: Date, endedAt: Date, workoutId: UUID? = nil,
                           writeToHealth: Bool = true) {
        let hadActivity = openWorkout.map { $0.lastActivityAt > $0.startedAt } ?? false
        openWorkout = nil
        // Said "done" or "quit": this is the one ending that means it. Anything
        // else that closes the screen leaves the session resumable.
        forgetUnfinishedSession()

        // The moment to ask about the next one: they have just done this one
        // and are still standing in the gym. Only after a workout that
        // actually happened — being offered a next session for a screen you
        // opened and closed again is noise.
        if let workoutId, hadActivity, endedAt > startedAt {
            justFinished = FinishedWorkout(workoutId: workoutId,
                                           startedAt: startedAt, endedAt: endedAt)
        }

        guard writeToHealth, healthEnabled, hadActivity, endedAt > startedAt else { return }
        // Deferred on purpose: HealthKit may put its permission sheet on screen,
        // and must never block the log screen from closing first.
        DispatchQueue.main.async {
            HealthWorkoutLogger.shared.saveStrengthWorkout(start: startedAt, end: endedAt)
        }
    }

    /// A workout that has just ended, for whatever wants to offer something at
    /// the end of one. Cleared as soon as it has been dealt with.
    struct FinishedWorkout: Equatable, Identifiable {
        let workoutId: UUID
        let startedAt: Date
        let endedAt: Date
        /// The workout AND when it ended: finishing the same routine twice in
        /// a day is two different endings, and a sheet keyed on the workout
        /// alone would not open again for the second.
        var id: String { "\(workoutId.uuidString)-\(endedAt.timeIntervalSince1970)" }
    }
    @Published var justFinished: FinishedWorkout? = nil

    /// What the Watch asked this device to put in the calendar.
    ///
    /// Held rather than acted on here: writing needs the model (for the
    /// workout's name) and may need the permission prompt, which belongs to a
    /// view. Cleared once it has been dealt with.
    struct ScheduleRequest: Equatable {
        let workoutId: UUID
        /// Empty for "not now" on the wrist: nothing to schedule, but the
        /// workout that was done still gets written down.
        let starts: [Date]
        let duration: TimeInterval
        /// When the workout really ran, for the record of it. Nil from a Watch
        /// older than records, and then only the plans go in.
        let ranFrom: Date?
        let ranTo: Date?
    }
    @Published var scheduleRequestedFromWatch: ScheduleRequest? = nil

    /// A prior workout was left open and superseded/abandoned — save it capped at
    /// its last activity, then forget it.
    private func finalizeAbandonedOpenWorkout() {
        guard let w = openWorkout else { return }
        if healthEnabled,
           let end = OpenWorkoutPolicy.closingDate(startedAt: w.startedAt,
                                                   lastActivityAt: w.lastActivityAt) {
            HealthWorkoutLogger.shared.saveStrengthWorkout(start: w.startedAt, end: end)
        }
        openWorkout = nil
        // The workout is closed, so there is nothing left to carry on from.
        forgetUnfinishedSession()
    }

    /// Called on launch / foreground: finalize a workout left un-ended for > 1h.
    func checkAutoEnd() {
        guard let w = openWorkout else { return }
        if OpenWorkoutPolicy.endDate(startedAt: w.startedAt,
                                     lastActivityAt: w.lastActivityAt,
                                     now: Date()) != nil {
            finalizeAbandonedOpenWorkout()
        }
    }

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Store attachment
    func attach(store: AppStore) {
        self.store = store
        pushDefinitions()
        // Finalize any workout that was left un-ended before this launch.
        checkAutoEnd()
        // NOTE: permission is requested from the Settings toggle only — never at
        // launch, so HealthKit's sheet can't appear over an unrelated screen.
    }

    // MARK: - Definitions + session stash
    func pushDefinitions() {
        guard let data = store?.watchSyncPayloadData() else { return }
        lastPayloadData = data
        sendContext()
    }

    private func sendContext() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isWatchAppInstalled else { return }
        var ctx: [String: Any] = [:]
        if let data = lastPayloadData { ctx["payload"] = data }
        if role == .driving, let snap = liveSnapshot, let d = try? JSONEncoder().encode(outgoing(snap)) {
            ctx["session"] = d
        }
        if let aerobicContext { ctx["aerobic"] = aerobicContext }
        guard !ctx.isEmpty else { return }
        try? session.updateApplicationContext(ctx)
    }

    // MARK: - Handover: called by the log view / app

    /// The local log view opened `workoutId` and becomes the driver. Adopts the
    /// other device's state if it was already in the same workout.
    func enterSession(workoutId: String, current: SessionSnapshot,
                      adopt: @escaping (SessionSnapshot) -> Void) {
        updateLiveSnapshot(current)
        adoptSnapshot = nil
        routeWorkoutId = nil
        role = .driving
        snoozed = false
        noteWorkoutStarted(at: Date(timeIntervalSince1970: current.startedAt))
        requestTakeOver { [weak self] snap in
            guard let self else { return }
            if let snap, snap.workoutId == workoutId {
                self.liveSnapshot = snap
                self.noteWorkoutStarted(at: Date(timeIntervalSince1970: snap.startedAt))
                adopt(snap)
            }
            self.sendContext()
        }
        broadcastDriverActive()
        sendContext()
    }

    func updateLiveSnapshot(_ snapshot: SessionSnapshot) {
        liveSnapshot = snapshot
        // Every change, not only the checkpoints. What is dialled into a wheel
        // before the phone goes into a pocket is exactly what gets lost, and it
        // is the part the user has to remember to type again. Written with the
        // rest as it stands, so a reopened workout carries on with it too.
        unfinishedSession = UnfinishedSession(snapshot: outgoing(snapshot), savedAt: Date())
    }

    /// A rest started, ended or was skipped without any wheel moving. Brings
    /// the written-down session up to date, so reopening the app after it was
    /// reclaimed neither loses a running rest nor revives a skipped one.
    func restChanged() {
        guard role == .driving, let snap = liveSnapshot else { return }
        unfinishedSession = UnfinishedSession(snapshot: outgoing(snap), savedAt: Date())
    }
    func checkpoint() { if role == .driving { sendContext() } }

    /// The local log view went away (quit/finished) — ends the session for both.
    func leaveSession() {
        let wasDriving = (role == .driving)
        role = .none
        liveSnapshot = nil
        adoptSnapshot = nil
        routeWorkoutId = nil
        snoozed = false
        if wasDriving { broadcastSessionEnded() }
        sendContext()
    }

    /// "Continue here" — take the active session onto this device.
    func reclaim() {
        requestTakeOver { [weak self] snap in
            guard let self else { return }
            guard let snap else {
                // Refused: the Watch is running an Apple workout and keeps it.
                // Standing by is the truth here, not "no session anywhere".
                if self.remoteAppleWorkout { self.role = .paused; return }
                self.role = .none; self.snoozed = false; self.routeWorkoutId = nil; return
            }
            self.adoptSnapshot = snap
            self.liveSnapshot = snap
            self.role = .driving
            self.snoozed = false
            self.routeWorkoutId = snap.workoutId
            self.broadcastDriverActive()
            self.sendContext()
        }
    }

    /// True while the Watch is running the workout as an Apple workout, which
    /// cannot be handed back: HealthKit will not move a session between
    /// devices, and half a workout in Fitness would be worse than none. The
    /// phone shows what is happening instead of offering to take it, and locks
    /// the screens that would change the workout underneath it.
    @Published private(set) var remoteAppleWorkout = false

    /// "Not now" — dismiss the Paused screen and browse normally.
    func dismissPaused() {
        role = .none
        snoozed = true
    }

    /// The Watch is running an Apple workout and the phone is standing by: the
    /// screens that would change the workout are locked, the ones that only
    /// read are not. Cleared when the Watch says the session ended.
    var isLockedByWatchWorkout: Bool { remoteAppleWorkout && role == .paused }

    /// Consume `adoptSnapshot` for `workoutId` (log view calls on appear/change).
    func takeAdoptSnapshot(for workoutId: String) -> SessionSnapshot? {
        guard let snap = adoptSnapshot, snap.workoutId == workoutId else { return nil }
        adoptSnapshot = nil
        return snap
    }

    /// Coming to the foreground only *checks* for an active session elsewhere and
    /// shows the Paused screen — it never takes over on its own.
    func onForeground() {
        checkAutoEnd()
        guard role == .none, !snoozed else { return }
        queryDriver { [weak self] isDriving, snap in
            guard let self, isDriving else { return }
            self.remoteSnapshot = snap
            self.role = .paused
        }
    }

    // MARK: - Handover messaging (outgoing)

    private func requestTakeOver(_ completion: @escaping (SessionSnapshot?) -> Void) {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else {
            completion(remoteSnapshot); return
        }
        // @Sendable so these are nonisolated: WatchConnectivity calls a reply
        // handler on its own queue, the same as it calls the delegate, and the
        // project's default would otherwise put them on the main actor. The
        // Watch trapped on exactly this, in its own requestSync.
        let finish = SendableAcrossQueues(completion)
        session.sendMessage(["type": "takeOver"], replyHandler: { @Sendable reply in
            let snap = (reply["snapshot"] as? Data)
                .flatMap { try? JSONDecoder().decode(SessionSnapshot.self, from: $0) }
            // The Watch can say no: an Apple workout stays where it is.
            if reply["refused"] as? Bool == true {
                DispatchQueue.main.async {
                    self.remoteAppleWorkout = true
                    self.role = .paused
                    finish.value(nil)
                }
                return
            }
            DispatchQueue.main.async { finish.value(snap ?? self.remoteSnapshot) }
        }, errorHandler: { @Sendable _ in
            DispatchQueue.main.async { finish.value(self.remoteSnapshot) }
        })
    }

    private func queryDriver(_ completion: @escaping (Bool, SessionSnapshot?) -> Void) {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else {
            completion(false, nil); return
        }
        let finish = SendableAcrossQueues(completion)
        session.sendMessage(["type": "queryDriver"], replyHandler: { @Sendable reply in
            let driving = reply["isDriving"] as? Bool ?? false
            let apple = reply["appleWorkout"] as? Bool ?? false
            let snap = (reply["snapshot"] as? Data)
                .flatMap { try? JSONDecoder().decode(SessionSnapshot.self, from: $0) }
            DispatchQueue.main.async {
                self.remoteAppleWorkout = driving && apple
                finish.value(driving, snap)
            }
        }, errorHandler: { @Sendable _ in
            DispatchQueue.main.async { finish.value(false, nil) }
        })
    }

    private func broadcastDriverActive() {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }
        var msg: [String: Any] = ["type": "driverActive"]
        if let snap = liveSnapshot, let d = try? JSONEncoder().encode(outgoing(snap)) { msg["snapshot"] = d }
        session.sendMessage(msg, replyHandler: nil, errorHandler: nil)
    }

    private func broadcastSessionEnded() {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }
        session.sendMessage(["type": "sessionEnded"], replyHandler: nil, errorHandler: nil)
    }

    // MARK: - Rest timer mirroring
    //
    // Only the end date travels, never a countdown: the Watch schedules its own
    // notification from that date, so it buzzes the wrist even with its screen
    // off and neither side has to stay awake.
    //
    // Sent ONLY while the Watch is reachable, and never handed to
    // transferUserInfo. Queued delivery is what would turn a walk out of range
    // into a burst of notifications for rests that finished long ago; a rest
    // the Watch misses is simply a rest the Watch misses.

    func sendRestTimer(endsAt: Date, total: Int, exercise: String) {
        // The length goes too: the Watch greys its screen across the whole
        // rest, and cannot tell how much of it has gone from the end alone.
        deliver(["type": "restTimer",
                 "endsAt": endsAt.timeIntervalSince1970,
                 "total": total,
                 "exercise": exercise])
    }

    func cancelRestTimerOnWatch() {
        deliver(["type": "restTimerCancelled"])
    }

    private func deliver(_ msg: [String: Any]) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated,
              session.isWatchAppInstalled,
              session.isReachable else { return }
        session.sendMessage(msg, replyHandler: nil, errorHandler: nil)
    }

    // MARK: - Aerobic sessions
    //
    // Only the Watch can run an HKWorkoutSession, so an aerobic exercise
    // started here asks the Watch to run one and then listens. Live sends
    // only, never queued: a workout instruction that turns up ten minutes late
    // would start a session for something already finished.

    /// Get the Watch running the workout, whether or not its app is open.
    ///
    /// Three routes on purpose, because the obvious one is not enough:
    ///
    ///   • `startWatchApp(toHandle:)` is the one that matters. WatchConnectivity
    ///     messages need "two actively running apps", so with the Watch app
    ///     closed — the ordinary case — a message goes nowhere: no session, no
    ///     heart rate, and nothing in Fitness. This launches the Watch app in
    ///     the background and hands it the configuration.
    ///   • The application context carries the name and the finishing time,
    ///     because a workout configuration has nowhere to put them. Context is
    ///     delivered on the counterpart's next launch even if it was not
    ///     running, which is exactly the case being served.
    ///   • The live message is kept for when the Watch app IS already open, so
    ///     it starts at once rather than waiting on a launch.
    func startAerobicOnWatch(activityRaw: String?, exercise: String, endsAt: Date) {
        aerobicContext = ["activity": activityRaw ?? "",
                          "exercise": exercise,
                          "endsAt": endsAt.timeIntervalSince1970]
        sendContext()

        var msg: [String: Any] = ["type": "aerobicStart", "exercise": exercise,
                                  "endsAt": endsAt.timeIntervalSince1970]
        if let activityRaw { msg["activity"] = activityRaw }
        deliver(msg)

        // No Watch app to launch, nothing to launch it for. The countdown on
        // this device runs regardless — it simply has no heart rate in it.
        guard WCSession.isSupported(),
              WCSession.default.activationState == .activated,
              WCSession.default.isWatchAppInstalled,
              HKHealthStore.isHealthDataAvailable() else { return }

        // Launching the Watch app for a workout needs this app authorised to
        // share workouts, and that authorisation was previously only ever asked
        // for by the "Save workouts to Apple Health" switch. Anyone who had
        // left that off would have had the launch refused with nothing to
        // explain it. Asked here so the aerobic feature stands on its own.
        let store = HKHealthStore()
        let configuration = WatchAerobicActivity.configuration(for: activityRaw)
        let workoutType = HKObjectType.workoutType()
        // Awaited rather than nested in a completion handler, which is not
        // only easier to read: the handler runs on a queue of HealthKit's
        // choosing, so the launch it called had to be carried across to the
        // main queue inside a closure, and a closure holding a health store
        // is not something Swift will let cross a thread.
        //
        // The answer is not examined at either step. A Watch that cannot be
        // launched, for want of permission or for any other reason, simply
        // means no heart rate, and the countdown on this device is unaffected.
        Task { @MainActor in
            if store.authorizationStatus(for: workoutType) == .notDetermined {
                try? await store.requestAuthorization(toShare: [workoutType], read: [])
            }
            store.startWatchApp(with: configuration) { _, _ in }
        }
    }

    func endAerobicOnWatch() {
        aerobicContext = nil
        sendContext()
        deliver(["type": "aerobicEnd"])
    }

    // MARK: - Incoming: watch logs
    private func handleIncomingLog(_ info: [String: Any]) {
        guard let type = info["type"] as? String, type == "logSet",
              let widStr = info["workoutId"] as? String, let wid = UUID(uuidString: widStr),
              let eidStr = info["exerciseId"] as? String, let eid = UUID(uuidString: eidStr)
        else { return }
        // Two keys, and which one is present says which build the Watch is on.
        // "weightsGrams" is this build; "weights" alone is a Watch that has not
        // updated yet, whose numbers are pounds or kilograms and would be a set
        // logged at a four-hundredth of its weight if taken for grams.
        let weights = info["weightsGrams"] as? [Int] ?? []
        let legacy  = info["weights"] as? [Int] ?? []
        let reps    = info["reps"] as? [Int] ?? []
        let date    = (info["date"] as? Double).map { Date(timeIntervalSince1970: $0) } ?? Date()
        let id      = (info["id"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID()
        // Present only for an aerobic exercise, and the phone stores whatever
        // the Watch measured rather than measuring again.
        let duration = info["durationSeconds"] as? Int
        store?.addWatchLog(id: id, date: date, workoutId: wid,
                           exerciseId: eid, weights: weights, reps: reps,
                           legacyWeights: legacy,
                           durationSeconds: duration,
                           averageHeartRate: info["averageHeartRate"] as? Int ?? 0,
                           maximumHeartRate: info["maximumHeartRate"] as? Int ?? 0,
                           zoneSeconds: info["zoneSeconds"] as? [Int] ?? [])
        noteActivity(at: date)
    }

    // A JSON decode and nothing else.
    private nonisolated func decodeSnapshot(_ any: Any?) -> SessionSnapshot? {
        (any as? Data).flatMap { try? JSONDecoder().decode(SessionSnapshot.self, from: $0) }
    }
}

// MARK: - WCSessionDelegate (iOS)
// Not on the main actor, and marked so.
//
// WatchConnectivity calls every one of these on a queue of its own, and the
// project's default puts anything unmarked on the main actor — which under
// Swift 6 is checked at the moment of the call, not assumed. The app trapped
// on launch in `dispatch_assert_queue` the first time the Watch session
// activated: a real crossing that Swift 5 let through in silence.
//
// The bodies were already written for it. Each one reads what it needs off
// the WCSession synchronously and hands the rest to the main queue, which is
// why marking the extension changes nothing about what runs where. It only
// says out loud where these arrive.
nonisolated extension PhoneSessionManager: WCSessionDelegate {

    func session(_ session: WCSession,
                 activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        let reachable = session.isReachable
        let installed = session.isWatchAppInstalled
        DispatchQueue.main.async {
            self.isWatchReachable = reachable
            self.watchAppInstalled = installed
            self.pushDefinitions()
        }
    }

    /// Paired, unpaired, or the Watch app installed or removed while we run.
    func sessionWatchStateDidChange(_ session: WCSession) {
        let installed = session.isWatchAppInstalled
        DispatchQueue.main.async {
            self.watchAppInstalled = installed
            self.pushDefinitions()
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        DispatchQueue.main.async {
            self.isWatchReachable = reachable
            if reachable { self.pushDefinitions() }
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let snap = decodeSnapshot(applicationContext["session"])
        DispatchQueue.main.async { self.remoteSnapshot = snap }
    }

    /// Queued deliveries — `transferUserInfo`.
    ///
    /// Routed through the SAME switch as a live message, which it was not.
    /// This went straight to the log handler, which ignores anything that is
    /// not a logged set, so every other kind of message silently vanished
    /// whenever it came this way. And it comes this way exactly when it
    /// matters: `transferUserInfo` is the fallback when the phone is not
    /// reachable, which at the end of a workout — phone in a locker, in a bag,
    /// app closed — is the normal case rather than the exception. A workout
    /// finished on the Watch was lost here, which is why nothing was offered
    /// afterwards even once the phone was opened.
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        self.session(session, didReceiveMessage: userInfo)
    }

    // Messages WITH a reply handler.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                 replyHandler: @escaping ([String: Any]) -> Void) {
        let answer = SendableAcrossQueues(replyHandler)
        switch message["type"] as? String {
        case "requestSync":
            let watchOS = message["watchOS"] as? String
            DispatchQueue.main.async {
                // Which watchOS is on the wrist, for the settings screen — see
                // `WatchSystemVersion`. Absent from a Watch build that predates
                // this, and then nothing is recorded.
                if let watchOS { WatchSystemVersion.record(watchOS) }
                self.watchOSMajor = WatchSystemVersion.major
                self.pushDefinitions()
                answer.value(["payload": self.store?.watchSyncPayloadData() ?? Data()])
            }
        case "queryDriver":
            DispatchQueue.main.async {
                let offer = self.sessionToOffer
                var reply: [String: Any] = ["isDriving": offer != nil]
                if let offer, let d = try? JSONEncoder().encode(offer) { reply["snapshot"] = d }
                answer.value(reply)
            }
        case "takeOver":
            DispatchQueue.main.async {
                // Built BEFORE anything here is stopped, so it carries the rest
                // as it was at the moment of hand-over.
                let snap = self.sessionToOffer
                if self.role == .driving { self.role = .paused }
                // The Watch owns the workout now, and the rest with it. Ended
                // here quietly — a cancel that told the Watch would arrive just
                // after it had picked the rest up, and end it there too.
                RestTimer.shared.handOver()
                // A killed phone handing over must not also reopen the workout
                // at its next launch: the Watch is carrying it now.
                self.forgetUnfinishedSession()
                var reply: [String: Any] = [:]
                if let snap, let d = try? JSONEncoder().encode(snap) { reply["snapshot"] = d }
                answer.value(reply)
            }
        default:
            let incoming = SendableAcrossQueues(message)
            DispatchQueue.main.async { self.handleIncomingLog(incoming.value) }
            answer.value([:])
        }
    }

    // Messages WITHOUT a reply handler.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        switch message["type"] as? String {
        case "aerobicStartedOnWatch":
            // The Watch is measuring; this device only shows the same countdown
            // so an open phone is not sitting on wheels for an exercise already
            // under way.
            let exercise = message["exercise"] as? String ?? ""
            let endsAt = (message["endsAt"] as? Double).map { Date(timeIntervalSince1970: $0) }
            Task { @MainActor in
                if let endsAt {
                    AerobicCountdown.shared.mirrorFromWatch(exercise: exercise, endsAt: endsAt)
                }
            }
        case "aerobicStopped":
            // Stopped on the wrist. The countdown here is the same session, so
            // it ends too rather than carrying on counting something nobody is
            // doing any more.
            Task { @MainActor in AerobicCountdown.shared.stopFromWatch() }
        case "heartRate":
            guard let bpm = message["bpm"] as? Int else { return }
            let zone = message["zone"] as? Int
            Task { @MainActor in
                AerobicCountdown.shared.receiveHeartRate(bpm, zone: zone)
            }
        case "restTimerCancelled":
            // Skipped on the Watch. Calls off the phone's rest so it does not
            // buzz later for a rest the user has already walked away from.
            Task { @MainActor in RestTimer.shared.cancel() }
        case "sessionEnded":
            DispatchQueue.main.async {
                if self.role != .none {
                    self.role = .none
                    self.routeWorkoutId = nil
                    self.adoptSnapshot = nil
                }
                self.snoozed = false
                self.remoteAppleWorkout = false
                self.remoteSnapshot = nil
            }
        case "driverActive":
            let snap = decodeSnapshot(message["snapshot"])
            let apple = message["appleWorkout"] as? Bool ?? false
            DispatchQueue.main.async {
                self.remoteSnapshot = snap
                self.snoozed = false
                self.remoteAppleWorkout = apple
                if let snap { self.noteWorkoutStarted(at: Date(timeIntervalSince1970: snap.startedAt)) }
                if self.role != .driving { self.role = .paused }
            }
        case "workoutFinished":
            // The Watch completed the workout — the phone is the sole Health
            // writer, so record it here using the times the Watch reported.
            let started = (message["startedAt"] as? Double).map { Date(timeIntervalSince1970: $0) }
            let ended = (message["endedAt"] as? Double).map { Date(timeIntervalSince1970: $0) } ?? Date()
            let finishedId = (message["workoutId"] as? String).flatMap(UUID.init(uuidString:))
            // The Watch wrote the HKWorkout itself in Apple-workout mode, so
            // this device must not write a second one — but everything else
            // about finishing still applies.
            let recordedOnWatch = message["recordedOnWatch"] as? Bool ?? false
            DispatchQueue.main.async {
                if let started {
                    self.finishWorkoutHere(startedAt: started, endedAt: ended,
                                           workoutId: finishedId,
                                           writeToHealth: !recordedOnWatch)
                } else { self.openWorkout = nil }
            }
        case "scheduleNext":
            // The wrist asked; this device writes. See
            // WatchSessionManager.requestSchedule for why it has to be here.
            let id = (message["workoutId"] as? String).flatMap(UUID.init(uuidString:))
            let starts = (message["starts"] as? [Double] ?? [])
                .map { Date(timeIntervalSince1970: $0) }
            let duration = message["durationSeconds"] as? Double ?? 0
            let ranFrom = (message["ranFrom"] as? Double).map { Date(timeIntervalSince1970: $0) }
            let ranTo = (message["ranTo"] as? Double).map { Date(timeIntervalSince1970: $0) }
            DispatchQueue.main.async {
                guard let id else { return }
                // No starts and no times is a message with nothing in it. No
                // starts WITH times is "not now", which still has something
                // to say: that this workout was done.
                let plans = !starts.isEmpty && duration > 0
                let ran = ranFrom != nil && ranTo != nil
                guard plans || ran else { return }
                self.scheduleRequestedFromWatch = ScheduleRequest(
                    workoutId: id, starts: plans ? starts : [], duration: duration,
                    ranFrom: ranFrom, ranTo: ranTo)
            }
        default:
            let incoming = SendableAcrossQueues(message)
            DispatchQueue.main.async { self.handleIncomingLog(incoming.value) }
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }
}
