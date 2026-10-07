#!/bin/sh
# Pause counting check (task: pause counting). Drives the bundled app in test mode with a
# frozen clock (--at) against an isolated data dir and fails unless:
#   - while paused (15 minutes), simulated key presses and clicks for several apps add
#     nothing, also after an app restart, and the same events count again at the end time,
#   - a pause of 1 hour and one "until resumed" pause hold across restarts (even months
#     later) and stop only on --resume,
#   - the pause file holds only an end time (no app, key or text),
#   - the menu bar icon is the pause sign while paused and the keyboard otherwise,
#   - the real popup, rendered while paused, says when counting resumes and offers Resume,
#     the running popup says Counting and offers Pause, and both have the same pixel size.
# Needs: sh scripts/bundle-app.sh first.
set -eu
cd "$(dirname "$0")/.."
ROOT=$(pwd)
BIN="$ROOT/.build/TypeStats.app/Contents/MacOS/TypeStats"
W="$ROOT/.po/tmp/pause-counting/check"
DATA="$W/data"
A=local.typestats.pause.alpha
B=local.typestats.pause.beta
MARKER=TSPAUSEMARKERqxz
TAB=$(printf '\t')
fail() { echo "FAIL pause: $1"; exit 1; }
[ -x "$BIN" ] || fail "$BIN missing; run scripts/bundle-app.sh"

mkdir -p "$W"
find "$W" -mindepth 1 -delete
mkdir -p "$DATA"
SNAP="$W/ready.png"

# run_app <local time> <options...>: start the app at that frozen time, wait until it has
# processed its options (it renders --snapshot after feeding the simulated events), then
# quit it the normal way, which saves anything it counted.
run_app() {
  at=$1; shift
  rm -f "$SNAP"
  "$BIN" --data-dir "$DATA" --no-tap --at "$at" --snapshot "$SNAP" "$@" >/dev/null 2>&1 &
  pid=$!
  i=0
  until [ -s "$SNAP" ]; do
    i=$((i + 1)); [ $i -le 100 ] || { kill "$pid" 2>/dev/null || true; fail "app did not start ($at $*)"; }
    sleep 0.2
  done
  sleep 0.3
  kill -TERM "$pid"
  wait "$pid" 2>/dev/null || true
}
# "Today" for the dump is fixed too (COUNT_AT), so the check does not depend on the real date.
COUNT_AT=2026-10-05T23:00
counts() { "$BIN" --data-dir "$DATA" --at "$COUNT_AT" --dump-counts | sort; }
expect_counts() {
  label=$1; shift
  want=$(printf '%s\n' "$@" | sed '/^$/d' | sort)
  got=$(counts)
  [ "$got" = "$want" ] || { echo "expected:"; echo "$want"; echo "got:"; echo "$got"; fail "$label: counts mismatch"; }
  echo "PASS $label: $(echo "$got" | tr '\t\n' ' ;')"
}
pause_state() { "$BIN" --data-dir "$DATA" --at "$1" --dump-pause; }
# expect_pause <label> <time> <state> <until> <menu bar symbol> <status text prefix or ->
# The status text is locale formatted (12 or 24 hour, narrow spaces), so only its start is compared.
expect_pause() {
  label=$1; at=$2; want=$(printf '%s\t%s\t%s' "$3" "$4" "$5"); prefix=$6
  got=$(pause_state "$at")
  [ "$(echo "$got" | cut -f1-3)" = "$want" ] || { echo "expected: $want"; echo "got:      $got"; fail "$label: pause state mismatch"; }
  text=$(echo "$got" | cut -f4)
  case "$text" in "$prefix"*) ;; *) echo "status text: $text"; fail "$label: status text should start with \"$prefix\"" ;; esac
  echo "PASS $label: $got"
}
EVENTS="--simulate-keys $A:5,$B:3 --simulate-clicks $A:4,$B:2 --simulate-text $A:$MARKER"

# 1. Paused for 15 minutes at 10:00: nothing is counted, for any app, keys or clicks.
run_app 2026-10-05T10:00 --pause 15m $EVENTS
expect_counts "paused 15 min: nothing counted" ""
expect_pause "paused 15 min" 2026-10-05T10:00 paused 2026-10-05T10:15:00 pause.circle.fill "Paused until 10:15"
[ -f "$DATA/pause.json" ] || fail "no pause file written"

# 2. Restart inside the pause (10:14): still paused, still nothing counted.
run_app 2026-10-05T10:14 $EVENTS
expect_counts "restart at 10:14 stays paused: nothing counted" ""

# 3. Restart at the end time (10:15): counting is back, exact counts.
run_app 2026-10-05T10:15 --simulate-keys "$A:5" --simulate-clicks "$B:2"
expect_counts "restart at 10:15 counts again" "$A${TAB}5${TAB}0" "$B${TAB}0${TAB}2"
expect_pause "pause over" 2026-10-05T10:15 running - keyboard "-"

# 4. One hour: holds across restarts, ends at 12:00.
run_app 2026-10-05T11:00 --pause 1h --simulate-keys "$A:100"
run_app 2026-10-05T11:59 --simulate-keys "$A:100" --simulate-clicks "$A:100"
expect_counts "1 hour pause: nothing counted before 12:00" "$A${TAB}5${TAB}0" "$B${TAB}0${TAB}2"
run_app 2026-10-05T12:00 --simulate-keys "$A:1"
expect_counts "1 hour pause: counted at 12:00" "$A${TAB}6${TAB}0" "$B${TAB}0${TAB}2"

