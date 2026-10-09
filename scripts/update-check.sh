#!/bin/sh
# Drive App Updates in the real bundle. Fixtures never run the system brew or touch user data.
set -eu
cd "$(dirname "$0")/.."
ROOT=$(pwd -P)
BIN="$ROOT/.build/TypeStats.app/Contents/MacOS/TypeStats"
W=$(mktemp -d "$ROOT/.po/tmp/updates.XXXXXX")
pid=
cleanup() {
  [ -z "$pid" ] || kill -TERM "$pid" 2>/dev/null || true
  # A successful update creates a new process; terminate that exact isolated-data copy too.
  pkill -TERM -f "TypeStats --no-tap --data-dir $W" 2>/dev/null || true
}
trap cleanup EXIT HUP INT TERM
fail() { echo "FAIL updates: $1"; exit 1; }
wait_file() {
  n=0
  until [ -s "$1" ]; do
    n=$((n + 1)); [ "$n" -le 150 ] || fail "app did not produce $1"
    sleep 0.2
  done
}
stop() { kill -TERM "$pid"; wait "$pid" 2>/dev/null || true; pid=; }
printf 'cask "type-stats" do\n  version "0.1.0"\nend\n' > "$W/cask.rb"
run() {
  name=$1; shift
  "$BIN" --no-tap --data-dir "$W/$name" --update-cask "$W/cask.rb" \
    --snapshot "$W/$name.png" --ready-file "$W/$name.ready" "$@" > "$W/$name.log" 2>&1 &
  pid=$!
  wait_file "$W/$name.ready"
  kill -0 "$pid" || fail "app quit unexpectedly"
  stop
  swift scripts/ocr.swift "$W/$name.png" > "$W/$name.txt"
}
run current --update-version 0.1.0 --updates-window
grep -q 'Current version' "$W/current.txt" || fail 'no current version in dialog'
grep -q 'Latest version' "$W/current.txt" || fail 'no latest version in dialog'
grep -q "latest release" "$W/current.txt" || fail 'no up-to-date status'
grep -q 'Check for Updates' "$W/current.txt" || fail 'wrong current action'
run available --update-version 0.0.0 --updates-window
grep -q 'new version is available' "$W/available.txt" || fail 'no update status'
grep -q 'Update from Homebrew' "$W/available.txt" || fail 'wrong update action'
run footer-current --update-version 0.1.0
# Vision can read the leading zero as a capital O in the taller shared popup.
grep -Eq 'Version [0O]\.1\.0' "$W/footer-current.txt" || fail 'footer version missing'
run footer-available --update-version 0.0.0
grep -q 'Update available' "$W/footer-available.txt" || fail 'footer indicator missing'
[ "$(sips -g pixelHeight "$W/footer-current.png" | awk '/pixelHeight/ {print $2}')" = \
  "$(sips -g pixelHeight "$W/footer-available.png" | awk '/pixelHeight/ {print $2}')" ] || fail 'footer changes popup size'
# Broken release responses must not claim that the app is current.
printf 'bad cask data\n' > "$W/cask.rb"
run bad-source --updates-window
grep -q 'Could not check for updates' "$W/bad-source.txt" || fail 'no check error'
printf 'version "0.1.0"\n' > "$W/cask.rb"
# Argument recording proves explicit brew selection, refresh and --no-quit; failure keeps the app alive.
cat > "$W/brew" <<SHBREW
#!/bin/sh
printf '%s\\n' "\$*" >> '$W/brew-args'
case "\$1" in
  update) exit 0 ;;
  info) printf '%s\\n' '{"casks":[{"installed":"0.1.0","artifacts":[{"target":"$ROOT/.build/TypeStats.app"}]}]}' ;;
  upgrade) echo 'Homebrew fixture upgrade failed' >&2; exit 1 ;;
esac
SHBREW
chmod +x "$W/brew"
run failure --update-version 0.0.0 --updates-window --update-brew "$W/brew" --perform-update
grep -q 'Homebrew fixture upgrade failed' "$W/failure.txt" || fail 'no upgrade error'
grep -qx 'upgrade --cask --no-quit dctmfoo/type-stats/type-stats' "$W/brew-args" || fail 'unsafe or incorrect upgrade command'
grep -qx 'update --quiet' "$W/brew-args" || fail 'tap was not refreshed'
# Successful fixture upgrade drives NSWorkspace relaunch, retaining the same isolated store.
sed 's/echo .* >&2; exit 1/exit 0/' "$W/brew" > "$W/brew-success"
chmod +x "$W/brew-success"
"$BIN" --no-tap --data-dir "$W/relaunch" --update-version 0.0.0 --update-cask "$W/cask.rb" \
  --update-brew "$W/brew-success" --perform-update --update-relaunch-ready "$W/relaunched.ready" \
  --simulate-keys sample.Update:7 > "$W/relaunch.log" 2>&1 &
pid=$!
wait_file "$W/relaunched.ready"
n=0
while kill -0 "$pid" 2>/dev/null; do
  n=$((n + 1)); [ "$n" -le 50 ] || fail 'old app did not quit after replacement launch'; sleep 0.2
done
wait "$pid" 2>/dev/null || true
pid=
cleanup
n=0
# Match the isolated data path literally; pgrep would treat it as a regular expression.
# shellcheck disable=SC2009
while ps -axo command= | grep -F "TypeStats --no-tap --data-dir $W/relaunch" | grep -v grep >/dev/null; do
  n=$((n + 1)); [ "$n" -le 50 ] || fail 'replacement app did not quit'; sleep 0.2
done
[ "$("$BIN" --no-tap --data-dir "$W/relaunch" --dump-counts)" = "$(printf 'sample.Update\t7\t0')" ] || fail 'counts lost after relaunch'
echo "PASS updates: footer, dialog, errors, Homebrew arguments and real app relaunch with counts preserved ($W)"
