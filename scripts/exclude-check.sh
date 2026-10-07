#!/bin/sh
# Excluded apps check (task: exclude apps from counting). Drives the bundled TypeStats.app
# against isolated data dirs and fails unless:
#   1. an excluded app's key presses, clicks and typed text are not counted while other
#      apps still are exactly,
#   2. the exclusion list survives quitting and relaunching (the app is still not counted),
#   3. removing an exclusion counts the app again, and excluding it again keeps what was
#      counted (history kept) while new presses and clicks are dropped,
#   4. a click found by the real under-pointer lookup (no app given) is dropped when its
#      app is excluded, and counted when it is not (the control that proves the check can fail),
#   5. the popup renders the excluded marker (the rendering differs from the same popup
#      with nothing excluded) and the Excluded apps page, both at the popup's usual size.
# Needs: sh scripts/bundle-app.sh first.
set -eu
cd "$(dirname "$0")/.."
ROOT=$(pwd)
APP="$ROOT/.build/TypeStats.app"
BIN="$APP/Contents/MacOS/TypeStats"
W="$ROOT/.po/tmp/exclude-apps/check"
A=local.typestats.excl.vault   # the excluded app (a password manager, say)
B=local.typestats.excl.editor
SELF=local.typestats.TypeStats
TAB=$(printf '\t')

fail() { echo "FAIL exclude: $*"; stop_app || true; exit 1; }
[ -x "$BIN" ] || { echo "FAIL exclude: $BIN missing; run scripts/bundle-app.sh"; exit 1; }
mkdir -p "$W"
find "$W" -mindepth 1 -delete

app_pid() { pgrep -f "TypeStats.app/Contents/MacOS/TypeStats --data-dir $DATA" | head -1; }
stop_app() {
  pid=$(app_pid || true)
  [ -n "$pid" ] || return 0
  kill -TERM "$pid"
  i=0
  while kill -0 "$pid" 2>/dev/null; do
    i=$((i + 1)); [ $i -le 100 ] || { echo "FAIL exclude: app did not quit"; exit 1; }
    sleep 0.1
  done
}
launch() {
  open ${OPEN_FLAGS:-} -n "$APP" --args --data-dir "$DATA" --no-tap "$@"
  i=0
  until [ -n "$(app_pid || true)" ]; do
    i=$((i + 1)); [ $i -le 150 ] || fail "app did not start"
    sleep 0.1
  done
}
dump() { "$BIN" --data-dir "$DATA" --dump-counts | sort; }
# Waits for the store to hold exactly these rows (bundleId<TAB>keys<TAB>clicks).
expect_counts() {
  label=$1; shift
  want=$(printf '%s\n' "$@" | sort)
  i=0
  while :; do
    got=$(dump)
    [ "$got" = "$want" ] && { echo "PASS $label: $(echo "$got" | tr '\t\n' ' ;')"; return 0; }
    i=$((i + 1))
    if [ $i -gt 100 ]; then
      echo "expected:"; echo "$want"; echo "got:"; echo "$got"
      fail "$label: counts mismatch"
    fi
    sleep 0.2
  done
}
expect_excluded() {
  label=$1; shift
  want=$(printf '%s\n' "$@" | sort)
  got=$("$BIN" --data-dir "$DATA" --dump-excluded | cut -f1 | sort)
  [ "$got" = "$want" ] || { echo "expected:"; echo "$want"; echo "got:"; echo "$got"; fail "$label: exclusion list mismatch"; }
  echo "PASS $label: excluded = $(echo "$got" | tr '\n' ' ')"
}

# 1. Excluded before any event: vault gets 5 keys, 8 typed characters, 4 clicks and timed
#    typing, editor gets 3 keys and 1 click. Only the editor is counted, and no row exists
#    for the vault.
DATA="$W/data"; mkdir -p "$DATA"
launch --exclude "$A" --simulate-keys "$A:5,$B:3" --simulate-text "$A:TSVAULTx" --simulate-clicks "$A:4,$B:1" \
  --simulate-typing "$A:50:10"
