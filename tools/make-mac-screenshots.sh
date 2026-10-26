#!/bin/bash
# App Store screenshots for SetsRepsWheels on the Mac.
#
# The Mac App Store takes 1280×800, 1440×900, 2560×1600 or 2880×1800. This
# shoots at 1440×900 points, which on a Retina display lands as 2880×1800 —
# an accepted size, and the one that looks best.
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
# The script checks before capturing rather than producing black images, which
# is what screencapture does when it is not allowed to see anything.
#
# Usage:  tools/make-mac-screenshots.sh
#         SCREENS="logs workouts" tools/make-mac-screenshots.sh
set -uo pipefail
cd "$(dirname "$0")/.."

BUNDLE="robotex.workout-aicode-MacOS"
OUT="${OUT:-screenshots/mac}"
# SIZE picks one of the four the Mac App Store accepts: 1280x800, 1440x900,
# 2560x1600, 2880x1800. The big two need a display tall enough to hold the
# window — 1600 or 1800 points — so on a 1440-tall screen only the small two
# are reachable, and 1440x900 is the better of them.
SIZE="${SIZE:-1440x900}"
WIDTH="${SIZE%%x*}"
HEIGHT="${SIZE##*x}"
SCREENS="${SCREENS:-workouts exercises logs graphs progress importExport settings info}"

mkdir -p "$OUT"
# Clear what is there first. A capture left behind by an earlier run looks
# exactly like one this run made — which is how a picture of a desktop,
# taken before the window-id fix, survived two runs and nearly went to Apple.
rm -f "$OUT"/*.png
IDFILE="$(mktemp -t srw-window-id)"
trap 'rm -f "$IDFILE"' EXIT

APP=$(find ~/Library/Developer/Xcode/DerivedData -maxdepth 4 -name "workout_aicode_MacOS.app" \
      -path "*Debug*" 2>/dev/null | head -1)
if [ -z "$APP" ]; then
  echo "No built Mac app found. Build the workout_aicode_MacOS scheme first." >&2
  exit 1
fi
echo "Using $APP"

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

shoot() {
  local screen="$1"
  shift
  echo "— $screen"
  osascript -e "quit app id \"$BUNDLE\"" >/dev/null 2>&1
  sleep 1
  rm -f "$IDFILE"
  # -SRWDemo gives the app its own in-memory store with sample data, so a
  # capture never contains real training and never shows an empty app.
  open -n "$APP" --args -SRWDemo -SRWShot "${WIDTH}x${HEIGHT}" \
       -SRWShotId "$IDFILE" -SRWScreen "$screen" "$@"

  # The id file appearing is the app saying its window exists and is sized.
  local waited=0
  while [ ! -s "$IDFILE" ] && [ $waited -lt 20 ]; do
    sleep 0.5
    waited=$((waited + 1))
  done
  if [ ! -s "$IDFILE" ]; then
    echo "  the app never reported a window for $screen (it may still be building)" >&2
    return 1
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
  screencapture -x -o -l"$(cat "$IDFILE")" "$file"

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
