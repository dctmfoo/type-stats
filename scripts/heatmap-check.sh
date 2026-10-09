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
"$BIN" --no-tap --data-dir "$DATA" --at 2026-10-05T10:30 --hold-flush \
  --simulate-keys sample.Notes:1 --view week --dark-snapshot \
  --snapshot "$W/popup-week.png" --ready-file "$W/ready" > "$W/popup.log" 2>&1 &
pid=$!
n=0
until [ -s "$W/ready" ]; do
  n=$((n + 1)); [ "$n" -le 150 ] || fail 'popup did not render'
  sleep 0.2
done
kill -TERM "$pid"; wait "$pid" 2>/dev/null || true; pid=
python3 scripts/heatmap-probe.py "$W/popup-week.png" "$W/share-week.png" || fail 'grid or shade mismatch'
swift scripts/ocr.swift "$W/share-week.png" > "$W/share.txt"
grep -q 'Based on 704 of 804 keys' "$W/share.txt" || fail 'coverage note missing or wrong'
grep -q 'Peak Tue 29, 4-5 pm' "$W/share.txt" || fail 'peak label missing or wrong'
grep -q 'Not yet' "$W/share.txt" || fail 'future-hour legend missing'
[ "$(sips -g pixelWidth -g pixelHeight "$W/popup-week.png" | awk '/pixel/ {printf "%sx", $2}' | sed 's/x$//')" = "$(cat scripts/popup-size.txt)" ] || fail 'popup size changed'
[ "$(sips -g pixelWidth -g pixelHeight "$W/share-week.png" | awk '/pixel/ {printf "%sx", $2}' | sed 's/x$//')" = '2400x1260' ] || fail 'share size changed'
echo "PASS heatmap: 7x24 cells, four blue steps, zero and future cells, pending count, coverage and peak; renders in $W"
