# Architecture

For somebody reading this code for the first time. The user guide is
[README.md](README.md); this is the map underneath it.

The code itself is commented generously, and those comments are the real
documentation — most of them say why something is the way it is, usually
because the obvious version was tried first and failed. This file exists to
tell you which of them to go and read.

## The name

The product is **SetsRepsWheels**. The repository, the targets, the folders
and the Swift modules are all called **workout_aicode**, which is what Xcode
was given on the first day and has been the internal name ever since.

The two can't be fully reconciled, and it is worth knowing which parts are
frozen before you try:

| | can it change? |
|---|---|
| `robotex.workout-aicode` and `robotex.workout-aicode.watchkitapp` (bundle IDs) | **No.** The apps are on the App Store under them. |
| `iCloud.robotex.workout-aicode` (CloudKit container) | **No.** Renaming it orphans everybody's data. |
| Folder, target, scheme and module names | Yes, but it is a large, dull change across nine directories, the test hosts, the schemes and every `@testable import`. |

What *is* already consistent is everything a user sees: `CFBundleDisplayName`
is SetsRepsWheels on all three platforms, and the Mac target's `PRODUCT_NAME`
is too, so the menu bar and the Finder agree with the App Store. The Mac
target also pins `PRODUCT_MODULE_NAME` back to `workout_aicode_MacOS`, which
is why its product is `SetsRepsWheels.app` while its tests still say
`@testable import workout_aicode_MacOS`.

So: when you see `workout_aicode` in a path or an import, read it as "this
app". Nothing is hiding behind the two names.

## Targets

Nine targets, three of them apps.

| Target | Folder | Scheme |
|---|---|---|
| `workout_aicode` (iPhone) | `workout_aicode/` | `workout_aicode` |
| `workout_aicode Watch App-` | `workout_aicode Watch App/` | `workout_aicode Watch App-` |
| `workout_aicode_MacOS` | `workout_aicode_MacOS/` | `workout_aicode_MacOS` |
| `workout_aicodeTests` | `workout_aicodeTests/` | (in the iPhone scheme) |
| `workout_aicode Watch AppTests` | `workout_aicode Watch AppTests/` | (in the Watch scheme) |
| `workout_aicode_MacOSTests` | `workout_aicode_MacOSTests/` | (in the Mac scheme) |
| three UI test targets | `*UITests/` | — |

Two things to know before you go looking:

