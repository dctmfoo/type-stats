#!/bin/sh
# The real menu bar popup (not a hosting window): open it from the status item of the bundled app,
# switch Today / 7 days / 30 days, and require the same window frame every time, the detail area
# (charts, heatmap, Top apps) at its full height, and its text on screen. A second pass on a short
# screen (--screen-height) requires the popup to fit it with the footer still showing.
# Moves the mouse. Needs Accessibility and Screen Recording permission and cliclick.
set -eu
cd "$(dirname "$0")/.."
ROOT=$(pwd -P)
APP="$ROOT/.build/TypeStats.app"
BIN="$APP/Contents/MacOS/TypeStats"
W=${TYPESTATS_POPUP_ARTIFACTS:-$(mktemp -d "$ROOT/.po/tmp/popup-real.XXXXXX")}
mkdir -p "$W"
DATA=$(mktemp -d "$ROOT/.po/tmp/popup-real-data.XXXXXX")
# Tall screen: the shared popup gives the detail area 580 points; a collapsed area is a few points.
FLOOR=400
SHORT=700
cleanup() { pkill -TERM -f "$DATA" 2>/dev/null || true; sleep 0.5; find "$DATA" -mindepth 1 -delete; rmdir "$DATA"; }
trap cleanup EXIT HUP INT TERM
fail() { echo "FAIL popup-real: $1 (artifacts in $W)"; exit 1; }
probe() { swift scripts/popup-probe.swift "$@"; }
[ -x "$BIN" ] || fail "$BIN missing; run scripts/bundle-app.sh"
command -v cliclick >/dev/null || fail 'cliclick is needed to click the status item (brew install cliclick)'
: > "$W/frames.txt"
"$BIN" --no-tap --data-dir "$DATA" --at 2026-10-03T09:00 --simulate-keys sample.Mail:60 --share-save "$W/seed.png"
"$BIN" --no-tap --data-dir "$DATA" --at 2026-10-04T10:00 --simulate-keys sample.Notes:40 --share-save "$W/seed.png"

# The popup closes if something takes focus, and a click on a still-starting status item can be lost:
# click the item until the popup is open.
open_popup() {
  clicks=0
  until probe window "$pid" >/dev/null 2>&1; do
    clicks=$((clicks + 1)); [ "$clicks" -le 4 ] || fail 'popup did not open from the status item'
    cliclick m:"$(probe item "$pid" | tr ' ' ',')"
    cliclick c:"$(probe item "$pid" | tr ' ' ',')"
    n=0
    until probe window "$pid" >/dev/null 2>&1 || [ "$n" -ge 8 ]; do n=$((n + 1)); sleep 0.2; done
  done
}

# run_case <name> <detail floor> [launch options]: one launch, every period.
run_case() {
  name=$1; floor=$2; shift 2
  # Launched by LaunchServices like the installed app, so the status item and popup are the real ones.
  open -n "$APP" --args --no-tap --data-dir "$DATA" --at 2026-10-05T10:30 \
    --simulate-keys sample.Xcode:99,sample.Mail:20 --simulate-clicks sample.Xcode:5 "$@"
  pid=
  n=0
  until [ -n "$pid" ] && probe item "$pid" >/dev/null 2>&1; do
    n=$((n + 1)); [ "$n" -le 50 ] || fail 'status item did not appear'
    sleep 0.2
    pid=$(pgrep -f "TypeStats --no-tap --data-dir $DATA" | head -1 || true)
  done
  sleep 2
  i=0
  for view in today week month; do
    # Another app taking focus closes the popup (not what is under test): reopen and select again.
    tries=0
    while :; do
      open_popup
      probe period "$pid" "$i" || fail "could not select $view"
      sleep 0.8
      if measure=$(probe measure "$pid" 2>/dev/null); then break; fi
      tries=$((tries + 1))
      [ "$tries" -lt 3 ] || { probe measure "$pid" || true; fail "$name $view popup has no window or no detail area"; }
    done
    i=$((i + 1))
    window=$(echo "$measure" | cut -f1-5)
    frame=$(echo "$measure" | cut -f2-5)
    detail=$(echo "$measure" | cut -f6)
    printf '%s\t%s\t%s\tdetail %s\n' "$name" "$view" "$frame" "$detail" | tee -a "$W/frames.txt"
    [ "$detail" -ge "$floor" ] || fail "$name $view detail area is $detail pt tall, below the $floor pt floor"
    shot="$W/popup-$name-$view"
    screencapture -x -l "$(echo "$window" | cut -f1)" "$shot.png"
    swift scripts/ocr.swift "$shot.png" > "$shot.txt"
    grep -q 'Share' "$shot.txt" || fail "$name $view popup is missing the footer"
    case $view in
      today) grep -q 'By hour' "$shot.txt" || fail "$name Today popup is missing the hour chart" ;;
      *) grep -q 'By day' "$shot.txt" || fail "$name $view popup is missing the day chart" ;;
    esac
    # A short screen scrolls the detail area, so only the tall screen shows all of it at once.
    [ "$name" = tall ] || continue
    grep -q 'Top apps' "$shot.txt" || fail "$view popup is missing Top apps"
    [ "$view" != week ] || grep -q 'When you typed' "$shot.txt" || fail '7 days popup is missing the heatmap'
  done
  pkill -TERM -f "TypeStats --no-tap --data-dir $DATA"
  n=0
  while kill -0 "$pid" 2>/dev/null; do
    n=$((n + 1)); [ "$n" -le 50 ] || fail 'test copy did not quit'
    sleep 0.2
  done
}

run_case tall "$FLOOR"
run_case short 200 --screen-height "$SHORT"
# One frame for every period at a given screen height; the short screen caps it at the screen, less the margin.
[ "$(grep '^tall' "$W/frames.txt" | cut -f3-6 | sort -u | wc -l | tr -d ' ')" = 1 ] || fail 'popup window frame changed between periods'
[ "$(grep '^short' "$W/frames.txt" | cut -f3-6 | sort -u | wc -l | tr -d ' ')" = 1 ] || fail 'popup window frame changed between periods on a short screen'
short_height=$(grep '^short' "$W/frames.txt" | head -1 | cut -f6)
[ "$short_height" = $((SHORT - 8)) ] || fail "popup on a $SHORT pt screen is $short_height pt tall, expected $((SHORT - 8))"
tall_height=$(grep '^tall' "$W/frames.txt" | head -1 | cut -f6)
[ "$tall_height" -gt "$short_height" ] || fail 'tall screen popup is not taller than the short one'
echo "PASS popup-real: the real menu bar popup keeps one frame across Today, 7 days and 30 days ($(grep '^tall' "$W/frames.txt" | head -1 | cut -f3-6 | tr '\t' ' ') tall, $(grep '^short' "$W/frames.txt" | head -1 | cut -f3-6 | tr '\t' ' ') on a $SHORT pt screen) with its detail area, charts, Top apps and footer; renders in $W"
