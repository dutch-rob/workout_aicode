import Foundation
import CoreMotion

// MARK: - WatchRepCounter
//
// Drives automatic rep-counting from CMMotionManager device-motion data.
//
// Algorithm per update (50 Hz):
//   1. Extract the relevant axis from CMDeviceMotion based on movementType.
//   2. Apply an EMA low-pass filter to the absolute signal value.
//   3. Ignore the first `warmUpSamples` so the filter can settle.
//   4. Threshold + hysteresis:  enter "peak" state when ema > peakThreshold;
//      exit when ema < resetThreshold, then arm for the next rep.
//
// Movement type → axis mapping
//   vertical   → userAcceleration.y  (lat pull-down, overhead press, …)
//   horizontal → userAcceleration.x  (row, machine chest press, …)
//   rotational → rotationRate.z      (bicep curl, hammer curl, lateral raise, …)
//   none       → no motion started   (manual counting only)
//
// Thread safety:
//   start() / stop() are called on the main thread (@MainActor WatchSessionManager).
//   CMMotionManager delivers updates on OperationQueue.main, so process() also runs
//   on main — onRep is therefore already main-thread and needs no extra dispatch.

final class WatchRepCounter {

    // MARK: - Public interface

    /// Called on the main thread each time a rep is detected.
    var onRep: (() -> Void)?

    /// True while CoreMotion is actively sampling.
    private(set) var isRunning = false

    // MARK: - Configuration (tweakable without recompile)

    private let updateInterval: TimeInterval = 1.0 / 50  // 50 Hz
    private let emaAlpha: Double             = 0.30       // smoothing factor (0 < α ≤ 1)
    private let warmUpSamples: Int           = 25         // ~0.5 s at 50 Hz

    // MARK: - Axis abstraction

    private enum Axis {
        case y, x, rotZ, none

        /// Peak threshold: signal must *exceed* this to count as a rep peak.
        /// Linear axes are in g-units; rotational is in rad/s.
        var peakThreshold: Double  { self == .rotZ ? 1.2 : 0.7 }

        /// Reset threshold: signal must *fall below* this before the next rep
        /// can be detected (hysteresis band).
        var resetThreshold: Double { self == .rotZ ? 0.4 : 0.2 }

        static func from(_ raw: String) -> Axis {
            switch raw {
            case "vertical":   return .y
            case "horizontal": return .x
            case "rotational": return .rotZ
            default:           return .none
            }
        }
    }

    // MARK: - State

    private let motion = CMMotionManager()
    private var axis:        Axis   = .none
    private var ema:         Double = 0
    private var inPeak:      Bool   = false
    private var sampleCount: Int    = 0

    // MARK: - Lifecycle

    /// Start sampling for the given movementType raw value.
    /// Calling start() while already running first calls stop() (clean slate).
    func start(movementTypeRaw: String) {
        stop()

        guard motion.isDeviceMotionAvailable else {
            print("[WatchRepCounter] device motion unavailable (simulator?)")
            return
        }

        let a = Axis.from(movementTypeRaw)
        guard a != .none else { return }   // manual mode — nothing to start

        axis        = a
        ema         = 0
        inPeak      = false
        sampleCount = 0
        isRunning   = true

        motion.deviceMotionUpdateInterval = updateInterval
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            self.process(data)
        }
        print("[WatchRepCounter] started (\(movementTypeRaw))")
    }

    /// Stop sampling. Safe to call when not running.
    func stop() {
        guard isRunning else { return }
        motion.stopDeviceMotionUpdates()
        isRunning = false
        print("[WatchRepCounter] stopped")
    }

    // MARK: - Signal processing (runs on main thread via OperationQueue.main)

    private func process(_ data: CMDeviceMotion) {
        // Extract raw signal for this exercise type
        let raw: Double
        switch axis {
        case .y:    raw = data.userAcceleration.y
        case .x:    raw = data.userAcceleration.x
        case .rotZ: raw = data.rotationRate.z
        case .none: return
        }

        // EMA low-pass filter on absolute value
        ema = emaAlpha * abs(raw) + (1.0 - emaAlpha) * ema

        // Skip first N samples while filter settles
        sampleCount += 1
        guard sampleCount > warmUpSamples else { return }

        // Threshold + hysteresis peak detection
        let peak  = axis.peakThreshold
        let reset = axis.resetThreshold

        if !inPeak && ema > peak {
            inPeak = true
            onRep?()   // already on main thread
        } else if inPeak && ema < reset {
            inPeak = false
        }
    }
}
