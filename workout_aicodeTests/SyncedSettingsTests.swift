import Testing
import Foundation
import SwiftData
@testable import workout_aicode

// MARK: - The settings that travel
//
// This is the rule that decides whose settings everybody ends up with, so it
// is tested against a real store and a throwaway UserDefaults rather than
// tried out on three devices. Every test uses its own suite name, so nothing
// here can touch the preferences of whatever is running the tests.

@Suite struct SyncedSettingsTests {

    @MainActor private func store() throws -> ModelContext {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("settings-\(UUID().uuidString).sqlite")
        let container = try ModelContainer(
            for: Schema(versionedSchema: WorkoutLogSchemaV11.self),
            configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
        return ModelContext(container)
    }

    private func defaults() -> UserDefaults {
        let name = "srw-tests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    private func records(_ context: ModelContext) throws -> [AppSettings] {
        try context.fetch(FetchDescriptor<AppSettings>())
    }

    // MARK: Seeding

    @MainActor @Test func theFirstDeviceFillsItIn() throws {
        let context = try store()
        let d = defaults()
        d.set(42, forKey: WorkoutScheduleKey.daysAhead)

        #expect(SyncedSettings.sync(in: context, device: .iPhone, defaults: d) == .seeded)
        let all = try records(context)
        #expect(all.count == 1)
        #expect(all.first?.scheduleDaysAhead == 42)
        #expect(all.first?.seededBy == "iPhone")
    }

    // A setting that was never touched has to arrive as the app's own default,
    // not as the zero every field of the record starts at — CloudKit insists
    // on those zeros, and they are not what anybody chose.
    @MainActor @Test func anUntouchedSettingTravelsAsItsRealDefault() throws {
        let context = try store()
        let d = defaults()

        SyncedSettings.sync(in: context, device: .iPhone, defaults: d)
        let record = try #require(try records(context).first)
        #expect(record.scheduleDaysAhead == WorkoutSchedule.defaultDaysAhead)
        #expect(record.newExerciseIncrement == ExerciseDefaults.increment)
        #expect(record.watchZoneTint == WatchPreferences.defaultZoneTint)
        #expect(record.prefillAcrossWorkouts == PrefillScope.defaultAcrossWorkouts)
    }

    // MARK: The phone's answers win

    @MainActor @Test func aPhoneArrivingAfterAMacTakesTheRecordOver() throws {
        let context = try store()
        let mac = defaults()
        mac.set(9, forKey: WorkoutScheduleKey.daysAhead)
        #expect(SyncedSettings.sync(in: context, device: .Mac, defaults: mac) == .seeded)

        let phone = defaults()
        phone.set(3, forKey: WorkoutScheduleKey.daysAhead)
        #expect(SyncedSettings.sync(in: context, device: .iPhone, defaults: phone)
                == .claimedByPhone)

        let record = try #require(try records(context).first)
        #expect(record.scheduleDaysAhead == 3)
        #expect(record.seededBy == "iPhone")
    }

