import SwiftUI

// AUTO-GENERATED — edit README.md and run generate_infoview.py to update.

struct InfoView: View {
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                Group {
                    Text("SetsRepsWheels logs the sets, weights and repetitions of weight training. All the sets of an exercise are on one screen, and you set the numbers with picker wheels that start where you left them the last time you did that exercise — so tracking an exercise is just some flicks and a tap. There is a companion Apple Watch app that logs the same workout at the machine, and you can hand a workout over between your iPhone and your Watch part-way through. Everything stays on your devices unless you turn something on yourself.")
                    Text("I made this app for myself because I wanted logging to be quicker than in the apps I tried. It is deliberately bare-bones. I hope you find it useful too (though it is probably not the best workout app for everybody).")
                }

                Group {
                    Text("Contents").font(.headline).id("contents")
                    VStack(alignment: .leading, spacing: 8) {
                        Button { withAnimation { proxy.scrollTo("getting-started", anchor: .top) } } label: { Text("Getting started — defining your first workout and exercises").multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading) }
                        Button { withAnimation { proxy.scrollTo("logging-a-workout", anchor: .top) } } label: { Text("Logging a workout — the wheels, the buttons, skipping an exercise").multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading) }
                        Button { withAnimation { proxy.scrollTo("the-apple-watch-app", anchor: .top) } } label: { Text("The Apple Watch app — logging at the machine").multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading) }
                        Button { withAnimation { proxy.scrollTo("handing-a-workout-over", anchor: .top) } } label: { Text("Handing a workout over — moving between iPhone and Watch").multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading) }
                        Button { withAnimation { proxy.scrollTo("apple-health", anchor: .top) } } label: { Text("Apple Health — optional, off by default").multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading) }
                        Button { withAnimation { proxy.scrollTo("editing-workouts", anchor: .top) } } label: { Text("Editing workouts — order, adding and removing exercises").multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading) }
                        Button { withAnimation { proxy.scrollTo("editing-exercises", anchor: .top) } } label: { Text("Editing exercises — sets, weight range, increments").multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading) }
                        Button { withAnimation { proxy.scrollTo("your-logs-and-export", anchor: .top) } } label: { Text("Your logs and export — reading, exporting, importing").multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading) }
                        Button { withAnimation { proxy.scrollTo("settings", anchor: .top) } } label: { Text("Settings — sharing between devices, Health, deleting data").multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading) }
                        Button { withAnimation { proxy.scrollTo("your-data-and-privacy", anchor: .top) } } label: { Text("Your data and privacy — what leaves your device").multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading) }
                        Button { withAnimation { proxy.scrollTo("notes-and-feedback", anchor: .top) } } label: { Text("Notes and Feedback — and the open source").multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading) }
                    }
                }

                Group {
                    Text("Getting started").font(.headline).id("getting-started")
                    Text("When you open the app for the first time there are no workouts or exercises yet: you define them yourself.")
                    Text("Start by tapping **new workout**. This opens the *edit workout* screen. Give the workout a name, then — since you have no exercises yet — tap **new exercise**. On the *edit exercise* screen you set the number of sets, the lowest and the highest weight you use for that exercise, and the increment between the weights that appear on the wheel. Use the back button to return to the workout and add more exercises. When you are done, go back to the start screen: your workout is listed there, and tapping it starts logging.")
                }

                Group {
                    Text("Logging a workout").font(.headline).id("logging-a-workout")
                    Text("Tap a workout on the start screen. The first exercise appears with a row of wheels for each set: the top row is the weights, the bottom row the repetitions. If you have logged this exercise before, the wheels start at the numbers you logged last time, so you usually only need to adjust what changed.")
                    Text("After finishing a set, tap **log, next** to record the exercise and move to the next one. On the last exercise that button reads **log, end**, which records it and takes you back to the start screen.")
                    Text("**quit** ends the workout without logging the exercise that is on screen. Anything you already logged during the workout is kept.")
                    Text("If a machine is busy you can skip ahead: swipe left for the next exercise you have not logged yet, and right for the previous one. Swiping leaves the current exercise without logging it, so you can come back to it later.")
                }

                Group {
                    Text("The Apple Watch app").font(.headline).id("the-apple-watch-app")
                    Text("The Watch app is a companion to the iPhone app: it shows your workouts and lets you log them at the machine, without taking your phone out. Everything else — creating workouts and exercises, browsing and exporting logs, settings — is done on the iPhone.")
                    Text("Your workouts appear on the Watch automatically; they are sent from the iPhone, so open the iPhone app once after you change something. Tap a workout to start logging.")
                    Text("Because the screen is small, the Watch shows **one** row of wheels at a time. The button at the top switches between the repetitions and the weights; whichever row is not on the wheels is shown underneath them as numbers, prefixed **r** for repetitions and **w** for weights. The exercise starts on the repetitions.")
                    Text("The buttons work like the iPhone: **log** records the exercise and moves on (**end** on the last one), **quit** ends the workout, and **list** jumps straight to any exercise. Swiping left and right moves between exercises without logging, exactly as on the phone.")
                }

                Group {
                    Text("Handing a workout over").font(.headline).id("handing-a-workout-over")
                    Text("A workout runs on one device at a time, and you can move it across whenever you like — the sets you have already logged, the wheel positions and where you are in the workout all come with it.")
                    Text("When a workout is running on one device and you open the other, that other device shows that the workout is active elsewhere and offers **Continue here**. Nothing moves until you tap it: just looking at your Watch never takes the workout off your phone. Tapping **Continue here** brings the workout across, and the device you left shows the same offer, so you can move it back just as easily. **Not now** dismisses the message and lets you use that device normally.")
                }

                Group {
                    Text("Apple Health").font(.headline).id("apple-health")
                    Text("The app can save each finished workout to Apple Health as a **Traditional Strength Training** session. This is **off by default** — turn on *Save workouts to Apple Health* in Settings, and grant permission when iOS asks.")
                    Text("Only the workout itself is recorded: when it started, when it ended, and therefore how long it took. Your sets, weights and repetitions are **not** written to Health. The duration covers the whole workout even if you handed it over between iPhone and Watch part way through, and the workout is written by the iPhone, so it also works if you do not have an Apple Watch.")
                    Text("A workout is recorded when you end it, either with **log, end** or with **quit**. If you forget to end one, it is closed automatically after an hour without activity and recorded as having ended at your last logged set, so a forgotten workout does not turn into an eight-hour one.")
                }

                Group {
                    Text("Editing workouts").font(.headline).id("editing-workouts")
                    Text("Once you have at least one workout and one exercise, the start screen changes: **new workout** becomes **edit workouts** and **new exercise** becomes **edit exercises**.")
                    Text("**edit workouts** lists your workouts. Tap one to change the exercises in it. There you can define a new exercise, or add an existing one from the list of all your exercises. **reorder exercises** lets you drag exercises into the order you want them during the workout, using the handle on the right. The red icon to the left of an exercise removes it from this workout — the exercise itself stays in your list of all exercises.")
                    Text("Back in *edit workouts* you can likewise reorder your workouts, and remove one with the red icon.")
                }

                Group {
                    Text("Editing exercises").font(.headline).id("editing-exercises")
                    Text("**edit exercises** lists every exercise you have made, whether you created it here or while building a workout. Tap one to change its name, its number of sets, and the lowest weight, highest weight and increment that determine the numbers on its wheel.")
                    Text("You can also delete an exercise here. Deleting it removes it from your list *and* from any workouts that used it.")
                }

                Group {
                    Text("Your logs and export").font(.headline).id("your-logs-and-export")
                    Text("The **logs** button shows your logged sets, most recent first. A weight is green when it is higher than the last time you did that set of that exercise, and red when it is lower. A repetition count is green when it is higher than last time and the weight has not dropped, and red when it is lower and the weight has not risen.")
                    Text("The log screen has these buttons:")
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("    • export TSV — your log as a tab separated file, easy to open in a spreadsheet")
                            Text("    • export JSON — your log together with your workout and exercise definitions")
                            Text("    • import JSON — read back a file in the same format (easiest starting from one you exported)")
                            Text("    • undo import — restore the previous data if an import did not do what you wanted")
                        }
                    }
                    Text("Exports are sent wherever you choose. Editing an exported JSON file and importing it back is currently the only way to correct a mistake in your log; I intend to make that easier.")
                    Text("After importing a JSON file you can:")
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("    • validate — check that the file has the right format and chronology")
                            Text("    • check counts — compare how many items are in the file and in the app")
                            Text("    • replace data — replace what is in the app with the imported data")
                            Text("    • merge data — add only the items that are not in the app yet")
                        }
                    }
                }

                Group {
                    Text("Settings").font(.headline).id("settings")
                    Text("The settings screen has:")
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("    • **Share data among your iPhones/iPads** — keeps your workouts, exercises and logs in step across your devices through your own iCloud account. Off by default.")
                            Text("    • **Save workouts to Apple Health** — see [Apple Health](#apple-health) above. Off by default.")
                            Text("    • **Delete all my data** — removes everything this app has stored. With iCloud sharing on, this also removes it from your other devices.")
                        }
                    }
                }

                Group {
                    Text("Your data and privacy").font(.headline).id("your-data-and-privacy")
                    Text("Your workouts, exercises and logs are stored on your device. There is no account, no server of mine, and no analytics or tracking of any kind.")
                    Text("Two things leave the app, and both are your choice and off until you switch them on: iCloud sharing keeps your data in step across *your own* devices through your private iCloud account, and Apple Health receives the start and end time of a finished workout if you turn that on. Data sent to Health stays on your device under your control in the Health app, where you can review or withdraw it at any time. Exports go wherever you send them.")
                }

                Group {
                    Text("Notes and Feedback").font(.headline).id("notes-and-feedback")
                    VStack(alignment: .leading, spacing: 8) {
                        Text("1. This app is free and open source. The source is on GitHub:")
                        Link("https://github.com/dutch-rob/workout_aicode", destination: URL(string: "https://github.com/dutch-rob/workout_aicode")!)
                        Text("2. Feedback is very welcome, in an App Store review or on GitHub — pull requests too. For example:")
                        VStack(alignment: .leading, spacing: 4) {
                            Text("    • Did anything go wrong? (Please describe what you did.)")
                            Text("    • Is the Apple Watch app missing something you need at the machine?")
                            Text("    • Should the app log something it does not log now?")
                            Text("    • Changes to the log screen or the exports?")
                            Text("    • Would you like to edit logged data in the app, and how would you expect that to work?")
                            Text("    • Statistics or trends?")
                        }
                    }
                }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Info")
        .textSelection(.enabled)
    }
}

#Preview {
    NavigationStack {
        InfoView()
    }
}
