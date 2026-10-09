#!/bin/sh
# Real hourly-store -> popup and share-image proof, in a fresh isolated fixture.
set -eu
cd "$(dirname "$0")/.."
ROOT=$(pwd -P)
BIN="$ROOT/.build/TypeStats.app/Contents/MacOS/TypeStats"
W=${TYPESTATS_HEATMAP_ARTIFACTS:-$(mktemp -d "$ROOT/.po/tmp/heatmap.XXXXXX")}
mkdir -p "$W"
FIXTURES=$(mktemp -d "$ROOT/.po/tmp/heatmap-data.XXXXXX")
DATA="$FIXTURES/main"
mkdir -p "$DATA"
pid=
cleanup() {
  if [ -n "$pid" ]; then kill -TERM "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; fi
  rm -rf "$FIXTURES"
}
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
popup popup-week-banners --popup-banners --screen-height 875
popup popup-week-banners-full --popup-banners --screen-height 5000
python3 scripts/heatmap-probe.py dark:"$W/popup-week-dark.png" light:"$W/popup-week-light.png" dark:"$W/share-week.png" || fail 'grid or shade mismatch'
swift scripts/ocr.swift "$W/share-week.png" > "$W/share.txt"
grep -q 'Based on 704 of 804 keys' "$W/share.txt" || fail 'coverage note missing or wrong'
grep -q 'Peak Tue 29, 4-5 pm' "$W/share.txt" || fail 'peak label missing or wrong'
grep -q 'Not yet' "$W/share.txt" || fail 'future-hour legend missing'
# The 7-day popup is 296 px (148 pt) taller than the other views, with full-height Top apps,
# and only the Top apps list shrinks (the footer stays) when the visible screen height is smaller.
today=$(cat scripts/popup-size.txt)
week_height=$((${today#*x} + 296))
[ "$(size "$W/popup-week-dark.png")" = "${today%x*}x$week_height" ] || fail "7-day popup is $(size "$W/popup-week-dark.png"), expected ${today%x*}x$week_height"
[ "$(size "$W/popup-week-light.png")" = "${today%x*}x$week_height" ] || fail '7-day light popup size differs from dark'
[ "$(size "$W/popup-week-capped.png")" = "${today%x*}x1384" ] || fail "7-day popup on a 700 pt screen is $(size "$W/popup-week-capped.png"), expected ${today%x*}x1384"
swift scripts/ocr.swift "$W/popup-week-capped.png" | grep -q Quit || fail 'capped 7-day popup lost its footer'
banner_size=$(size "$W/popup-week-banners.png")
[ "$banner_size" = "${today%x*}x1734" ] || fail "banner popup is $banner_size, expected ${today%x*}x1734"
for image in popup-week-banners popup-week-banners-full; do
  swift scripts/ocr.swift "$W/$image.png" > "$W/$image.txt"
  for text in 'Permission needed' 'Allow TypeStats in Login Items' 'Could not change login item' 'Share' 'Quit'; do
    grep -q "$text" "$W/$image.txt" || fail "$image lost $text"
  done
done
[ "$(sips -g pixelWidth -g pixelHeight "$W/share-week.png" | awk '/pixel/ {printf "%sx", $2}' | sed 's/x$//')" = '2400x1260' ] || fail 'share size changed'
DATA="$FIXTURES/edge"; mkdir -p "$DATA"
record 2026-09-28T10:00 --simulate-keys sample.OutsideWeek:9999
record 2026-09-29T10:00 --simulate-keys sample.First:20,sample.Second:20
record 2026-10-05T10:30 --simulate-keys sample.Today:40
for view in today week month; do
  "$BIN" --no-tap --data-dir "$DATA" --at 2026-10-05T10:30 --view "$view" --share-save "$W/edge-$view.png"
  swift scripts/ocr.swift "$W/edge-$view.png" > "$W/edge-$view.txt"
done
grep -q '2 tied' "$W/edge-week.txt" || fail 'equal hourly peaks were not reported as tied'
grep -q 'Peak Tue 29, 10-11 am' "$W/edge-week.txt" || fail 'peak date or seven-day boundary is wrong'
"$BIN" --no-tap --data-dir "$DATA" --at 2026-10-05T10:30 --dump-history 7 > "$W/edge-history.txt"
[ "$(tail -1 "$W/edge-history.txt" | cut -f2)" = 80 ] || fail 'weekly counts changed on reopen or included the eighth day'
for view in today month; do
  if grep -q 'When you typed' "$W/edge-$view.txt"; then fail "$view unexpectedly includes the weekly heatmap"; fi
done
DATA="$FIXTURES/legacy"; mkdir -p "$DATA"
"$BIN" --no-tap --data-dir "$DATA" --at 2026-10-05T10:30 --seed-nohour sample.Legacy:75 --view week --share-save "$W/legacy-only.png"
swift scripts/ocr.swift "$W/legacy-only.png" > "$W/legacy-only.txt"
grep -q 'No hourly typing yet' "$W/legacy-only.txt" || fail 'legacy-only week invents a peak'
grep -q 'Based on 0 of 75 keys' "$W/legacy-only.txt" || fail 'legacy-only coverage is wrong'
DATA="$FIXTURES/empty"; mkdir -p "$DATA"
"$BIN" --no-tap --data-dir "$DATA" --at 2026-10-05T10:30 --view week --share-save "$W/empty-week.png"
swift scripts/ocr.swift "$W/empty-week.png" > "$W/empty-week.txt"
grep -q 'No hourly typing yet' "$W/empty-week.txt" || fail 'empty week invents a peak'
echo "PASS heatmap: 7x24 cells in light and dark, full-height Top apps capped to the screen, four blue steps, zero and future cells, pending count, coverage and peak; renders in $W"
