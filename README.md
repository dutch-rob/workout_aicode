# SetsRepsWheels

A practical workout tracker for iPhone and Apple Watch, available in the Apple App Store as **SetsRepsWheels**.

There is a Mac app in here as well (`workout_aicode_MacOS`), in the Mac App Store under the same name: the same workouts, exercises and logs on a big screen, with the two lists side by side, a log editor, the graphs and statistics, and import/export. With iCloud sharing switched on it works from the same data as your iPhone; with it off it keeps its own store, and the export file moves things across. The guide below is the iPhone's, which is the fuller of the two — the Mac app carries its own under **info**, and its Help menu opens it.

Source: https://github.com/dutch-rob/workout_aicode

Working on the code rather than using the app? [ARCHITECTURE.md](ARCHITECTURE.md)
is the map: the targets, the shared folder, the data and its migrations, the
phone ⇄ Watch contract, and why the project is called `workout_aicode` inside.

---

<!-- INFO_SCREEN_START -->
SetsRepsWheels logs the sets, weights and repetitions of weight training. All the sets of an exercise are on one screen, and you set the numbers with picker wheels that start where you left them the last time you did that exercise — so tracking an exercise is just some flicks and a tap. There is a companion Apple Watch app that logs the same workout at the machine, and you can hand a workout over between your iPhone and your Watch part-way through. There is an optional rest timer that counts the rest between your sets and taps your wrist when it is over, so you can pocket the phone in between. Cardio fits alongside the weights: an aerobic exercise counts down instead of counting sets, and with an Apple Watch it runs as a real Apple workout, showing your heart rate zone and landing in Fitness. Once you have some history it estimates how your strength is trending per exercise, and shows you which exercises are moving and which are stuck. Everything stays on your devices unless you turn something on yourself.

I made this app for myself because I wanted logging to be quicker than in the apps I tried. It is deliberately bare-bones. I hope you find it useful too (though it is probably not the best workout app for everybody).

