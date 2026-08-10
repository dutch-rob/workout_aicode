import SwiftUI

// AUTO-GENERATED — edit README.md and run generate_infoview.py to update.

struct InfoView: View {
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                Group {
                    Text("SetsRepsWheels logs the sets, weights and repetitions of weight training. All the sets of an exercise are on one screen, and you set the numbers with picker wheels that start where you left them the last time you did that exercise — so tracking an exercise is just some flicks and a tap. There is a companion Apple Watch app that logs the same workout at the machine, and you can hand a workout over between your iPhone and your Watch part-way through. Once you have some history it estimates how your strength is trending per exercise, and shows you which exercises are moving and which are stuck. Everything stays on your devices unless you turn something on yourself.")
                    Text("I made this app for myself because I wanted logging to be quicker than in the apps I tried. It is deliberately bare-bones. I hope you find it useful too (though it is probably not the best workout app for everybody).")
                }

                Group {
                    Text("Contents").font(.headline).id("contents")
                    VStack(alignment: .leading, spacing: 8) {
                        Button { withAnimation { proxy.scrollTo("getting-started", anchor: .top) } } label: { Text("Getting started — defining your first workout and exercises").multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading) }
                        Button { withAnimation { proxy.scrollTo("logging-a-workout", anchor: .top) } } label: { Text("Logging a workout — the wheels, the buttons, skipping an exercise").multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading) }
                        Button { withAnimation { proxy.scrollTo("the-rest-timer", anchor: .top) } } label: { Text("The rest timer — optional, off by default").multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading) }
                        Button { withAnimation { proxy.scrollTo("the-apple-watch-app", anchor: .top) } } label: { Text("The Apple Watch app — logging at the machine").multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading) }
                        Button { withAnimation { proxy.scrollTo("handing-a-workout-over", anchor: .top) } } label: { Text("Handing a workout over — moving between iPhone and Watch").multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading) }
                        Button { withAnimation { proxy.scrollTo("apple-health", anchor: .top) } } label: { Text("Apple Health — optional, off by default").multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading) }
                        Button { withAnimation { proxy.scrollTo("editing-workouts", anchor: .top) } } label: { Text("Editing workouts — adding, ordering and removing exercises").multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading) }
                        Button { withAnimation { proxy.scrollTo("the-exercise-library", anchor: .top) } } label: { Text("The exercise library — finding exercises by muscle group").multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading) }
                        Button { withAnimation { proxy.scrollTo("editing-an-exercise", anchor: .top) } } label: { Text("Editing an exercise — sets, weight range, muscle groups").multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading) }
                        Button { withAnimation { proxy.scrollTo("your-logs-and-statistics", anchor: .top) } } label: { Text("Your logs and statistics — the four tabs").multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading) }
                        Button { withAnimation { proxy.scrollTo("how-the-strength-numbers-work", anchor: .top) } } label: { Text("How the strength numbers work — one-rep max, hard sets, trend").multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading) }
                        Button { withAnimation { proxy.scrollTo("muscle-groups", anchor: .top) } } label: { Text("Muscle groups — the body picture and the fifteen groups").multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading) }
                        Button { withAnimation { proxy.scrollTo("settings", anchor: .top) } } label: { Text("Settings — sharing between devices, Health, the rest timer, statistics, deleting data").multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading) }
                        Button { withAnimation { proxy.scrollTo("your-data-and-privacy", anchor: .top) } } label: { Text("Your data and privacy — what leaves your device").multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading) }
                        Button { withAnimation { proxy.scrollTo("notes-and-feedback", anchor: .top) } } label: { Text("Notes and Feedback — and the open source").multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading) }
                    }
                }

                Group {
                    Text("Getting started").font(.headline).id("getting-started")
                    Text("When you open the app for the first time there are no workouts or exercises yet: you define them yourself.")
                    Text("The first time you open the app it asks for your usual numbers — how many sets you normally do, the lowest and highest weight you use, and the step between weights on the wheel. Every exercise you add starts from those, and you can change any of them later, per exercise or for all new ones in Settings.")
                    Text("Then tap **new workout** and give it a name. Tap **add exercise** to open the exercise library: pick a ready-made exercise, or tap **new exercise** to describe your own. Add as many as you like, then **save**. Back on the start screen your workout is listed, and tapping it starts logging.")
                }

                Group {
                    Text("Logging a workout").font(.headline).id("logging-a-workout")
                    Text("Tap a workout on the start screen. The first exercise appears with a row of wheels for each set: the top row is the weights, the bottom row the repetitions. If you have logged this exercise before, the wheels start at the numbers you logged last time, so you usually only need to adjust what changed.")
                    Text("After finishing a set, tap **log, next** to record the exercise and move to the next one. On the last exercise that button reads **log, end**, which records it and takes you back to the start screen.")
                    Text("**quit** ends the workout without logging the exercise that is on screen. Anything you already logged during the workout is kept.")
                    Text("If a machine is busy you can skip ahead: swipe left for the next exercise you have not logged yet, and right for the previous one. Swiping leaves the current exercise without logging it, so you can come back to it later.")
                }

                Group {
                    Text("The rest timer").font(.headline).id("the-rest-timer")
                    Text("Off unless you switch it on, in Settings. With it off the app behaves exactly as it always has.")
                    Text("With it on, a rest is counted after every set and after each exercise you log. A set ends when you touch a wheel — you roll it to what you just lifted, and the rest starts. Touching a wheel and putting it back on the same number counts too, which is what happens when you repeat the previous set, and a plain tap on a wheel is the simplest way to start a rest by hand. The countdown appears a few seconds after your last touch, so setting the weight and then the repetitions does not take the second wheel away from you.")
                    Text("The countdown opens a few seconds down rather than at the full time, because your rest started when the set did, not when the screen changed. Swiping to another exercise counts as still working and puts the countdown off again.")
                    Text("While it runs you are free to put the phone in your pocket or use something else: the countdown is only a display, and the phone shows a notification when the rest is over whether or not the app is on screen. If your Apple Watch is nearby and awake when the rest starts, it is told when the rest ends and taps your wrist itself. **skip rest** ends it early and takes you straight back to the wheels.")
                    Text("How loudly the phone announces it is the phone's business, not the app's: an app cannot buzz you while it is in the background, so what you feel is whatever your Sounds & Haptics settings do for a notification. The Watch is the more dependable tap on the shoulder.")
                    Text("How long the rest is belongs to the exercise, because a heavy compound needs longer than a light isolation movement. The first-run question sets what new exercises start with, from 0:15 up to 5:00 in quarter minutes, and 1:30 by default; any exercise can be given its own on its *edit exercise* screen.")
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
                    Text("Once you have a workout, **new workout** on the start screen becomes **edit workouts**. Beside it, **exercise library** is where all your exercises live.")
                    Text("**edit workouts** lists your workouts. Tap one to change it. On the *edit workout* screen you can rename it, and:")
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("    • **add exercise** — opens the library to pick one, or make a new one")
                            Text("    • tap an exercise — opens it, to change its sets, weights or muscle groups")
                            Text("    • drag the handle on the right — moves an exercise up or down in the workout")
                            Text("    • the red button on the left — takes an exercise out of this workout; the exercise itself stays in your library")
                        }
                    }
                    Text("**quit** leaves without keeping anything you changed on that screen, and **save** keeps it. A workout needs a name before it can be saved, and the name has to be one you are not already using: two workouts with the same name cannot be told apart in your logs.")
                    Text("Back in *edit workouts* you can likewise reorder your workouts and remove one with the red icon.")
                }

                Group {
                    Text("The exercise library").font(.headline).id("the-exercise-library")
                    Text("**exercise library** holds every exercise: the ones you have made and the ready-made ones you have not taken yet, together in one list.")
                    Text("At the top is a picture of the front and back of a body. Tap a muscle on it — or one of the labels beside it — to narrow the list to exercises for that muscle group. **all groups** brings everything back. The button on the right of that row swaps the picture for plain buttons if you prefer, and the star beside it narrows the list to your favourites.")
                    Text("In the list, a **star** marks an exercise as a favourite, which also floats it to the top. A tick on the right means the exercise is in one of your workouts. Tapping one of your own exercises opens it; tapping a ready-made one copies it into your exercises, with its muscle groups already filled in. Swiping an exercise to the left offers **Duplicate**, for a variant that keeps the original's settings, and **Delete**.")
                    Text("Deleting an exercise removes it from your list *and* from any workout that used it. Sets you have already logged are kept.")
                }

                Group {
                    Text("Editing an exercise").font(.headline).id("editing-an-exercise")
                    Text("On the *edit exercise* screen you set the name, the number of sets, the lowest weight, the highest weight and the increment that determine the numbers on its wheel, the rest this exercise gets when the rest timer is on, and the muscle groups it works. Underneath, **In these workouts** shows which workouts contain it, and you can add or remove it from any of them right there — the same relationship, editable from either end.")
                    Text("An exercise needs a name and a primary muscle group before it can be saved, and the name has to be one you are not already using. Without a muscle group an exercise cannot be found on the body picture or grouped with anything else. **quit** leaves without keeping your changes; on an exercise you have only just created, it removes it again rather than leaving a nameless one behind.")
                }

                Group {
                    Text("Your logs and statistics").font(.headline).id("your-logs-and-statistics")
                    Text("The **logs/stats** button opens four tabs.")
                    Text("**logs** shows your logged sets, most recent first. A weight is green when it is higher than the last time you did that set of that exercise, and red when it is lower. A repetition count is green when it is higher than last time and the weight has not dropped, and red when it is lower and the weight has not risen.")
                    Text("**graphs** draws one chart per exercise: a dot for each workout, and a straight trendline through them. A graph appears once you have logged that exercise in at least 8 workouts, so the tab fills in gradually; below the graphs you will see which exercises are still short and by how much.")
                    Text("**progress** lists those same exercises ordered from least to most progress, so whatever is falling behind is at the top. Each line shows the trend per week, the best estimate from your last workout, and how many hard sets that exercise usually takes.")
                    Text("**import/export** holds the file tools:")
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
                    Text("How the strength numbers work").font(.headline).id("how-the-strength-numbers-work")
                    Text("Everything on the graphs and progress tabs comes from one idea: from a set of several repetitions you can estimate what you could have lifted just once. That estimate is your **one-rep max**, and tracking it lets a heavy set of 5 and a lighter set of 12 be compared on the same scale.")
                    Text("You choose the formula in settings. All three are in common use and none is exactly right; they mostly agree, and what matters is that you keep to one:")
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("    • **Epley** — w × (1 + r/30), the default")
                            Text("    • **Brzycki** — w / (1.0278 − 0.0278 × r)")
                            Text("    • **Lombardi** — w × r^0.1")
                        }
                    }
                    Text("For each exercise in a workout, the app takes the best estimate among its sets. That best number is what the graphs plot and what the trend is measured on.")
                    Text("A set counts as **hard** if it was your best set that day, or if four more repetitions at that weight would have matched it. The rest count as warm-ups or back-off sets. This is the app's measure of how much real work an exercise took.")
                    Text("The **trend** is a straight line fitted through your best estimates over your most recent workouts (16 by default, at least 8), divided by their average so that exercises of very different weights can be compared. It is shown as a percentage per week. Steady progress is a small number: around half a percent to one percent per week is real progress, and a long run at zero means a plateau, not a mistake.")
                    Text("The dots on a graph can be averaged over several workouts to make the pattern easier to see — 3 by default. Averaging only affects the dots; the trendline always follows your actual numbers.")
                    Text("Two cautions. These are estimates from your own logged numbers, not measurements: a bad night's sleep shows up as lost strength. And a trend needs a run of workouts before it means much — with 8 workouts a single unusual day still moves it.")
                }

                Group {
                    Text("Muscle groups").font(.headline).id("muscle-groups")
                    Text("An exercise records which muscles it works: one **primary muscle group** and up to four **secondary** ones, from a fixed list of fifteen. The primary group is required, because it is what the body picture and the filters go by, and what lets the app group your training by muscle rather than by exercise name.")
                    Text("The body picture in the library is an anatomical drawing with each of those fifteen groups marked on it. Tapping a muscle selects it; tapping it again clears the selection. Where two groups overlap — the traps lie over the upper back, the deltoid heads run into one another — the smaller one takes the tap, since the larger has plenty of clear area elsewhere. Muscles that show from both sides, like the traps and the side delts, can be tapped on either figure.")
                    Text("The **ready-made exercises** cover every primary muscle group and come already filled in, so most people never need to describe an exercise from scratch. Taking one copies it into your own exercises, where you can rename it and change anything you like.")
                }

                Group {
                    Text("Settings").font(.headline).id("settings")
                    Text("The settings screen has:")
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("    • **Share data among your iPhones/iPads** — keeps your workouts, exercises and logs in step across your devices through your own iCloud account. Off by default.")
                            Text("    • **Save workouts to Apple Health** — see [Apple Health](#apple-health) above. Off by default.")
                            Text("    • **Rest timer** — counts your rest after every set and after each exercise you log. Off by default, see [The rest timer](#the-rest-timer) above.")
                            Text("    • **Numbers for a new exercise** — the sets, weight range, increment and rest each new exercise starts with. Exercises you already have are not changed.")
                            Text("    • **One-rep max formula** — which of the three formulas the statistics use. Epley by default.")
                            Text("    • **Workouts in the trend** — how many recent workouts the trend line uses, 16 by default and never fewer than 8.")
                            Text("    • **Averaging in graphs** — smooths the dots over this many workouts, 3 by default; set it to off to see every workout as logged.")
                            Text("    • **Share anonymous data with the developer** — off by default, see below.")
                            Text("    • **Delete all my data** — removes everything this app has stored, and takes back anything you shared anonymously. With iCloud sharing on, it also removes it from your other devices.")
                        }
                    }
                }

                Group {
                    Text("Your data and privacy").font(.headline).id("your-data-and-privacy")
                    Text("Your workouts, exercises and logs are stored on your device. There is no account and no tracking: nothing about you is collected automatically, and nothing is sold or shared with anyone else, ever.")
                    Text("Four things can leave the app, and every one of them is off until you switch it on:")
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("    • **iCloud sharing** keeps your data in step across *your own* devices through your private iCloud account.")
                            Text("    • **Apple Health** receives the start and end time of a finished workout. Data sent to Health stays on your device under your control in the Health app, where you can review or withdraw it at any time.")
                            Text("    • **Exports** go wherever you send them.")
                            Text("    • **Sharing anonymous data with the developer** sends your logged sets so the app can be improved with real training data — in particular the individual advice described below. This is the one thing that goes to me rather than to you, so it is worth being precise about.")
                        }
                    }
                    Text("What that last option sends, when you turn it on: the weights, repetitions and dates you logged, which muscle groups an exercise works, and your answers if you fill in the questionnaire. What it never sends: your name, your Apple ID, your device, your location, or the names you gave your workouts and exercises. An exercise you named yourself travels as an unreadable code, unique to your installation, so your own sets can be recognised as belonging together without the name being recoverable. Exercises taken from the library also carry the library's own name for the movement, which is what allows a bench press to be compared across people.")
                    Text("Your data is identified only by a random code created on your device the first time you turn the option on. It is not linked to your Apple ID or to anything else about you, and I have no way to work out who any of it belongs to. Turning the option off deletes what your device has shared, and so does *Delete all my data*.")
                    Text("Once you have been using the app for a while you may see a short questionnaire, asking which parts of logs/stats you find useful and whether you would want more individual statistics. Answering is voluntary, \"Not now\" is a complete answer, and it will not keep asking.")
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
                        Text("3. The muscle diagram is \"Muscles front and back\" by OpenStax, Tomáš Kebert and umimeto.org, from Wikimedia Commons, used under the Creative Commons Attribution-ShareAlike 4.0 licence (https://creativecommons.org/licenses/by-sa/4.0/). It was cropped into two figures and given a transparent background; the anatomy itself is unchanged. Those two images stay under CC BY-SA 4.0.")
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
