import Foundation
import WatchConnectivity

// MARK: - WatchSessionManager
//
// Manages the WatchConnectivity session on the watchOS side.
//
// Responsibilities:
//   • Activate WCSession at launch (App entry point holds a @StateObject).
//   • Receive "setStart" messages from the iPhone and expose the exercise
//     context as @Published properties so ContentView reacts automatically.
//   • Expose a manual rep counter (+/-) that the user can tap on the crown
//     dial or buttons.
//   • Send "setComplete" back to the iPhone when the user taps Done, then
//     reset local state so the next setStart feels fresh.
//
// Next step (CoreMotion layer, separate commit):
//   WatchRepCounter will read movementTypeRaw and start CMMotionManager
//   peak-detection, driving repCount automatically instead of manually.

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

    // MARK: Live rep counter (manual; CoreMotion auto-count added later)
    @Published var repCount: Int = 0

    /// Convenience: true when there is an active exercise context to display.
    var isActive: Bool { !exerciseName.isEmpty }

    private override init() {
        super.init()
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

    /// Finalise the set: send the rep count to the iPhone, then reset to idle.
    func completeSet() {
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

    func session(_ session: WCSession,
                 activationDidCompleteWith state: WCSessionActivationState,
                 error: Error?) {}

    func session(_ session: WCSession,
                 didReceiveMessage message: [String: Any]) {
        guard let type = message["type"] as? String,
              type == "setStart" else { return }

        exerciseName    = message["exerciseName"]    as? String ?? ""
        movementTypeRaw = message["movementType"]    as? String ?? "none"
        setNumber       = message["setNumber"]       as? Int    ?? 1
        targetReps      = message["targetReps"]      as? Int    ?? 0
        suggestedWeight = message["suggestedWeight"] as? Int    ?? 0
        repCount        = 0   // reset counter for the new set
    }
}
