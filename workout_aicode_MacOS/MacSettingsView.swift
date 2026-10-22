import SwiftUI
import SwiftData

struct MacSettingsView: View {
    @Environment(\.modelContext) private var macContext
    @AppStorage(WeightUnit.key) private var weightUnitRaw = WeightUnit.regionDefault.rawValue
    /// Redrawn after the question below is answered.
    @State private var unitAnswered = WeightHistory.isAnswered

    @Environment(\.modelContext) private var context
    @Query private var drafts: [DraftSession]
    @State private var syncOn = MacAppSetup.syncEnabled
    @State private var askingToEnd = false

    // The same keys the iPhone writes, so the fields read familiarly — but not
    // the same storage. UserDefaults is per-device, and nothing syncs it, so
    // what is set here applies to exercises made here. Said plainly below
    // rather than left for someone to discover.
    @AppStorage(ExerciseDefaultsKey.sets) private var sets = ExerciseDefaults.sets
    @AppStorage(ExerciseDefaultsKey.lowest) private var lowest = ExerciseDefaults.lowest
    @AppStorage(ExerciseDefaultsKey.highest) private var highest = ExerciseDefaults.highest
    @AppStorage(ExerciseDefaultsKey.increment) private var increment = ExerciseDefaults.increment
    @AppStorage(RestTimerKey.defaultSeconds) private var restSeconds = defaultRestSeconds

    private var draft: DraftSession? { drafts.first { $0.isActive } }

    var body: some View {
        Form {
            Section {
                if unitAnswered {
                    Picker("Weights in", selection: $weightUnitRaw) {
                        ForEach(WeightUnit.allCases) { unit in
                            Text(unit == .kilograms ? "Kilograms (kg)" : "Pounds (lb)")
                                .tag(unit.rawValue)
                        }
                    }
                } else {
                    // The same question the iPhone asks, for whoever opens
                    // this app first. Weights are kept in a form that has no
                    // unit, and nothing can be shown until somebody says what
                    // the numbers logged so far were in.
                    Text("The weights you have logged so far — what were they in?")
                        .font(.callout).bold()
                    HStack {
                        ForEach(WeightUnit.allCases) { unit in
                            Button(unit == .kilograms ? "Kilograms" : "Pounds") {
                                WeightHistory.adopt(unit, in: macContext)
                                weightUnitRaw = unit.rawValue
                                unitAnswered = true
                            }
                        }
                    }
                    .onAppear { unitAnswered = !WeightHistory.shouldAsk(in: macContext) }
                }
            } footer: {
                Text(unitAnswered
                     ? "Your weights are kept without a unit, so switching here re-presents everything you have logged in the other one — nothing is recalculated and nothing is lost."
                     : "Until this is answered your weights cannot be shown: the numbers are there, but what they mean is not.")
            }

            Section {
                Toggle("Share data through iCloud", isOn: $syncOn)
                    .onChange(of: syncOn) { _, on in
                        MacAppSetup.setSyncEnabled(on)
                    }
            } footer: {
                Text("On by default on the Mac, unlike the iPhone. This app does not log workouts — the iPhone and Watch do — so a Mac keeping its data to itself could never get what you define here to the device you train with.\n\nChanging this takes effect when you next open the app. Your iPhone has its own switch, and both must be on for the two to see each other.")
            }

            Section {
                LabeledContent("Sets") {
                    Stepper(value: $sets, in: 1...10) {
                        TextField("", value: $sets, format: .number).frame(width: 60)
                    }
                }
                LabeledContent("Lowest weight") {
                    TextField("", value: $lowest, format: .number).frame(width: 80)
                }
                LabeledContent("Highest weight") {
                    TextField("", value: $highest, format: .number).frame(width: 80)
                }
                LabeledContent("Weight increment") {
                    TextField("", value: $increment, format: .number).frame(width: 80)
                }
                Picker("Rest after a set", selection: $restSeconds) {
                    ForEach(ExerciseDefaults.restChoices, id: \.self) {
                        Text(ExerciseDefaults.restLabel($0)).tag($0)
                    }
                }
            } header: {
                Text("Numbers for a new exercise")
            } footer: {
                Text("Where a new exercise starts. Every exercise can still be changed on its own afterwards, and changing these leaves existing exercises alone.\n\nThe wheels on the iPhone show weights from the lowest to the highest in steps of the increment — match the increment to your gym, often 5, or 2 for dumbbells.\n\nThis is this Mac's answer. Your iPhone asked the same question when you first used it and keeps its own; the two do not travel through iCloud, because only your workouts and exercises do.")
            }

            Section {
                MacStatsOptions()
            } header: {
                Text("Statistics and graphs")
            } footer: {
                Text("How the graphs and the progress ranking are worked out. The formula turns a set of reps at a weight into an estimated one-rep max, which is the number everything else is built on; the trend is fitted over the last so many sessions of each exercise; smoothing averages neighbouring points to quiet the dots down.\n\nSmoothing changes only how the dots read — the trendline is always fitted to the real sessions, so it never moves when you change it.\n\nThe same options sit in the toolbar of the graphs and progress screens, for trying a value while looking at what it does.")
            }

            Section {
                Toggle("Draft", isOn: Binding(
                    get: { draft != nil },
                    set: { on in
                        if on {
                            DraftMode.start(in: context)
                        } else if draft?.isEmpty == false {
                            askingToEnd = true          // ask before anything goes
                        } else {
                            DraftMode.keepAll(in: context)
                        }
                    }))
            } footer: {
                Text("While draft is on, anything you make is marked, and the toolbar says so. Turning it off asks whether to keep what you made or throw it away — it never decides for you. Changes to things that already existed are yours to keep either way.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .confirmationDialog("Finish draft?", isPresented: $askingToEnd, titleVisibility: .visible) {
            if let draft {
                Button("Keep \(draft.summary)") { DraftMode.keepAll(in: context) }
                Button("Discard \(draft.summary)", role: .destructive) {
                    DraftMode.discardAll(in: context)
                }
            }
            Button("Stay in draft", role: .cancel) { }
        } message: {
            Text(draft.map { "You made \($0.summary) while drafting." } ?? "")
        }
    }
}
