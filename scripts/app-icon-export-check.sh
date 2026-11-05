#!/bin/sh
# Compile actual UI/actions with a probe entry point, without changing the app's seams.
set -eu
cd "$(dirname "$0")/.."
W=$1
mkdir -p "$W"
swiftc -swift-version 6 -parse-as-library -target "$(uname -m)-apple-macos14.0" \
  -emit-module -emit-library -module-name TypeStatsCore Sources/TypeStatsCore/*.swift \
  -o "$W/libTypeStatsCore.dylib" -emit-module-path "$W/TypeStatsCore.swiftmodule"
set --
for source in Sources/TypeStats/*.swift; do
  case "$source" in */main.swift|*/TypeStatsApp.swift) continue ;; esac
  set -- "$@" "$source"
done
swiftc -swift-version 6 -parse-as-library -target "$(uname -m)-apple-macos14.0" \
  -I "$W" -L "$W" -lTypeStatsCore "$@" scripts/app-icon-export-probe.swift -o "$W/export-probe"
for order in popup-first export-first; do
  for appearance in light dark; do
    "$W/export-probe" "$W/$order-$appearance" "$order" "$appearance"
  done
done
python3 scripts/app-icon-export-probe.py "$W"
