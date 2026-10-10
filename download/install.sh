#!/bin/bash
#
# Vaultline Ingest installer.
#
#   curl -fsSL https://vaultline.io/ingest/install.sh | bash
#
# It downloads a notarized DMG, checks its SHA-256, copies the app to
# /Applications, and opens the standalone utility. It never installs anything else, never writes outside
# /Applications, and never asks for sudo.
#
set -euo pipefail

VERSION="0.3.0"
SHA256="7fb29c2cfa78920e674346cf8da8b34e5a3ed2f2e8d93185650c0d9d519a25c0"
BASE="https://github.com/jake-vaultline/vaultline-labs/releases/download"
DMG="ingest-v${VERSION}/VaultlineIngest-${VERSION}.dmg"
APP="VaultlineIngest.app"

bold() { printf "\033[1m%s\033[0m\n" "$1"; }
die()  { printf "\033[31m✗ %s\033[0m\n" "$1" >&2; exit 1; }

bold "Vaultline Ingest ${VERSION}"

[[ "$(uname)" == "Darwin" ]] || die "This installer is for macOS."
MAJOR=$(sw_vers -productVersion | cut -d. -f1)
[[ "$MAJOR" -ge 13 ]] || die "macOS 13 or later is required (found $(sw_vers -productVersion))."

TMP="$(mktemp -d)"
cleanup() {
  [[ -d "$TMP/mnt" ]] && hdiutil detach "$TMP/mnt" -quiet >/dev/null 2>&1 || true
  rm -rf "$TMP"
}
trap cleanup EXIT

echo "  Downloading…"
curl -fsSL "${BASE}/${DMG}" -o "$TMP/$DMG" || die "Download failed."

# Verify before mounting. A DMG that doesn't match the published checksum does
# not get opened, let alone installed.
echo "  Verifying…"
GOT=$(shasum -a 256 "$TMP/$DMG" | awk '{print $1}')
[[ "$GOT" == "$SHA256" ]] || die "Checksum mismatch. Not installing.
  expected $SHA256
  got      $GOT"

echo "  Installing…"
mkdir -p "$TMP/mnt"
hdiutil attach "$TMP/$DMG" -nobrowse -quiet -mountpoint "$TMP/mnt" || die "Couldn't open the disk image."

if [[ -d "/Applications/$APP" ]]; then
  echo "  Replacing the existing copy…"
  rm -rf "/Applications/$APP"
fi
cp -R "$TMP/mnt/$APP" /Applications/ || die "Couldn't copy to /Applications."
hdiutil detach "$TMP/mnt" -quiet

# Confirm what actually landed on disk is Apple-notarized. If Gatekeeper is
# unhappy, say so here rather than letting the user meet it as a scary dialog.
if ! spctl -a -t exec "/Applications/$APP" >/dev/null 2>&1; then
  echo "  ! macOS could not verify this copy. Remove it and download manually from ${BASE}."
fi

bold "Installed to /Applications/${APP}"

open -a "/Applications/$APP"

echo
echo "  Drop a card on the window to start. Nothing is ever moved or deleted —"
echo "  files are copied, then read back and checksummed before they're called done."
