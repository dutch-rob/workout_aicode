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
#   • `screencapture` needs Screen Recording permission for whatever runs it
#     (Terminal, or the app driving it). macOS asks once, then you must run it
#     again — the permission does not apply to the process already running.
#   • Positioning the window uses System Events, which needs Accessibility.
#
# Both are one-time grants in System Settings → Privacy & Security. The script
# says which one is missing rather than producing black images, which is what
# screencapture does when it is not allowed to see anything.
#
# Usage:  tools/make-mac-screenshots.sh
#         SCREENS="logs workouts" tools/make-mac-screenshots.sh
set -uo pipefail
cd "$(dirname "$0")/.."

BUNDLE="robotex.workout-aicode-MacOS"
OUT="${OUT:-screenshots/mac}"
WIDTH=1440
HEIGHT=900
SCREENS="${SCREENS:-workouts exercises logs graphs progress importExport settings info}"

mkdir -p "$OUT"

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

# Accessibility, checked here rather than discovered three screens in. The
# first System Events call also raises the Automation prompt, so this gets
# both out of the way before anything is captured.
if ! osascript -e 'tell application "System Events" to get name of first process' >/dev/null 2>&1; then
  cat >&2 <<MSG
Cannot drive the window, so it cannot be sized for the screenshots.

Grant to:  $GRANTEE
  System Settings → Privacy & Security → Accessibility

If a dialog asked about controlling "System Events" and was declined, that
answer is remembered in Privacy & Security → Automation → $GRANTEE.
MSG
  exit 1
fi

shoot() {
  local screen="$1"
  shift
  echo "— $screen"
  osascript -e "quit app id \"$BUNDLE\"" >/dev/null 2>&1
  sleep 1
  open -n "$APP" --args -SRWScreen "$screen" "$@"
  sleep 4   # the window, its data and its first layout

  # Put the window where we want it and size it in points.
  if ! osascript <<EOF >/dev/null 2>&1
tell application "System Events"
  tell process "SetsRepsWheels"
    set frontmost to true
    set position of window 1 to {60, 60}
    set size of window 1 to {$WIDTH, $HEIGHT}
  end tell
end tell
EOF
  then
    echo "Could not position the window. Grant Accessibility to this terminal in" >&2
    echo "System Settings → Privacy & Security → Accessibility, then run again." >&2
    exit 1
  fi
  sleep 2

  # The region the window was just moved to, which is why it was positioned
  # exactly rather than left where macOS put it. Capturing by window id would
  # avoid the arithmetic, but a SwiftUI app exposes no AppleScript window to
  # ask an id of, and the fallback would be this anyway.
  local file="$OUT/$screen.png"
  screencapture -x -R60,60,$WIDTH,$HEIGHT "$file"

  if [ ! -s "$file" ]; then
    echo "  nothing captured for $screen" >&2
    return 1
  fi
  echo "  $(sips -g pixelWidth -g pixelHeight "$file" 2>/dev/null | awk '/pixel/ {printf "%s ", $2}')→ $file"
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
