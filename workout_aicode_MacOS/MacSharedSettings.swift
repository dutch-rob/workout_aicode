import SwiftUI
import SwiftData

// MARK: - The settings that belong to the phone and the Watch
//
// Set here, used there. The Mac does not log a workout, does not own a
// calendar and has no Watch on its wrist, so for a long time none of this was
// offered: a control that changed a `UserDefaults` value nothing syncs would
// have been a control that did nothing.
//
// `AppSettings` changed that — see `SyncedSettings`. These values now travel,
// so the Mac can be what it is meant to be, which is the comfortable place to
// set up the thing you then train with.
//
// What is still missing from this screen is missing because it cannot travel:
// Apple Health sharing, where body weight comes from, which calendar events go
// in, and sharing data with the developers. Each is a fact about one device.
// The list and the reasons are on `AppSettings`.

struct MacSharedSettings: View {
    @AppStorage(PrefillScope.key) private var prefillAcrossWorkouts = PrefillScope.defaultAcrossWorkouts
    @AppStorage(RestTimerKey.enabled) private var restTimerOn = false

    @AppStorage(WorkoutScheduleKey.enabled) private var scheduleOn = false
    @AppStorage(WorkoutScheduleKey.daysAhead) private var daysAhead = WorkoutSchedule.defaultDaysAhead
    @AppStorage(WorkoutScheduleKey.count) private var howMany = WorkoutSchedule.defaultCount

    @AppStorage(WatchWorkoutMode.key) private var watchModeRaw = WatchWorkoutMode.handover.rawValue
    @AppStorage(WatchPreferences.wheelRowsKey) private var wheelRows = WatchPreferences.defaultWheelRows
    @AppStorage(WatchPreferences.restTapsKey) private var restTaps = WatchPreferences.defaultRestTaps
    @AppStorage(WatchPreferences.zoneTintKey) private var zoneTint = WatchPreferences.defaultZoneTint
    @AppStorage(WatchPreferences.zoneBoundariesKey) private var zoneBoundariesText = ""

    /// The four fields, as typed. Written back as one string when they change,
    /// exactly as the iPhone does it — see `WatchPreferences.boundariesText`.
    @State private var zoneText: [String] = ["", "", "", ""]

    private var watchMode: WatchWorkoutMode {
        WatchWorkoutMode(rawValue: watchModeRaw) ?? .handover
    }
    private var typedBoundaries: [Int] {
        WatchPreferences.validBoundaries(
            zoneText.compactMap { Int($0.trimmingCharacters(in: .whitespaces)) })
    }
    private var zoneTextIsEmpty: Bool {
        zoneText.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        Group {
            Section {
                Toggle("Carry weights between workouts", isOn: $prefillAcrossWorkouts)
                Toggle("Rest timer", isOn: $restTimerOn)
            } header: {
                Text("Logging")
            } footer: {
                Text("Carrying weights over opens a wheel on the last time you did that exercise, whichever workout you did it in — so splitting or reorganising a routine keeps your numbers. With it off, each workout remembers its own, which suits a heavy day and a light day that share the same exercise.\n\nThe rest timer counts down after a logged set on the iPhone and the Watch. How long each exercise rests is on the exercise; what a new one starts with is above.")
            }

            Section {
                Toggle("Offer the next workout at the end of one", isOn: $scheduleOn)
                if scheduleOn {
                    Picker("How far ahead", selection: $daysAhead) {
                        ForEach(Array(WorkoutSchedule.daysAheadRange), id: \.self) { days in
                            Text(days == 1 ? "1 day" : "\(days) days").tag(days)
                        }
                    }
                    Picker("How many", selection: $howMany) {
                        ForEach(Array(WorkoutSchedule.countRange), id: \.self) { count in
                            Text(count == 1 ? "Just the next one" : "The next \(count)").tag(count)
                        }
                    }
                }
            } header: {
                Text("Scheduling")
            } footer: {
                Text("Finishing a workout on your iPhone or Watch offers to put the next one in your calendar, at the time this one began, rounded up to the quarter hour. Nothing is ever added without being asked.\n\nWhich calendar they go in is the iPhone's own choice, and stays there: a calendar's identifier means nothing on another device. This Mac has no calendar of its own — it sets the question, the iPhone writes the answer.")
            }

            Section {
                Picker("Workouts on the Watch", selection: $watchModeRaw) {
                    ForEach(WatchWorkoutMode.allCases) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
                Picker("Wheels on the Watch", selection: $wheelRows) {
                    Text("One row, with a reps/weights toggle").tag(1)
                    Text("Both rows at once").tag(2)
                }
                LabeledContent("Taps at the end of a rest") {
                    Stepper(value: $restTaps, in: 1...WatchPreferences.maximumRestTaps) {
                        Text("\(restTaps)")
                    }
                }
                if watchMode == .appleWorkout {
                    LabeledContent("Heart rate band") {
                        Slider(value: $zoneTint,
                               in: WatchPreferences.minimumZoneTint...1, step: 0.05)
                            .frame(width: 180)
                    }
                }
            } header: {
                Text("The Apple Watch")
            } footer: {
                Text(watchMode == .appleWorkout
                     ? "Starting a workout on the Watch makes it a real Apple workout: your heart rate is recorded, the zone shows behind the exercise name, and it counts towards your rings. The price is that a workout on your wrist cannot come back to the iPhone part-way through.\n\nThe band is how strongly the zone colours are drawn behind the exercise name. Your iPhone shows a live preview of it, which this app cannot.\n\nThese reach the Watch through your iPhone, which is the only thing it talks to. A change made here arrives once the iPhone has seen it."
                     : "A workout can be moved between your iPhone and your Watch as often as you like; whichever device you pick it up on asks first. Your Watch does not record a workout of its own in this mode, so there is no heart rate during the weights.\n\nThese reach the Watch through your iPhone, which is the only thing it talks to. A change made here arrives once the iPhone has seen it.")
            }

            Section {
                ForEach(0..<4, id: \.self) { index in
                    LabeledContent("Zone \(index + 2) starts at") {
                        TextField("—", text: $zoneText[index])
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                    }
                }
                if !zoneTextIsEmpty && typedBoundaries.isEmpty {
                    Text("Four rising heart rates are needed, no two the same. Until then, the Watch works them out itself.")
                        .foregroundStyle(.orange)
                }
                if !zoneTextIsEmpty {
                    Button("Work them out for me instead") { zoneText = ["", "", "", ""] }
                }
            } header: {
                Text("Heart rate zones")
            } footer: {
                Text("Only used by an Apple Watch that cannot read your zones from Apple Health itself — from watchOS 27 on a Series 9 or later it takes whatever the Workout app is using, which is better than anything that can be typed here. Your iPhone knows which Watch you have and hides these when they are of no use; this app cannot tell, so it always shows them.")
            }
            .onAppear {
                zoneText = {
                    let stored = WatchPreferences.parseBoundaries(zoneBoundariesText)
                    return stored.count == 4 ? stored.map(String.init) : ["", "", "", ""]
                }()
            }
            .onChange(of: zoneText) { _, _ in
                zoneBoundariesText = WatchPreferences.boundariesText(typedBoundaries)
            }
        }
    }
}
