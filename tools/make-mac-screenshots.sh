#!/bin/bash
# App Store screenshots for SetsRepsWheels on the Mac.
#
# The Mac App Store takes 1280×800, 1440×900, 2560×1600 or 2880×1800. This
# shoots a 1440×900 window, which is one of them on a 1x display and lands as
# 2880×1800 on a Retina one — also accepted. Either way the app sizes itself
# against what the WINDOW SERVER reports rather than its own frame, because
# those differ by a shadow margin and it is the window server's number that
# becomes the size of the picture. See ScreenshotMode.
#
# UNLIKE the iOS script this cannot run unattended the first time, and the
# reason is macOS privacy rather than anything about the app:
#
# The app is given its own in-memory sample data (-SRWDemo): a capture never
# contains anybody's real training, and never shows an empty app.
#
#   • `screencapture` needs Screen Recording permission for whatever runs it
#     (Terminal, or the app driving it). macOS asks once, then you must QUIT
#     AND REOPEN that app — the permission does not apply to a process that is
#     already running, so the toggle looks on while capture still fails.
#
# That is the only grant needed. The window is positioned and sized by the app
# itself when launched with -SRWShot, rather than by System Events from here,
# which would have meant Accessibility as well: a second permission, for a
# second app, to set a rectangle the app can set on its own.
#
# Finding WHICH window to shoot is this script's job, not the app's. The app
# used to write its window id to a file passed in with -SRWShotId; sandboxing
# the app for the App Store ended that, silently, and every screen then
# reported "the app never reported a window" while the window was up and
# correctly sized. The window server will say, and needs no permission to.
#
# EVERY -SRW FLAG BELOW MUST BE GIVEN A VALUE, hence "-SRWDemo 1" rather than
# a bare "-SRWDemo". NSUserDefaults parses the launch arguments as -key value
# pairs, so a flag with nothing after it swallows the NEXT flag as its value
# and leaves that flag's value behind as a bare word. AppKit reads a bare
# launch argument as a file to open, an app launched to open a file gets no
# untitled window, and SwiftUI's WindowGroup therefore builds nothing: the
# app runs, seeds, logs nothing and shows no window at all. That cost a long
# evening of bisecting the sample data, which was never the problem.
#
# The script checks before capturing rather than producing black images, which
# is what screencapture does when it is not allowed to see anything.
#
# Usage:  tools/make-mac-screenshots.sh
#         SCREENS="logs workouts" tools/make-mac-screenshots.sh
#         APPEARANCE=light tools/make-mac-screenshots.sh
#         NOBUILD=1 tools/make-mac-screenshots.sh     # app just built in Xcode
set -uo pipefail
cd "$(dirname "$0")/.."

OUT="${OUT:-screenshots/mac}"
# SIZE picks one of the four the Mac App Store accepts: 1280x800, 1440x900,
# 2560x1600, 2880x1800. The big two need a display tall enough to hold the
# window — 1600 or 1800 points — so on a 1440-tall screen only the small two
# are reachable, and 1440x900 is the better of them.
SIZE="${SIZE:-1440x900}"
WIDTH="${SIZE%%x*}"
HEIGHT="${SIZE##*x}"
SCREENS="${SCREENS:-workouts exercises logs graphs progress importExport settings info}"
# Dark or light. The app itself has no appearance setting — it follows the Mac
# it runs on — so without saying, a run shoots whatever the machine happens to
# be set to, and a set half dark and half light is no set at all.
APPEARANCE="${APPEARANCE:-dark}"

mkdir -p "$OUT"
# Asks the window server which window belongs to the app. Compiled fresh each
# run — it is thirty lines and takes a moment, and a stale binary beside the
# source would be one more thing that can quietly be wrong.
WORK="$(mktemp -d -t srw-shots)"
trap 'rm -rf "$WORK"' EXIT
HELPER="$WORK/srw-window-id"
if ! swiftc -O tools/srw-window-id.swift -o "$HELPER" 2>"$WORK/swiftc.log"; then
  echo "Could not compile tools/srw-window-id.swift:" >&2
  cat "$WORK/swiftc.log" >&2
  exit 1
fi

