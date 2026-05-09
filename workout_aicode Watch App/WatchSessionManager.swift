import Foundation
import Combine
import WatchConnectivity

// MARK: - WatchSessionManager
//
// Manages the WatchConnectivity session on the watchOS side.
//
// Responsibilities:
//   • Activate WCSession at launch (App entry point holds a @StateObject).
//   • Receive "setStart" messages from the iPhone and expose the exercise
//     context as @Published properties so ContentView reacts automatically.
//   • Own a WatchRepCounter that auto-counts reps via CoreMotion when the
//     exercise has a movementType other than "none".
//   • Expose manual +/- rep buttons so the user can correct the count.
//   • Send "setComplete" back to the iPhone when the user taps Done, then
//     reset local state so the next setStart feels fresh.

@MainActor
final class WatchSessionManager: NSObject, ObservableObject {

    static let shared = WatchSessionManager()

    // MARK: Context received from iPhone

    /// Display name of the exercise currently being logged.
    @Published private(set) var exerciseName: String    = ""

    /// Raw string of MovementType enum — used by future CoreMotion layer to
    /// select the correct peak-detection algorithm.
    @Published private(set) var movementTypeRaw: String = "none"

    /// Which set of the exercise the user is logging (1-based).
    @Published private(set) var setNumber: Int          = 1

    /// Previous rep count for this exercise — shown as a target on the watch.
    @Published private(set) var targetReps: Int         = 0

    /// Weight suggested based on the last log entry.
    @Published private(set) var suggestedWeight: Int    = 0

    // MARK: Live rep counter (manual tap OR CoreMotion auto-count)
    @Published var repCount: Int = 0

    /// True while the CoreMotion counter is actively sampling.
    /// ContentView uses this to show the "AUTO" badge.
    var isAutoCountingActive: Bool { repCounter.isRunning }

    /// Convenience: true when there is an active exercise context to display.
    var isActive: Bool { !exerciseName.isEmpty }

    private let repCounter = WatchRepCounter()

    private override init() {
        super.init()
        // Wire up CoreMotion rep callback — fires on main thread.
        repCounter.onRep = { [weak self] in
            guard let self else { return }
            self.repCount += 1
        }
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Rep counter actions

    func incrementRep() {
        repCount += 1
    }

    func decrementRep() {
        repCount = max(0, repCount - 1)
    }

    /// Finalise the set: stop CoreMotion, send the rep count to the iPhone,
    /// then reset to idle.
    func completeSet() {
        repCounter.stop()
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(
                ["type": "setComplete", "count": repCount],
                replyHandler: nil
            )
        }
        // Back to idle — ContentView will show the "open iPhone" screen
        // until the next setStart arrives.
        exerciseName = ""
        repCount     = 0
    }
}

// MARK: - WCSessionDelegate (watchOS)
extension WatchSessionManager: WCSessionDelegate {

    // WatchConnectivity calls these on its own internal queue — always
    // hop to the main thread before touching @Published properties.

    func session(_ session: WCSession,
                 activationDidCompleteWith state: WCSessionActivationState,
                 error: Error?) {}

    func session(_ session: WCSession,
                 didReceiveMessage message: [String: Any]) {
        guard let type = message["type"] as? String,
              type == "setStart" else { return }

        let name    = message["exerciseName"]    as? String ?? ""
        let mvType  = message["movementType"]    as? String ?? "none"
        let setNum  = message["setNumber"]       as? Int    ?? 1
        let target  = message["targetReps"]      as? Int    ?? 0
        let weight  = message["suggestedWeight"] as? Int    ?? 0

        DispatchQueue.main.async {
            self.exerciseName    = name
            self.movementTypeRaw = mvType
            self.setNumber       = setNum
            self.targetReps      = target
            self.suggestedWeight = weight
            self.repCount        = 0   // reset counter for the new set
            // Start CoreMotion auto-counting (no-ops for movementType == "none")
            self.repCounter.start(movementTypeRaw: mvType)
        }
    }
}
