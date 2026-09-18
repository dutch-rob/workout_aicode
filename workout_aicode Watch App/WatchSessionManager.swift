import Foundation
import Combine
import WatchConnectivity

// MARK: - WatchSessionManager
//
// watchOS side of WatchConnectivity.
//
//   • Receives / pulls workout & exercise definitions from the iPhone.
//   • Sends completed sets back to the iPhone.
//   • Participates in the single-driver "handover" session. Handover is
//     TAP-ONLY: opening / glancing at the Watch never moves the session; it
//     only shows a Paused screen offering "Continue here". See PhoneSessionManager
//     for the full protocol description.

enum HandoverRole { case none, driving, paused }

@MainActor
final class WatchSessionManager: NSObject, ObservableObject {

    static let shared = WatchSessionManager()

    // MARK: Definitions from the iPhone
    @Published private(set) var workouts: [SyncWorkout]  = []
    @Published private(set) var exercises: [SyncExercise] = []
    /// The phone's rest-timer switch. Off until a payload says otherwise, so a
    /// Watch that has not heard from the phone never invents a rest.
    @Published private(set) var restTimerEnabled = false
    private var lastEntries: [String: SyncLastEntry] = [:]

    // MARK: Handover session state
    @Published private(set) var role: HandoverRole = .none
    @Published var routeWorkoutId: String? = nil
    @Published private(set) var adoptSnapshot: SessionSnapshot? = nil

    private var liveSnapshot: SessionSnapshot?
    private var remoteSnapshot: SessionSnapshot?
    private var snoozed = false

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    #if DEBUG
    /// Load screenshot sample data (see DemoMode.swift).
    func loadDemoData() {
        workouts    = DemoMode.workouts
        exercises   = DemoMode.exercises
        lastEntries = DemoMode.lastEntries
    }
    /// Force the Paused screen for a screenshot of the hand-over prompt.
    func showDemoPaused() { role = .paused }
    #endif

    // MARK: - Lookups
    func workout(id: String) -> SyncWorkout? { workouts.first { $0.id == id } }
    func exercise(id: String) -> SyncExercise? { exercises.first { $0.id == id } }
    func lastEntry(workoutId: String, exerciseId: String) -> SyncLastEntry? {
        lastEntries[SyncPayload.lastEntryKey(workoutId: workoutId, exerciseId: exerciseId)]
    }

    // MARK: - Ingest phone application context (definitions + session stash)
    private func ingest(context: [String: Any]) {
        #if DEBUG
        // Screenshot runs must show the demo data and nothing else. A simulator
        // keeps the last received application context inside the app's data
        // container, so without this an old context from a previously paired
        // phone gets replayed on activation and silently replaces the seed.
        if DemoMode.isEnabled { return }
        #endif
        if let data = context["payload"] as? Data,
           let payload = try? JSONDecoder().decode(SyncPayload.self, from: data) {
            workouts    = payload.workouts
            exercises   = payload.exercises
            lastEntries = payload.lastEntries
            restTimerEnabled = payload.restTimerEnabled
        }
        // Left by the phone for a Watch app that was not running when the
        // aerobic session began — which is the usual way it begins.
        if let aerobic = context["aerobic"] as? [String: Any] {
            let exercise = aerobic["exercise"] as? String ?? ""
            let endsAt = (aerobic["endsAt"] as? Double).map { Date(timeIntervalSince1970: $0) }
            Task { @MainActor in
                WatchAerobicWorkout.shared.describe(exercise: exercise, endsAt: endsAt)
            }
        }
        // The phone stashes its driving snapshot here (nil when it isn't
        // driving). Only believed while fresh: a phone reclaimed by iOS never
        // gets to clear it, and a workout abandoned yesterday must not be
        // offered for taking over today.
        remoteSnapshot = decodeSnapshot(context["session"]).flatMap { $0.isFresh() ? $0 : nil }
    }

