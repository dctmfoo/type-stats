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
  name=$1; view=$2; shift 2
  rm -f "$W/ready"
  "$BIN" --no-tap --data-dir "$DATA" --at 2026-10-05T10:30 --hold-flush \
    --simulate-keys sample.Notes:1 --view "$view" "$@" \
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
for view in today week month; do
  popup "popup-$view-dark" "$view" --dark-snapshot --screen-height 5000
  popup "popup-$view-light" "$view" --screen-height 5000
  popup "popup-$view-capped" "$view" --screen-height 700
  popup "popup-$view-small" "$view" --screen-height 500
  popup "popup-$view-banners" "$view" --popup-banners --screen-height 875
  popup "popup-$view-banners-full" "$view" --popup-banners --screen-height 5000
done
python3 scripts/heatmap-probe.py dark:"$W/popup-week-dark.png" light:"$W/popup-week-light.png" dark:"$W/share-week.png" || fail 'grid or shade mismatch'
swift scripts/ocr.swift "$W/share-week.png" > "$W/share.txt"
grep -q 'Based on 704 of 804 keys' "$W/share.txt" || fail 'coverage note missing or wrong'
grep -q 'Peak Tue 29, 4-5 pm' "$W/share.txt" || fail 'peak label missing or wrong'
grep -q 'Not yet' "$W/share.txt" || fail 'future-hour legend missing'
# One snapshot size across periods, appearances, data shapes and screen caps.
# Permission and login banners do not take height away from the footer.
expected=$(cat scripts/popup-size.txt)
for view in today week month; do
  for appearance in dark light; do
    [ "$(size "$W/popup-$view-$appearance.png")" = "$expected" ] \
      || fail "$view $appearance popup is $(size "$W/popup-$view-$appearance.png"), expected $expected"
  done
  for cap in capped small banners banners-full; do
    image=popup-$view-$cap
    [ "$(size "$W/$image.png")" = "$(size "$W/popup-today-$cap.png")" ] || fail "$image size differs from Today"
    swift scripts/ocr.swift "$W/$image.png" > "$W/$image.txt"
    for text in 'Share' 'Quit'; do
      grep -q "$text" "$W/$image.txt" || fail "$image lost $text"
    done
    case "$cap" in
      capped) wanted="${expected%x*}x1384" ;;
      small) wanted="${expected%x*}x984" ;;
      banners) wanted="${expected%x*}x1734" ;;
      banners-full) wanted=$(size "$W/popup-today-banners-full.png") ;;
    esac
    [ "$(size "$W/$image.png")" = "$wanted" ] || fail "$image did not respect the screen cap ($wanted)"
    case "$cap" in
      banners*)
        for text in 'Permission needed' 'Allow TypeStats in Login Items' 'Could not change login item'; do
          grep -q "$text" "$W/$image.txt" || fail "$image lost $text"
        done ;;
    esac
  done
done
# A hosting window follows content size, so a stray per-period height must fail here too.
for height in 5000 700 500 875; do
  banners=
  [ "$height" != 875 ] || banners=--popup-banners
  "$BIN" --no-tap --data-dir "$DATA" --at 2026-10-05T10:30 --screen-height "$height" \
    $banners --measure-views > "$W/measure-$height.txt" &
  pid=$!
  n=0
  while kill -0 "$pid" 2>/dev/null; do
    n=$((n + 1)); [ "$n" -le 150 ] || fail '--measure-views did not finish'
    sleep 0.2
  done
  wait "$pid" || fail '--measure-views failed'; pid=
  [ "$(wc -l < "$W/measure-$height.txt" | tr -d ' ')" = 13 ] || fail '--measure-views did not report 13 steps'
  [ "$(cut -f2- "$W/measure-$height.txt" | sort -u | wc -l | tr -d ' ')" = 1 ] \
    || fail "popup fitting size or window frame changed on a $height pt screen"
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
echo "PASS heatmap: 7x24 cells in light and dark, identical popup sizes and live frames across periods and screen caps, fixed footer, four blue steps, zero and future cells, pending count, coverage and peak; renders in $W"