# THE APP IS BUILT HERE, and the path comes from the build rather than from a
# search. This used to hunt DerivedData for any Debug SetsRepsWheels.app and
# take the first one, which silently shot WHATEVER WAS LYING AROUND: a run
# after an edit produced pictures of the previous binary, looking exactly like
# pictures of the new one. An afternoon went on a layout bug that had already
# been fixed, and the only hint was two "different" screenshots with the same
# checksum. Nothing in the output said the app was months old, because
# nothing knew.
#
# `-showBuildSettings` is asked rather than guessed at for the same reason the
# bundle identifier is read out of the app below: DerivedData paths, the
# configuration's folder name and the product's own name are all Xcode's to
# change.
#
# NOBUILD=1 skips the build for a quick reshoot of an app just built in Xcode.
# The path still comes from the build settings, so it is still the app this
# scheme builds and not one found somewhere.
SCHEME="${SCHEME:-workout_aicode_MacOS}"
SETTINGS=$(xcodebuild -project workout_aicode.xcodeproj -scheme "$SCHEME" \
           -configuration Debug -destination 'platform=macOS' \
           -showBuildSettings 2>"$WORK/settings.log")
PRODUCTS=$(awk -F' = ' '/^ *BUILT_PRODUCTS_DIR = /{print $2; exit}' <<<"$SETTINGS")
PRODUCT=$(awk -F' = ' '/^ *FULL_PRODUCT_NAME = /{print $2; exit}' <<<"$SETTINGS")
if [ -z "$PRODUCTS" ] || [ -z "$PRODUCT" ]; then
  echo "Could not ask Xcode where the $SCHEME scheme puts its app:" >&2
  tail -20 "$WORK/settings.log" >&2
  exit 1
fi
APP="$PRODUCTS/$PRODUCT"

if [ "${NOBUILD:-0}" = "1" ]; then
  echo "NOBUILD=1, so using whatever is already at $APP"
else
  echo "Building $SCHEME (Debug)…"
  if ! xcodebuild -project workout_aicode.xcodeproj -scheme "$SCHEME" \
       -configuration Debug -destination 'platform=macOS' \
       build >"$WORK/build.log" 2>&1; then
    echo "The Mac app did not build, so nothing was captured:" >&2
    grep -E "error:|BUILD FAILED" "$WORK/build.log" | head -20 >&2
    tail -5 "$WORK/build.log" >&2
    exit 1
  fi
fi

if [ ! -d "$APP" ]; then
  echo "No app at $APP. Build the $SCHEME scheme, or run without NOBUILD=1." >&2
  exit 1
fi
echo "Using $APP"

# Asked of the built app rather than written down here. Both are build
# settings, and a copy in this script is a copy that goes stale: the day the
# Mac target took the iPhone's bundle identifier, the quit between screens
# stopped matching anything. It fails silently — osascript has nothing to say
# about an app id that is not running — so instances piled up instead of
# being replaced, and a run of eight screens produced two pictures.
BUNDLE=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Contents/Info.plist" 2>/dev/null)
PROCESS=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$APP/Contents/Info.plist" 2>/dev/null)
if [ -z "$BUNDLE" ] || [ -z "$PROCESS" ]; then
  echo "Could not read the identifier and executable name out of $APP" >&2
  exit 1
fi

# Throwaway stores from earlier runs. Each launch makes its own and cannot
# tidy up after itself once it has exited.
rm -f "$HOME/Library/Containers/$BUNDLE/Data/tmp"/srw-shots-*.sqlite* 2>/dev/null