* The watch target's name really does end in a hyphen — `workout_aicode Watch
  App-`. Quote it in any `xcodebuild` command.
* There is a second, **sourceless** `workout_aicode Watch App` target in the
  project with no files and nothing depending on it: a leftover from the
  rename that produced the hyphenated one. Ignore it.

Every group is a **file-system synchronized group** (Xcode 16 and later). A
`.swift` file dropped into a target's folder is in that target, with no
project-file edit. This also means a stray file in one of those folders gets
compiled, so don't leave scratch files there.

## `Shared/`

`Shared/` is compiled into **all three apps** — iPhone, Watch and Mac. That is
the one rule in the project that will bite you:

> Anything you put in `Shared/` must compile on watchOS and macOS too.

No `UIKit`, nothing that assumes a phone. `Shared/Models.swift` has a comment
about the time the model layer quietly acquired a UIKit dependency through a
default value, and what it cost.

The payoff is the wire format. `Shared/WatchSync.swift` holds the Codable
types the phone and the Watch exchange, and because both ends compile the same
file the JSON keys cannot drift. They used to be two hand-synced copies.

## Data

SwiftData, backed by CloudKit when the user turns iCloud on.

* `Shared/Models.swift` is the whole schema: `ExerciseDef`, `WorkoutDef`,
  `WorkoutLog`, `AerobicResult`, `AssistedResult`, `LogWeights`,
  `DraftSession`, plus `ExportEnvelope` for the JSON files.
* **Ten versioned schemas**, `WorkoutLogSchemaV1` … `V10`, and
  `WorkoutMigrationPlan` between them. A `VersionedSchema` is only meaningful
  if its model shapes stay fixed, so the old ones are frozen copies — don't
  "tidy" them.
* **Fields are never deleted.** A field that has been in a CloudKit schema is
  there for good. `MovementType` is the clearest example: nothing reads it,
  every exercise is `.none`, and it stays because removing it would break
  existing stores and older export files.
* `Shared/SyncedSettings.swift` and `AppSettings` are the **settings that
  travel**. Preferences used to be `UserDefaults` on each device, which is why
  the Mac could show a setting and never change anything — nothing syncs
  UserDefaults. The ones that are about TRAINING rather than about a device now
  live in the store and reach every device the way workouts do.

  It is a MIRROR, not a rewrite. `UserDefaults` is still what the app reads,
  everywhere it always did: thirty-odd `@AppStorage` bindings,
  `WorkoutSchedule.isEnabled`, `WatchPreferences.zoneTint` and the payload the
  Watch is sent all read it from a static context, and routing those through a
  `ModelContext` there is none would have been a large change for nothing.
  `SettingsMirror` runs the step at launch, on any UserDefaults change, and on
  coming back to the front. No view knows any of this exists.

  Three rules worth knowing. **Duplicates are possible** — CloudKit has no
  uniqueness, so two devices can each make the first record; newest
  `updatedAt` wins and `resolve` deletes the rest. **The iPhone's answers
  win once**: a Mac or iPad that opens first seeds the record provisionally,
  and the first phone overwrites it, after which `seededBy` says "iPhone" and
  normal last-writer-wins applies. And **`revision`, not `updatedAt`, decides
  what to adopt** — a `Date` put through Core Data comes back a ten-millionth
  of a second later than it went in, because Core Data counts from 2001 and
  this counts from 1970, so every run looked newer than the last and nothing
  a device changed was ever published.

  What does NOT travel is listed on `AppSettings`: Health sharing and the
  body-weight source (a per-device HealthKit authorisation), the calendar id
  (an `EKCalendar` identifier means nothing elsewhere), the developer-sharing
  consent (each device uploads on its own), the iCloud switch itself, and the
  Mac's text size.

  The phone sets `SettingsMirror.didAdopt` to `reloadAll`, and must: the Watch
  only ever hears from the phone, so a wheel count set on the Mac would reach
  the phone and stop there.
* `Shared/WorkoutGrouping.swift` holds the rules for **workout groups**: a
  set of workouts that mean the same session, for somebody who trains the same
  muscles two ways at two gyms. When grouping is on it is the GROUP that gets
  scheduled, so the calendar says "Push" rather than whichever variant was
  done last. Nothing else in the app knows groups exist — logging, statistics
  and the start screen are untouched.

  The switch does not simply turn on: it opens `WorkoutGroupSetupView` and
  only takes once **every** workout is in a group. A half-assigned state would
  mean the calendar named some workouts by their group and some by
  themselves, with nothing on screen saying which. `canEnable` is that rule.

  The Mac has the switch too, since `scheduleByGroup` travels with the other
  settings (`SyncedSettings`) and a Mac reading it no longer always sees
  "off". It is shaped differently: the phone's switch opens the setup sheet,
  while `MacWorkoutGroups` already IS that screen, so there the switch simply
  refuses to move until `canEnable` says yes, and drops itself if an edit
  invalidates it. The mutations both screens run are
  `Shared/WorkoutGroupEditing.swift`, so the iPhone sheet and the Mac section
  cannot drift apart. The calendar itself stays the phone's: the Mac can say
  what gets scheduled, not write it.

  What the WATCH is told is the group's NAME, resolved by the phone before the
  payload goes out (`SyncWorkout.groupName`), because the Watch cannot edit
  groups and would otherwise need the group list and the ids to join it with.
  `SyncWorkout.scheduledName` is what the end-of-workout offer uses, so the
  wrist and the calendar name the same thing.
* `Shared/CalendarIdentity.swift` decides **which calendar events belong to
  which workout**, and it is the reason the grouping switch can be moved at
  all. An event carries BOTH ids it could be filed under —
  `setsrepswheels://workout/<workout id>?group=<group id>` — where the workout
  id is whichever of a group's workouts was actually finished.

  With one id, turning grouping off orphaned everything written while it was
  on: the app looked for the workout's id, found an event filed under the
  group, matched nothing, wrote a second event, and left the first in the
  calendar for ever with nothing able to claim it again. `ScheduleTarget.claims`
  is the rule that fixes it — grouped, the group's id matches and so does any
  of its workouts', which collapses their separate events into one; ungrouped,
  only the exact workout, so alternating a heavy day and a light one still
  keeps two events and finishing one does not touch the other.

  A URL with no `group` is read as BOTH ids at once. Every event written
  before this, and every ungrouped one written after it, is like that: the app
  wrote one id without saying which kind it was, and reading it as both makes
  the two cases the same case — UUIDs being UUIDs, no workout can claim a
  group's event by accident. An event found again under the other id is
  ADOPTED where it sits (re-tagged and retitled) rather than removed and
  re-made, so an alarm or an invitation on it survives; one whose ids already
  match is not touched at all, so a title typed over by hand survives too.

  A third thing on the URL, `done=1`, says whether an event is a **plan** for
  a workout or a **record** of one that happened. They are treated as
  opposites: a plan is the app's to move, retitle or remove whenever the
  schedule changes, and `claimsPlan` is what every such path asks; a record is
  a fact and nothing reaches it again. Without the mark the next reschedule
  would find a record sitting at a time nobody wants any more and delete the
  only evidence the workout was ever done. A record is named for the workout
  and then the group — "Biceps curls — Pull" — because the thing a plan cannot
  say ("which of them will it be?") is settled by the time one is written, and
  saying which is the whole value of keeping it. It gets the real times, not
  the quarter hours a plan is rounded to.

  Plans whose time has come and gone are cleared away by the next finished
  workout, two weeks back (`WorkoutCalendar.noteFinished`, `sweepsUp`). They
  have to be, because a reschedule only ever looks FORWARD: a plan that had
  already finished by the time the workout ended was never in its window, and
  would sit in last Tuesday for ever next to nothing saying whether Tuesday
  happened. Finishing a workout is the one moment the app learns something
  about a day gone by, and the only thing allowed to touch one.

  Both types are plain values with no EventKit in them, so the decision is
  tested (`CalendarIdentityTests`) rather than tried out on a real diary.
  `WorkoutCalendar` searches `calendars: nil` — every calendar, not just the
  one it writes to — so an event another device put somewhere else is still
  found; what it cannot see, it cannot move.
