#!/bin/sh
# Option C in the bundled app: short replies keep key totals but contribute no speed;
# qualifying typing supplies one estimate to dumps, history, popup and share outputs.
set -eu
cd "$(dirname "$0")/.."
BIN="$(pwd)/.build/TypeStats.app/Contents/MacOS/TypeStats"
W="$(mktemp -d "$(pwd)/.po/tmp/steady-wpm-XXXXXX")"
A=sample.Writer
run() { "$BIN" --no-tap --data-dir "$W/data" --at 2026-10-07T12:00 "$@"; }
fail() { echo "FAIL steady WPM: $*"; exit 1; }

run --simulate-typing "$A:20:10,$A:20:10" --share-save "$W/short.png"
run --dump-wpm > "$W/short-wpm.txt"
grep -q '^overall[[:space:]]-$' "$W/short-wpm.txt" || fail 'two 9.5-second replies contributed speed'
run --dump-counts > "$W/short-counts.txt"
grep -q "$A[[:space:]]40[[:space:]]0" "$W/short-counts.txt" || fail 'short replies changed key totals'
# 51 chars from first to last span exactly 10 seconds. 12 * 51 / 10 = 61.2 WPM.
run --simulate-typing "$A:51:10.2" --share-save "$W/qualified.png"
run --dump-wpm > "$W/qualified-wpm.txt"
run --dump-wpm > "$W/reopened-wpm.txt"
cmp "$W/qualified-wpm.txt" "$W/reopened-wpm.txt" || fail 'qualified estimate changed on reopen'
python3 - "$W/qualified-wpm.txt" "$A" <<'PY'
import sys
from pathlib import Path
rows = dict(line.split('\t') for line in Path(sys.argv[1]).read_text().splitlines())
assert abs(float(rows['overall']) - 61.2) < 0.1, rows
assert abs(float(rows[sys.argv[2]]) - 61.2) < 0.1, rows
PY
# The existing share checks assert image/text WPM for every period. Here a short
# burst followed by qualifying typing must yield 61 in each period's shared summary.
for view in today week month; do
  board="typestats.steady-wpm.$$.${view}"
  run --view "$view" --share-copy text --pasteboard "$board"
  run --pasteboard-read "$board" > "$W/share-$view.txt"
  grep -q '91 keys · 0 clicks · 61 wpm' "$W/share-$view.txt" || fail "$view share WPM differs"
  run --view "$view" --share-save "$W/share-$view.png"
done
pid=
trap 'if [ -n "$pid" ]; then kill -TERM "$pid" 2>/dev/null || true; wait "$pid" || true; fi' EXIT HUP INT TERM
"$BIN" --no-tap --data-dir "$W/data" --at 2026-10-07T12:00 --snapshot "$W/popup.png" --ready-file "$W/ready" > "$W/popup.log" 2>&1 &
pid=$!
i=0
until [ -e "$W/ready" ]; do
  i=$((i + 1)); [ "$i" -le 100 ] || fail 'popup did not become ready'
  sleep 0.1
done
kill -TERM "$pid"
wait "$pid"
pid=

echo "PASS steady WPM: short stretches ignored, keys kept, 61.2 WPM persisted and shared; evidence $W"
