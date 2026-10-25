#!/bin/sh
# Exercise real app-hour rows, both native render paths, and the actual MenuBarExtra's hover/focus.
set -eu
cd "$(dirname "$0")/.."
ROOT=$(pwd -P)
APP="$ROOT/.build/TypeStats.app"
BIN="$APP/Contents/MacOS/TypeStats"
W=${TYPESTATS_APP_COLOR_ARTIFACTS:-$(mktemp -d "$ROOT/.po/tmp/app-colors.XXXXXX")}
mkdir -p "$W"
DATA=$(mktemp -d "$ROOT/.po/tmp/app-color-data.XXXXXX")
pid=
cleanup() {
  if [ -n "$pid" ]; then kill -TERM "$pid" 2>/dev/null || true; fi
  pkill -TERM -f "$DATA" 2>/dev/null || true
  n=0
  while pgrep -f "$DATA" >/dev/null; do
    n=$((n+1))
    if [ "$n" -ge 100 ]; then pkill -KILL -f "$DATA" 2>/dev/null || true; break; fi
    sleep 0.1
  done
  if [ -d "$DATA" ]; then find "$DATA" -mindepth 1 -delete; rmdir "$DATA"; fi
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
fail() { echo "FAIL app-colors: $* (artifacts $W)"; exit 1; }
# Same AX helper, compiled once: exclude interpreter startup from focus-sensitive scenarios.
swiftc scripts/popup-probe.swift -o "$W/popup-probe"
probe() { "$W/popup-probe" "$@"; }
trace() { printf '%s\t%s\t' "$(date +%s)" "$1" >> "$W/focus-trace.txt"; probe diagnostic "$pid" >> "$W/focus-trace.txt"; }
[ -x "$BIN" ] || fail 'bundle missing'
identity=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")
[ "$identity" != local.typestats.TypeStats ] || fail 'native proof requires a separate development bundle identity'
# The same module identity ensures the fixture uses exactly the app's existing SwiftData schema.
swiftc -swift-version 6 -parse-as-library -module-name TypeStatsCore -target "$(uname -m)-apple-macos14.0" \
  Sources/TypeStatsCore/*.swift scripts/app-colors-fixture.swift -o "$W/fixture"
"$W/fixture" "$DATA"
swiftc -parse-as-library Sources/TypeStats/AppIconStore.swift Sources/TypeStats/StandardBitmap.swift scripts/app-icon-probe.swift -o "$W/icon-probe"
"$W/icon-probe" "$W/icons"
"$BIN" --no-tap --data-dir "$DATA" --at 2026-10-05T14:30 --view week --share-save "$W/share-week.png"
for view in today month; do
  "$BIN" --no-tap --data-dir "$DATA" --at 2026-10-05T14:30 --view "$view" --share-save "$W/share-$view.png"
done
python3 scripts/share-app-gap-probe.py "today:$W/share-today.png" "week:$W/share-week.png" "month:$W/share-month.png"
"$BIN" --no-tap --data-dir "$DATA" --at 2026-10-05T14:30 --view week --snapshot "$W/week-light.png" \
  --screen-height 5000 --ready-file "$W/ready" > "$W/snapshot.log" 2>&1 &
pid=$!
n=0
until [ -s "$W/ready" ]; do
  n=$((n+1)); [ "$n" -le 100 ] || fail 'snapshot did not complete'; sleep 0.2
done
kill -TERM "$pid"; wait "$pid" 2>/dev/null || true; pid=
swift scripts/ocr.swift "$W/share-week.png" > "$W/share.txt"
for label in Claude ChatGPT Teams Discord Ghostty Chrome; do
  grep -q "$label" "$W/share.txt" || fail "static export omits named legend entry $label"
done
# LaunchServices exposes the real status item. No hosting-window substitution is used here.
open -n "$APP" --args --no-tap --data-dir "$DATA" --at 2026-10-05T14:30
n=0
until [ -n "$pid" ] && probe item "$pid" >/dev/null 2>&1; do
  n=$((n+1)); [ "$n" -le 60 ] || fail 'status item did not appear'; sleep 0.2
  pid=$(pgrep -f "TypeStats --no-tap --data-dir $DATA" | head -1 || true)
done
sleep 2
open_popup() {
  clicks=0
  until probe window "$pid" >/dev/null 2>&1; do
    clicks=$((clicks+1)); [ "$clicks" -le 4 ] || fail 'real popup did not open'
    point=$(probe item "$pid" | tr ' ' ',')
    printf '%s\t%s\n' "$pid" "$point" >> "$W/status-item.txt"
    cliclick m:"$point"
    cliclick c:"$point"
    trace after-status-click
    n=0
    until probe window "$pid" >/dev/null 2>&1 || [ "$n" -ge 8 ]; do n=$((n+1)); sleep 0.2; done
  done
}
: > "$W/frames.txt"
for pair in today:0 week:1 month:2 week-again:1 today-again:0 week-final:1; do
  open_popup
  trace "${pair%:*}-before-period"
  probe period "$pid" "${pair#*:}"
  trace "${pair%:*}-after-period"
  sleep 0.5
  trace "${pair%:*}-before-measure"
  measure=$(probe measure "$pid")
  printf '%s\t%s\n' "${pair%:*}" "$measure" >> "$W/frames.txt"
  case "$pair" in
    today:0|week:1|month:2)
      screencapture -x -l "$(printf '%s' "$measure" | cut -f1)" "$W/native-${pair%:*}.png" ;;
  esac
done
[ "$(cut -f3-7 "$W/frames.txt" | sort -u | wc -l | tr -d ' ')" = 1 ] || fail 'native popup frame moved on repeated switching'
# The cell's actual accessibility node must expose the same non-colour facts.
probe tree "$pid" > "$W/accessibility-tree.txt"
probe hour-label "$pid" hour-2026-10-05-13 > "$W/cell-accessibility.txt"
for text in 'Total 957 keys' 'Leading app: Claude' '62.7%'; do
  grep -q "$text" "$W/cell-accessibility.txt" || fail "cell accessibility is missing $text"
done
# Pointer movement is not a key press/click. Hover must expose the exact hour's denominator.
trace before-hover
cliclick m:"$(probe hour "$pid" hour-2026-10-05-13 | tr ' ' ',')"
sleep 0.5
trace after-hover
probe hour-detail "$pid" > "$W/hover.txt"
for text in '1-2 pm' 'Total 957 keys' 'Leading app: Claude' '62.7%' '600 of 957 keys'; do
  grep -q "$text" "$W/hover.txt" || fail "hover is missing $text"
done
screencapture -x -l "$(probe window "$pid" | cut -f1)" "$W/native-hover.png"
# Keyboard/accessibility focus shares the same visible detail, even after moving the pointer away.
cliclick m:0,100
trace before-focus
probe focus-hour "$pid" hour-2026-10-01-9
sleep 0.5
trace after-focus
probe tree "$pid" > "$W/focus-accessibility-tree.txt"
probe hour-detail "$pid" > "$W/focus.txt"
grep -q 'Tied leaders: Claude, ChatGPT' "$W/focus.txt" || fail 'focus mislabels an exact tie'
grep -q '50.0% each' "$W/focus.txt" || fail 'focus uses the wrong tied share'
screencapture -x -l "$(probe window "$pid" | cut -f1)" "$W/native-focus.png"
probe leave-grid "$pid" || fail 'one Tab did not leave the hourly grid'
# Free the desktop as soon as native assertions finish; pixel analysis is noninteractive.
cleanup
pid=
date +%s > "$W/desktop-free"
python3 scripts/app-colors-probe.py "$W/week-light.png" "$W/share-week.png"
echo "PASS app-colors: separate identity $identity; exact native/export app hues, total intensity and named legend; repeated real menu popup switching; readable hover and normal keyboard focus; full per-cell accessibility labels. Evidence $W"
