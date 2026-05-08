import Foundation
import Combine
import WatchConnectivity

// MARK: - PhoneSessionManager
//
// Manages the WatchConnectivity session on the iPhone side.
//
// Responsibilities:
//   • Activate WCSession early (called from App init).
//   • Send the current exercise context to the Watch whenever the user
//     navigates to a new exercise in the log screen ("setStart" message).
//   • Receive "setComplete" messages from the Watch and expose the rep
//     count via `completedRepCount` + a UUID trigger so SwiftUI onChange
//     fires exactly once per completed set.
//
// Usage:
//   PhoneSessionManager.shared.sendSetContext(...)   // from LogExerciseView
//   .onChange(of: watchSession.setCompleteTrigger)   // react in LogExerciseView

@MainActor
final class PhoneSessionManager: NSObject, ObservableObject {

    static let shared = PhoneSessionManager()

    /// True when the paired Watch is reachable right now.
    @Published private(set) var isWatchReachable = false

    /// The rep count sent by the Watch after the user taps "Done" on watch.
    @Published private(set) var completedRepCount: Int = 0

    /// Changes to a new UUID each time the Watch completes a set, giving
    /// SwiftUI's onChange a unique value to react to.
    @Published private(set) var setCompleteTrigger: UUID = UUID()

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Outgoing

    /// Send exercise context to the Watch when the user lands on an exercise.
    /// Safe to call even when Watch is not reachable — the message is silently
    /// dropped in that case.
    func sendSetContext(exerciseName: String,
                        movementType: MovementType,
                        setNumber: Int,
                        targetReps: Int,
                        suggestedWeight: Int) {
        guard WCSession.default.isReachable else { return }
        let msg: [String: Any] = [
            "type":            "setStart",
            "exerciseName":    exerciseName,
            "movementType":    movementType.rawValue,
            "setNumber":       setNumber,
            "targetReps":      targetReps,
            "suggestedWeight": suggestedWeight
        ]
        WCSession.default.sendMessage(msg, replyHandler: nil)
    }
}

// MARK: - WCSessionDelegate (iOS)
extension PhoneSessionManager: WCSessionDelegate {

    // WatchConnectivity calls these on its own internal queue — always
    // hop to the main thread before touching @Published properties.

    func session(_ session: WCSession,
                 activationDidCompleteWith state: WCSessionActivationState,
                 error: Error?) {
        let reachable = session.isReachable
        DispatchQueue.main.async { self.isWatchReachable = reachable }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        DispatchQueue.main.async { self.isWatchReachable = reachable }
    }

    func session(_ session: WCSession,
                 didReceiveMessage message: [String: Any]) {
        guard let type = message["type"] as? String,
              type == "setComplete" else { return }
        let count = message["count"] as? Int ?? 0
        DispatchQueue.main.async {
            self.completedRepCount  = count
            self.setCompleteTrigger = UUID()   // unique value → onChange fires once
        }
    }

    // Required on iOS (not needed on watchOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
}
