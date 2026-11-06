import Foundation
import SwiftData
#if os(iOS)
import UIKit
#endif

// MARK: - Keeping the settings that travel in step with UserDefaults
//
// `AppSettings` is the copy of record and reaches every device through iCloud;
// `UserDefaults` is what the app actually READS, everywhere it always did.
// This file is the only thing that knows both, and it keeps them equal.
//
// It is a mirror rather than a rewrite on purpose. Thirty-odd `@AppStorage`
// bindings, `WorkoutSchedule.isEnabled`, `WatchPreferences.zoneTint` and the
// payload the Watch is sent all read UserDefaults from a static context; going
// through the store at each of those would have meant a context where there is
// none, on three platforms, for no gain. Mirroring leaves every reader alone.
//
// The rules, in order:
//
//   • There may be more than one record. CloudKit has no uniqueness, so two
//     devices can both make the first one before either has seen the other's.
//     The newest `updatedAt` wins and the rest are deleted — `resolve`.
//   • A record newer than what this device last took is adopted, overwriting
//     local values. Last writer wins, per record, which is what CloudKit does
//     with everything else here.
//   • Otherwise, if this device's defaults disagree with the record, this
//     device changed something and the record is brought up to date.
//   • The first device to arrive fills it in. If that was a Mac or an iPad,
//     the first iPhone to arrive overwrites it ONCE — the phone is where these
//     were set and where the training happens — and after that `seededBy` says
//     "iPhone" and nobody overwrites anybody again.
//
// The Watch is not part of any of this. It has no store; it is told what it
// needs in `SyncPayload`, which the phone builds from UserDefaults as before.

enum SyncedSettings {

    /// Which revision of the record this device last took. Its own, never
    /// mirrored — it is a fact about this device, not a setting.
    ///
    /// A counter rather than a date: see `AppSettings.revision` for what
    /// comparing dates across the store does.
    static let adoptedRevisionKey = "syncedSettingsAdoptedRevision"

    enum DeviceClass: String {
        case iPhone, iPad, Mac
    }

    /// What this device calls itself in `seededBy`.
    static var thisDevice: DeviceClass {
        #if os(macOS)
        return .Mac
        #elseif os(iOS)
        return UIDeviceIsPad() ? .iPad : .iPhone
        #else
        return .iPhone
        #endif
    }

    // MARK: The fields

    /// One mirrored setting: how to move a value between the record and
    /// UserDefaults, and how to tell whether the two already agree.
    ///
    /// Built by `field` so the key, the stored property and the app's own
    /// default are named once each. Three parallel lists would have been three
    /// chances to forget one.
    struct Field {
        let key: String
        let adopt: (AppSettings, UserDefaults) -> Void
        let capture: (AppSettings, UserDefaults) -> Void
        let agrees: (AppSettings, UserDefaults) -> Bool
    }

    private static func field<V: DefaultsValue>(
        _ path: ReferenceWritableKeyPath<AppSettings, V>,
        _ key: String, or fallback: V) -> Field {
        Field(key: key,
              adopt: { record, defaults in
                  V.write(record[keyPath: path], to: defaults, forKey: key)
              },
              capture: { record, defaults in
                  record[keyPath: path] = V.read(defaults, forKey: key) ?? fallback
              },
              agrees: { record, defaults in
                  (V.read(defaults, forKey: key) ?? fallback) == record[keyPath: path]
              })
    }

