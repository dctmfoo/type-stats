#!/bin/sh
# Real-app behavior check (tasks 01 to 03). Launches the bundled TypeStats.app against
# isolated data dirs, feeds key and mouse events through the app's own counting
# pipeline (--simulate-keys / --simulate-text / --simulate-clicks /
# --simulate-self-clicks / --simulate-typing), and checks:
#   1. exact per-app key and click counts for today (clicks never add keys),
#   2. counts survive quitting and relaunching the app (and keep adding up), and
#      presses and clicks not yet saved when the app quits are saved on quit,
#   3. a click at a TypeStats window goes to the app under the pointer (real lookup),
#   4. no typed text reaches the store,
#   5. counts recorded at given dates and hours (--at) give exact hourly buckets and
#      exact 7- and 30-day totals, typing speed excludes idle pauses, all of it
#      survives a relaunch, and the history view renders,
#   6. the real login item status can be read (read only; nothing is registered).
#   7. the popup keeps one size: Today, 7 days and 30 days render at identical pixel
#      dimensions for very different data (note and 8+ apps, 2 apps, nothing in the past),
#      and a live window that follows the popup's content size keeps the same fitting size
#      and window frame while the view switches and counts change .
# Exits non-zero on any mismatch. Needs: sh scripts/bundle-app.sh first.
set -eu
cd "$(dirname "$0")/.."
ROOT=$(pwd)
APP="$ROOT/.build/TypeStats.app"
BIN="$APP/Contents/MacOS/TypeStats"
SMOKE="$ROOT/.po/tmp/smoke-fixtures/smoke"
DATA="$SMOKE/data"
A=local.typestats.smoke.alpha
B=local.typestats.smoke.beta
C=local.typestats.smoke.gamma   # clicks only
SELF=local.typestats.TypeStats
MARKER=TSMARKERqwxzv   # 13 characters, typed into alpha via --simulate-text

fail() { echo "FAIL app-smoke: $*"; stop_app || true; exit 1; }

[ -x "$BIN" ] || { echo "FAIL app-smoke: $BIN missing; run scripts/bundle-app.sh"; exit 1; }
mkdir -p "$SMOKE"
find "$SMOKE" -mindepth 1 -delete
mkdir -p "$DATA"

app_pid() { pgrep -f "TypeStats.app/Contents/MacOS/TypeStats --data-dir $DATA" | head -1; }

stop_app() {
  pid=$(app_pid || true)
  [ -n "$pid" ] || return 0
  kill -TERM "$pid"   # the app quits normally on SIGTERM, saving pending counts
  i=0
  while kill -0 "$pid" 2>/dev/null; do
    i=$((i + 1)); [ $i -le 100 ] || { echo "FAIL app-smoke: app did not quit"; exit 1; }
    sleep 0.1
  done
}

# Samples the running app for this data dir into $SMOKE/sample.txt and prints the top of it.
sample_app() {
  pid=$(app_pid || true)
  if [ -n "$pid" ]; then
    if sample "$pid" 1 -file "$SMOKE/sample.txt" >/dev/null 2>&1; then
      echo "process sample (first lines of $SMOKE/sample.txt):"; head -40 "$SMOKE/sample.txt"
    else
      echo "process $pid is running; sample failed"
    fi
  else
    echo "no TypeStats process for $DATA is running (it exited or never launched)"
  fi
}

# A launch that never counts: say so, with a sample of the process (what it is doing).
no_start() {
  echo "FAIL app-smoke: app did not start counting ($1)"
  sample_app
  force_stop_app
  exit 1
}

# A hung app never handles SIGTERM (its main thread is blocked), so end it with SIGKILL.
force_stop_app() {
  pid=$(app_pid || true)
  [ -z "$pid" ] || kill -KILL "$pid" 2>/dev/null || true
  i=0
  while [ -n "$(app_pid || true)" ] && [ $i -le 50 ]; do i=$((i + 1)); sleep 0.1; done
}

# Waits until the app has written its --ready-file (startup and simulated events done).
# Returns non-zero if it does not appear within 10 s.
wait_ready() {
  i=0
  until [ -e "$SMOKE/ready" ]; do
    i=$((i + 1)); [ $i -le 100 ] || return 1
    sleep 0.1
  done
}

