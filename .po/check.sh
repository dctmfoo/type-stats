#!/bin/sh
# type-stats project check: sh .po/check.sh
set -eu
cd "$(dirname "$0")/.."
python3 .po/bin/secret-scan.py
python3 .po/bin/freshness.py
git diff --check

# Tooling prerequisites for the agreed stack (Swift 6, SwiftUI, Swift Charts, SwiftData).
xcode-select -p >/dev/null
swift_major=$(swift --version 2>&1 | sed -n 's/.*Swift version \([0-9]*\).*/\1/p' | head -1)
[ "${swift_major:-0}" -ge 6 ] || { echo "FAIL Swift 6+ required (found ${swift_major:-none})"; exit 1; }
macos_major=$(sw_vers -productVersion | cut -d. -f1)
[ "$macos_major" -ge 14 ] || { echo "FAIL macOS 14+ required for SwiftData"; exit 1; }
echo "PASS tooling: Swift $swift_major, macOS $(sw_vers -productVersion)"

[ -d Tests ] && [ -n "$(find Tests -name '*.swift' | head -1)" ] || { echo "FAIL no Swift tests under Tests/"; exit 1; }
[ -f scripts/bundle-app.sh ] || { echo "FAIL scripts/bundle-app.sh missing"; exit 1; }
[ -f scripts/app-smoke.sh ] || { echo "FAIL scripts/app-smoke.sh missing (real-app behavior check)"; exit 1; }

mkdir -p .po/tmp
swift build
# Capture swift test's own exit status (a pipe into tee would hide failures).
if ! swift test > .po/tmp/swift-test.log 2>&1; then
  grep -E 'error:|failed|Executed' .po/tmp/swift-test.log || tail -40 .po/tmp/swift-test.log
  echo "FAIL swift test"; exit 1
fi
grep -E 'Executed [0-9]+ tests|Test run with' .po/tmp/swift-test.log
if grep -Eq 'Executed 0 tests|Test run with 0 tests' .po/tmp/swift-test.log; then
  echo "FAIL swift test ran zero tests"; exit 1
fi

sh scripts/bundle-app.sh
codesign --verify --deep .build/TypeStats.app
# Launches the real bundled app against an isolated data dir under .po/tmp/,
# feeds key events, checks per-app counts, restart persistence and that no
# key codes or typed text are stored.
sh scripts/app-smoke.sh
sh scripts/wpm-check.sh
# Share prototype (task 05): card sizes, sample text, popup mockup size.
sh scripts/share-prototype-check.sh
# Share (task 06): copy text/image to a named pasteboard, save, zero data, popup Share button.
sh scripts/share-check.sh
# Excluded apps: excluded apps are never counted, the list persists, history is kept, popup marker.
sh scripts/exclude-check.sh
# Pause counting: nothing counted while paused, pause survives restart, popup and icon show it.
sh scripts/pause-check.sh
# App Updates: states, errors, explicit brew arguments and replacement launch.
sh scripts/update-check.sh
# Seam coverage (every documented test seam is driven by a check or listed in .po/manual-seams.txt)
# is part of the freshness check above. No test copy of the app is left running:
sh scripts/leak-check.sh
echo "PASS type-stats checks"
