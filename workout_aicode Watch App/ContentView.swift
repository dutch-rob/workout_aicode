import SwiftUI

// MARK: - ContentView (watchOS home)
//
// The opening screen: a list of workout buttons. Tapping one opens the log
// screen for that workout. The current time is shown automatically by watchOS
// in the top status bar.
//
// When a workout is active on the iPhone, opening the Watch app takes the
// session over here (jumping straight into that workout); the phone then shows
// its Paused screen. Tapping a workout in the list starts/joins that session.

struct ContentView: View {
    @StateObject private var session = WatchSessionManager.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var path: [String] = []   // workout ids on the nav stack

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if session.workouts.isEmpty {
                    emptyState
                } else {
                    List(session.workouts) { workout in
                        NavigationLink(value: workout.id) {
                            Text(workout.name)
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .navigationTitle("Workouts")
            .navigationDestination(for: String.self) { workoutId in
                WorkoutLoaderView(workoutId: workoutId, onEndSession: { path.removeAll() })
            }
        }
        // Take over into a workout being handed over from the iPhone.
        .onChange(of: session.routeWorkoutId) { _, id in
            guard let id else { return }
            if path.last != id { path = [id] }
            session.routeWorkoutId = nil
        }
        // Opening / returning to the Watch app pulls fresh data and checks
        // whether the phone is mid-workout (shown as a Paused screen).
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { session.onForeground() }
        }
        // When the workout session ends (finished or quit), pop back to the list.
        // Driven from here (not the log view's dismiss()) so it's reliable with
        // the path-bound NavigationStack.
        .onChange(of: session.role) { _, newRole in
            if newRole == .none, !path.isEmpty { path.removeAll() }
        }
        .onAppear {
            session.requestSync()
            if let id = session.routeWorkoutId {
                if path.last != id { path = [id] }
                session.routeWorkoutId = nil
            }
            #if DEBUG
            // Screenshot demo mode — see DemoMode.swift.
            guard DemoMode.isEnabled else { return }
            session.loadDemoData()
            switch DemoMode.screen {
            case "log":    path = [DemoMode.workoutId]
            case "paused": session.showDemoPaused()
            default:       break
            }
            #endif
        }
        // A workout active on the iPhone shows here as a Paused screen; the
        // session only moves over when the user taps "Continue here".
        .overlay {
            if session.role == .paused {
                WatchPausedView(onContinue: { session.reclaim() },
                                onDismiss: { session.dismissPaused() })
            }
        }
        // Mirrors the rest the phone is counting. Only visible if the user
        // happens to be looking at the watch — the buzz at the end comes from
        // a scheduled notification, not from this view being on screen.
        .overlay {
            if restTimer.isRunning {
                WatchRestCountdownView()
            }
        }
    }

    @ObservedObject private var restTimer = WatchRestTimer.shared

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "dumbbell")
                .font(.system(size: 30))
                .foregroundStyle(.tint)
            Text("Open SetsRepsWheels on iPhone to set up your workouts")
                .multilineTextAlignment(.center)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

// MARK: - WorkoutLoaderView
//
// Resolves a workout id to its definition. If the definition hasn't synced yet
// (e.g. the phone mirrored us into a workout before data arrived), it shows a
// brief loading state and pulls from the phone; the view swaps to the log
// screen automatically once the workout appears.

private struct WorkoutLoaderView: View {
    @ObservedObject private var session = WatchSessionManager.shared
    let workoutId: String
    var onEndSession: () -> Void = {}

    var body: some View {
        if let workout = session.workout(id: workoutId) {
            WatchLogExerciseView(workout: workout, onEndSession: onEndSession)
        } else {
            VStack(spacing: 8) {
                ProgressView()
                Text("Loading workout…")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .onAppear { session.requestSync() }
        }
    }
}

#Preview {
    ContentView()
}