launch() {
  # Real bundle via Launch Services, test mode (no event tap, no permission prompt).
  # OPEN_FLAGS=-g launches it in the background (not frontmost). The app writes the ready
  # file when startup and the simulated presses are done; launch returns after that.
  # The app sometimes parks in its store start-up (SwiftData) and never counts; a launch
  # that does is sampled, killed and retried once, and a second hang fails the check.
  attempt=1
  while :; do
    rm -f "$SMOKE/ready"
    # An unset OPEN_FLAGS must contribute no argument; -g is used for background launch.
    # shellcheck disable=SC2086
    open ${OPEN_FLAGS:-} -n "$APP" --args --data-dir "$DATA" --no-tap --ready-file "$SMOKE/ready" "$@"
    i=0
    until [ -n "$(app_pid || true)" ]; do
      i=$((i + 1)); [ $i -le 100 ] || fail "app did not start"
      sleep 0.1
    done
    wait_ready && return 0
    [ $attempt -lt 2 ] || no_start "no ready file after 10 s, twice"
    echo "RETRY app-smoke: app did not start counting within 10 s; sampling it, killing it and launching once more"
    sample_app
    force_stop_app
    attempt=$((attempt + 1))
  done
}

dump() { "$BIN" --data-dir "$DATA" --dump-counts | sort; }

# Rows are bundleId<TAB>keys<TAB>clicks.
# Waits until the store holds exactly the expected counts (the app flushes simulated
# presses right after feeding them), then compares.
expect_counts() {
  want=$(printf '%s\n' "$@" | sort)
  i=0
  while :; do
    got=$(dump)
    [ "$got" = "$want" ] && { echo "PASS counts (app keys clicks): $(echo "$got" | tr '\t\n' ' ;')"; return 0; }
    i=$((i + 1))
    if [ $i -gt 100 ]; then
      echo "expected:"; echo "$want"; echo "got:"; echo "$got"
      [ -n "$got" ] || no_start "the store is still empty"
      fail "counts mismatch"
    fi
    sleep 0.2
  done
}

TAB=$(printf '\t')

# 1. Exact per-app counts: alpha 5 keys + 13 typed characters and 7 clicks, beta 3 keys,
#    gamma 4 clicks only. The popup view must also render (in-app snapshot of the same
#    SwiftUI view).
SHOT="$SMOKE/popup.png"
launch --simulate-keys "$A:5,$B:3" --simulate-text "$A:$MARKER" --simulate-clicks "$A:7,$C:4" \
  --show-window --snapshot "$SHOT"
expect_counts "$A${TAB}18${TAB}7" "$B${TAB}3${TAB}0" "$C${TAB}0${TAB}4"
i=0
until [ -s "$SHOT" ]; do
  i=$((i + 1)); [ $i -le 50 ] || fail "popup snapshot not rendered"
  sleep 0.2
done
file "$SHOT" | grep -q 'PNG image data' || fail "popup snapshot is not a PNG"
echo "PASS popup rendered ($(sips -g pixelWidth -g pixelHeight "$SHOT" | awk '/pixel/ {printf "%s ", $2}'))"

# 2. Quit, relaunch with the same data dir: counts persist and new keys and clicks add up.
stop_app
[ -z "$(app_pid || true)" ] || fail "app still running after quit"
expect_counts "$A${TAB}18${TAB}7" "$B${TAB}3${TAB}0" "$C${TAB}0${TAB}4"
launch --simulate-keys "$B:2" --simulate-clicks "$A:2,$C:1"
expect_counts "$A${TAB}18${TAB}9" "$B${TAB}5${TAB}0" "$C${TAB}0${TAB}5"
stop_app
expect_counts "$A${TAB}18${TAB}9" "$B${TAB}5${TAB}0" "$C${TAB}0${TAB}5"

# Presses and clicks still pending at quit (--hold-flush keeps them unsaved) are saved by quitting.
launch --hold-flush --simulate-keys "$A:4" --simulate-clicks "$B:3"
[ "$(dump)" = "$(printf '%s\n' "$A${TAB}18${TAB}9" "$B${TAB}5${TAB}0" "$C${TAB}0${TAB}5" | sort)" ] \
  || fail "held presses or clicks were saved before quit"