expect_counts "excluded app is not counted (app keys clicks)" "$B${TAB}3${TAB}1"
"$BIN" --data-dir "$DATA" --dump-wpm | grep -q "^$A" && fail "excluded app has a typing speed"
stop_app

# 2. Restart without --exclude: still excluded, still not counted; editor adds up.
expect_excluded "list persists across a restart" "$A"
launch --simulate-keys "$A:2,$B:2" --simulate-clicks "$A:2"
expect_counts "still excluded after a restart" "$B${TAB}5${TAB}1"
stop_app

# 3. Remove the exclusion: counted again. Exclude again: kept, no longer growing.
launch --include "$A" --simulate-keys "$A:4" --simulate-clicks "$A:1"
expect_counts "counted again after removing the exclusion" "$A${TAB}4${TAB}1" "$B${TAB}5${TAB}1"
expect_excluded "removal persisted" ""
stop_app
launch --exclude "$A" --simulate-keys "$A:9,$B:1" --simulate-clicks "$A:9"
expect_counts "history kept, nothing new counted" "$A${TAB}4${TAB}1" "$B${TAB}6${TAB}1"
stop_app
expect_excluded "excluded again" "$A"

# 4. Real under-pointer lookup (no app given): TypeStats's own window. Control first.
DATA="$W/self-control"; mkdir -p "$DATA"
OPEN_FLAGS=-g launch --simulate-self-clicks 3
expect_counts "control: clicks on TypeStats's window are counted" "$SELF${TAB}0${TAB}3"
stop_app
DATA="$W/self"; mkdir -p "$DATA"
OPEN_FLAGS=-g launch --exclude "$SELF" --simulate-self-clicks 3 --simulate-keys "$B:1"
expect_counts "clicks found by the real lookup are dropped when excluded" "$B${TAB}1${TAB}0"
sleep 3   # the clicks wait up to 5 s for the window, then 0.2 s
expect_counts "...and still nothing after the clicks landed" "$B${TAB}1${TAB}0"
stop_app

# 5. Popup: marker and page. Same data, with and without the exclusion.
png_size() { sips -g pixelWidth -g pixelHeight "$1" | awk '/pixel/ {printf "%sx", $2}' | sed 's/x$//'; }
snap() {  # snap <name> <launch options...>: render a snapshot and wait for it
  name=$1; shift
  launch --simulate-keys "$A:40,$B:10" --simulate-clicks "$A:3" --snapshot "$W/$name.png" "$@"
  i=0; until [ -s "$W/$name.png" ]; do i=$((i + 1)); [ $i -le 100 ] || fail "$name snapshot not rendered"; sleep 0.2; done
  stop_app
}
DATA="$W/shot-plain"; mkdir -p "$DATA"; snap plain
DATA="$W/shot-excluded"; mkdir -p "$DATA"; snap marked --exclude "$A"
DATA="$W/shot-page"; mkdir -p "$DATA"; snap page --exclude "$A" --excluded-page
for n in plain marked page; do file "$W/$n.png" | grep -q 'PNG image data' || fail "$n snapshot is not a PNG"; done
# Same counts in both; the only difference is the exclusion: the "excluded" marker on the
# app's row and the "(1)" on the Excluded apps button.
cmp -s "$W/plain.png" "$W/marked.png" && fail "popup looks the same with an excluded app (no marker)"
cmp -s "$W/marked.png" "$W/page.png" && fail "Excluded apps page looks the same as the popup"
[ "$(png_size "$W/plain.png")" = "$(png_size "$W/marked.png")" ] || fail "popup size changed with an excluded app"
[ "$(png_size "$W/plain.png")" = "$(png_size "$W/page.png")" ] || fail "Excluded apps page has a different size from the popup"
echo "PASS popup shows the excluded marker and the Excluded apps page at one size ($(png_size "$W/plain.png") px)"
echo "PASS exclude-check"
