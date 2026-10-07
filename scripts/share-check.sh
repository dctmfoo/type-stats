#!/bin/sh
# Share check (task 06). Drives the bundled app's Share actions with simulated counts in a
# temp data dir and a NAMED pasteboard (never the general one), then reads the results back
# in a separate process. Fails unless, for Today and 7 days:
#   - Copy text leaves exactly the expected line built from the simulated totals,
#   - Copy image leaves a PNG (and a TIFF) of 2400x1260 pixels (the 1200x630 card at 2x),
#   - Save writes a PNG of that size, and the two views produce different images,
# plus: zero data still gives a valid line and image, copying without a named pasteboard is
# refused, and the real popup shows the Share button (blue pixels left of Quit) at the
# unchanged popup size.
# Needs: sh scripts/bundle-app.sh first. SHARE_EXPECT_TODAY_KEYS overrides the expected
# Today key total (used only to prove this check fails when a total is wrong).
set -eu
cd "$(dirname "$0")/.."
ROOT=$(pwd)
BIN="$ROOT/.build/TypeStats.app/Contents/MacOS/TypeStats"
W="$ROOT/.po/tmp/06-share/check"
DATA="$W/data"
EMPTY="$W/empty"
fail() { echo "FAIL share: $1"; exit 1; }
[ -x "$BIN" ] || fail "$BIN missing; run scripts/bundle-app.sh"

mkdir -p "$W"
find "$W" -mindepth 1 -delete
mkdir -p "$DATA" "$EMPTY"
size() { sips -g pixelWidth -g pixelHeight "$1" | awk '/pixelWidth/ {w=$2} /pixelHeight/ {h=$2} END {print w "x" h}'; }

# Friday 2 Oct: keys with no timing; Monday 5 Oct (today): timed typing (60 wpm) and clicks.
"$BIN" --data-dir "$DATA" --no-tap --at 2026-10-02T14:00 \
  --simulate-keys "sample.Claude:1000,sample.Zed:200" --simulate-clicks "sample.Claude:40" \
  --share-save "$W/warmup.png" || fail "could not simulate the earlier day"
SIM="--data-dir $DATA --no-tap --at 2026-10-05T01:00"
TODAY_ARGS='--simulate-typing sample.Claude:600:120,sample.Discord:300:60,sample.Google_Chrome:150:30,sample.Notes:30:6 --simulate-clicks sample.Claude:70,sample.Discord:30,sample.Google_Chrome:20,sample.Notes:5'
# shellcheck disable=SC2086
"$BIN" $SIM $TODAY_ARGS --share-save "$W/warmup2.png" || fail "could not simulate today"

TODAY_KEYS="${SHARE_EXPECT_TODAY_KEYS:-1,080}"
EXPECT_today="Today: $TODAY_KEYS keys · 125 clicks · 60 wpm. Top: Claude 600 · Discord 300 · Chrome 150. via TypeStats"
EXPECT_week="Last 7 days: 2,280 keys · 165 clicks · 60 wpm. Top: Claude 1,600 · Discord 300 · Zed 200. via TypeStats"

for view in today week; do
  eval "expect=\$EXPECT_$view"
  pb="typestats-share-check-$$-$view"
  # Copy text
  # shellcheck disable=SC2086
  "$BIN" $SIM --view "$view" --share-copy text --pasteboard "$pb.text" || fail "$view: copy text exited non-zero"
  got=$("$BIN" --pasteboard-read "$pb.text" | sed -n 's/^text	//p')
  [ "$got" = "$expect" ] || fail "$view: copied text is \"$got\", expected \"$expect\""
  echo "PASS $view copy text: $got"
  # Copy image
  # shellcheck disable=SC2086
  "$BIN" $SIM --view "$view" --share-copy image --pasteboard "$pb.image" || fail "$view: copy image exited non-zero"
  "$BIN" --pasteboard-read "$pb.image" --pasteboard-png "$W/copied-$view.png" > "$W/read-$view.txt"
  grep -q "^png	2400x1260	" "$W/read-$view.txt" || fail "$view: pasteboard has no 2400x1260 PNG: $(cat "$W/read-$view.txt")"
  grep -q "^tiff	2400x1260	" "$W/read-$view.txt" || fail "$view: pasteboard has no 2400x1260 TIFF"
  file "$W/copied-$view.png" | grep -q 'PNG image data' || fail "$view: copied image is not a PNG"
  echo "PASS $view copy image: PNG and TIFF 2400x1260"
  # Save image
  # shellcheck disable=SC2086
  "$BIN" $SIM --view "$view" --share-save "$W/saved-$view.png" || fail "$view: save exited non-zero"
  [ -s "$W/saved-$view.png" ] || fail "$view: saved file missing"
  [ "$(size "$W/saved-$view.png")" = "2400x1260" ] || fail "$view: saved image is $(size "$W/saved-$view.png")"
  echo "PASS $view save image: 2400x1260"
done
cmp -s "$W/saved-today.png" "$W/saved-week.png" && fail "today and week cards are identical"
echo "PASS today and week cards differ"

# Zero data is still valid output.
"$BIN" --data-dir "$EMPTY" --no-tap --at 2026-10-05T01:00 --share-copy text --pasteboard "typestats-share-check-$$-zero" || fail "zero: copy text failed"
got=$("$BIN" --pasteboard-read "typestats-share-check-$$-zero" | sed -n 's/^text	//p')
[ "$got" = "Today: 0 keys · 0 clicks. via TypeStats" ] || fail "zero data text is \"$got\""
"$BIN" --data-dir "$EMPTY" --no-tap --at 2026-10-05T01:00 --share-save "$W/zero.png" || fail "zero: save failed"
[ "$(size "$W/zero.png")" = "2400x1260" ] || fail "zero data image has the wrong size"
echo "PASS zero data: valid line and image"

# Copy never defaults to the owner's clipboard.
if "$BIN" --data-dir "$EMPTY" --no-tap --share-copy text >/dev/null 2>&1; then fail "copy without --pasteboard should be refused"; fi
echo "PASS copy without a named pasteboard is refused"

# The real popup (no flag) shows Share next to Quit.
"$BIN" $SIM --snapshot "$W/popup.png" >/dev/null 2>&1 &
pid=$!
i=0
until [ -s "$W/popup.png" ]; do
  i=$((i + 1)); [ $i -le 100 ] || { kill "$pid" 2>/dev/null || true; fail "popup not rendered"; }
  sleep 0.2
done
sleep 0.5; kill -TERM "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true
[ "$(size "$W/popup.png")" = "$(cat scripts/popup-size.txt)" ] || fail "popup size changed: $(size "$W/popup.png")"
python3 scripts/share-button-probe.py "$W/popup.png" || fail "the popup shows no Share button"
echo "PASS share"