## Contents
- [Getting started](#getting-started) — defining your first workout and exercises
- [Logging a workout](#logging-a-workout) — the wheels, the buttons, which set you are on, skipping an exercise
- [Aerobic exercises](#aerobic-exercises) — cardio, with heart rate on the Watch
- [The rest timer](#the-rest-timer) — optional, off by default
- [Scheduling the next one](#scheduling-the-next-one) — optional, off by default
- [The Apple Watch app](#the-apple-watch-app) — logging at the machine
- [Handing a workout over](#handing-a-workout-over) — moving between iPhone and Watch
- [Apple Health](#apple-health) — optional, off by default
- [Editing workouts](#editing-workouts) — adding, ordering and removing exercises
- [The exercise library](#the-exercise-library) — finding exercises by muscle group
- [Editing an exercise](#editing-an-exercise) — sets, weight range, muscle groups
- [Your logs and statistics](#your-logs-and-statistics) — the four tabs
- [How the strength numbers work](#how-the-strength-numbers-work) — one-rep max, hard sets, trend
- [Muscle groups](#muscle-groups) — the body picture and the fifteen groups
- [Settings](#settings) — sharing between devices, Health, the rest timer, statistics, deleting data
- [Your data and privacy](#your-data-and-privacy) — what leaves your device
- [Notes and Feedback](#notes-and-feedback) — and the open source

## Getting started
When you open the app for the first time there are no workouts or exercises yet: you define them yourself.

The first time you open the app it asks for your usual numbers — how many sets you normally do, the lowest and highest weight you use, and the step between weights on the wheel. Every exercise you add starts from those, and you can change any of them later, per exercise or for all new ones in Settings.

Then tap **new workout** and give it a name. Tap **add exercise** to open the exercise library: pick a ready-made exercise, or tap **new exercise** to describe your own. Add as many as you like, then **save**. Back on the start screen your workout is listed, and tapping it starts logging.

## Logging a workout
Tap a workout on the start screen. The first exercise appears with a row of wheels for each set: the top row is the weights, the bottom row the repetitions. If you have logged this exercise before, the wheels start at the numbers you logged last time, so you usually only need to adjust what changed.

After finishing a set, tap **log, next** to record the exercise and move to the next one. On the last exercise that button reads **log, end**, which records it and takes you back to the start screen.

A set with no repetitions is not a set, so the button waits until at least one of the repetition wheels is off nought. What then goes into the log is every set on screen, a set you left alone included — which is why a workout where you stopped after two of three sets shows a third set of nought. The *logs* tab can be corrected afterwards on a Mac if you would rather it were not there.

### Which set you are on
Three sets is one more than you can keep track of while you are out of breath, so the app does it for you: a column of wheels turns **yellow** once it believes you have done that set. It works out from the wheels themselves, with no button to press, and it is only a reminder — what gets logged is still everything on screen when you press **log**. Yellow rather than the obvious green, because on the Watch green is already taken: watchOS rings whichever wheel the Digital Crown is pointed at in it.

The rule is five seconds of quiet. Arriving at an exercise you usually set the wheels up, three columns one after another; that flurry marks nothing, however long it goes on, because there is no pause in it. A touch on the leftmost unmarked column five seconds or more after you arrived — or after the last column was marked — marks that column, once you have left the wheels alone for five seconds again. So the mark always arrives about five seconds after you stop touching, and it goes left to right: reaching past a column does not mark it.

It is on the Watch too, on the same rule, and the marks travel with the workout if you hand it between your iPhone and your Watch part-way through. They last the whole workout and survive swiping to another exercise and back.

**quit** ends the workout without logging the exercise that is on screen. Anything you already logged during the workout is kept.

If a machine is busy you can skip ahead: swipe left for the next exercise you have not logged yet, and right for the previous one. Swiping leaves the current exercise without logging it, so you can come back to it later. **list** opens the whole workout and jumps straight to any exercise in it; the ones you have already logged carry a tick, and you can still go back to them — to add a set, or to look at what you did.

At the bottom of that list is a switch between the whole workout and **only what's left**. Part way through a long workout most of the list is behind you, and narrowing it puts what you still have to do under your thumb. Whichever exercise you are on stays listed either way, so the list can always tell you where you are, and a workout with everything logged shows the whole list again rather than nothing. The choice is remembered, and each device keeps its own.

## Aerobic exercises
Not everything in a gym has weights on it. An exercise can be **aerobic** instead of strength: pick it from the heart-shaped **AE** button beside the body picture in the exercise library, where every indoor workout the Apple Workout app offers is waiting ready-made — indoor walk, run and cycle, elliptical, rower, stair stepper, and the rest. Take one, or make your own and choose its activity on the *edit exercise* screen.

An aerobic exercise has no sets, weights or muscle groups, because none of those say anything about twenty minutes on a bike. It has one wheel for how long, and a **start** button.

The wheel opens on however many minutes you chose for that exercise last time — twenty to begin with — so a regular session is one tap to start. It remembers what you *chose*, not what you did: stopping a twenty-minute ride early does not quietly turn it into a shorter ride for ever after.

Starting one runs a countdown. As with the rest timer, the clock keeps the time rather than the screen, so you can pocket the phone: it buzzes and shows a notification when the time is up, and **stop** ends it early.

**log, next** stays greyed out until a session has actually run, because a number on a wheel is a plan and this app logs what happened. Once it has, what the session came to appears under the exercise name — the time, your average heart rate, and how long you spent in each zone — and the button comes back. What gets logged is what you actually did: stopping at twelve minutes of a twenty-minute ride records twelve. Those same numbers are what the *logs* tab shows for that session, in place of the weights and repetitions a strength exercise has.

With a Watch, the end of a rest is a tap on your wrist. How many taps is up to you, from one to five in Settings: watchOS has no way to make a tap harder, so the only way to make the end of a rest harder to miss in a gym is to repeat it. Two by default.

The rest timer stays quiet after cardio. You have just done twenty minutes of it, and a ninety-second rest prompt on top would be noise.

### With an Apple Watch
If you have one, the Watch does the measuring, and it does it as a **real Apple workout**: the session is written to Health as the activity you chose, so it appears in Fitness and counts towards your rings like any other. Starting on the phone wakes the Watch app by itself — you do not have to open it.

While it runs, the Watch shows your heart rate and which of five zones you are in, as a coloured band. You can start on either device and stop on either; whichever you use, the other follows.

From **watchOS 27** the zones are your own: Health hands over the very boundaries the Workout app is using, whether those are the ones it worked out for you or ones you set by hand, and the band here agrees with the one on your wrist. That needs an Apple Watch Series 9 or later, since no earlier Watch can run watchOS 27.

On an older Watch, the zones are worked out from your resting heart rate and your age, following the method Apple describes for its automatic zones. Expect them to be in the right area rather than identical — Apple uses a maximum heart rate measured from your own history, which no app can read, so a rate your Watch calls zone 3 may well show here as zone 4. If that bothers you, type the real boundaries in under **Settings › Heart rate zones**: open Health › Browse › Heart › Heart Rate Zones, copy the four numbers each zone starts at, and the Watch uses those instead. The line under the band on the Watch always says which of the three it is using.

Without a Watch everything works except the heart rate. The countdown runs, the session is logged with its duration, and the screen says plainly that heart rate needs a Watch rather than leaving a blank space. The session is still written to Apple Health as a workout of the chosen activity — the Fitness app has been on iPhone in its own right since iOS 16, with a Move ring but no Exercise or Stand ring — so it counts for what it can.

If a Watch is there but nothing arrives from it for a while, the screen says that too, and points at Settings › Health on the Watch. It does not claim to know that permission was refused: HealthKit deliberately will not say whether a read was denied, so the app reports what it can actually see — that no readings are coming — and names the likeliest fix.

### Only one workout at a time
**Your Watch runs one workout at a time.** That is watchOS, not this app, and there is no way round it: no app can see another app's workout session, let alone share one.

So starting a cardio session here ends whatever workout was already running. If you began a ride by holding your Watch to the machine, the machine stops showing your heart rate the moment you tap **start** here — that link belonged to the workout it just replaced. The same happens to a workout you started yourself in the Workout app.

Pick one, in advance. If you want the machine, or the Workout app, to have the ride, let it: start it there and leave the **start** button here alone. If you would rather have the ride in your log with its time in each zone, start it here and do not tap the reader. Either way, nothing is lost twice over — a ride recorded by the Workout app is still in Health and Fitness, it simply is not attached to the exercise in your log.

Weights are not affected while *Workouts on the Watch* is set to **hand over between devices**, which is the default: no workout session is started for the weights at all. With **Apple workout on the Watch** the whole workout is a session, and takes the Watch for its whole length.

## The rest timer
Off unless you switch it on, in Settings. With it off the app behaves exactly as it always has.

With it on, a rest is counted after every set, and after each exercise you log. What ends a set is a wheel: you roll it to what you just lifted, and the rest starts from there. On the iPhone the touch is enough on its own, so moving a wheel and putting it back on the same number counts too — which is what happens when you simply repeat the previous set — and a plain tap on a wheel is the easiest way to start a rest by hand.

The rest happens on the screen you are already on. The log screen greys over the moment it starts, and the grey drains down as the rest runs: how much is left is how much time is left, readable from across a bench. The seconds show small beside **log exercise** at the top, and tapping them ends the rest. The wheels stay usable throughout, and touching one starts the rest again from the top — because a wheel that moves is a set that just finished.

Earlier versions took the screen away for a separate countdown with a **skip rest** button. It was fussy in use: the screen you needed for the next set was gone, and you had to dismiss it to get back.

While a rest runs you are free to put the phone in your pocket or use something else. The countdown is only a display: the rest is kept by the clock, and a notification arrives when it is over whether or not the app is on screen. How loudly that lands is the phone's business rather than the app's — an app cannot buzz you while it is in the background, so what you feel is whatever your Sounds & Haptics settings do for a notification. An Apple Watch that was nearby when the rest started is told when it ends and taps your wrist itself, which is the more dependable tap on the shoulder.

It works the same way on the Apple Watch, though it looks different there: a bar fills the left edge of the screen when the rest starts and drains away as it runs, under the **weight** and **reps** labels, where it crosses nothing you need to read. It is split down its length into two colours. The red half is the rest itself, draining once from top to bottom across the whole of it; the orange half beside it sweeps the full height every fifteen seconds and starts again, so there is always something moving fast enough to see. A long rest drains about two points a second, which is too slow to tell from a bar that has stopped. The seconds show small over the wheels, or beside the exercise name, and tapping them ends the rest. One difference the hardware forces — the Digital Crown only reports a wheel that actually lands on a new number, so on the Watch repeating a set exactly is best logged with the **log** button rather than by nudging a wheel back where it was.

Whichever device you are logging on runs the rest, and ending it on one calls it off on the other. A rest started on the Watch stays on the Watch, so your phone does not buzz in a locker for a set you logged at the machine. If you move the workout between devices in the middle of a rest, the rest moves with it and carries on where it was — the time the hand-over takes comes off the rest rather than being added to it.

How long the rest is belongs to the exercise, because a heavy compound needs longer than a light isolation movement. The first-run question sets what new exercises start with, from 0:15 up to 5:00 in quarter minutes and 1:30 by default; any exercise can be given its own on its *edit exercise* screen, and Settings holds the starting value for new ones.

## Scheduling the next one
Off unless you switch it on, in Settings under **Schedule the next workout**.

With it on, finishing a workout offers to put the next one in your calendar. The moment is deliberate: you have just trained, so you know when you are coming back. Opening a workout and leaving it again without logging anything is not a workout, so nothing is offered — on the phone or on the Watch. It proposes the time this workout began, rounded up to the quarter hour, a chosen number of days from now — and you can change the day and time before adding anything. The event is as long as the workout you have just done, rounded up the same way, because whatever you usually take is what you just took.

You can put in just the next one or the next few at a spacing you choose, and you can say which calendar they go in. Scheduling again later moves what has changed and leaves the rest exactly where it is, so an event you have edited by hand — a different time, an alarm, somebody invited — keeps your edit.

The workout you have just **done** goes in too, at the time it really happened rather than the quarter hour a plan is rounded to, so your calendar reads as a record of your training and not only a plan for it. That one is named for the workout and then its group — "Biceps curls — Pull" — because by then there is nothing left to decide, and which of them you actually did is the whole point of keeping it. Nothing the app does afterwards touches a record: rescheduling will not move it, and switching anything off will not take it away.

Say "not now" to the next one and today is still written down, as long as you are already using the calendar for that workout. And when a workout is finished, plans of the app's own whose time has come and gone are cleared out of the last fortnight — either you did it, and there is now a record saying so, or you did not. Either way, a date last Tuesday saying you are about to train is no use to anybody.

Nothing is ever added without you asking, and the app only ever touches events it added itself: each one carries a mark of its own, and anything else in your calendars is left alone and never read. Delete one in the Calendar app and it stays deleted. iOS asks for full access to Calendars rather than add-only, and that is the reason — finding the app's own events again is what makes moving them possible instead of leaving a trail of duplicates behind.

The mark travels with the event, so an iPhone that gets a workout added by another of your devices recognises it and moves that one rather than adding a second. It can only do that for a calendar it can actually see, though: an event written to a calendar that is not on this phone is one this phone cannot find, and rescheduling will add its own beside it. One iPhone and one iCloud account is the ordinary case, and there is nothing to notice.

### Workout groups
Some sessions are done more than one way. If you train at two gyms the machines differ, so you keep two versions of the same workout — and scheduling whichever one you happened to do last puts the wrong gym in your calendar.

Switch on **Schedule by group** and you can put those workouts in a group. The calendar then gets the group's name, and which of its workouts you actually do is decided on the day, at the door.

Turning it on is a short job rather than a switch: you name your groups and say which group each workout is in, and it only takes effect once every workout has one. That is deliberate — half-assigned, your calendar would name some workouts by their group and some by themselves, with nothing to tell you which you were about to get. After that, a new workout asks for its group, and you can change it any time on the workout's own screen or on the Mac.

The Mac app's Settings has the same **Workout groups** section — naming them, saying which group each workout is in, and the switch itself — because all of it travels through iCloud. The Mac never writes to a calendar; it says what gets scheduled and your iPhone does the writing. When the Watch asks at the end of a workout whether to schedule the next one, it asks by the group's name too.

A workout belongs to one group at most. You can switch grouping off again whenever you like, and nothing is stranded in your calendar: a workout you had already scheduled under its group is found again, renamed back to itself, and carries on being moved as usual — and switching it back on collapses the separate events of a group's workouts into one instead of adding to them. Your groups are remembered either way.

## If the app closes mid-workout
iPhones close apps that have been in a pocket for a while — that is iOS reclaiming memory, and no app can prevent it. Opening SetsRepsWheels again within the hour takes you straight back to the workout you were in, on the exercise you were on, with everything you had already logged and every number you had dialled into the wheels. A badge says **Carried on from earlier** so you can tell it apart from a fresh start.

The same hour decides when a workout you never finished is treated as over: an hour after your last logged exercise it is written to Apple Health as having ended then, not whenever you next opened the app.

## The Apple Watch app
The Watch app is a companion to the iPhone app: it shows your workouts and lets you log them at the machine, without taking your phone out. Everything else — creating workouts and exercises, browsing and exporting logs, settings — is done on the iPhone.

Your workouts appear on the Watch automatically; they are sent from the iPhone, so open the iPhone app once after you change something. Tap a workout to start logging.

Because the screen is small, the Watch shows **one** row of wheels at a time. The button at the top switches between the repetitions and the weights; whichever row is not on the wheels is shown underneath them as numbers, prefixed **r** for repetitions and **w** for weights. The exercise starts on the repetitions.

If the rest timer is on, it runs here too — see [The rest timer](#the-rest-timer).

The buttons work like the iPhone: **log** records the exercise and moves on (**end** on the last one; **reps?** while every repetition wheel is still on nought, for the same reason as on the phone), **quit** ends the workout, and **list** jumps straight to any exercise, with a ✓ against the ones already logged. The last entry in that list switches it between the whole workout and only what's left, the same as on the phone — handy on a small screen, where the exercises still to do can otherwise be off the bottom. Swiping left and right moves between exercises without logging, exactly as on the phone.

### One row of wheels or two
Settings › *Wheels on the Watch*.

**One row** is how the Watch has always worked: a toggle at the top switches the wheels between repetitions and weights, and whichever row is not on the wheels is shown underneath them as numbers.

**Both rows at once** puts the weights and the repetitions on screen together, so there is nothing to switch at the machine. The wheels are shorter — three numbers each rather than five — the exercise name moves up onto the clock's row, and the numbers under the wheels go, since each row now shows itself. A rest counts down beside the name, which shortens to make room for it.

### Two ways to record a Watch workout
Settings › *Workouts on the Watch* chooses between them.

**Hand over between devices** is how the app has always worked, and stays the default. A workout can move between your iPhone and your Watch as often as you like; whichever one you pick it up on asks first, and nothing moves until you say so. The Watch does not record a workout of its own, so there is no heart rate during the weights.

**Apple workout on the Watch** makes a workout you start there a real Apple workout. Your heart rate is recorded, the zone shows as a colour behind the exercise name with a line across it marking where in that zone you are, and the workout lands in Fitness and counts towards your rings. The Watch also keeps the app on screen for the whole session, which is the other thing a real workout buys you — see above.

What it costs is the way back. A workout on your wrist cannot return to the phone part-way through: Health will not move a running session between devices, and ending it early to hand over would leave half a workout in Fitness. You can still **start on the phone and carry on at the machine** — the Apple workout is back-dated to when you really began, so its length is the whole workout, with heart rate from the moment the Watch picked it up.

While a workout is running on your Watch, the phone keeps out of the way: the workouts, *edit workouts*, *exercise library* and *settings* are greyed out, and a workout screen says where the workout is and offers the way back to the start screen. Your logs, graphs, progress and this information screen are all still there to read.

Cardio inside such a workout is still recorded as its own Apple workout of the activity you chose, because watchOS runs one workout at a time. A session with a bike ride in the middle therefore arrives in Health as three: strength, the ride, then strength again — which is what you did.

That same rule means an Apple workout here ends one started anywhere else, including by holding your Watch to a machine — see [Only one workout at a time](#only-one-workout-at-a-time) above. In this mode it is the whole workout that takes the Watch, not just the cardio.

### Keeping the app on screen between sets
Lower your wrist and the Watch goes back to the clock face, and by default raising it again only returns you to the app for about two minutes — roughly one rest. After that you have to find the app again to log the next set.

This is a Watch setting rather than anything this app controls, and it is worth changing. On the Watch, open **Settings › General › Return to Clock**, find **SetsRepsWheels** in the list of apps, choose **Return to App**, and set it to **after 1 hour**. You can do the same from your iPhone in the **Watch** app, under *General › Return to Clock*. A workout then stays where you left it for as long as the workout lasts.

Worth checking even if you have set it before: an app given its own entry can still be sitting on the two-minute default.

## Handing a workout over
A workout runs on one device at a time, and you can move it across whenever you like — the sets you have already logged, the wheel positions and where you are in the workout all come with it.

When a workout is running on one device and you open the other, that other device shows that the workout is active elsewhere and offers **Continue here**. Nothing moves until you tap it: just looking at your Watch never takes the workout off your phone. Tapping **Continue here** brings the workout across, and the device you left shows the same offer, so you can move it back just as easily. **Not now** dismisses the message and lets you use that device normally.

## Apple Health
The app can save each finished workout to Apple Health as a **Traditional Strength Training** session. This is **off by default** — turn on *Save workouts to Apple Health* in Settings, and grant permission when iOS asks.

With *Workouts on the Watch* set to **Apple workout on the Watch**, a workout you log on your Watch is written to Health by the Watch itself, as the Apple workout it is, whatever the setting above says — and the setting then covers the rest, the workouts you log only on the phone. It is labelled that way when you choose that mode.

Only the workout itself is recorded: when it started, when it ended, and therefore how long it took. Your sets, weights and repetitions are **not** written to Health. The duration covers the whole workout even if you handed it over between iPhone and Watch part way through, and the workout is written by the iPhone, so it also works if you do not have an Apple Watch.

An **aerobic exercise** is different, and deliberately so: it is recorded by the Apple Watch as a real workout of the activity you chose — an indoor cycle as an indoor cycle — which is what makes it show up properly in Fitness and count towards your rings. That one does need a Watch, and it happens whether or not the setting above is on, because it is the workout itself rather than a copy of your log.

### What is read
Heart rate is the only thing this app reads from Health, and only on the Apple Watch: while an aerobic countdown is running, and — if you chose *Apple workout on the Watch* — during the workout itself. It is used to show your current rate and zone, and to record the average, the maximum and the minutes in each zone against that session. Your resting heart rate and date of birth are read at the start of a session for the sole purpose of working out where your zones fall.

None of it is sent anywhere. Heart rate never leaves your devices, and it is never included in the anonymous data you can choose to share with the developer — see [Your data and privacy](#your-data-and-privacy).

A workout is recorded when you end it, either with **log, end** or with **quit**. If you forget to end one, it is closed automatically after an hour without activity and recorded as having ended at your last logged set, so a forgotten workout does not turn into an eight-hour one.

## Editing workouts
Once you have a workout, **new workout** on the start screen becomes **edit workouts**. Beside it, **exercise library** is where all your exercises live.

**edit workouts** lists your workouts. Tap one to change it. On the *edit workout* screen you can rename it, and:

   - **add exercise** — opens the library to pick one, or make a new one
   - tap an exercise — opens it, to change its sets, weights or muscle groups
   - drag the handle on the right — moves an exercise up or down in the workout
   - the red button on the left — takes an exercise out of this workout; the exercise itself stays in your library

**quit** leaves without keeping anything you changed on that screen, and **save** keeps it. A workout needs a name before it can be saved, and the name has to be one you are not already using: two workouts with the same name cannot be told apart in your logs.

Back in *edit workouts* you can likewise reorder your workouts and remove one with the red icon. Swiping a workout to the right offers two more: **Duplicate**, which copies it under a new name over the same exercises, and **Merge**, which makes a third workout out of this one and another — this one's exercises, then the other's, with anything in both appearing once. Neither original is changed, so a split routine can be tried out before anything is thrown away. The same two are on a long press.

## The exercise library
**exercise library** holds every exercise: the ones you have made and the ready-made ones you have not taken yet, together in one list.

At the top is a picture of the front and back of a body. Tap a muscle on it — or one of the labels beside it — to narrow the list to exercises for that muscle group. **all groups** brings everything back. The button on the right of that row swaps the picture for plain buttons if you prefer, and the star beside it narrows the list to your favourites.

In the list, a **star** marks an exercise as a favourite, which also floats it to the top. A tick on the right means the exercise is in one of your workouts. Tapping one of your own exercises opens it; tapping a ready-made one copies it into your exercises, with its muscle groups already filled in. Swiping an exercise to the left offers **Duplicate**, for a variant that keeps the original's settings, and **Delete**.

Deleting an exercise removes it from your list *and* from any workout that used it. Sets you have already logged are kept.

## Editing an exercise
On the *edit exercise* screen you set the name, the number of sets, the lowest weight, the highest weight and the increment that determine the numbers on its wheel, the rest this exercise gets when the rest timer is on, and the muscle groups it works. Underneath, **In these workouts** shows which workouts contain it, and you can add or remove it from any of them right there — the same relationship, editable from either end.

### Kilograms or pounds
Settings › *Weights in*. Pounds to start with in the United States and Canada, kilograms elsewhere, and you can change it whenever you like.

Your weights are stored in a form that has no unit at all, so switching re-presents everything you have ever logged in the other one. Nothing is recalculated, nothing drifts, and switching back and forth costs nothing.

The unit is written only where you type a weight — on the *edit exercise* screen, beside each of the three numbers. The wheels, your logs and the graphs leave it off: the unit is the same down the whole screen there, and the space is worth more than the repetition.

Weights can be halves and quarters, which is what machines are actually marked in: a half-pound increment, a quarter-kilogram plate. They are written with the short forms — 130, 130¼, 130½, 130¾ — because "130.25" is wider than a wheel wants to be.

If you were using the app before it knew about units, it asks once what the weights you have already logged were in. Your numbers do not change: 130 stays 130, and the answer only says what it means.

### Machines that take weight off you
An assisted chin-up or dip works the other way round from everything else: the number you set is how much of your own weight the machine carries, so a *bigger* number is an *easier* set. Tick **subtracted from body weight** on the exercise and the app handles that.

The wheels still show what you set on the machine, because that is what you do at the machine. What gets logged is what you actually lifted — your body weight less that setting — so your graphs, trends and one-rep-max estimates read the right way round, and an assisted chin-up can be compared with any other exercise. Each set also records the body weight it was worked out from and the machine's own number, so an old session still makes sense years later when your weight has moved.

Your body weight comes from Settings: from Apple Health, where it follows your weigh-ins on its own, or typed in and left alone. Nothing is ever written to Health.

**In the same units as your weights.** This app has no units of its own — the wheels are numbers, and whether they mean kilograms or pounds is between you and your gym. A body weight in kilograms against a machine set in pounds is nonsense, so from Health it arrives in whichever unit you read your weight in there. Until a body weight is known, an exercise like this cannot be logged: the screen says so and the log button waits, rather than recording a set you did not do.

One consequence worth knowing: because the logged weight moves with your body weight, the colours in your logs ignore any difference of half an increment or less. A kilo after breakfast is not a personal best.

**An ordinary chin-up or dip** — no machine, no assistance — is the same thing with nothing taken off: tick *subtracted from body weight* and leave the machine setting at 0. What gets logged is your body weight, which is what you lifted, and it follows your weight as it changes.

An exercise needs a name and a primary muscle group before it can be saved, and the name has to be one you are not already using. Without a muscle group an exercise cannot be found on the body picture or grouped with anything else. **quit** leaves without keeping your changes; on an exercise you have only just created, it removes it again rather than leaving a nameless one behind.

## Your logs and statistics
The **logs/stats** button opens four tabs.

**logs** shows your logged sets, most recent first, with each set coloured against the same set of the last time you did that exercise. A number is green when it went up and the other one did not go down, and red when it went down and the other one did not go up. So more weight for more reps is green on both, and less for fewer is red on both — but more weight for fewer reps is a trade rather than an improvement, and neither number is coloured, because which side of it came out ahead is not something the app can know.

**graphs** draws one chart per exercise: a dot for each workout, and a straight trendline through them. A graph appears once you have logged that exercise in at least 8 workouts, so the tab fills in gradually; below the graphs you will see which exercises are still short and by how much.

**progress** lists those same exercises ordered from least to most progress, so whatever is falling behind is at the top. Each line shows the trend per week, the best estimate from your last workout, and how many hard sets that exercise usually takes.

**import/export** holds the file tools:
   - export TSV — your log as a tab separated file, easy to open in a spreadsheet
   - export JSON — your log together with your workout and exercise definitions, and what hangs off each set: what an aerobic session measured, and the body weight and machine setting behind an assisted one
   - import JSON — read back a file in the same format (easiest starting from one you exported). Files exported by older versions still read; they simply have none of the extra detail.
   - undo import — restore the previous data if an import did not do what you wanted

Exports are sent wherever you choose. Editing an exported JSON file and importing it back is currently the only way to correct a mistake in your log; I intend to make that easier.

Picking a file to import does not change anything by itself. The file is read
and described first — what it holds, when it was written and which app wrote
it, and how its counts compare with what you have — and only then are the two
things that write offered:
   - merge into what I have — add only what is missing, never overwriting a set you already have
   - replace everything — throw away what is in the app and put the file in its place

A file that cannot be read says why, and neither button is offered. Either way
a copy of what you have now is kept first, which is what **undo import** puts
back.

## How the strength numbers work
Everything on the graphs and progress tabs comes from one idea: from a set of several repetitions you can estimate what you could have lifted just once. That estimate is your **one-rep max**, and tracking it lets a heavy set of 5 and a lighter set of 12 be compared on the same scale.

You choose the formula in settings. All three are in common use and none is exactly right; they mostly agree, and what matters is that you keep to one:
   - **Epley** — w × (1 + r/30), the default
   - **Brzycki** — w / (1.0278 − 0.0278 × r)
   - **Lombardi** — w × r^0.1

For each exercise in a workout, the app takes the best estimate among its sets. That best number is what the graphs plot and what the trend is measured on.

A set counts as **hard** if it was your best set that day, or if four more repetitions at that weight would have matched it. The rest count as warm-ups or back-off sets. This is the app's measure of how much real work an exercise took.

The **trend** is a straight line fitted through your best estimates over your most recent workouts (16 by default, at least 8), divided by their average so that exercises of very different weights can be compared. It is shown as a percentage per week. Steady progress is a small number: around half a percent to one percent per week is real progress, and a long run at zero means a plateau, not a mistake.

The dots on a graph can be averaged over several workouts to make the pattern easier to see — 3 by default. Averaging only affects the dots; the trendline always follows your actual numbers.

Two cautions. These are estimates from your own logged numbers, not measurements: a bad night's sleep shows up as lost strength. And a trend needs a run of workouts before it means much — with 8 workouts a single unusual day still moves it.

## Muscle groups
An exercise records which muscles it works: one **primary muscle group** and up to four **secondary** ones, from a fixed list of fifteen. The primary group is required, because it is what the body picture and the filters go by, and what lets the app group your training by muscle rather than by exercise name.

The body picture in the library is an anatomical drawing with each of those fifteen groups marked on it. Tapping a muscle selects it; tapping it again clears the selection. Where two groups overlap — the traps lie over the upper back, the deltoid heads run into one another — the smaller one takes the tap, since the larger has plenty of clear area elsewhere. Muscles that show from both sides, like the traps and the side delts, can be tapped on either figure.

The **ready-made exercises** cover every primary muscle group and come already filled in, so most people never need to describe an exercise from scratch. Taking one copies it into your own exercises, where you can rename it and change anything you like.

## Settings
The settings screen has:
   - **Share data among your iPhones/iPads** — keeps your workouts, exercises and logs in step across your devices through your own iCloud account. Off by default.
   - **Save workouts to Apple Health** — see [Apple Health](#apple-health) above. Off by default.
   - **Rest timer** — counts your rest after every set and after each exercise you log. Off by default, see [The rest timer](#the-rest-timer) above. With a Watch, **taps on the wrist** sets how many taps mark the end of a rest, from one to five.

   - **Workouts on the Watch** — hand over between devices, or record a Watch workout as a real Apple workout. See [The Apple Watch app](#the-apple-watch-app) above. Handing over by default.
   - **Weights in** — kilograms or pounds. See [Kilograms or pounds](#kilograms-or-pounds) above. Follows your region to begin with.
   - **Body weight** — from Apple Health or set by hand, used only by exercises marked *subtracted from body weight*. Shown only when you have one. See [Machines that take weight off you](#machines-that-take-weight-off-you) above.
   - **Wheels on the Watch** — one row with a reps/weights toggle, or both rows at once. See [The Apple Watch app](#the-apple-watch-app) above. One row by default.
   - **Heart rate band** — how strongly the zone colours are drawn behind the exercise name on the Watch, from barely there to full strength, with a preview to judge it against. Only shown when the Watch records Apple workouts.
   - **Heart rate zones** — the four boundaries between the five zones. On watchOS 27 and later there is nothing to set: they come from Health. On an older Watch you can copy them in by hand rather than let the app estimate them. See [Aerobic exercises](#aerobic-exercises) above.
   - **Remember an exercise across workouts** — on by default: a wheel opens on the last time you did that exercise, whichever workout you did it in, so splitting or reorganising a routine keeps your numbers. Turn it off if you want each workout to remember its own — a heavy day and a light day that share an exercise.
   - **Numbers for a new exercise** — the sets, weight range, increment and rest each new exercise starts with. Exercises you already have are not changed.
   - **Schedule the next workout** — whether finishing a workout offers to put the next one in your calendar, and how far ahead. Off by default, see [Scheduling the next one](#scheduling-the-next-one) above.
   - **One-rep max formula** — which of the three formulas the statistics use. Epley by default.
   - **Workouts in the trend** — how many recent workouts the trend line uses, 16 by default and never fewer than 8.
   - **Averaging in graphs** — smooths the dots over this many workouts, 3 by default; set it to off to see every workout as logged.
   - **Share anonymous data with the developer** — off by default, see below.
   - **Delete all my data** — removes everything this app has stored, and takes back anything you shared anonymously. With iCloud sharing on, it also removes it from your other devices.

### Settings on the Mac
Most of these settings travel with your workouts and exercises, so the Mac app's Settings can set them too — including the ones that are used on your iPhone and Watch, which the Mac does not have. Change a setting on either and the other follows; what the Watch needs reaches it the next time your iPhone sees the change.

Five settings stay with the device you set them on, because each is a fact about that device rather than about your training:

   - **Save workouts to Apple Health** and **Body weight from Health**, which depend on a Health permission each device grants separately.
   - **Which calendar** the next workout goes in, because a calendar's identifier means nothing on another device.
   - **Share anonymous data with the developer**, because each device sends its own.
   - **Share data among your iPhones/iPads**, which is the switch that makes the rest of this possible and so cannot travel through it.

The Mac also has **Text size**, which no other device needs, and does not have **Delete all my data**.

## Your data and privacy
Your workouts, exercises and logs are stored on your device. There is no account and no tracking: nothing about you is collected automatically, and nothing is sold or shared with anyone else, ever.

Four things can leave the app, and every one of them is off until you switch it on:

   - **iCloud sharing** keeps your data in step across *your own* devices through your private iCloud account.
   - **Apple Health** receives the start and end time of a finished workout. Data sent to Health stays on your device under your control in the Health app, where you can review or withdraw it at any time.
   - **Exports** go wherever you send them.
   - **Sharing anonymous data with the developer** sends your logged sets so the app can be improved with real training data — in particular the individual advice described below. This is the one thing that goes to me rather than to you, so it is worth being precise about.

What that last option sends, when you turn it on: the weights, repetitions and dates you logged, which muscle groups an exercise works, and your answers if you fill in the questionnaire. What it never sends: your name, your Apple ID, your device, your location, or the names you gave your workouts and exercises. An exercise you named yourself travels as an unreadable code, unique to your installation, so your own sets can be recognised as belonging together without the name being recoverable. Exercises taken from the library also carry the library's own name for the movement, which is what allows a bench press to be compared across people.

Your data is identified only by a random code created on your device the first time you turn the option on. It is not linked to your Apple ID or to anything else about you, and I have no way to work out who any of it belongs to. Turning the option off deletes what your device has shared, and so does *Delete all my data*.

Once you have been using the app for a while you may see a short questionnaire, asking which parts of logs/stats you find useful and whether you would want more individual statistics. Answering is voluntary, "Not now" is a complete answer, and it will not keep asking.

## Notes and Feedback
1. This app is free and open source. The source is on GitHub:
   https://github.com/dutch-rob/workout_aicode
2. Feedback is very welcome, in an App Store review or on GitHub — pull requests too. For example:
   - Did anything go wrong? (Please describe what you did.)
   - Is the Apple Watch app missing something you need at the machine?
   - Should the app log something it does not log now?
   - Changes to the log screen or the exports?
   - Would you like to edit logged data in the app, and how would you expect that to work?
   - Statistics or trends?
3. The muscle diagram is "Muscles front and back" by OpenStax, Tomáš Kebert and umimeto.org, from Wikimedia Commons, used under the Creative Commons Attribution-ShareAlike 4.0 licence (https://creativecommons.org/licenses/by-sa/4.0/). It was cropped into two figures and given a transparent background; the anatomy itself is unchanged. Those two images stay under CC BY-SA 4.0.
<!-- INFO_SCREEN_END -->
