#!/bin/sh
# Reproducible Porcelain screenshots from the illustrative app/hour fixture, never real usage.
# Generates Today/week popup images and the matching weekly share with ChatGPT's desktop icon.
set -eu
cd "$(dirname "$0")/.."
ROOT=$(pwd -P)
export TYPESTATS_BUNDLE_ID="${TYPESTATS_BUNDLE_ID:-local.typestats.TypeStats.check}"
BIN="$ROOT/.build/TypeStats.app/Contents/MacOS/TypeStats"
W="$ROOT/.po/tmp/readme-screenshots"
DATA="$W/data"
OUT="$ROOT/docs/images"
pid=
cleanup() {
  if [ -n "$pid" ]; then kill -TERM "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; fi
  if [ -d "$DATA" ]; then find "$DATA" -mindepth 1 -delete; rmdir "$DATA"; fi
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
fail() { echo "FAIL readme-screenshots: $1"; exit 1; }

sh scripts/bundle-app.sh >/dev/null
identity=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$ROOT/.build/TypeStats.app/Contents/Info.plist")
[ "$identity" != local.typestats.TypeStats ] || fail 'screenshots require a development bundle identity'
mkdir -p "$W" "$OUT"
find "$W" -mindepth 1 -delete
mkdir -p "$DATA"
swiftc -swift-version 6 -parse-as-library -module-name TypeStatsCore -target "$(uname -m)-apple-macos14.0" \
  Sources/TypeStatsCore/*.swift scripts/app-colors-fixture.swift -o "$W/fixture"
"$W/fixture" "$DATA"

snapshot() {
  rm -f "$W/ready"
  "$BIN" --data-dir "$DATA" --no-tap --no-test-banner --at 2026-10-05T14:30 --view "$1" \
    --snapshot "$OUT/$2" --ready-file "$W/ready" >/dev/null 2>&1 &
  pid=$!
  i=0
  until [ -e "$W/ready" ]; do
    i=$((i + 1)); [ "$i" -le 150 ] || fail "$2 not rendered"
    sleep 0.2
  done
  kill -TERM "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  pid=
  file "$OUT/$2" | grep -q 'PNG image data' || fail "$2 is not a PNG"
  echo "wrote docs/images/$2"
}
snapshot today popup-today.png
snapshot week popup-week.png
"$BIN" --data-dir "$DATA" --no-tap --at 2026-10-05T14:30 --view week --share-save "$OUT/share-card.png" \
  || fail "share card not written"
sips --resampleWidth 1200 "$OUT/share-card.png" >/dev/null
echo "wrote docs/images/share-card.png"
