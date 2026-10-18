import Foundation

/// Where the numbers a wheel opens on come from.
///
/// The app used to look only at logs from the SAME workout, which is wrong as
/// soon as a routine is split in two: a new workout that reuses exercises from
/// an old one opened every wheel at nothing, although those exercises had been
/// logged for months.
///
/// It is not simply a bug, though, which is why it is a setting. Someone whose
/// "heavy day" and "light day" share a bench press wants each workout to
/// remember its own numbers; someone who has just reorganised their routine
/// wants the exercise's own history to follow it across.
enum PrefillScope {
    static let key = "prefillAcrossWorkouts"

    /// Default: an exercise remembers its own last session, whichever workout
    /// it was logged in.
    static let defaultAcrossWorkouts = true

    static var acrossWorkouts: Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? defaultAcrossWorkouts
    }
}
