#!/bin/zsh
# Packages Kyomei.app into Kyomei-X.Y.Z-macOS.dmg (drag to Applications) plus a .sha256 file,
# then mounts the image read-only and checks what is inside.
#   scripts/package-dmg.sh [path/to/Kyomei.app] [output-dir]
# CODESIGN_IDENTITY, when set, also signs the disk image.
set -euo pipefail

ROOT="${0:A:h:h}"
APP="${1:-$ROOT/build/Kyomei.app}"
OUT_DIR="${2:-$ROOT/build}"
fail() { echo "✗ $*" >&2; exit 1; }

[[ -d "$APP" ]] || fail "$APP does not exist; run scripts/build-app.sh first"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$OUT_DIR/Kyomei-$VERSION-macOS.dmg"
mkdir -p "$OUT_DIR"
[[ ! -e "$DMG" ]] || fail "$DMG already exists; refusing to overwrite"

STAGING="$(mktemp -d)"
MOUNT=""
cleanup() {
  [[ -n "$MOUNT" ]] && hdiutil detach "$MOUNT" -quiet 2>/dev/null || true
  rm -rf "$STAGING"
}
trap cleanup EXIT

echo "▸ Staging…"
ditto "$APP" "$STAGING/Kyomei.app"
ln -s /Applications "$STAGING/Applications"

echo "▸ Creating $(basename "$DMG")…"
hdiutil create -volname "Kyōmei $VERSION" -srcfolder "$STAGING" -fs HFS+ -format UDZO \
  -imagekey zlib-level=9 -ov "$DMG" >/dev/null

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  echo "▸ Signing disk image…"
  codesign --force --timestamp --sign "$CODESIGN_IDENTITY" "$DMG"
  codesign --verify --strict "$DMG"
fi

echo "▸ Verifying…"
hdiutil verify "$DMG" >/dev/null || fail "image checksum verification failed"
MOUNT="$(mktemp -d)"
hdiutil attach "$DMG" -readonly -nobrowse -noautoopen -mountpoint "$MOUNT" -quiet
[[ -d "$MOUNT/Kyomei.app" ]] || fail "Kyomei.app missing from image"
[[ "$(readlink "$MOUNT/Applications")" == "/Applications" ]] || fail "Applications link missing from image"
"$ROOT/scripts/verify-app.sh" "$MOUNT/Kyomei.app" "$VERSION" >/dev/null || fail "app inside the image failed verification"
hdiutil detach "$MOUNT" -quiet
MOUNT=""

SIZE="$(stat -f %z "$DMG")"
(( SIZE > 1000000 )) || fail "image is suspiciously small ($SIZE bytes)"
(cd "$OUT_DIR" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")

echo "✓ $DMG ($SIZE bytes)"
echo "  sha256  $(cut -d' ' -f1 "$DMG.sha256")"