    // Once. A second phone is just another device, and must not undo what the
    // first one settled.
    @MainActor @Test func aSecondPhoneDoesNotTakeItOverAgain() throws {
        let context = try store()
        let first = defaults()
        first.set(3, forKey: WorkoutScheduleKey.daysAhead)
        SyncedSettings.sync(in: context, device: .iPhone, defaults: first)

        let second = defaults()
        second.set(11, forKey: WorkoutScheduleKey.daysAhead)
        #expect(SyncedSettings.sync(in: context, device: .iPhone, defaults: second)
                == .adopted)
        #expect(second.integer(forKey: WorkoutScheduleKey.daysAhead) == 3)
    }

    @MainActor @Test func aMacArrivingAfterAPhoneAdoptsWhatItFinds() throws {
        let context = try store()
        let phone = defaults()
        phone.set(false, forKey: WorkoutScheduleKey.enabled)
        phone.set(5, forKey: WorkoutScheduleKey.count)
        SyncedSettings.sync(in: context, device: .iPhone, defaults: phone)

        let mac = defaults()
        mac.set(1, forKey: WorkoutScheduleKey.count)
        #expect(SyncedSettings.sync(in: context, device: .Mac, defaults: mac) == .adopted)
        #expect(mac.integer(forKey: WorkoutScheduleKey.count) == 5)
    }

    // MARK: Changing something

    @MainActor @Test func aChangeMadeHereReachesTheRecord() throws {
        let context = try store()
        let d = defaults()
        SyncedSettings.sync(in: context, device: .Mac, defaults: d)

        d.set(true, forKey: WorkoutGrouping.enabledKey)
        #expect(SyncedSettings.sync(in: context, device: .Mac, defaults: d) == .published)
        #expect(try #require(try records(context).first).scheduleByGroup)
    }

    @MainActor @Test func runningAgainWithNothingChangedWritesNothing() throws {
        let context = try store()
        let d = defaults()
        SyncedSettings.sync(in: context, device: .Mac, defaults: d)
        #expect(SyncedSettings.sync(in: context, device: .Mac, defaults: d) == .alreadyInStep)
        #expect(SyncedSettings.sync(in: context, device: .Mac, defaults: d) == .alreadyInStep)
    }

    // What the mirror is for: a value set on one device turns up on the other.
    @MainActor @Test func whatOneDeviceSetsAnotherReads() throws {
        let context = try store()
        let phone = defaults()
        SyncedSettings.sync(in: context, device: .iPhone, defaults: phone)

        let mac = defaults()
        SyncedSettings.sync(in: context, device: .Mac, defaults: mac)
        mac.set(true, forKey: WorkoutScheduleKey.enabled)
        mac.set(7, forKey: WorkoutScheduleKey.daysAhead)
        mac.set(2, forKey: WatchPreferences.wheelRowsKey)
        #expect(SyncedSettings.sync(in: context, device: .Mac, defaults: mac) == .published)

        #expect(SyncedSettings.sync(in: context, device: .iPhone, defaults: phone) == .adopted)
        #expect(phone.bool(forKey: WorkoutScheduleKey.enabled))
        #expect(phone.integer(forKey: WorkoutScheduleKey.daysAhead) == 7)
        #expect(phone.integer(forKey: WatchPreferences.wheelRowsKey) == 2)
    }

    // MARK: Duplicates

    // CloudKit has no uniqueness, so two devices that have never seen each
    // other both make the first record. Newest wins and the rest go.
    // The reason `revision` exists rather than a date comparison: a Date put
    // through the store comes back a ten-millionth of a second later than it
    // went in, so "newer than what I last took" was true for ever and nothing
    // a device changed was ever published. See AppSettings.revision.
    @MainActor @Test func aDeviceKeepsPublishingItsOwnChanges() throws {
        let context = try store()
        let d = defaults()
        SyncedSettings.sync(in: context, device: .iPhone, defaults: d)
        try context.save()

        for taps in [3, 4, 5] {
            d.set(taps, forKey: WatchPreferences.restTapsKey)
            #expect(SyncedSettings.sync(in: context, device: .iPhone, defaults: d)
                    == .published)
            #expect(try #require(try records(context).first).watchRestTaps == taps)
            try context.save()
        }
    }

    @MainActor @Test func duplicateRecordsAreResolvedToTheNewest() throws {
        let context = try store()
        let older = AppSettings()
        older.updatedAt = Date(timeIntervalSince1970: 1_000)
        older.scheduleDaysAhead = 2
        let newer = AppSettings()
        newer.updatedAt = Date(timeIntervalSince1970: 2_000)
        newer.scheduleDaysAhead = 8
        context.insert(older); context.insert(newer)
        try context.save()

        let kept = try #require(SyncedSettings.resolve(in: context))
        #expect(kept.scheduleDaysAhead == 8)
        #expect(try records(context).count == 1)
    }

    // MARK: What does not travel

    // Health sharing, the body-weight source, the calendar, the sharing
    // consent and the iCloud switch are each a fact about ONE device. A
    // settings record that carried them would have an iPad claiming a
    // HealthKit permission nobody granted it.
    @MainActor @Test func theDeviceOnlySettingsAreNotMirrored() {
        let mirrored = SyncedSettings.mirroredKeys
        #expect(!mirrored.contains("healthSharingEnabled"))
        #expect(!mirrored.contains("iCloudSyncEnabled"))
        #expect(!mirrored.contains(BodyWeight.sourceKey))
        #expect(!mirrored.contains(WorkoutScheduleKey.calendar))
        #expect(!mirrored.contains(SharingKey.consent))
        // Spelled out rather than through MacAppearanceKey, which is the
        // Mac target's and not in this one.
        #expect(!mirrored.contains("macTextSize"))
        // And the bookkeeping key is not a setting either.
        #expect(!mirrored.contains(SyncedSettings.adoptedRevisionKey))
    }

    @MainActor @Test func everySettingThatTravelsIsListedOnce() {
        #expect(SyncedSettings.mirroredKeys.count == SyncedSettings.fields.count)
        #expect(SyncedSettings.fields.count == 21)
    }
}