    /// Everything that travels. What is missing from this list is missing on
    /// purpose — see the comment on `AppSettings` for which and why.
    static let fields: [Field] = [
        field(\.weightUnitRaw, WeightUnit.key, or: WeightUnit.regionDefault.rawValue),
        field(\.bodyWeightManual, BodyWeight.manualKey, or: 0),

        field(\.prefillAcrossWorkouts, PrefillScope.key, or: PrefillScope.defaultAcrossWorkouts),
        field(\.restTimerEnabled, RestTimerKey.enabled, or: false),
        field(\.restDefaultSeconds, RestTimerKey.defaultSeconds, or: defaultRestSeconds),

        field(\.newExerciseSets, ExerciseDefaultsKey.sets, or: ExerciseDefaults.sets),
        field(\.newExerciseLowest, ExerciseDefaultsKey.lowest, or: ExerciseDefaults.lowest),
        field(\.newExerciseHighest, ExerciseDefaultsKey.highest, or: ExerciseDefaults.highest),
        field(\.newExerciseIncrement, ExerciseDefaultsKey.increment, or: ExerciseDefaults.increment),

        field(\.statsFormulaRaw, StatsSettingsKey.formula, or: OneRMFormula.epley.rawValue),
        field(\.statsWindow, StatsSettingsKey.window, or: StatsEngine.defaultWindow),
        field(\.statsSmoothing, StatsSettingsKey.smoothing, or: StatsEngine.defaultSmoothing),

        field(\.scheduleEnabled, WorkoutScheduleKey.enabled, or: false),
        field(\.scheduleDaysAhead, WorkoutScheduleKey.daysAhead, or: WorkoutSchedule.defaultDaysAhead),
        field(\.scheduleCount, WorkoutScheduleKey.count, or: WorkoutSchedule.defaultCount),
        field(\.scheduleByGroup, WorkoutGrouping.enabledKey, or: false),

        field(\.watchWorkoutModeRaw, WatchWorkoutMode.key, or: WatchWorkoutMode.handover.rawValue),
        field(\.watchZoneTint, WatchPreferences.zoneTintKey, or: WatchPreferences.defaultZoneTint),
        field(\.watchRestTaps, WatchPreferences.restTapsKey, or: WatchPreferences.defaultRestTaps),
        field(\.watchWheelRows, WatchPreferences.wheelRowsKey, or: WatchPreferences.defaultWheelRows),
        field(\.watchZoneBoundaries, WatchPreferences.zoneBoundariesKey, or: ""),
    ]

    /// The keys this file owns, for anything that wants to know whether a
    /// UserDefaults change was one of ours.
    static var mirroredKeys: Set<String> { Set(fields.map(\.key)) }

    // MARK: Moving the values

    static func adopt(_ record: AppSettings, into defaults: UserDefaults = .standard) {
        for field in fields { field.adopt(record, defaults) }
    }

    static func capture(into record: AppSettings, from defaults: UserDefaults = .standard) {
        for field in fields { field.capture(record, defaults) }
    }

    static func agree(_ record: AppSettings, _ defaults: UserDefaults = .standard) -> Bool {
        fields.allSatisfy { $0.agrees(record, defaults) }
    }

    // MARK: The one record

    /// The record to use, with any duplicates removed.
    ///
    /// Duplicates are not a fault to be reported, they are a thing CloudKit
    /// allows: two devices that have never seen each other both make the
    /// first one. Newest wins, because that is the rule everywhere else here.
    static func resolve(in context: ModelContext) -> AppSettings? {
        let all = (try? context.fetch(FetchDescriptor<AppSettings>())) ?? []
        guard let keep = all.max(by: { $0.updatedAt < $1.updatedAt }) else { return nil }
        guard all.count > 1 else { return keep }
        for spare in all where spare.id != keep.id { context.delete(spare) }
        // Saved here rather than left to the caller: the branches that adopt
        // or find nothing to do do not save, and a deletion left sitting in
        // the context would be re-found as a duplicate on the next run.
        StoreSave.save(context, doing: "removing a duplicate settings record")
        return keep
    }

    // MARK: The step every device runs