# WHICH app needs the permission. macOS grants these to the application
# responsible for the process, which for a shell is whatever opened it — and
# "this terminal" is the wrong answer often enough to be worth working out:
# run from the terminal pane inside an editor or an assistant, the app that
# needs granting is that one, and granting Terminal does nothing at all.
responsible_app() {
  local pid=$PPID app=""
  for _ in 1 2 3 4 5 6 7 8; do
    [ -z "$pid" ] || [ "$pid" = "0" ] || [ "$pid" = "1" ] && break
    local path
    path=$(ps -o comm= -p "$pid" 2>/dev/null)
    case "$path" in
      /Applications/*.app/Contents/MacOS/*) app="$path" ;;
      */*.app/Contents/MacOS/*) [ -z "$app" ] && app="$path" ;;
    esac
    pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
  done
  if [ -n "$app" ]; then
    # /Applications/Foo.app/Contents/MacOS/Foo -> Foo
    basename "${app%%.app/*}"
  else
    echo "your terminal"
  fi
}

GRANTEE="$(responsible_app)"

# Screen Recording, checked before anything else: without it every capture is
# a black rectangle of exactly the right size, which is the most misleading
# possible failure.
probe="$(mktemp -t srw-probe).png"
screencapture -x -R0,0,8,8 "$probe" 2>/dev/null
if [ ! -s "$probe" ]; then
  rm -f "$probe"
  cat >&2 <<MSG
Screen recording is not permitted, so nothing can be captured.

Grant it to:  $GRANTEE
  System Settings → Privacy & Security → Screen & System Audio Recording
  (called "Screen Recording" before macOS 15)

That is the app this script is running inside, which is what macOS asks
about — granting it to Terminal does nothing unless Terminal is what you
ran it from.

Then QUIT AND REOPEN $GRANTEE: macOS does not apply a new recording
permission to a process that is already running.
MSG
  exit 1
fi
rm -f "$probe"

# Only now clear what is there. A capture left behind by an earlier run looks
# exactly like one this run made — which is how a picture of a desktop, taken
# before the window-id fix, survived two runs and nearly went to Apple. It
# used to be cleared at the top, which meant a run that could not capture
# anything still threw away the pictures from the run that could.
#
# ONLY THE SCREENS THIS RUN SHOOTS. It used to clear the lot, so reshooting one
# screen with SCREENS= deleted the other seven — a tidy-looking one-file change
# that also took seven tracked pictures out of the repository.
for screen in $SCREENS; do
  rm -f "$OUT/$screen.png"
done

shoot() {
  local screen="$1"
  shift
  echo "— $screen"
  osascript -e "quit app id \"$BUNDLE\"" >/dev/null 2>&1
  sleep 1
  # -SRWDemo gives the app a throwaway store of its own with sample data, so a
  # capture never contains real training and never shows an empty app.
  open -n "$APP" --args -SRWDemo 1 -SRWShot "${WIDTH}x${HEIGHT}" \
       -SRWAppearance "$APPEARANCE" -SRWScreen "$screen" "$@"

  # Wait for a window the size we asked for. That is a better ready signal
  # than the app saying so: it means the window exists AND has been resized,
  # where the old id file only ever meant the app got as far as writing one.
  local pid="" wid="" gw="" gh="" waited=0
  while [ $waited -lt 40 ]; do
    [ -n "$pid" ] || pid=$(pgrep -n "$PROCESS" 2>/dev/null)
    if [ -n "$pid" ]; then
      wid="" gw="" gh=""
      read -r wid gw gh < <("$HELPER" "$pid" 2>/dev/null) || true
      [ "$gw" = "$WIDTH" ] && [ "$gh" = "$HEIGHT" ] && break
    fi
    sleep 0.5
    waited=$((waited + 1))
  done
  if [ -z "$wid" ]; then
    echo "  no window appeared for $screen (the app may still be launching)" >&2
    return 1
  fi
  if [ "$gw" != "$WIDTH" ] || [ "$gh" != "$HEIGHT" ]; then
    echo "  WARNING: the window is ${gw}x${gh}, not the ${WIDTH}x${HEIGHT} asked for." >&2
  fi
  sleep 2   # its data and first layout

  # Bring it to the front immediately before the shutter. macOS draws an
  # unfocused window greyed — grey title, grey selection, washed-out
  # controls — and one capture came out that way while another did not, which
  # is activation losing a race rather than failing. `open -a` asks
  # LaunchServices to front the running app and needs no permission; asking
  # System Events would have meant Accessibility again.
  open -a "$APP" >/dev/null 2>&1
  sleep 1

  # The window itself. A region shot takes whatever happens to be on screen
  # at those coordinates — the first attempt photographed a browser — and
  # AppKit measures from the bottom-left while screencapture measures from the
  # top-left, so the arithmetic was wrong as well as unsafe.
  local file="$OUT/$screen.png"
  screencapture -x -o -l"$wid" "$file"

  if [ ! -s "$file" ]; then
    echo "  nothing captured for $screen" >&2
    return 1
  fi

  # What came out, against what the App Store takes. A 1x display yields the
  # window's point size; a Retina one yields twice that. Both are fine, but
  # only if the result is one of the four accepted sizes, and silently
  # shipping a rejected one wastes a submission.
  local got
  got=$(sips -g pixelWidth -g pixelHeight "$file" 2>/dev/null \
        | awk '/pixelWidth/{w=$2} /pixelHeight/{h=$2} END{print w "x" h}')
  case "$got" in
    1280x800|1440x900|2560x1600|2880x1800) ;;
    *) echo "  WARNING: $got is not a size the Mac App Store accepts." >&2 ;;
  esac
  echo "  $got → $file"
}

for screen in $SCREENS; do
  if [ "$screen" = "info" ]; then
    shoot info -SRWTopic logs
  else
    shoot "$screen"
  fi
done

osascript -e "quit app id \"$BUNDLE\"" >/dev/null 2>&1
echo
echo "Done. $OUT:"
ls -l "$OUT" | tail -n +2 | awk '{print "  " $9 "  " $5 " bytes"}'