* `Shared/LogTransfer.swift` is the whole JSON/TSV transfer format and the
  only place that knows what a file may say, what replacing means and what
  merging means. Both apps import through it. They did not always: the phone
  grew its own copy inside its view, the two drifted, and the phone's copy
  ended up crashing on a file with no logs. A screen decides which buttons to
  offer and what to say afterwards; it decides nothing about the format.
* `Shared/StoreSave.swift` is the only place that saves. Every write used to
  end in `try? context.save()` — a failure nobody heard, in an app whose job
  is remembering what you lifted. Read the comment at the top of that file
  before adding a save anywhere else.

### Weights

Weights are stored in **grams**, as integers. Alongside them sit the original
unit-less integers (`lowestWeight`, `highestWeight`, `weightIncrement`), which
are legacy, are no longer written, and cannot be removed — an older Watch and
the export format still read them.

`Shared/WeightStorage.swift` is where the two live together, and
`legacyRangeIsTheSameWheel` is the function that decides whether a number from
an older device means a *position on the wheel* or a *weight*. The comments
there are worth the read; the distinction is not obvious and getting it wrong
silently moves people's numbers.

## Phone ⇄ Watch

`WCSession`, driven from `workout_aicode/PhoneSessionManager.swift` and
`workout_aicode Watch App/WatchSessionManager.swift`, over the value types in
`Shared/WatchSync.swift`:

* **Phone → Watch**: `SyncPayload` (workouts, exercises, prefill history) via
  `updateApplicationContext`, plus live "mirror" messages so the Watch can
  follow the exercise being logged on the phone.
* **Watch → Phone**: a finished set as a `logSet` dictionary via
  `transferUserInfo`, which survives the counterpart not being open.

Only one workout runs at a time, on one device; `Shared/OpenWorkoutPolicy.swift`
holds the rules for when an open workout goes stale, and the hand-over between
devices is in `WatchStatusViews.swift` on the phone side.

## Concurrency

The project compiles in **Swift 6 language mode**, with
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` on every app and unit-test target.
So the default is: everything is on the main actor unless it says otherwise.

Things that say otherwise are marked `nonisolated`, and they are all the same
kind of thing — value types and arithmetic with no interface in them:
`WeightUnit`, `WeightText`, `MuscleGroup`, `HeartRateZones`, `StatsEngine`,
`WorkoutSchedule`, `RestBar`, the `WatchSync` wire types, and the `Shape`
conformances (SwiftUI calls `path(in:)` off the main actor). They have to be,
because the SwiftData models call them from their own methods, and the tests
call them too.

The three **UI** test targets are deliberately left on the default isolation:
their cases subclass `XCTestCase`, whose `setUp`/`tearDown`/`init` are
nonisolated, and a main-actor default makes every override a mismatch.

### The one that mattered

Both `WCSessionDelegate` conformances are `nonisolated`, and that is not a
tidying-up detail. WatchConnectivity calls every delegate method on a queue of
its own. Under Swift 5 those methods were nominally main-actor and were called
off it anyway, in silence. Under Swift 6 the crossing is checked at the call,
and the app **trapped in `dispatch_assert_queue` the moment the Watch session
activated** — which is to say, at launch. It was a real data race the whole
time; only the check is new.

The bodies did not have to change: each one already read what it needed off
the `WCSession` synchronously and handed the rest to the main queue. What they
did need was `SendableAcrossQueues` (in `Shared/WatchSync.swift`), a one-field
`@unchecked Sendable` box for the `[String: Any]` dictionaries and reply
handlers WatchConnectivity deals in. Swift cannot see inside an `Any`; the
guarantee comes from the framework's contract that these are property-list
values. Don't reach for that box for anything else.

### The second doorway

The delegate is not the only way WatchConnectivity calls back into this app.
**Every `replyHandler` and `errorHandler` handed to `sendMessage` is called on
that same queue**, and marking the delegate changed nothing about those: a
closure written without an annotation picks up the target's main-actor
default, so each one was a main-actor closure being run off the main actor.

Marking the delegate alone therefore moved the crash rather than fixing it.
The Watch app still trapped the moment it launched — activation calls
`requestSync`, the phone answers, and the answer arrives on WatchConnectivity's
`NSOperationQueue`. The crash report named the closure outright, and at the
faulting address sat `bl _swift_task_isCurrentExecutor` followed by the branch
that fails.

So every one of those handlers is written `{ @Sendable ... }`, which makes it
nonisolated, with the hop to the main queue inside it. Seven of them, in both
apps. If you add a `sendMessage` with a handler, write `@Sendable` on it.

Worth knowing how to check this without a device: disassemble the closure and
look for `_swift_task_isCurrentExecutor`. A handler that still has one is a
handler that will trap.

```bash
otool -arch arm64_32 -tV "…/workout_aicode Watch App-.debug.dylib" \
  | grep -A40 'requestSync.*cfU_:' | grep isCurrentExecutor