    // MARK: - Pull definitions
    func requestSync() {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }
        session.sendMessage(["type": "requestSync"], replyHandler: { [weak self] reply in
            DispatchQueue.main.async { self?.ingest(context: reply) }
        }, errorHandler: nil)
    }

    // MARK: - Send a completed set
    func logSet(workoutId: String, exerciseId: String, weights: [Int], reps: [Int],
                aerobic: WatchAerobicWorkout.Summary? = nil) {
        var info: [String: Any] = [
            "type": "logSet", "id": UUID().uuidString,
            "date": Date().timeIntervalSince1970,
            "workoutId": workoutId, "exerciseId": exerciseId,
            "weights": weights, "reps": reps
        ]
        if let aerobic {
            info["durationSeconds"] = aerobic.durationSeconds
            info["averageHeartRate"] = aerobic.averageHeartRate
            info["maximumHeartRate"] = aerobic.maximumHeartRate
            info["zoneSeconds"] = aerobic.zoneSeconds
        }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        if session.isReachable {
            session.sendMessage(info, replyHandler: nil, errorHandler: { _ in
                session.transferUserInfo(info)
            })
        } else {
            session.transferUserInfo(info)
        }
    }

    // MARK: - Handover: called by the log view / app

    func enterSession(workoutId: String, current: SessionSnapshot,
                      adopt: @escaping (SessionSnapshot) -> Void) {
        liveSnapshot = current
        adoptSnapshot = nil
        routeWorkoutId = nil
        role = .driving
        snoozed = false
        requestTakeOver { [weak self] snap in
            guard let self else { return }
            if let snap, snap.workoutId == workoutId {
                self.liveSnapshot = snap
                adopt(snap)
            }
            self.sendSessionContext()
        }
        broadcastDriverActive()
        sendSessionContext()
    }

    func updateLiveSnapshot(_ snapshot: SessionSnapshot) { liveSnapshot = snapshot }

    /// A snapshot as it leaves the Watch: the rest as it stands this moment,
    /// and when. Stamped on the way out, because skipping a rest moves no
    /// wheel — the last recorded snapshot would still say it was running.
    private func outgoing(_ snap: SessionSnapshot) -> SessionSnapshot {
        var s = snap
        let rest = WatchRestTimer.shared
        s.restEndsAt = rest.endsAt?.timeIntervalSince1970
        s.restTotal = rest.endsAt == nil ? nil : rest.totalSeconds
        s.updatedAt = Date().timeIntervalSince1970
        return s
    }
    func checkpoint() { if role == .driving { sendSessionContext() } }

    /// The workout was completed on the Watch: tell the phone the times so it
    /// records the workout to Apple Health (the phone is the sole Health writer).
    func finishWorkout(startedAt: Date, endedAt: Date) {
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        let msg: [String: Any] = [
            "type": "workoutFinished",
            "startedAt": startedAt.timeIntervalSince1970,
            "endedAt": endedAt.timeIntervalSince1970
        ]
        if session.isReachable {
            session.sendMessage(msg, replyHandler: nil, errorHandler: { _ in
                session.transferUserInfo(msg)
            })
        } else {
            session.transferUserInfo(msg)
        }
    }

    func leaveSession() {
        let wasDriving = (role == .driving)
        role = .none
        liveSnapshot = nil
        adoptSnapshot = nil
        routeWorkoutId = nil
        snoozed = false
        if wasDriving { broadcastSessionEnded() }
        sendSessionContext()
    }

    /// "Continue here" — take the active session onto the Watch.
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
            self.sendSessionContext()
        }
    }

    /// "Not now" — dismiss the Paused screen and browse normally.
    func dismissPaused() {
        role = .none
        snoozed = true
    }

    func takeAdoptSnapshot(for workoutId: String) -> SessionSnapshot? {
        guard let snap = adoptSnapshot, snap.workoutId == workoutId else { return nil }
        adoptSnapshot = nil
        return snap
    }

    /// Coming forward pulls fresh definitions and *checks* (never takes over)
    /// whether the phone is driving, showing the Paused screen if so.
    func onForeground() {
        requestSync()
        checkForDriver()
    }

    /// Is the phone in the middle of a workout? If so, show the Paused screen
    /// with "Continue here".
    ///
    /// Asked from two places. Coming back to the foreground, as before — and
    /// when the connection to the phone has finished setting up. The second is
    /// what a cold launch needed: `onChange(of: scenePhase)` does not fire for
    /// the phase an app STARTS in, and before activation the question cannot
    /// be sent anyway. So opening the Watch app from scratch mid-workout went
    /// straight to the workout list, and the session was only picked up once
    /// the workout was tapped.
    ///
    /// If the phone cannot be asked, the snapshot it last left in the
    /// application context stands in — provided it is fresh.
    func checkForDriver() {
        guard role == .none, !snoozed else { return }
        queryDriver { [weak self] isDriving, snap in
            guard let self, self.role == .none, !self.snoozed else { return }
            if isDriving {
                self.remoteSnapshot = snap ?? self.remoteSnapshot
                self.role = .paused
            } else if snap == nil, let stashed = self.remoteSnapshot, stashed.isFresh() {
                // No answer (as opposed to "no, I am not driving"): go by what
                // the phone last said.
                self.role = .paused
            }
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

    /// Calls back with (driving, snapshot). A phone that ANSWERED "not
    /// driving" clears the stashed snapshot, so only a phone that could not be
    /// reached leaves the stash standing for `checkForDriver` to fall back on.
    private func queryDriver(_ completion: @escaping (Bool, SessionSnapshot?) -> Void) {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else {
            completion(false, nil); return
        }
        session.sendMessage(["type": "queryDriver"], replyHandler: { reply in
            let driving = reply["isDriving"] as? Bool ?? false
            let snap = (reply["snapshot"] as? Data)
                .flatMap { try? JSONDecoder().decode(SessionSnapshot.self, from: $0) }
            DispatchQueue.main.async {
                if !driving { self.remoteSnapshot = nil }
                completion(driving, snap)
            }
        }, errorHandler: { _ in
            DispatchQueue.main.async { completion(false, nil) }
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

    private func sendSessionContext() {
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        var ctx: [String: Any] = ["ts": Date().timeIntervalSince1970]
        if role == .driving, let snap = liveSnapshot, let d = try? JSONEncoder().encode(outgoing(snap)) {
            ctx["session"] = d
        }
        try? session.updateApplicationContext(ctx)
    }


    // MARK: - Rest timer (phone-driven)
    //
    // Live messages only — the phone never queues these, so nothing arrives
    // late enough to schedule a notification for a rest that is already over.

    private func handleRestTimer(_ msg: [String: Any]) -> Bool {
        switch msg["type"] as? String {
        case "restTimer":
            guard let ends = msg["endsAt"] as? Double else { return true }
            let name = msg["exercise"] as? String ?? ""
            let total = msg["total"] as? Int
            Task { @MainActor in
                WatchRestTimer.shared.requestNotificationPermission()
                WatchRestTimer.shared.mirror(endsAt: Date(timeIntervalSince1970: ends),
                                             total: total, exercise: name)
            }
            return true
        case "restTimerCancelled":
            Task { @MainActor in WatchRestTimer.shared.cancel() }
            return true
        default:
            return false
        }
    }

    /// Skipping here calls off the phone's rest too, so the phone does not
    /// buzz for a rest the user has already finished with. Live send only, for
    /// the same reason the phone never queues these.
    func cancelRestTimerOnPhone() {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }
        session.sendMessage(["type": "restTimerCancelled"], replyHandler: nil, errorHandler: nil)
    }

    // MARK: - Aerobic sessions (phone-driven)
    //
    // Only the Watch can run an HKWorkoutSession, so the phone asks and this
    // obliges. Live messages only, like the rest timer: an instruction to start
    // a workout that arrives ten minutes late would start one for a session
    // already over.

    private func handleAerobic(_ msg: [String: Any]) -> Bool {
        switch msg["type"] as? String {
        case "aerobicStart":
            let activity = msg["activity"] as? String
            let exercise = msg["exercise"] as? String ?? ""
            let endsAt = (msg["endsAt"] as? Double).map { Date(timeIntervalSince1970: $0) }
            Task { @MainActor in
                WatchAerobicWorkout.shared.describe(exercise: exercise, endsAt: endsAt)
                await WatchAerobicWorkout.shared.start(activityRaw: activity,
                                                       exercise: exercise)
            }
            return true
        case "aerobicEnd":
            Task { @MainActor in _ = await WatchAerobicWorkout.shared.finish() }
            return true
        default:
            return false
        }
    }

    /// Started on the wrist. The phone does not measure anything for this, but
    /// an open phone should show the same exercise counting down rather than
    /// its wheels.
    func reportAerobicStarted(exercise: String, endsAt: Date) {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }
        session.sendMessage(["type": "aerobicStartedOnWatch",
                             "exercise": exercise,
                             "endsAt": endsAt.timeIntervalSince1970],
                            replyHandler: nil, errorHandler: nil)
    }

    /// Stopped on the wrist — the phone's countdown is the same session.
    func reportAerobicStopped() {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }
        session.sendMessage(["type": "aerobicStopped"], replyHandler: nil, errorHandler: nil)
    }

    /// One heart-rate reading on its way to the phone, with the zone it fell
    /// in — worked out here because this is the device allowed to read the
    /// resting rate and date of birth the boundaries come from.
    func sendHeartRate(_ beatsPerMinute: Int, zone: Int?) {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }
        var msg: [String: Any] = ["type": "heartRate", "bpm": beatsPerMinute]
        if let zone { msg["zone"] = zone }
        session.sendMessage(msg, replyHandler: nil, errorHandler: nil)
    }

    private func decodeSnapshot(_ any: Any?) -> SessionSnapshot? {
        (any as? Data).flatMap { try? JSONDecoder().decode(SessionSnapshot.self, from: $0) }
    }
}

