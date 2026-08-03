#!/bin/bash
# Double-click this in Finder to download the shared data set.
#
# A .command file is the clickable kind on macOS: Finder opens Terminal and
# runs it. (A .sh would just open in an editor.)
#
# The key ID below is only an identifier and is safe to keep here. The private
# key is NOT — its location is remembered in tools/export.config, which is
# gitignored, and the key itself should live outside the repository.

set -uo pipefail

# Finder runs this from the user's home folder, not from where the file is.
cd "$(dirname "$0")/.." || exit 1

CONFIG="tools/export.config"
KEY_ID="d547ab297cc3581ec8c58ed878fc8c3df0cd6d82a2dbc36bf1f49de6cdd211c3"
CONTAINER="iCloud.robotex.workout-aicode"
ENVIRONMENT="production"
KEY_PATH=""

# Remembered settings win over the defaults above.
[ -f "$CONFIG" ] && . "$CONFIG"

echo "SetsRepsWheels — download shared data"
echo "  container:   $CONTAINER"
echo "  environment: $ENVIRONMENT"
echo

# Ask for the key the first time, and remember where it is.
while [ ! -f "$KEY_PATH" ]; do
  if [ -n "$KEY_PATH" ]; then
    echo "Not found: $KEY_PATH"
  fi
  echo "Where is your CloudKit server-to-server key (.pem)?"
  echo "Tip: drag the file into this window and press return."
  printf "> "
  read -r reply
  # Dragging a file in gives a shell-escaped path, possibly quoted. Unescape it
  # by hand rather than with eval, which would run whatever was pasted.
  KEY_PATH="${reply%\"}"; KEY_PATH="${KEY_PATH#\"}"
  KEY_PATH="${KEY_PATH%\'}"; KEY_PATH="${KEY_PATH#\'}"
  KEY_PATH="${KEY_PATH//\\ / }"
  [ -z "$KEY_PATH" ] && { echo "Nothing entered — stopping."; break; }
done

if [ ! -f "$KEY_PATH" ]; then
  echo
  echo "No key, no download. Create one in the CloudKit Console under"
  echo "Tokens & Keys -> Server-to-Server Keys, then run this again."
  printf "\nPress return to close. "
  read -r _
  exit 1
fi

# Remember it for next time.
{
  echo "# Written by export-shared-data.command. Not committed — see tools/.gitignore."
  echo "KEY_ID=\"$KEY_ID\""
  echo "KEY_PATH=\"$KEY_PATH\""
  echo "CONTAINER=\"$CONTAINER\""
  echo "ENVIRONMENT=\"$ENVIRONMENT\""
} > "$CONFIG"

OUT="$HOME/Desktop/SetsRepsWheels data $(date +%Y-%m-%d)"
echo "Saving to: $OUT"
echo

python3 tools/export-shared-data.py \
  --key-id "$KEY_ID" \
  --key "$KEY_PATH" \
  --container "$CONTAINER" \
  --environment "$ENVIRONMENT" \
  --out-dir "$OUT" \
  --long
status=$?

echo
if [ $status -eq 0 ]; then
  echo "Done."
  open "$OUT"
else
  # Do not leave an empty dated folder on the Desktop after a failure.
  rmdir "$OUT" 2>/dev/null
  echo "That did not work — the message above says why."
  echo "A missing index is the usual cause; the script names the field if so."
fi

# Keep the window readable: Finder closes it on exit otherwise.
printf "\nPress return to close. "
read -r _
