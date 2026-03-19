//
//  ContentView.swift
//  workout_aicode
//
//  Created by Rob Boer on 3/4/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\WorkoutDef.name)]) private var workouts: [WorkoutDef]

    @State private var showEditWorkouts = false
    @State private var showExercises = false
    @State private var navigateToLogs = false
    @State private var path = NavigationPath()
    @State private var refreshTick: Int = 0

    init() {}

    var body: some View {
        NavigationStack(path: $path) {
            VStack(alignment: .leading, spacing: 12) {
                Text("workouts")
                    .font(.largeTitle).bold()
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 12) {
                    Button {
                        let w = WorkoutDef(name: "")
                        modelContext.insert(w)
                        path.append(NavDestination.editWorkout(w))
                    } label: {
                        Text("new")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button("edit") { showEditWorkouts = true }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)

                    NavigationLink(value: NavDestination.logs) {
                        Text("logs").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                if workouts.isEmpty {
                    ContentUnavailableView("No workouts", systemImage: "list.bullet", description: Text("Tap New to create your first workout"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(workouts.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }, id: \.self) { workout in
                                NavigationLink(value: NavDestination.logWorkout(workout)) {
                                    Text(workout.name)
                                        .font(.headline)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding()
                                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.1)))
                                }
                            }
                        }.padding(.top, 4)
                    }
                    .id(refreshTick)
                }
            }
            .padding()
            .gesture(DragGesture().onEnded { value in
                if value.translation.width < -40 || value.translation.width > 40 {
                    showExercises = true
                }
            })
            .navigationDestination(for: NavDestination.self) { dest in
                switch dest {
                case .logs:
                    LogsView()
                case .logWorkout(let workout):
                    LogExerciseView(workout: workout)
                case .editWorkout(let workout):
                    EditWorkoutView(workout: workout)
                case .exercises:
                    ExercisesView()
                }
            }
            .sheet(isPresented: $showEditWorkouts) {
                EditWorkoutsView()
            }
            .sheet(isPresented: $showExercises) {
                ExercisesView()
            }
            .onReceive(NotificationCenter.default.publisher(for: .modelDataDidChange)) { _ in
                refreshTick &+= 1
            }
        }
    }
}

// MARK: - Navigation Destinations

enum NavDestination: Hashable {
    case logs
    case logWorkout(WorkoutDef)
    case editWorkout(WorkoutDef)
    case exercises
}

#Preview {
    ContentView()
        .modelContainer(for: [WorkoutDef.self, ExerciseDef.self, WorkoutLog.self], inMemory: true)
}