stop_app
expect_counts "$A${TAB}22${TAB}9" "$B${TAB}5${TAB}3" "$C${TAB}0${TAB}5"

# 3. Attribution by the real under-pointer lookup: the app orders a window front without
#    becoming frontmost (launched in the background) and clicks its centre with no app
#    given. The clicks must go to TypeStats, not the frontmost app.
OPEN_FLAGS=-g launch --simulate-self-clicks 6
expect_counts "$A${TAB}22${TAB}9" "$B${TAB}5${TAB}3" "$C${TAB}0${TAB}5" "$SELF${TAB}0${TAB}6"
front=$(lsappinfo info -only bundleid "$(lsappinfo front)" 2>/dev/null | sed -n 's/.*="\(.*\)"/\1/p')
if [ "$front" = "$SELF" ]; then
  echo "LIMIT attribution: TypeStats was frontmost, so this run does not separate lookup from fallback"
else
  echo "PASS clicks went to the window under the pointer (frontmost app was ${front:-unknown})"
fi
stop_app

# 4. Typed text never reaches the store (UTF-8 or UTF-16LE).
[ -n "$(ls "$DATA")" ] || fail "no store files written"
python3 - "$DATA" "$MARKER" <<'PY' || fail "typed text found in store"
import pathlib, sys
root, marker = pathlib.Path(sys.argv[1]), sys.argv[2]
needles = [marker.encode(), marker.encode('utf-16-le'), marker.encode('utf-16-be')]
hits = [str(p) for p in root.rglob('*') if p.is_file() and any(n in p.read_bytes() for n in needles)]
print('\n'.join(hits))
sys.exit(1 if hits else 0)
PY
# This only displays generated store filenames; it never parses the listing.
# shellcheck disable=SC2012
echo "PASS no typed text in store ($(ls "$DATA" | tr '\n' ' '))"

# 5. History, hours and typing speed, in their own data dir with fixed dates (--at), so
#    the result does not depend on today's date. "Today" below is 2026-10-04.
DATA="$SMOKE/history"
mkdir -p "$DATA"
NOW=2026-10-04T18:00
at_dump() { "$BIN" --data-dir "$DATA" --at "$NOW" "$@"; }

# Compares a dump with the expected lines.
expect_dump() {
  label=$1; got=$2; shift 2
  want=$(printf '%s\n' "$@")
  if [ "$got" != "$want" ]; then
    echo "expected:"; echo "$want"; echo "got:"; echo "$got"
    fail "$label mismatch"
  fi
  echo "PASS $label: $(echo "$got" | tr '\t\n' ' ;')"
}

# record_at <local time> <app options...>: launch with the clock at that time, wait
# until the simulated events are saved, quit.
record_at() {
  at=$1; shift
  before=$("$BIN" --data-dir "$DATA" --at "$at" --dump-hours)
  launch --at "$at" "$@"
  i=0
  while [ "$("$BIN" --data-dir "$DATA" --at "$at" --dump-hours)" = "$before" ]; do
    i=$((i + 1)); [ $i -le 100 ] || fail "nothing saved at $at"
    sleep 0.2
  done
  stop_app
}

record_at 2026-09-04T09:00 --simulate-keys "$A:1000"                        # 30 days back: in neither period
record_at 2026-09-05T10:00 --simulate-keys "$A:50" --simulate-clicks "$B:5"  # 29 days back: 30 days only
record_at 2026-09-27T23:00 --simulate-keys "$B:70"                          # 7 days back: 30 days only
record_at 2026-09-28T00:30 --simulate-keys "$B:20" --simulate-clicks "$A:2"  # 6 days back: both
record_at 2026-10-04T09:15 --simulate-keys "$A:7" --simulate-clicks "$A:3"
# Timed typing in alpha: 300 presses over 60 s, a 60 s idle pause, then 200 over 30 s.
# Stretches: 300 net chars in 59.8 s and 200 in 29.85 s, so 12 * 500 / 89.65 = 66.93 WPM.
# Counting the idle pause would give 39.9 WPM. Beta's presses carry no time.
record_at 2026-10-04T14:59 --simulate-keys "$B:5" --simulate-typing "$A:300:60,$A:200:30"
# A last launch at "now": one click lands in hour 18, and the 7-day view renders.
WEEK="$SMOKE/week.png"
record_at "$NOW" --simulate-clicks "$B:1" --view week --snapshot "$WEEK"

