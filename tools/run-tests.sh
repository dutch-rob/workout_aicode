#!/bin/bash
# The unit test suites for SetsRepsWheels — iOS, watchOS and macOS — and the
# clearing up Xcode does not do.
#
# WHY THIS SCRIPT EXISTS AT ALL, given that it is three xcodebuild lines: the
# clean-up at the end. Xcode makes a throwaway simulator clone under
# ~/Library/Developer/XCTestDevices for every `xcodebuild test` run and is
# meant to delete it afterwards. On this Mac it never has. By 16 November 2026
# there were 202 of them going back to 14 October — about 1.5 million files —
# and removing the directory took the data volume from 9.8 GB free to 27 GB,
# 96% full to 87%. The volume has hit literally zero twice, which stops every
# tool on the machine, so the suites now tidy up after themselves.
#
# The UI test targets are skipped. They drive the simulator, take minutes
# rather than seconds, and are not what a change to the model wants to know.
# Run them by hand from Xcode when the thing being changed is the interface.
#
# Usage:  tools/run-tests.sh                 # all three platforms, then tidy up
#         tools/run-tests.sh ios             # one or more of: ios watch mac
#         tools/run-tests.sh ios watch
#         KEEP_TEST_DEVICES=1 tools/run-tests.sh    # leave the clones alone
#
# Exits non-zero if any suite failed, and tidies up either way: a failed run
# leaves a clone behind exactly like a passing one.
set -uo pipefail
cd "$(dirname "$0")/.."

IOS_DESTINATION='platform=iOS Simulator,name=iPhone 18 Pro Max'
WATCH_DESTINATION='platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)'

# The trailing hyphen is part of the scheme's real name, not a typo — see
# ARCHITECTURE.md. Quote it or the shell eats it.
WATCH_SCHEME='workout_aicode Watch App-'

WANTED=("$@")
[ ${#WANTED[@]} -eq 0 ] && WANTED=(ios watch mac)

wants() {
    local name
    for name in "${WANTED[@]}"; do [ "$name" = "$1" ] && return 0; done
    return 1
}

failed=()

run() {
    local label="$1"; shift
    echo
    echo "=== $label ==="
    if xcodebuild "$@" 2>&1 | tail -40; then
        echo "--- $label passed"
    else
        echo "--- $label FAILED"
        failed+=("$label")
    fi
}

if wants ios; then
    run iOS test -scheme workout_aicode \
        -destination "$IOS_DESTINATION" \
        -skip-testing:workout_aicodeUITests
fi

if wants watch; then
    run watchOS test -scheme "$WATCH_SCHEME" \
        -destination "$WATCH_DESTINATION"
fi

if wants mac; then
    run macOS test -scheme workout_aicode_MacOS -destination 'platform=macOS'
fi

# MARK: - The clearing up
#
# The whole directory, not its contents: `rm -rf .../XCTestDevices/*` trips
# zsh's "sure you want to delete more than 100 files" guard, which needs an
# answer and so cannot be put in a script. Xcode makes it again on the next
# run.
#
# Nothing else is touched. In particular NOT ~/Library/Developer/Xcode/Archives,
# which holds the dSYMs for symbolicating crash reports from released versions,
# and not iOS DeviceSupport, which is rebuilt the moment a device is attached
# and so comes straight back if an install is under way.
tidy_up() {
    local devices="$HOME/Library/Developer/XCTestDevices"
    [ -d "$devices" ] || return 0
    local count
    count=$(find "$devices" -maxdepth 1 -mindepth 1 -type d | wc -l | tr -d ' ')
    [ "$count" -eq 0 ] && return 0
    echo
    echo "=== clearing up $count throwaway test device(s) ==="
    # Belt and braces: never while a test run is in flight, since the clone a
    # running suite is using is in there too.
    if pgrep -q xcodebuild; then
        echo "xcodebuild still running — left alone. Run tools/run-tests.sh again when it is done."
        return 0
    fi
    rm -rf "$devices"
    df -h /System/Volumes/Data | sed -n 2p
}

if [ -n "${KEEP_TEST_DEVICES:-}" ]; then
    echo
    echo "(KEEP_TEST_DEVICES set — leaving ~/Library/Developer/XCTestDevices alone)"
else
    tidy_up
fi

echo
if [ ${#failed[@]} -eq 0 ]; then
    echo "All requested suites passed."
else
    echo "FAILED: ${failed[*]}"
    exit 1
fi