// MARK: - WCSessionDelegate (watchOS)
extension WatchSessionManager: WCSessionDelegate {

    func session(_ session: WCSession,
                 activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        let context = session.receivedApplicationContext
        DispatchQueue.main.async {
            self.ingest(context: context)
            self.requestSync()
            // The cold-launch half of the Paused check — see checkForDriver.
            self.checkForDriver()
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { self.requestSync() }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        DispatchQueue.main.async { self.ingest(context: applicationContext) }
    }

    // Messages WITH a reply handler.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                 replyHandler: @escaping ([String: Any]) -> Void) {
        switch message["type"] as? String {
        case "queryDriver":
            DispatchQueue.main.async {
                var reply: [String: Any] = ["isDriving": self.role == .driving]
                if self.role == .driving, let snap = self.liveSnapshot,
                   let d = try? JSONEncoder().encode(self.outgoing(snap)) { reply["snapshot"] = d }
                replyHandler(reply)
            }
        case "takeOver":
            DispatchQueue.main.async {
                // Stamped before the rest is let go, so it travels as it was.
                let snap = self.liveSnapshot.map(self.outgoing)
                if self.role == .driving { self.role = .paused }
                // The phone carries the rest on from here. cancel() is local —
                // it tells the phone nothing, which is the point: a message
                // now would end the rest the phone has just picked up.
                WatchRestTimer.shared.cancel()
                var reply: [String: Any] = [:]
                if let snap, let d = try? JSONEncoder().encode(snap) { reply["snapshot"] = d }
                replyHandler(reply)
            }
        default:
            replyHandler([:])
        }
    }

    // Messages WITHOUT a reply handler.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if handleRestTimer(message) { return }
        if handleAerobic(message) { return }
        switch message["type"] as? String {
        case "sessionEnded":
            DispatchQueue.main.async {
                Task { @MainActor in
                    WatchRestTimer.shared.cancel()
                    _ = await WatchAerobicWorkout.shared.finish()
                }
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
                if self.role != .driving { self.role = .paused }
            }
        default:
            break
        }
    }
}