```

The *inner* `DispatchQueue.main.async` blocks keep their check, and should:
they really do run on the main queue, so it passes.

## Screens

One file per screen, in each app's folder. On the phone:

| File | Screen |
|---|---|
| `ContentView.swift` | the tab shell, and which overlay is up |
| `EditWorkoutsView.swift` | the workout list, and one workout |
| `EditExerciseView.swift` | one exercise's definition |
| `ExerciseLibraryView.swift` | the ready-made library |
| `LogExerciseView.swift` | **the screen a workout is done on** — wheels, series, rest, heart rate |
| `LogsListView.swift`, `LogsStatsView.swift` | the logs tab |
| `ImportExportView.swift`, `ImportReviewSheet.swift` | JSON and TSV in and out, and the sheet that describes a file before it is let in |
| `SettingsView.swift` | settings |
| `ScheduleNextWorkout.swift`, `WorkoutGroupSetup.swift` | the end-of-workout calendar offer, its settings, and naming groups |
| `WorkoutCalendar.swift` | the only EventKit in the app: reading back, writing and clearing away the app's own events — plans ahead and records of workouts done |
| `RecoveryView.swift` | what is offered when the store will not load |
| `InfoView.swift` | the in-app guide, generated by `generate_infoview.py` from README.md |
| `WatchStatusViews.swift`, `ViewHelpers.swift` | overlays and small shared pieces |

`LogExerciseView.swift` is by far the largest and is the one to read first if
you want to understand the app.

## Tests

Swift Testing (`@Test`, `#expect`) throughout the unit test targets; XCTest
only in the UI ones.

```bash
xcodebuild test -scheme workout_aicode \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max' \
  -skip-testing:workout_aicodeUITests

xcodebuild test -scheme 'workout_aicode Watch App-' \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)'

xcodebuild test -scheme workout_aicode_MacOS -destination 'platform=macOS'
```

`workout_aicodeTests/MigrationTests.swift` is the big one — every schema
version is migrated and checked. `MixedBuildTests.swift` covers the case the
app is hardest to get right in: an older Watch or Mac reading data a newer
phone wrote, and the other way round.

The style across the suites is worth matching. Tests are named as sentences
about behaviour (`aWeightSurvivesARoundTripThroughEitherUnit`), and the ones
that exist because of a real bug say so in a comment above them, with what the
symptom was. Several of them exist because reading the code did not find the
bug and rendering the view did.

## Tools

| Script | What it does |
|---|---|
| `tools/make-screenshots.sh` | App Store screenshots for iPhone and Watch |
| `tools/make-mac-screenshots.sh` | the same for the Mac — needs Screen Recording for whatever runs it |
| `tools/srw-window-id.swift` | asks the window server which window belongs to a process |
| `tools/svg-to-bodydiagram.py` | turns the body artwork into `Shared/BodyDiagram.json` |
| `tools/export-shared-data.py` | pulls the anonymous shared data people opt into |
| `generate_infoview.py` | turns README.md into the in-app guide |

The screenshot scripts launch the app with `-SRW…` flags (`-SRWDemo`,
`-SRWShot`, `-SRWScreen`, `-SRWAppearance`) handled in `ScreenshotMode`. Every
flag must be given a value — `NSUserDefaults` reads the launch arguments as
pairs, and a bare flag swallows the next one. The header of
`tools/make-mac-screenshots.sh` explains what that cost.

## Building

Xcode 27 or later. Deployment targets: iOS 18.6, watchOS 26.4, macOS 26.5.

`CURRENT_PROJECT_VERSION` is **shared by every target**, so raising the build
number raises it for all three apps at once. That matters when one platform is
mid-submission.
