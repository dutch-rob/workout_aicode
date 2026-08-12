#!/bin/bash
# App Store screenshots for SetsRepsWheels — iPhone, iPad and Apple Watch.
#
# Uses simctl directly rather than fastlane's `capture_screenshots`: snapshot
# 2.236.x crashes on Xcode 26's new simctl JSON (it calls .name on a String in
# test_command_generator.rb). The app's DEBUG-only demo mode (DemoMode.swift)
# supplies sample data through launch arguments, so captures never touch real
# data and no UI test driving is needed.
#
#   -SRWDemo             seed sample workouts + history (in-memory on iOS)
#   -SRWScreen <name>    which screen to open ("rest" opens the log screen with
#                        the rest countdown over it — the timer is off by
#                        default, so it cannot be reached by launching alone)
#
# Usage:  tools/make-screenshots.sh            # everything
#         DEVICES=phone tools/make-screenshots.sh
#         DEVICES="phone watch" tools/make-screenshots.sh
#         SCREENS=info tools/make-screenshots.sh   # re-shoot one screen only
set -uo pipefail
cd "$(dirname "$0")/.."

IOS_BUNDLE="robotex.workout-aicode"
WATCH_BUNDLE="robotex.workout-aicode.watchkitapp"
OUT="fastlane/screenshots/en-US"
# The simulator is slow to settle (SwiftData + WatchConnectivity start-up), and
# a too-early capture silently yields a blank screen. Note file size is NOT a
# usable "did it render" signal here: a blank white frame can be LARGER than the
# real screen, which is mostly white and compresses well. So: wait generously.
SETTLE="${SETTLE:-15}"          # seconds to let a screen finish rendering
WARMUP="${WARMUP:-15}"          # first launch after install is much slower
WHICH="${DEVICES:-phone ipad watch}"
# Optional space-separated filter of screen names (the part before ":" in the
# *_SCREENS lists), for re-shooting a single screen after a UI tweak.
ONLY="${SCREENS:-}"
mkdir -p "$OUT"

DERIVED=~/Library/Developer/Xcode/DerivedData
IOS_APP=$(find "$DERIVED"/workout_aicode-*/Build/Products/Debug-iphonesimulator \
            -maxdepth 1 -name "workout_aicode.app" 2>/dev/null | head -1)
WATCH_APP=$(find "$DERIVED"/workout_aicode-*/Build/Products/Debug-watchsimulator \
            -maxdepth 1 -name "workout_aicode Watch App-.app" 2>/dev/null | head -1)

udid_of() {   # exact device name -> UDID
  xcrun simctl list devices available 2>/dev/null \
    | grep -F "$1 (" | head -1 | grep -oE "[0-9A-Fa-f-]{36}"
}

# Screens per form factor: "<launch-arg-screen>:<file label>"
# Order matters: this is the order they appear on the App Store page.
IOS_SCREENS=("workouts:01_workouts" "log:02_log_exercise" "rest:03_rest_timer"
             "library:04_library" "graphs:05_graphs" "progress:06_progress"
             "logs:07_logs" "info:08_info")
WATCH_SCREENS=("workouts:01_watch_workouts" "log:02_watch_log"
               "rest:03_watch_rest_timer" "paused:04_watch_handover")

