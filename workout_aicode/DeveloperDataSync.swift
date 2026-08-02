import Foundation
import CloudKit
import OSLog

// MARK: - Opt-in sharing of anonymised training data
//
// Uploads logged sets and survey answers to the app's CloudKit *public*
// database so patterns across users can inform what the app does next —
// particularly the individualised advice the survey asks about.
//
// OFF until the user turns it on. Training logs are health data, which needs
// explicit consent rather than a pre-ticked box, and the app's info text
// promises that nothing leaves the device unless the user says so.
//
// What is uploaded, per set: a random per-install id, the date, weight, reps,
// and which movement it was. What is NOT uploaded: any name — not the user's,
// not the workout's, not the exercise's. A user's own exercise name is
// replaced by a salted hash, which groups that user's sets without revealing
// the text; library exercises additionally carry their stable key, which is
// what makes the same movement comparable BETWEEN users.
//
// Turning the switch off deletes everything this install uploaded.

private let log = Logger(subsystem: "robotex.workout-aicode", category: "DataSync")

enum SharingKey {
    static let consent = "shareDataWithDevs"
}

enum DeveloperDataSync {

    private static let installIDKey = "developerShareInstallID"
    private static let saltKey      = "developerShareNameSalt"
    private static let uploadedKey  = "developerShareUploadedLogIDs"
    private static let surveyKey    = "developerSharePendingSurvey"
    /// Set when a withdrawal could not be completed, for Settings to show.
    static let withdrawProblemKey = "developerShareWithdrawProblem"
    /// Same, for uploads — which until now failed entirely silently, leaving
    /// nothing to look at on a build with no console.
    static let uploadProblemKey = "developerShareUploadProblem"
    /// What the last upload attempt did, so "is it working?" has an answer.
    static let uploadStatusKey = "developerShareUploadStatus"

    private static var database: CKDatabase { CKContainer.default().publicCloudDatabase }
    private static var defaults: UserDefaults { .standard }

    /// Random per-install identifier — not the Apple ID, not the device id.
    /// Lets one user's rows be grouped without identifying who they are.
    static var installID: String {
        if let s = defaults.string(forKey: installIDKey) { return s }
        let s = UUID().uuidString
        defaults.set(s, forKey: installIDKey)
        return s
    }

    /// Per-install salt for hashing exercise names. Without it, a hash of a
    /// common name like "Bench press" would be identical across users and the
    /// dictionary attack is trivial — the salt keeps a user's own names
    /// groupable to themselves and meaningless to anyone else.
    private static var nameSalt: String {
        if let s = defaults.string(forKey: saltKey) { return s }
        let s = UUID().uuidString
        defaults.set(s, forKey: saltKey)
        return s
    }

