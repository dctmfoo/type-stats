#!/bin/sh
# Real hourly-store -> popup and share-image proof, in a fresh isolated fixture.
set -eu
cd "$(dirname "$0")/.."
ROOT=$(pwd -P)
BIN="$ROOT/.build/TypeStats.app/Contents/MacOS/TypeStats"
W=$(mktemp -d "$ROOT/.po/tmp/heatmap.XXXXXX")
DATA="$W/data"
pid=
cleanup() { [ -z "$pid" ] || kill -TERM "$pid" 2>/dev/null || true; }
trap cleanup EXIT HUP INT TERM
fail() { echo "FAIL heatmap: $1"; exit 1; }
record() {
  at=$1; shift
  "$BIN" --no-tap --data-dir "$DATA" --at "$at" "$@" --share-save "$W/seed.png"
}
# Threshold cells against a 100-key maximum. The 1-key cell must differ from zero.
for pair in 09:1 10:25 11:26 12:50 13:51 14:75 15:76 16:100; do
  record "2026-09-29T${pair%:*}:00" --simulate-keys "sample.Xcode:${pair#*:}"
done
for pair in 2026-09-30:20 2026-10-01:30 2026-10-02:40 2026-10-03:50 2026-10-04:60; do
  record "${pair%:*}T09:00" --simulate-keys "sample.Mail:${pair#*:}"
done
record 2026-10-02T12:00 --seed-nohour sample.Legacy:50
record 2026-10-05T09:00 --simulate-keys sample.Xcode:99
record 2026-10-05T09:00 --seed-nohour sample.Legacy:50
# Render with a pending 1-key hour. The share seam exits without saving held counts.
"$BIN" --no-tap --data-dir "$DATA" --at 2026-10-05T10:30 --hold-flush \
  --simulate-keys sample.Notes:1 --view week --share-save "$W/share-week.png"
popup() {
  name=$1; shift
  rm -f "$W/ready"
  "$BIN" --no-tap --data-dir "$DATA" --at 2026-10-05T10:30 --hold-flush \
    --simulate-keys sample.Notes:1 --view week "$@" \
    --snapshot "$W/$name.png" --ready-file "$W/ready" > "$W/$name.log" 2>&1 &
  pid=$!
  n=0
  until [ -s "$W/ready" ]; do
    n=$((n + 1)); [ "$n" -le 150 ] || fail "$name did not render"
    sleep 0.2
  done
  kill -TERM "$pid"; wait "$pid" 2>/dev/null || true; pid=
}
size() { sips -g pixelWidth -g pixelHeight "$1" | awk '/pixel/ {printf "%sx", $2}' | sed 's/x$//'; }
# Light is the default appearance; the popup follows it.
popup popup-week-dark --dark-snapshot --screen-height 5000
popup popup-week-light --screen-height 5000
popup popup-week-capped --screen-height 700
python3 scripts/heatmap-probe.py dark:"$W/popup-week-dark.png" light:"$W/popup-week-light.png" dark:"$W/share-week.png" || fail 'grid or shade mismatch'
swift scripts/ocr.swift "$W/share-week.png" > "$W/share.txt"
grep -q 'Based on 704 of 804 keys' "$W/share.txt" || fail 'coverage note missing or wrong'
grep -q 'Peak Tue 29, 4-5 pm' "$W/share.txt" || fail 'peak label missing or wrong'
grep -q 'Not yet' "$W/share.txt" || fail 'future-hour legend missing'
# The 7-day popup is 296 px (148 pt) taller than the other views, with full-height Top apps,
# and only shrinks to a scrolling list when the visible screen height is smaller.
today=$(cat scripts/popup-size.txt)
week_height=$((${today#*x} + 296))
[ "$(size "$W/popup-week-dark.png")" = "${today%x*}x$week_height" ] || fail "7-day popup is $(size "$W/popup-week-dark.png"), expected ${today%x*}x$week_height"
[ "$(size "$W/popup-week-light.png")" = "${today%x*}x$week_height" ] || fail '7-day light popup size differs from dark'
[ "$(size "$W/popup-week-capped.png")" = "${today%x*}x1383" ] || fail "7-day popup on a 700 pt screen is $(size "$W/popup-week-capped.png"), expected ${today%x*}x1383"
[ "$(sips -g pixelWidth -g pixelHeight "$W/share-week.png" | awk '/pixel/ {printf "%sx", $2}' | sed 's/x$//')" = '2400x1260' ] || fail 'share size changed'
echo "PASS heatmap: 7x24 cells in light and dark, full-height Top apps capped to the screen, four blue steps, zero and future cells, pending count, coverage and peak; renders in $W"