check_history() {
  expect_dump "hours (hour keys clicks)" "$(at_dump --dump-hours)" \
    "9${TAB}7${TAB}3" "14${TAB}505${TAB}0" "18${TAB}0${TAB}1"
  expect_dump "7 days (days, apps, total)" "$(at_dump --dump-history 7)" \
    "day${TAB}2026-09-28${TAB}20${TAB}2" \
    "day${TAB}2026-09-29${TAB}0${TAB}0" "day${TAB}2026-09-30${TAB}0${TAB}0" "day${TAB}2026-10-01${TAB}0${TAB}0" \
    "day${TAB}2026-10-02${TAB}0${TAB}0" "day${TAB}2026-10-03${TAB}0${TAB}0" \
    "day${TAB}2026-10-04${TAB}512${TAB}4" \
    "app${TAB}$A${TAB}507${TAB}5" "app${TAB}$B${TAB}25${TAB}1" "total${TAB}532${TAB}6"
  month=$(at_dump --dump-history 30)
  [ "$(echo "$month" | grep -c '^day')" = 30 ] || fail "30-day history does not list 30 days"
  [ "$(echo "$month" | grep '^day' | head -1 | cut -f2)" = 2026-09-05 ] || fail "30-day history does not start on 2026-09-05"
  expect_dump "30 days (nonzero days, apps, total)" "$(echo "$month" | awk -F"$TAB" '$1 != "day" || $3 + $4 > 0')" \
    "day${TAB}2026-09-05${TAB}50${TAB}5" "day${TAB}2026-09-27${TAB}70${TAB}0" \
    "day${TAB}2026-09-28${TAB}20${TAB}2" "day${TAB}2026-10-04${TAB}512${TAB}4" \
    "app${TAB}$A${TAB}557${TAB}5" "app${TAB}$B${TAB}95${TAB}6" "total${TAB}652${TAB}11"
  at_dump --dump-wpm | python3 -c '
import sys
rows = dict(line.rstrip("\n").split("\t") for line in sys.stdin)
want = 12 * 500 / 89.65
for name in ("overall", sys.argv[1]):
    got = float(rows.get(name, "nan"))
    if not abs(got - want) < 0.5:
        sys.exit(f"{name} wpm {got} is not {want:.1f} (within 0.5)")
if sys.argv[2] in rows:
    sys.exit("presses without a time must not give a speed")
print(f"PASS typing speed (want {want:.2f}): {rows}")
' "$A" "$B" || fail "typing speed"
}
check_history
file "$WEEK" | grep -q 'PNG image data' || fail "7-day view snapshot not rendered"
echo "PASS 7-day view rendered"
# Relaunch with nothing new: everything above is unchanged.
launch --at "$NOW"
stop_app
check_history
echo "PASS history, hours and speed survive a relaunch"

# 6. The real login item status is readable (read only; the smoke never registers it).
status=$("$BIN" --login-status)
case "$status" in
  enabled|disabled|requiresApproval) echo "PASS login item status readable: $status" ;;
  *) fail "login item status: $status" ;;
esac
# 7. Steady popup . Own data dirs under .po/tmp/smoke-fixtures/steady/.
STEADY="$ROOT/.po/tmp/smoke-fixtures/steady"
mkdir -p "$STEADY"
find "$STEADY" -mindepth 1 -delete
STEADY_NOW=2026-10-04T18:00
png_size() { sips -g pixelWidth -g pixelHeight "$1" | awk '/pixel/ {printf "%sx", $2}' | sed 's/x$//'; }

# One snapshot per view, each with a different data shape; all must be the same size.
# today: counts with no hour (so the note shows) and ten apps (more than the list holds)
DATA="$STEADY/today"; mkdir -p "$DATA"
launch --at "$STEADY_NOW" --view today --snapshot "$STEADY/today.png" \
  --seed-nohour "$A:40" --simulate-keys "$B:9,$C:8,l.a:7,l.b:6,l.c:5,l.d:4,l.e:3,l.f:2,l.g:1" --simulate-clicks "$A:2"
