#!/bin/sh
# Install TypeStats to ~/Applications/TypeStats.app and open the installed copy.
# "Start at login" remembers the app's path, so turn it on from this installed copy,
# not from .build/TypeStats.app (which every rebuild replaces).
# Usage: sh scripts/install-app.sh
set -eu
cd "$(dirname "$0")/.."
[ -n "${HOME:-}" ] || { echo "HOME is not set"; exit 1; }
DEST="$HOME/Applications/TypeStats.app"

sh scripts/bundle-app.sh

# Quit every running TypeStats first. SIGTERM quits it normally, so its counts are saved.
for pid in $(pgrep -x TypeStats || true); do
  kill -TERM "$pid" 2>/dev/null || true
done
i=0
while pgrep -x TypeStats >/dev/null; do
  i=$((i + 1)); [ $i -le 100 ] || { echo "TypeStats did not quit; quit it from the menu bar and rerun"; exit 1; }
  sleep 0.1
done

# macOS ties the Input Monitoring grant to the app's designated requirement. When the installed
# copy's differs from this build's (the one-time switch from ad hoc to stable signing, or a
# different identity), the old grant is dead but still shows "on", so clear this app's entry and
# approve once. Same requirement (every rebuild with a stable identity): leave the grant alone.
requirement() { codesign -dr - "$1" 2>/dev/null | grep '^designated' || true; }
if [ -d "$DEST" ] && [ "$(requirement "$DEST")" != "$(requirement .build/TypeStats.app)" ]; then
  if tccutil reset ListenEvent local.typestats.TypeStats >/dev/null; then
    echo "Signing identity changed: reset TypeStats' Input Monitoring entry. Turn TypeStats on in System Settings > Privacy & Security > Input Monitoring once."
  else
    echo "Signing identity changed but the Input Monitoring reset failed; if the popup says Permission needed, remove TypeStats from that list and add it again."
  fi
fi

mkdir -p "$HOME/Applications"
# Replace the previous install as a whole (no stale files from an older build).
rm -rf "${DEST:?}"
ditto .build/TypeStats.app "$DEST"
codesign --verify --deep "$DEST"
open "$DEST"
echo "Installed and opened $DEST"
