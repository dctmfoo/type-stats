#!/bin/sh
# Share prototype check (task 05). Renders every share variant and the popup mockups with
# the bundled app (sample data only; never the real store) and fails unless:
#   - each card PNG exists with its exact size (A 1200x630, A week 1200x630, B 1080x1080,
#     C text image 1200x630),
#   - share-c-text.txt holds the sample totals and top apps,
#   - the Today popup matches the baseline in scripts/popup-size.txt.
#     See docs/run.md for the 7-day popup's taller, screen-capped layout.
# Usage: sh scripts/share-prototype-check.sh [out-dir]   (default .po/tmp/05-share-prototype/out)
# Needs: sh scripts/bundle-app.sh first. SHARE_CARD_A_HEIGHT overrides the expected card A
# height (used only to prove this check fails when a size is wrong).
set -eu
cd "$(dirname "$0")/.."
ROOT=$(pwd)
BIN="$ROOT/.build/TypeStats.app/Contents/MacOS/TypeStats"
OUT="${1:-$ROOT/.po/tmp/05-share-prototype/out}"
DATA="$ROOT/.po/tmp/05-share-prototype/data"
fail() { echo "FAIL share prototype: $1"; exit 1; }

mkdir -p "$OUT" "$DATA"
find "$DATA" -mindepth 1 -delete
rm -f "$OUT"/share-*.png "$OUT"/share-c-text.txt "$OUT"/popup-share*.png
"$BIN" --share-cards "$OUT" >/dev/null || fail "card render exited non-zero"

size() { sips -g pixelWidth -g pixelHeight "$1" | awk '/pixelWidth/ {w=$2} /pixelHeight/ {h=$2} END {print w "x" h}'; }
expect_size() {
  [ -s "$OUT/$1" ] || fail "$1 missing or empty"
  file "$OUT/$1" | grep -q 'PNG image data' || fail "$1 is not a PNG"
  got=$(size "$OUT/$1")
  [ "$got" = "$2" ] || fail "$1 is $got, expected $2"
  echo "PASS $1 $got"
}
expect_size share-a-full.png "1200x${SHARE_CARD_A_HEIGHT:-630}"
expect_size share-a-week.png 1200x630
expect_size share-b-numbers.png 1080x1080
expect_size share-c-text.png 1200x630

[ -s "$OUT/share-c-text.txt" ] || fail "share-c-text.txt missing"
for want in "Today:" "7,120 keys" "665 clicks" "58 wpm" "Xcode 3,840" "Mail 1,215" "Chrome 960" "via TypeStats"; do
  grep -qF "$want" "$OUT/share-c-text.txt" || fail "share-c-text.txt lacks \"$want\""
done
echo "PASS share-c-text.txt: $(cat "$OUT/share-c-text.txt")"

# Popup mockups: a made-up sample day, through the real pipeline.
popup() { # name flags...
  name=$1; shift
  "$BIN" --data-dir "$DATA" --no-tap --at 2026-10-05T01:00 \
    --simulate-typing "sample.Xcode:3840:795,sample.Mail:1215:251,sample.Google_Chrome:960:199,sample.Notes:702:145,sample.Terminal:85:18,sample.Other:14:3" \
    --simulate-clicks "sample.Xcode:300,sample.Mail:150,sample.Google_Chrome:120,sample.Notes:80,sample.Terminal:15" \
    --snapshot "$OUT/$name" "$@" >/dev/null 2>&1 &
  pid=$!
  i=0
  until [ -s "$OUT/$name" ]; do
    i=$((i + 1)); [ $i -le 100 ] || { kill "$pid" 2>/dev/null || true; fail "$name not rendered"; }
    sleep 0.2
  done
  sleep 0.5; kill -TERM "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true
  find "$DATA" -mindepth 1 -delete
}
popup popup-share.png
ref=$(cat scripts/popup-size.txt)
# A literal filename is intentional; this check covers only the Today share popup.
# shellcheck disable=SC2043
for f in popup-share.png; do
  got=$(size "$OUT/$f")
  [ "$got" = "$ref" ] || fail "$f is $got, scripts/popup-size.txt says $ref"
  echo "PASS $f $got (popup size)"
done
echo "PASS share prototype"
