#!/bin/sh
# Print the Homebrew cask for a TypeStats release zip.
# Usage: sh scripts/render-cask.sh VERSION SHA256 [OWNER/REPO]
# OWNER/REPO defaults to $GITHUB_REPOSITORY, then dctmfoo/type-stats.
set -eu
[ $# -ge 2 ] && [ $# -le 3 ] || { echo "Usage: sh scripts/render-cask.sh VERSION SHA256 [OWNER/REPO]" >&2; exit 2; }
VERSION=$1
SHA=$2
REPO=${3:-${GITHUB_REPOSITORY:-dctmfoo/type-stats}}
echo "$VERSION" | grep -Eq '^[0-9]+(\.[0-9]+){1,2}$' || { echo "VERSION must look like 1.2 or 1.2.3" >&2; exit 2; }
echo "$SHA" | grep -Eq '^[0-9a-f]{64}$' || { echo "SHA256 must be 64 lowercase hex characters" >&2; exit 2; }
cat <<CASK
cask "type-stats" do
  version "$VERSION"
  sha256 "$SHA"

  url "https://github.com/$REPO/releases/download/v#{version}/TypeStats-#{version}.zip"
  name "TypeStats"
  desc "Menu bar app that counts key presses and clicks per app"
  homepage "https://github.com/$REPO"

  depends_on macos: :sonoma

  app "TypeStats.app"

  uninstall quit: "local.typestats.TypeStats"

  zap trash: "~/Library/Application Support/TypeStats"
end
CASK
