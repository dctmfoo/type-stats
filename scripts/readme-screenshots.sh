#!/bin/sh
# Render the README screenshots from made-up sample data (never the real store):
#   docs/images/popup-today.png  the popup on Today
#   docs/images/popup-week.png   the popup on 7 days
#   docs/images/share-card.png   the Share > Copy image card for Today
# The sample is a week of typing in sample apps (Xcode, Mail, Google Chrome, Notes, Terminal)
# fed through the app's own pipeline with --simulate-typing and --simulate-clicks, at fixed
# dates (--at), in a scratch data dir under .po/tmp/.
# Usage: sh scripts/readme-screenshots.sh   (builds the app bundle first)
set -eu
cd "$(dirname "$0")/.."
ROOT=$(pwd)
BIN="$ROOT/.build/TypeStats.app/Contents/MacOS/TypeStats"
W="$ROOT/.po/tmp/readme-screenshots"
DATA="$W/data"
OUT="$ROOT/docs/images"
fail() { echo "FAIL readme-screenshots: $1"; exit 1; }

sh scripts/bundle-app.sh >/dev/null
mkdir -p "$W" "$OUT"
find "$W" -mindepth 1 -delete
mkdir -p "$DATA"

# One hour of sample use: record <yyyy-MM-ddTHH:mm> <scale 1..9>. Typing runs at about 60 wpm
# (keys / 5 seconds each); --share-save makes the app simulate, save and exit without UI.
record() {
  at=$1; n=$2
  "$BIN" --data-dir "$DATA" --no-tap --at "$at" \
    --simulate-typing "sample.Xcode:$((n * 60)):$((n * 12)),sample.Mail:$((n * 20)):$((n * 4)),sample.Google_Chrome:$((n * 15)):$((n * 3)),sample.Notes:$((n * 10)):$((n * 2))" \
    --simulate-keys "sample.Terminal:$((n * 3))" \
    --simulate-clicks "sample.Xcode:$((n * 4)),sample.Mail:$((n * 3)),sample.Google_Chrome:$((n * 5)),sample.Finder:$n" \
    --share-save "$W/scratch.png" || fail "could not record $at"
}

# Six earlier days, a few hours each, then today (Monday 5 October) from 9 to 17.
for day in 2026-09-29:5 2026-09-30:7 2026-10-01:4 2026-10-02:8 2026-10-03:2 2026-10-04:3; do
  date=${day%:*}; scale=${day#*:}
  for hour in 10 14 16; do record "${date}T$hour:00" "$scale"; done
done
for spec in 09:3 10:7 11:8 12:2 13:4 14:9 15:8 16:6 17:3; do
  record "2026-10-05T${spec%:*}:00" "${spec#*:}"
done

# The popup, rendered by the app itself (--snapshot), without the test-mode line.
snapshot() { # view file
  rm -f "$W/ready"
  "$BIN" --data-dir "$DATA" --no-tap --no-test-banner --at 2026-10-05T17:30 --view "$1" \
    --snapshot "$OUT/$2" --ready-file "$W/ready" >/dev/null 2>&1 &
  pid=$!
  i=0
  until [ -e "$W/ready" ]; do
    i=$((i + 1)); [ $i -le 150 ] || { kill -TERM "$pid" 2>/dev/null || true; fail "$2 not rendered"; }
    sleep 0.2
  done
  kill -TERM "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  file "$OUT/$2" | grep -q 'PNG image data' || fail "$2 is not a PNG"
  echo "wrote docs/images/$2"
}
snapshot today popup-today.png
snapshot week popup-week.png

"$BIN" --data-dir "$DATA" --no-tap --at 2026-10-05T17:30 --view today --share-save "$OUT/share-card.png" \
  || fail "share card not written"
# The card is 2400x1260; half size is plenty for the README and keeps the repository small.
sips --resampleWidth 1200 "$OUT/share-card.png" >/dev/null
echo "wrote docs/images/share-card.png"
