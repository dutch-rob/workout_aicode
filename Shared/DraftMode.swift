import Foundation
import SwiftData

// MARK: - Draft mode
//
// Somewhere to try things. Switch draft on, invent a workout, sketch a few
// exercises, log a session to see how it reads — then decide whether any of it
// was worth keeping.
//
// The rule that matters: nothing is ever discarded without being asked, and the
// question names what is at stake ("2 exercises, 1 workout") rather than
// offering a bare yes/no. The difference between "I was playing" and "I have
// just built my new routine" is not something the app can tell from the data,
// so it does not try.
//
// The second rule: only things CREATED during the session are on the table.
// Editing an exercise that already existed is a real edit and leaving draft
// never undoes it — otherwise a stray toggle could take away work that had
// nothing to do with the experiment.

@MainActor
enum DraftMode {

    // MARK: Reading

    /// The session in progress, if draft is on. Stored rather than held in
    /// memory, so it survives a relaunch or a crash: coming back to find the
    /// app quietly out of draft, with the marks gone from everything made, is
    /// how work gets lost by accident.
    static func active(in context: ModelContext) -> DraftSession? {
        let descriptor = FetchDescriptor<DraftSession>(
            predicate: #Predicate<DraftSession> { $0.isActive }
        )
        return (try? context.fetch(descriptor))?.first
    }

    static func isOn(in context: ModelContext) -> Bool { active(in: context) != nil }

    // MARK: Switching

    /// Starts a session, or leaves the existing one alone. Never starts a
    /// second: two overlapping drafts would make "what did I make just now"
    /// unanswerable.
    @discardableResult
    static func start(in context: ModelContext) -> DraftSession {
        if let existing = active(in: context) { return existing }
        let session = DraftSession()
        context.insert(session)
        StoreSave.save(context)
        return session
    }

    /// Ends the session, keeping everything made during it. The record goes;
    /// the work stays and stops being marked.
    static func keepAll(in context: ModelContext) {
        guard let session = active(in: context) else { return }
        context.delete(session)
        StoreSave.save(context)
    }

    /// Ends the session and removes what was made during it.
    ///
    /// Logs go first, then workouts, then exercises: a log refers to an
    /// exercise, and deleting the exercise first would leave a row pointing at
    /// something that is not there.
    static func discardAll(in context: ModelContext) {
        guard let session = active(in: context) else { return }

        for id in session.logIds {
            let descriptor = FetchDescriptor<WorkoutLog>(
                predicate: #Predicate<WorkoutLog> { $0.id == id })
            for log in (try? context.fetch(descriptor)) ?? [] {
                // Aerobic measurements belong to the log and go with it.
                let logId = log.id
                let results = FetchDescriptor<AerobicResult>(
                    predicate: #Predicate<AerobicResult> { $0.logId == logId })
                for result in (try? context.fetch(results)) ?? [] { context.delete(result) }
                context.delete(log)
            }
        }
        for id in session.workoutIds {
            let descriptor = FetchDescriptor<WorkoutDef>(
                predicate: #Predicate<WorkoutDef> { $0.id == id })
            for workout in (try? context.fetch(descriptor)) ?? [] { context.delete(workout) }
        }
        for id in session.exerciseIds {
            let descriptor = FetchDescriptor<ExerciseDef>(
                predicate: #Predicate<ExerciseDef> { $0.id == id })
            for exercise in (try? context.fetch(descriptor)) ?? [] {
                // An exercise made during the draft may have been added to a
                // workout that was NOT — take it back out, or that workout is
                // left pointing at nothing.
                let exerciseId = exercise.id
                for workout in (try? context.fetch(FetchDescriptor<WorkoutDef>())) ?? [] {
                    workout.exerciseOrder.removeAll { $0 == exerciseId }
                }
                context.delete(exercise)
            }
        }
        context.delete(session)
        StoreSave.save(context)
    }

    // MARK: Recording

    /// Called when something is created, so it can be offered back at the end.
    /// A no-op when draft is off, which is what lets the call sites be
    /// unconditional.

    static func note(exercise id: UUID, in context: ModelContext) {
        guard let session = active(in: context) else { return }
        guard !session.exerciseIds.contains(id) else { return }
        session.exerciseIds.append(id)
        StoreSave.save(context)
    }

    static func note(workout id: UUID, in context: ModelContext) {
        guard let session = active(in: context) else { return }
        guard !session.workoutIds.contains(id) else { return }
        session.workoutIds.append(id)
        StoreSave.save(context)
    }

    static func note(log id: UUID, in context: ModelContext) {
        guard let session = active(in: context) else { return }
        guard !session.logIds.contains(id) else { return }
        session.logIds.append(id)
        StoreSave.save(context)
    }

    /// Something made during the draft was deleted by hand — stop offering it
    /// back, or the count in the question would be a lie.
    static func forget(id: UUID, in context: ModelContext) {
        guard let session = active(in: context) else { return }
        session.exerciseIds.removeAll { $0 == id }
        session.workoutIds.removeAll { $0 == id }
        session.logIds.removeAll { $0 == id }
        StoreSave.save(context)
    }
}