    private static func hashedName(_ name: String) -> String {
        let normalised = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in Data((nameSalt + "|" + normalised).utf8) {
            hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
        return String(hash, radix: 36)
    }

    // MARK: Flattened, already-anonymised upload payload

    /// A value copy taken on the main actor, so the CloudKit work never touches
    /// SwiftData objects from another thread.
    struct LogLite {
        let id: String
        let date: Date
        let weights: [Int]
        let reps: [Int]
        /// Library movement key, when the exercise came from the library.
        let libraryKey: String?
        /// Salted hash of the user's exercise name — never the name itself.
        let exerciseHash: String
        let primaryMuscle: String?
        let secondaryMuscles: [String]
        /// Derived here so the stored numbers can be checked against the
        /// formulas the app actually used.
        let bestOneRM: Double?
        let hardSets: Int

        init(log: WorkoutLog, exercise: ExerciseDef?, formula: OneRMFormula) {
            self.id = log.id.uuidString
            self.date = log.date
            self.weights = log.weights
            self.reps = log.reps
            self.libraryKey = exercise?.libraryKey
            self.exerciseHash = hashedName(exercise?.name ?? "")
            self.primaryMuscle = exercise?.primaryMuscle?.rawValue
            self.secondaryMuscles = exercise?.secondaryMuscles.map(\.rawValue) ?? []
            let session = ExerciseSession(id: log.id, date: log.date,
                                          weights: log.weights, reps: log.reps,
                                          formula: formula)
            self.bestOneRM = session?.m1RM
            self.hardSets = session?.hardSetCount ?? 0
        }

        func record(install: String, formula: OneRMFormula) -> CKRecord {
            let rec = CKRecord(recordType: "SharedSet",
                               recordID: CKRecord.ID(recordName: "set-\(install)-\(id)"))
            rec["install"]      = install
            rec["ts"]           = date
            rec["weights"]      = weights.map(String.init).joined(separator: ",")
            rec["reps"]         = reps.map(String.init).joined(separator: ",")
            rec["setCount"]     = weights.count
            rec["libraryKey"]   = libraryKey ?? ""
            rec["exerciseHash"] = exerciseHash
            rec["primary"]      = primaryMuscle ?? ""
            rec["secondary"]    = secondaryMuscles.joined(separator: ",")
            rec["bestOneRM"]    = (bestOneRM?.isFinite == true) ? bestOneRM! : 0
            rec["hardSets"]     = hardSets
            rec["formula"]      = formula.rawValue
            return rec
        }
    }

    // MARK: Sync

    /// Upload anything not yet sent when consent is on; delete everything this
    /// install ever sent when consent is off.
    static func sync(consent: Bool, logs: [WorkoutLog], exercises: [ExerciseDef],
                     formula: OneRMFormula) {
        guard consent else {
            Task { await withdraw() }
            return
        }
        let byId = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let snapshot = logs.map { LogLite(log: $0, exercise: byId[$0.exerciseId], formula: formula) }
        Task { await upload(logs: snapshot, formula: formula) }
    }

    private static func upload(logs: [LogLite], formula: OneRMFormula) async {
        let install = installID
        var uploaded = Set(defaults.stringArray(forKey: uploadedKey) ?? [])

        var records = logs.filter { !uploaded.contains($0.id) }
                          .map { $0.record(install: install, formula: formula) }
        if let survey = pendingSurveyRecord(install: install) { records.append(survey) }
        guard !records.isEmpty else {
            // Not an error, but worth saying: everything on this device is
            // already marked as sent. That is also what it looks like when the
            // rows were deleted straight from the CloudKit console — the app
            // still believes it sent them. Turning sharing off and on again
            // clears the record and re-sends.
            defaults.set("nothing new to send — all \(logs.count) already sent",
                         forKey: uploadStatusKey)
            defaults.removeObject(forKey: uploadProblemKey)
            log.notice("Nothing to upload: all \(logs.count, privacy: .public) already sent.")
            return
        }

        do {
            // atomically:false does NOT throw on per-record failures, so each
            // result is inspected: only what actually saved is marked as sent,
            // and the rest is retried next time rather than silently lost.
            let result = try await database.modifyRecords(saving: records, deleting: [],
                                                          savePolicy: .allKeys, atomically: false)
            var saved = 0, failed = 0
            var firstFailure: String?
            for (recordID, res) in result.saveResults {
                switch res {
                case .success:
                    saved += 1
                    let prefix = "set-\(install)-"
                    if recordID.recordName.hasPrefix(prefix) {
                        uploaded.insert(String(recordID.recordName.dropFirst(prefix.count)))
                    }
                    if recordID.recordName.hasPrefix("survey-") {
                        defaults.removeObject(forKey: surveyKey)
                    }
                case .failure(let error):
                    failed += 1
                    if firstFailure == nil { firstFailure = describe(error) }
                    log.error("Save failed \(recordID.recordName, privacy: .public): \(describe(error), privacy: .public)")
                }
            }
            defaults.set(Array(uploaded), forKey: uploadedKey)
            defaults.set("sent \(saved), failed \(failed)", forKey: uploadStatusKey)
            if failed == 0 {
                defaults.removeObject(forKey: uploadProblemKey)
            } else {
                defaults.set("\(failed) of \(records.count) refused — \(firstFailure ?? "")",
                             forKey: uploadProblemKey)
            }
            log.notice("Upload finished: \(saved, privacy: .public) saved, \(failed, privacy: .public) failed.")
        } catch {
            defaults.set("could not reach iCloud — \(describe(error))", forKey: uploadProblemKey)
            defaults.set("last attempt failed", forKey: uploadStatusKey)
            log.error("Upload failed: \(describe(error), privacy: .public)")
        }
    }

    /// Called by "Delete all my data": take back everything shared, too.
    ///
    /// Deleting your data has to mean all of it. The install id and salt are
    /// deliberately KEPT: if the withdrawal fails because the device is
    /// offline, they are the only way to find those rows and delete them on a
    /// later run — throwing them away would strand the records for good.
    static func withdrawEverything() {
        Task { await withdraw() }
        defaults.removeObject(forKey: surveyKey)
    }

    /// Consent withdrawn: remove every record this install created. Best
    /// effort — if the network is down the ids stay on file so a later run
    /// tries again.
    private static func withdraw() async {
        let install = installID
        let uploaded = defaults.stringArray(forKey: uploadedKey) ?? []
        let hadSurvey = defaults.data(forKey: surveyKey) != nil
        guard !uploaded.isEmpty || hadSurvey else { return }

        var ids = uploaded.map { CKRecord.ID(recordName: "set-\(install)-\($0)") }
        ids.append(CKRecord.ID(recordName: "survey-\(install)"))

        do {
            let result = try await database.modifyRecords(saving: [], deleting: ids,
                                                          atomically: false)
            // Every result must be inspected. With atomically:false a failed
            // delete does NOT throw — an earlier version discarded this and
            // cleared the record of what had been uploaded regardless, so a
            // refused delete looked like success AND destroyed the only list of
            // what still needed deleting. Nothing could ever remove those rows
            // afterwards.
            var gone = Set<String>()
            var failures: [String] = []
            for (recordID, res) in result.deleteResults {
                switch res {
                case .success:
                    gone.insert(recordID.recordName)
                case .failure(let error):
                    // Already absent is the outcome we wanted anyway.
                    if let ck = error as? CKError, ck.code == .unknownItem {
                        gone.insert(recordID.recordName)
                    } else {
                        failures.append("\(recordID.recordName): \(describe(error))")
                    }
                }
            }

            // Keep whatever did not go, so the next attempt can try again.
            let prefix = "set-\(install)-"
            let remaining = uploaded.filter { !gone.contains(prefix + $0) }
            if remaining.isEmpty {
                defaults.removeObject(forKey: uploadedKey)
            } else {
                defaults.set(remaining, forKey: uploadedKey)
            }
            if gone.contains("survey-\(install)") {
                defaults.removeObject(forKey: surveyKey)
            }

            if failures.isEmpty {
                defaults.removeObject(forKey: withdrawProblemKey)
                log.notice("Withdrew \(gone.count, privacy: .public) records.")
            } else {
                // Carry the reason, not just a count: this message is the only
                // way to see why CloudKit refused, on a build with no console.
                defaults.set("\(failures.count) of \(ids.count) refused — \(failures[0])",
                             forKey: withdrawProblemKey)
                log.error("Withdraw incomplete: \(failures.joined(separator: "; "), privacy: .public)")
            }
        } catch {
            // Operation-level failure: nothing was deleted, so nothing is
            // forgotten and the next run retries the lot.
            defaults.set("could not reach iCloud", forKey: withdrawProblemKey)
            log.error("Withdraw failed: \(describe(error), privacy: .public)")
        }
    }

    /// Retry a withdrawal that did not finish — called at launch.
    ///
    /// Without this, a withdrawal refused while offline (or by a permission
    /// problem) would never be attempted again, and rows the user asked to have
    /// removed would stay for good.
    static func retryWithdrawIfPending() {
        guard !defaults.bool(forKey: SharingKey.consent) else { return }
        let pending = defaults.stringArray(forKey: uploadedKey) ?? []
        guard !pending.isEmpty || defaults.data(forKey: surveyKey) != nil else { return }
        log.notice("Retrying an unfinished withdrawal of \(pending.count, privacy: .public) records.")
        Task { await withdraw() }
    }

    /// Human-readable CloudKit error, including the code and any per-item
    /// partial errors, so a failure is not just "CAS failed".
    private static func describe(_ error: Error) -> String {
        guard let ck = error as? CKError else { return error.localizedDescription }
        var parts = ["CKError \(ck.errorCode) (\(ck.localizedDescription))"]
        for (item, e) in (ck.partialErrorsByItemID ?? [:]) {
            parts.append("[\(item): \(e.localizedDescription)]")
        }
        return parts.joined(separator: " ")
    }

    // MARK: Survey

    /// Stored locally first. If consent is off it simply stays there and is
    /// never sent; if the user later turns sharing on, it goes with the next
    /// upload rather than being lost.
    static func recordSurvey(_ answers: SurveyAnswers, consent: Bool) {
        if let data = try? JSONEncoder().encode(answers) {
            defaults.set(data, forKey: surveyKey)
        }
        guard consent else { return }
        Task { await upload(logs: [], formula: .epley) }
    }

    private static func pendingSurveyRecord(install: String) -> CKRecord? {
        guard let data = defaults.data(forKey: surveyKey),
              let a = try? JSONDecoder().decode(SurveyAnswers.self, from: data)
        else { return nil }
        let rec = CKRecord(recordType: "SharedSurvey",
                           recordID: CKRecord.ID(recordName: "survey-\(install)"))
        rec["install"]       = install
        rec["ts"]            = a.answeredAt
        rec["logsHelpful"]     = a.logsHelpful.rawValue
        rec["graphsHelpful"]   = a.graphsHelpful.rawValue
        rec["progressHelpful"] = a.progressHelpful.rawValue
        rec["wantsAdvanced"]   = a.wantsAdvancedStats.rawValue
        rec["wantsQuestions"]  = a.wantsToAnswerQuestions.rawValue
        return rec
    }
}

#if DEBUG
extension DeveloperDataSync {