shoot() {   # udid  devlabel  bundle  screen  filelabel  settle  minkb
  local udid="$1" dev="$2" bundle="$3" screen="$4" label="$5"
  local settle="$6" minkb="$7"
  local path="$OUT/${dev}-${label}.png"
  local tmp="/tmp/srw-shot-$$.png"
  local args=(-SRWDemo)
  [ "$screen" != "workouts" ] && args+=(-SRWScreen "$screen")

  local attempt=0 kb=0 tries=0
  while [ "$attempt" -lt 3 ]; do
    xcrun simctl terminate "$udid" "$bundle" >/dev/null 2>&1
    xcrun simctl launch "$udid" "$bundle" "${args[@]}" >/dev/null 2>&1
    sleep "$settle"

    # Capture only once the screen has STOPPED changing: launch and app-switcher
    # animations otherwise get caught mid-flight (a shrinking app card, a blank
    # still-rendering view). Two identical consecutive frames = settled.
    local prev="" cur=""
    tries=0
    while [ "$tries" -lt 10 ]; do
      xcrun simctl io "$udid" screenshot "$tmp" >/dev/null 2>&1
      cur=$(md5 -q "$tmp" 2>/dev/null)
      [ -n "$prev" ] && [ "$cur" = "$prev" ] && break
      prev="$cur"
      tries=$((tries + 1))
      sleep 2
    done

    kb=$(( $(stat -f%z "$tmp" 2>/dev/null || echo 0) / 1000 ))
    # A sleeping Watch shows solid black, which is perfectly "stable" — so the
    # stability check alone can't catch it. A size floor can.
    [ "$kb" -ge "$minkb" ] && break
    attempt=$((attempt + 1))
    echo "     (retry ${attempt}: screen looked asleep at ${kb}KB)"
  done

  mv -f "$tmp" "$path" 2>/dev/null
  echo "  ✓ ${dev}-${label}.png  (${kb}KB, settled after $((tries * 2))s)"
}

run_device() {   # devicename  bundle  app  settle  minkb  screens...
  local name="$1" bundle="$2" app="$3" settle="$4" minkb="$5"; shift 5
  local udid; udid=$(udid_of "$name")
  if [ -z "$udid" ]; then echo "!! simulator not found: $name"; return; fi
  if [ -z "$app" ]; then echo "!! app not built for $name — build the scheme first"; return; fi
  echo "== $name =="
  xcrun simctl boot "$udid" >/dev/null 2>&1
  xcrun simctl bootstatus "$udid" >/dev/null 2>&1
  # Uninstall first: `install` alone replaces the binary but keeps the data
  # container, and on the Watch that container holds the last received
  # WatchConnectivity context, which would be replayed over the demo data.
  xcrun simctl uninstall "$udid" "$bundle" >/dev/null 2>&1
  xcrun simctl install "$udid" "$app" >/dev/null 2>&1 || { echo "!! install failed"; return; }
  # Warm-up launch: the first launch after installing is far slower, and without
  # this the first capture is a blank, still-rendering screen.
  xcrun simctl launch "$udid" "$bundle" -SRWDemo >/dev/null 2>&1
  sleep "$WARMUP"
  for pair in "$@"; do
    if [ -n "$ONLY" ] && ! grep -qw -- "${pair%%:*}" <<<"$ONLY"; then continue; fi
    shoot "$udid" "$name" "$bundle" "${pair%%:*}" "${pair##*:}" "$settle" "$minkb"
  done
}

for group in $WHICH; do
  case "$group" in
    # The Watch gets a short settle: its screen sleeps quickly, and a long wait
    # captures solid black. minkb rejects a frame that is asleep anyway.
    phone) run_device "iPhone 17 Pro Max"       "$IOS_BUNDLE"   "$IOS_APP"   "$SETTLE" 0  "${IOS_SCREENS[@]}" ;;
    ipad)  run_device "iPad Pro 13-inch (M5)"   "$IOS_BUNDLE"   "$IOS_APP"   "$SETTLE" 0  "${IOS_SCREENS[@]}" ;;
    # 46mm, NOT 42mm: App Store Connect accepts only 422x514, 410x502, 416x496,
    # 396x484, 368x448 or 312x390 for Watch, and the 42mm renders at 374x446 —
    # a real device size that is simply not on Apple's accepted list. The 46mm
    # gives 416x496 and uploads fine.
    watch) run_device "Apple Watch Series 11 (46mm)" "$WATCH_BUNDLE" "$WATCH_APP" 4 8 "${WATCH_SCREENS[@]}" ;;
    *) echo "unknown group: $group" ;;
  esac
done

echo
echo "Screenshots in $OUT"
