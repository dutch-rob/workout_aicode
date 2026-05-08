import SwiftUI

// MARK: - ContentView (watchOS)
//
// Two states:
//  • Idle   – shown before iPhone sends any exercise context.
//  • Active – shown while a set is in progress; displays exercise name,
//             set number, suggested weight, a large rep counter, ±1 buttons
//             and a "Done" button that ships the count back to the iPhone.

struct ContentView: View {
    @StateObject private var session = WatchSessionManager.shared

    var body: some View {
        Group {
            if session.isActive {
                activeSetView
            } else {
                idleView
            }
        }
        .animation(.easeInOut(duration: 0.2), value: session.isActive)
    }

    // MARK: - Idle screen

    private var idleView: some View {
        VStack(spacing: 10) {
            Image(systemName: "dumbbell")
                .font(.system(size: 30))
                .foregroundStyle(.tint)
            Text("Open SetsRepsWheels on iPhone to begin logging")
                .multilineTextAlignment(.center)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    // MARK: - Active set screen

    private var activeSetView: some View {
        ScrollView {
            VStack(spacing: 3) {

                // Exercise name + context
                Text(session.exerciseName)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)

                Text("Set \(session.setNumber)  ·  \(session.suggestedWeight) kg")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Divider()
                    .padding(.vertical, 4)

                // Big rep count
                Text("\(session.repCount)")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(.tint)
                    .contentTransition(.numericText())

                Text("of \(session.targetReps) target")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Divider()
                    .padding(.vertical, 4)

                // Manual ±1 buttons
                HStack(spacing: 24) {
                    Button {
                        session.decrementRep()
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)

                    Button {
                        session.incrementRep()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.green)
                    }
                    .buttonStyle(.plain)
                }

                // Done — sends count to iPhone
                Button("Done") {
                    session.completeSet()
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .padding(.top, 4)
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
    }
}

#Preview {
    ContentView()
}
