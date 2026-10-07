#!/bin/sh
# Build a release of TypeStats: a universal TypeStats.app signed with a Developer ID, notarized
# and stapled, zipped, with its SHA-256 and the Homebrew cask that installs it.
# Usage: sh scripts/package-release.sh VERSION [BUILD_NUMBER]
# Output in dist/releases/VERSION/: TypeStats.app, TypeStats-VERSION.zip, TypeStats-VERSION.sha256,
# type-stats.rb.
# Signing: DEVELOPER_ID_APP_SIGNING_IDENTITY names a "Developer ID Application: ..." identity in
# the keychain. Without it the app is signed ad hoc, which is only good for trying the packaging:
# Gatekeeper blocks a downloaded ad hoc app.
# Notarization: NOTARYTOOL_KEYCHAIN_PROFILE, or APPLE_ID, APPLE_APP_SPECIFIC_PASSWORD and
# APPLE_TEAM_ID. Skipped when none is set, unless TYPESTATS_REQUIRE_NOTARIZATION=1 (then it fails).
# TYPESTATS_ARCHS overrides the architectures (default "arm64 x86_64").
set -eu
cd "$(dirname "$0")/.."
[ $# -ge 1 ] && [ $# -le 2 ] || { echo "Usage: sh scripts/package-release.sh VERSION [BUILD_NUMBER]" >&2; exit 2; }
VERSION=$1
BUILD=${2:-1}
echo "$VERSION" | grep -Eq '^[0-9]+(\.[0-9]+){1,2}$' || { echo "VERSION must look like 1.2 or 1.2.3, got '$VERSION'" >&2; exit 2; }
echo "$BUILD" | grep -Eq '^[0-9]+$' || { echo "BUILD_NUMBER must be a number, got '$BUILD'" >&2; exit 2; }

OUT="dist/releases/$VERSION"
APP="$OUT/TypeStats.app"
ZIP="$OUT/TypeStats-$VERSION.zip"
rm -rf "${OUT:?}"
mkdir -p "$OUT"

TYPESTATS_VERSION="$VERSION" TYPESTATS_BUILD="$BUILD" TYPESTATS_ARCHS="${TYPESTATS_ARCHS:-arm64 x86_64}" \
  TYPESTATS_SIGN_IDENTITY=- sh scripts/bundle-app.sh release
ditto .build/TypeStats.app "$APP"
lipo -info "$APP/Contents/MacOS/TypeStats"

if [ -n "${DEVELOPER_ID_APP_SIGNING_IDENTITY:-}" ]; then
  # Hardened runtime and a secure timestamp are required for notarization.
  codesign --force --timestamp --options runtime --sign "$DEVELOPER_ID_APP_SIGNING_IDENTITY" \
    --identifier local.typestats.TypeStats "$APP"
else
  echo "DEVELOPER_ID_APP_SIGNING_IDENTITY is not set: the app stays ad hoc signed (not for distribution)."
fi
codesign --verify --strict --verbose=2 "$APP"

if [ -n "${NOTARYTOOL_KEYCHAIN_PROFILE:-}" ]; then
  set -- --keychain-profile "$NOTARYTOOL_KEYCHAIN_PROFILE"
elif [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ]; then
  set -- --apple-id "$APPLE_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD" --team-id "$APPLE_TEAM_ID"
else
  set --
fi
if [ $# -gt 0 ]; then
  NOTARY_ZIP="$OUT/notary-upload.zip"
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$NOTARY_ZIP"
  xcrun notarytool submit "$NOTARY_ZIP" --wait "$@"
  rm -f "$NOTARY_ZIP"
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
  spctl --assess --type execute --verbose=2 "$APP"
elif [ "${TYPESTATS_REQUIRE_NOTARIZATION:-0}" = 1 ]; then
  echo "Notarization credentials are not set and TYPESTATS_REQUIRE_NOTARIZATION=1." >&2
  exit 1
else
  echo "No notarization credentials: skipping notarization (not for distribution)."
fi

ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
SHA=$(shasum -a 256 "$ZIP" | awk '{print $1}')
echo "$SHA" > "$OUT/TypeStats-$VERSION.sha256"
sh scripts/render-cask.sh "$VERSION" "$SHA" > "$OUT/type-stats.rb"
echo "Packaged $ZIP"
echo "SHA-256 $SHA"