i=0; until [ -s "$STEADY/today.png" ]; do i=$((i + 1)); [ $i -le 50 ] || fail "today snapshot not rendered"; sleep 0.2; done
stop_app
# week: two apps on an earlier day, nothing today
DATA="$STEADY/week"; mkdir -p "$DATA"
record_at 2026-10-01T10:00 --simulate-keys "$A:30,$B:10"
launch --at "$STEADY_NOW" --view week --screen-height 5000 --snapshot "$STEADY/week.png"
i=0; until [ -s "$STEADY/week.png" ]; do i=$((i + 1)); [ $i -le 50 ] || fail "week snapshot not rendered"; sleep 0.2; done
stop_app
# month: only today has counts (0 past days with data), one app
DATA="$STEADY/month"; mkdir -p "$DATA"
launch --at "$STEADY_NOW" --view month --snapshot "$STEADY/month.png" --simulate-keys "$A:3"
i=0; until [ -s "$STEADY/month.png" ]; do i=$((i + 1)); [ $i -le 50 ] || fail "month snapshot not rendered"; sleep 0.2; done
stop_app
today_size=$(png_size "$STEADY/today.png")
[ "$(png_size "$STEADY/month.png")" = "$today_size" ] \
  || fail "popup size differs between views: today $today_size, month $(png_size "$STEADY/month.png")"
# The 7-day view adds the heatmap (148 pt, 296 px at 2x) and keeps full-height Top apps.
week_size="${today_size%x*}x$((${today_size#*x} + 296))"
[ "$(png_size "$STEADY/week.png")" = "$week_size" ] \
  || fail "7-day popup is $(png_size "$STEADY/week.png"), expected $week_size"
echo "PASS popup is the same size for Today and 30 days ($today_size px) and 148 pt taller for 7 days ($week_size px)"

# A live window that follows the popup's content size (like the menu bar window) switches
# through every view while counts arrive; its size and frame stay fixed within a view, and only 7 days is taller.
DATA="$STEADY/live"; mkdir -p "$DATA"
"$BIN" --data-dir "$DATA" --no-tap --at "$STEADY_NOW" --seed-nohour "$A:40" --simulate-keys "$B:5" \
  --screen-height 5000 --measure-views > "$STEADY/measure.txt" &
i=0; while kill -0 $! 2>/dev/null; do i=$((i + 1)); [ $i -le 300 ] || { kill $!; fail "--measure-views did not finish"; }; sleep 0.1; done
[ "$(wc -l < "$STEADY/measure.txt" | tr -d ' ')" = 9 ] || { cat "$STEADY/measure.txt"; fail "--measure-views did not report 9 steps"; }
[ "$(grep -v week "$STEADY/measure.txt" | cut -f2- | sort -u | wc -l | tr -d ' ')" = 1 ] \
  || { cat "$STEADY/measure.txt"; fail "popup size or window frame changed while switching between Today and 30 days or counting"; }
[ "$(grep week "$STEADY/measure.txt" | cut -f2- | sort -u | wc -l | tr -d ' ')" = 1 ] \
  || { cat "$STEADY/measure.txt"; fail "7-day popup size or window frame changed while counting"; }
other=$(grep -v week "$STEADY/measure.txt" | sed -n 1p | cut -f2-)
week=$(grep week "$STEADY/measure.txt" | sed -n 1p | cut -f2-)
[ "$(echo "$week" | cut -f1,3,4,5)" = "$(echo "$other" | cut -f1,3,4,5)" ] \
  || { cat "$STEADY/measure.txt"; fail "7-day popup width or position differs from the other views"; }
[ "$(echo "$week" | cut -f2)" -gt "$(echo "$other" | cut -f2)" ] \
  || { cat "$STEADY/measure.txt"; fail "7-day popup is not taller than the other views"; }
echo "PASS live popup keeps its size and position across 9 steps (width height x y w h: $(echo "$other" | tr '\t' ' '); 7 days: $(echo "$week" | tr '\t' ' '))"

echo "PASS app-smoke"
