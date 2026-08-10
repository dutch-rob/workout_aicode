import Foundation
import Combine
import WatchConnectivity

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

    // MARK: - Apple Health: open-workout tracking
    //
    // The phone tracks the in-progress workout (start + last activity) and, if it
    // is left un-ended, auto-finalizes it after an hour of inactivity — assuming
    // it ended at the last logged set (so a forgotten workout isn't hours long).

    private struct OpenWorkout: Codable { var startedAt: Date; var lastActivityAt: Date }
    private let openWorkoutKey = "openHealthWorkout"
    private let autoEndAfter: TimeInterval = 3600   // 1 hour

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

    /// A workout began (on either device). Finalizes any stale prior one first.
    func noteWorkoutStarted(at date: Date) {
        if let w = openWorkout, abs(w.startedAt.timeIntervalSince(date)) < 1 { return }
        finalizeAbandonedOpenWorkout()
        openWorkout = OpenWorkout(startedAt: date, lastActivityAt: date)
    }

    /// A set was logged (on either device) — extend the workout's activity time.
    func noteActivity(at date: Date = Date()) {
        if var w = openWorkout {
            if date > w.lastActivityAt { w.lastActivityAt = date; openWorkout = w }
        } else {
            openWorkout = OpenWorkout(startedAt: date, lastActivityAt: date)
        }
    }

    /// The workout ended on THIS (phone) device — either by finishing every
    /// exercise or by quitting early. Both count as a workout, so both are saved
    /// (as long as at least one set was actually logged).
    func finishWorkoutHere(startedAt: Date, endedAt: Date) {
        let hadActivity = openWorkout.map { $0.lastActivityAt > $0.startedAt } ?? false
        openWorkout = nil
        guard healthEnabled, hadActivity, endedAt > startedAt else { return }
        // Deferred on purpose: HealthKit may put its permission sheet on screen,
        // and must never block the log screen from closing first.
        DispatchQueue.main.async {
            HealthWorkoutLogger.shared.saveStrengthWorkout(start: startedAt, end: endedAt)
        }
    }

    /// A prior workout was left open and superseded/abandoned — save it capped at
    /// its last activity, then forget it.
    private func finalizeAbandonedOpenWorkout() {
        guard let w = openWorkout else { return }
        if healthEnabled, w.lastActivityAt > w.startedAt {
            HealthWorkoutLogger.shared.saveStrengthWorkout(start: w.startedAt, end: w.lastActivityAt)
        }
        openWorkout = nil
    }

    /// Called on launch / foreground: finalize a workout left un-ended for > 1h.
    func checkAutoEnd() {
        guard let w = openWorkout else { return }
        if Date().timeIntervalSince(w.lastActivityAt) > autoEndAfter {
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
        if role == .driving, let snap = liveSnapshot, let d = try? JSONEncoder().encode(snap) {
            ctx["session"] = d
        }
        guard !ctx.isEmpty else { return }
        try? session.updateApplicationContext(ctx)
    }

    // MARK: - Handover: called by the log view / app

    /// The local log view opened `workoutId` and becomes the driver. Adopts the
    /// other device's state if it was already in the same workout.
    func enterSession(workoutId: String, current: SessionSnapshot,
                      adopt: @escaping (SessionSnapshot) -> Void) {
        liveSnapshot = current
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

    func updateLiveSnapshot(_ snapshot: SessionSnapshot) { liveSnapshot = snapshot }
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

    /// "Not now" — dismiss the Paused screen and browse normally.
    func dismissPaused() {
        role = .none
        snoozed = true
    }

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
        session.sendMessage(["type": "takeOver"], replyHandler: { reply in
            let snap = (reply["snapshot"] as? Data)
                .flatMap { try? JSONDecoder().decode(SessionSnapshot.self, from: $0) }
            DispatchQueue.main.async { completion(snap ?? self.remoteSnapshot) }
        }, errorHandler: { _ in
            DispatchQueue.main.async { completion(self.remoteSnapshot) }
        })
    }

    private func queryDriver(_ completion: @escaping (Bool, SessionSnapshot?) -> Void) {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else {
            completion(false, nil); return
        }
        session.sendMessage(["type": "queryDriver"], replyHandler: { reply in
            let driving = reply["isDriving"] as? Bool ?? false
            let snap = (reply["snapshot"] as? Data)
                .flatMap { try? JSONDecoder().decode(SessionSnapshot.self, from: $0) }
            DispatchQueue.main.async { completion(driving, snap) }
        }, errorHandler: { _ in
            DispatchQueue.main.async { completion(false, nil) }
        })
    }

    private func broadcastDriverActive() {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }
        var msg: [String: Any] = ["type": "driverActive"]
        if let snap = liveSnapshot, let d = try? JSONEncoder().encode(snap) { msg["snapshot"] = d }
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

    func sendRestTimer(endsAt: Date, exercise: String) {
        deliver(["type": "restTimer",
                 "endsAt": endsAt.timeIntervalSince1970,
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

    // MARK: - Incoming: watch logs
    private func handleIncomingLog(_ info: [String: Any]) {
        guard let type = info["type"] as? String, type == "logSet",
              let widStr = info["workoutId"] as? String, let wid = UUID(uuidString: widStr),
              let eidStr = info["exerciseId"] as? String, let eid = UUID(uuidString: eidStr)
        else { return }
        let weights = info["weights"] as? [Int] ?? []
        let reps    = info["reps"] as? [Int] ?? []
        let date    = (info["date"] as? Double).map { Date(timeIntervalSince1970: $0) } ?? Date()
        let id      = (info["id"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID()
        store?.addWatchLog(id: id, date: date, workoutId: wid,
                           exerciseId: eid, weights: weights, reps: reps)
        noteActivity(at: date)
    }

    private func decodeSnapshot(_ any: Any?) -> SessionSnapshot? {
        (any as? Data).flatMap { try? JSONDecoder().decode(SessionSnapshot.self, from: $0) }
    }
}

// MARK: - WCSessionDelegate (iOS)
extension PhoneSessionManager: WCSessionDelegate {

    func session(_ session: WCSession,
                 activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        let reachable = session.isReachable
        DispatchQueue.main.async {
            self.isWatchReachable = reachable
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

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        DispatchQueue.main.async { self.handleIncomingLog(userInfo) }
    }

    // Messages WITH a reply handler.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                 replyHandler: @escaping ([String: Any]) -> Void) {
        switch message["type"] as? String {
        case "requestSync":
            DispatchQueue.main.async {
                self.pushDefinitions()
                replyHandler(["payload": self.store?.watchSyncPayloadData() ?? Data()])
            }
        case "queryDriver":
            DispatchQueue.main.async {
                var reply: [String: Any] = ["isDriving": self.role == .driving]
                if self.role == .driving, let snap = self.liveSnapshot,
                   let d = try? JSONEncoder().encode(snap) { reply["snapshot"] = d }
                replyHandler(reply)
            }
        case "takeOver":
            DispatchQueue.main.async {
                let snap = self.liveSnapshot
                if self.role == .driving { self.role = .paused }
                var reply: [String: Any] = [:]
                if let snap, let d = try? JSONEncoder().encode(snap) { reply["snapshot"] = d }
                replyHandler(reply)
            }
        default:
            DispatchQueue.main.async { self.handleIncomingLog(message) }
            replyHandler([:])
        }
    }

    // Messages WITHOUT a reply handler.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        switch message["type"] as? String {
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
                self.remoteSnapshot = nil
            }
        case "driverActive":
            let snap = decodeSnapshot(message["snapshot"])
            DispatchQueue.main.async {
                self.remoteSnapshot = snap
                self.snoozed = false
                if let snap { self.noteWorkoutStarted(at: Date(timeIntervalSince1970: snap.startedAt)) }
                if self.role != .driving { self.role = .paused }
            }
        case "workoutFinished":
            // The Watch completed the workout — the phone is the sole Health
            // writer, so record it here using the times the Watch reported.
            let started = (message["startedAt"] as? Double).map { Date(timeIntervalSince1970: $0) }
            let ended = (message["endedAt"] as? Double).map { Date(timeIntervalSince1970: $0) } ?? Date()
            DispatchQueue.main.async {
                if let started { self.finishWorkoutHere(startedAt: started, endedAt: ended) }
                else { self.openWorkout = nil }
            }
        default:
            DispatchQueue.main.async { self.handleIncomingLog(message) }
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }
}