    /// Brings this device and the record into agreement. Safe to call often:
    /// it writes only when something actually differs.
    ///
    /// `now` and `defaults` are arguments so a test can run the whole rule
    /// without a clock or the real preferences.
    @discardableResult
    static func sync(in context: ModelContext,
                     device: DeviceClass = thisDevice,
                     defaults: UserDefaults = .standard,
                     now: Date = Date()) -> Outcome {
        let adopted = defaults.integer(forKey: adoptedRevisionKey)
        let neverSynced = defaults.object(forKey: adoptedRevisionKey) == nil

        guard let record = resolve(in: context) else {
            let made = AppSettings()
            capture(into: made, from: defaults)
            made.seededBy = device.rawValue
            made.revision = 1
            made.updatedAt = now
            context.insert(made)
            mark(adopted: made.revision, in: defaults)
            StoreSave.save(context, doing: "writing the shared settings")
            return .seeded
        }

        // A Mac or an iPad filled it in before any phone had been opened. The
        // phone's answers are the ones that were actually chosen, so they
        // replace what was put there — once, and never again afterwards.
        if device == .iPhone, record.seededBy != DeviceClass.iPhone.rawValue, neverSynced {
            capture(into: record, from: defaults)
            record.seededBy = DeviceClass.iPhone.rawValue
            record.revision += 1
            record.updatedAt = now
            mark(adopted: record.revision, in: defaults)
            StoreSave.save(context, doing: "writing the shared settings")
            return .claimedByPhone
        }

        if record.revision > adopted {
            adopt(record, into: defaults)
            mark(adopted: record.revision, in: defaults)
            return .adopted
        }

        if !agree(record, defaults) {
            capture(into: record, from: defaults)
            record.revision += 1
            record.updatedAt = now
            mark(adopted: record.revision, in: defaults)
            StoreSave.save(context, doing: "writing the shared settings")
            return .published
        }

        return .alreadyInStep
    }

    enum Outcome: Equatable {
        /// There was no record; this device's values became the shared ones.
        case seeded
        /// A Mac or iPad had seeded it; this phone's values replaced them.
        case claimedByPhone
        /// Another device had written since this one last looked.
        case adopted
        /// This device had changed something; the record now says so.
        case published
        case alreadyInStep
    }

    private static func mark(adopted revision: Int, in defaults: UserDefaults) {
        defaults.set(revision, forKey: adoptedRevisionKey)
    }
}

// MARK: - Reading and writing one value of UserDefaults

/// What a mirrored setting may be stored as.
///
/// `read` returns nil when the key has never been set, so the caller can put
/// the app's own default there rather than a zero — which matters because
/// every field of `AppSettings` has to default to zero or empty for CloudKit.
protocol DefaultsValue: Equatable {
    static func read(_ defaults: UserDefaults, forKey key: String) -> Self?
    static func write(_ value: Self, to defaults: UserDefaults, forKey key: String)
}

extension Bool: DefaultsValue {
    static func read(_ d: UserDefaults, forKey key: String) -> Bool? {
        d.object(forKey: key) == nil ? nil : d.bool(forKey: key)
    }
    static func write(_ value: Bool, to d: UserDefaults, forKey key: String) {
        d.set(value, forKey: key)
    }
}

extension Int: DefaultsValue {
    static func read(_ d: UserDefaults, forKey key: String) -> Int? {
        d.object(forKey: key) == nil ? nil : d.integer(forKey: key)
    }
    static func write(_ value: Int, to d: UserDefaults, forKey key: String) {
        d.set(value, forKey: key)
    }
}

extension Double: DefaultsValue {
    /// Through `double(forKey:)` rather than a cast, because a value written
    /// as a whole number comes back as an Int and a cast would miss it — the
    /// same reason `ExerciseDefaults` reads its weights through NSNumber.
    static func read(_ d: UserDefaults, forKey key: String) -> Double? {
        d.object(forKey: key) == nil ? nil : d.double(forKey: key)
    }
    static func write(_ value: Double, to d: UserDefaults, forKey key: String) {
        d.set(value, forKey: key)
    }
}

extension String: DefaultsValue {
    static func read(_ d: UserDefaults, forKey key: String) -> String? {
        d.string(forKey: key)
    }
    static func write(_ value: String, to d: UserDefaults, forKey key: String) {
        d.set(value, forKey: key)
    }
}

#if os(iOS)
private func UIDeviceIsPad() -> Bool {
    UIDevice.current.userInterfaceIdiom == .pad
}
#endif