    /// One-off: create the `SharedSurvey` record type in CloudKit Development.
    ///
    /// The record type only comes into existence when something first writes
    /// one, and the survey is otherwise only offered after 12 logging days AND
    /// 8 weeks — so it would be missing from the schema at deploy time, and the
    /// first real answer months later would fail against production.
    ///
    /// Run once with `-SRWSendTestSurvey` in the scheme's launch arguments,
    /// then untick it. DEBUG-only, so it cannot reach the App Store; there is
    /// nothing to remove from the code afterwards.
    ///
    /// It uploads regardless of the sharing setting — it is a deliberate,
    /// developer-only action on the developer's own device.
    static func sendTestSurveyIfRequested() {
        guard CommandLine.arguments.contains("-SRWSendTestSurvey") else { return }

        var answers = SurveyAnswers()
        answers.logsHelpful = .very
        answers.graphsHelpful = .aBit
        answers.progressHelpful = .very
        answers.wantsAdvancedStats = .yes
        answers.wantsToAnswerQuestions = .maybe
        answers.answeredAt = Date()

        log.notice("Sending a test survey to create the SharedSurvey record type.")
        recordSurvey(answers, consent: true)
        print("[DataSync] test survey sent — look for SharedSurvey in the CloudKit Console "
              + "(Development), then Deploy Schema Changes.")
    }
}
#endif