# 5. Until resumed: holds months later, and --resume (what the Resume button does) ends it.
run_app 2026-10-05T13:00 --pause until-resumed --simulate-keys "$A:100"
run_app 2026-12-31T09:00 --simulate-keys "$A:100"
expect_pause "until resumed, months later" 2026-12-31T09:00 paused - pause.circle.fill "Paused until you resume"
run_app 2026-12-31T09:01 --resume --simulate-keys "$A:2"
COUNT_AT=2026-12-31T23:00
expect_counts "resumed: counted again (new day, nothing counted while paused)" "$A${TAB}2${TAB}0"
COUNT_AT=2026-10-05T23:00
expect_pause "resumed" 2026-12-31T09:02 running - keyboard "-"

# 6. The pause file holds only an end time; nothing typed reaches any file in the data dir.
run_app 2026-10-05T14:00 --pause 15m
grep -q '"until"' "$DATA/pause.json" || fail "pause file has no end time"
[ "$(wc -c < "$DATA/pause.json" | tr -d ' ')" -lt 60 ] || fail "pause file holds more than an end time: $(cat "$DATA/pause.json")"
python3 - "$DATA" "$MARKER" "$A" "$B" <<'PY' || fail "typed text or app names found in the pause file or store"
import pathlib, sys
root, marker, *apps = pathlib.Path(sys.argv[1]), *sys.argv[2:]
bad = [str(p) for p in root.rglob('pause.json') if any(a.encode() in p.read_bytes() for a in apps)]
bad += [str(p) for p in root.rglob('*') if p.is_file() and any(n in p.read_bytes() for n in
        (marker.encode(), marker.encode('utf-16-le')))]
if bad: print('\n'.join(bad))
sys.exit(1 if bad else 0)
PY
echo "PASS pause file holds only an end time; no typed text stored"

# 7. The popup. Paused at 10:00 for 15 minutes vs running, same data.
run_app 2026-10-05T15:00 --resume --simulate-keys "$A:50"
SNAP="$W/running.png"; run_app 2026-10-05T15:00 --resume
SNAP="$W/paused.png"; run_app 2026-10-05T15:00 --pause 15m
size() { sips -g pixelWidth -g pixelHeight "$1" | awk '/pixelWidth/ {w=$2} /pixelHeight/ {h=$2} END {print w "x" h}'; }
[ "$(size "$W/paused.png")" = "$(size "$W/running.png")" ] \
  || fail "popup size changes when paused: running $(size "$W/running.png"), paused $(size "$W/paused.png")"
swift scripts/ocr.swift "$W/paused.png" > "$W/paused.txt"
swift scripts/ocr.swift "$W/running.png" > "$W/running.txt"
grep -q 'Paused until 15:15\|Paused until 3:15' "$W/paused.txt" || { cat "$W/paused.txt"; fail "paused popup does not say when counting resumes"; }
grep -q 'Resume' "$W/paused.txt" || fail "paused popup has no Resume button"
grep -q 'Counting' "$W/paused.txt" && fail "paused popup still says Counting"
grep -q 'Counting' "$W/running.txt" || { cat "$W/running.txt"; fail "running popup does not say Counting"; }
grep -q 'Pause' "$W/running.txt" || fail "running popup has no Pause button"
grep -q 'Paused' "$W/running.txt" && fail "running popup says Paused"
echo "PASS popup: paused shows \"$(grep 'Paused until' "$W/paused.txt")\" and Resume; running shows Counting and Pause; both $(size "$W/paused.png")"

# 8. The real menu bar icon (read through the accessibility API, so it needs the terminal to
#    have Accessibility permission; without it this part is reported as a LIMIT, not a pass).
#    The app starts paused, then resumes 12 s later as a click on Resume would. The status item
#    is named after its symbol: "Pause" for the pause sign, "Keyboard" for the keyboard.
icon_title() { osascript -e "tell application \"System Events\" to tell (first process whose unix id is $1) to get title of menu bar item 1 of menu bar 2" 2>/dev/null || true; }
wait_icon() { # <pid> <title> <seconds>: poll until the status item has that title
  i=0
  while [ $i -lt $(($3 * 5)) ]; do
    [ "$(icon_title "$1")" = "$2" ] && return 0
    i=$((i + 1)); sleep 0.2
  done
  return 1
}
mkdir -p "$W/icon"
"$BIN" --data-dir "$W/icon" --no-tap --at 2026-10-05T16:00 --pause 15m --resume-after 12 >/dev/null 2>&1 &
pid=$!
if wait_icon "$pid" Pause 8; then
  wait_icon "$pid" Keyboard 20 || { kill "$pid" 2>/dev/null || true; fail "menu bar icon stayed the pause sign after resuming"; }
  echo "PASS menu bar icon: pause sign while paused, keyboard after resuming (read live from the status item)"
elif [ -z "$(icon_title "$pid")" ]; then
  echo "LIMIT menu bar icon: the status item is not readable here (no Accessibility permission); only the symbol name from --dump-pause was checked"
else
  kill "$pid" 2>/dev/null || true; fail "menu bar icon is \"$(icon_title "$pid")\" while paused, expected the pause sign"
fi
kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true
echo "PASS pause"
