#!/bin/sh
# Build TypeStats and wrap it in .build/TypeStats.app (menu bar only).
# Signing: the app is signed with a local "Apple Development" identity so every rebuild keeps the
# same designated requirement and macOS keeps the Input Monitoring grant. Set
# TYPESTATS_SIGN_IDENTITY to a certificate name or SHA-1 to choose another identity, or to "-" to
# force ad hoc. With no usable identity it falls back to ad hoc (a new identity on every build).
# TYPESTATS_VERSION and TYPESTATS_BUILD set the bundle's version (default 0.1.0 and 1);
# TYPESTATS_ARCHS="arm64 x86_64" builds a universal binary (default: this Mac's architecture).
# Usage: sh scripts/bundle-app.sh [debug|release]   (default: release)
set -eu
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
VERSION="${TYPESTATS_VERSION:-0.1.0}"
BUILD="${TYPESTATS_BUILD:-1}"
ARCH_FLAGS=""
for arch in ${TYPESTATS_ARCHS:-}; do ARCH_FLAGS="$ARCH_FLAGS --arch $arch"; done

# shellcheck disable=SC2086
swift build -c "$CONFIG" $ARCH_FLAGS --product TypeStats
# shellcheck disable=SC2086
BIN_DIR=$(swift build -c "$CONFIG" $ARCH_FLAGS --show-bin-path)
APP=.build/TypeStats.app

rm -rf .build/TypeStats.app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/TypeStats" "$APP/Contents/MacOS/TypeStats"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleExecutable</key><string>TypeStats</string>
    <key>CFBundleIdentifier</key><string>local.typestats.TypeStats</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>TypeStats</string>
    <key>CFBundleDisplayName</key><string>TypeStats</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>MIT License</string>
</dict>
</plist>
PLIST
plutil -lint "$APP/Contents/Info.plist" >/dev/null

# Pick the signing identity: the override, else the first "Apple Development: <name>" certificate
# (by name; Xcode's "Created via API" ones are skipped). Never Developer ID or distribution.
IDENTITY="${TYPESTATS_SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
  IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
    | grep '"Apple Development: ' | grep -v 'Created via API' \
    | sed 's/^ *[0-9]*) //' | sort -k2 | awk 'NR==1 { print $1 }')
fi
if [ -n "$IDENTITY" ] && [ "$IDENTITY" != "-" ] \
  && codesign --force --sign "$IDENTITY" --identifier local.typestats.TypeStats "$APP" 2>/dev/null; then
  echo "Signed with identity $IDENTITY (stable across rebuilds)"
else
  if [ "$IDENTITY" = "-" ]; then
    echo "Ad hoc signing requested: macOS will ask for Input Monitoring again after each rebuild."
  else
    echo "No usable Apple Development signing identity: signing ad hoc, so macOS will ask for Input Monitoring again after each rebuild."
    echo "Install an Apple Development certificate, or set TYPESTATS_SIGN_IDENTITY to one."
  fi
  codesign --force --sign - --identifier local.typestats.TypeStats "$APP"
fi
echo "Built $APP ($CONFIG, version $VERSION build $BUILD)"
