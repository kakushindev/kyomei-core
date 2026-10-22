#!/bin/zsh
# Writes Markdown release notes to stdout.
#   scripts/release-notes.sh vX.Y.Z <unsigned|signed|notarized> path/to/Kyomei-X.Y.Z-macOS.dmg
set -euo pipefail

TAG="${1:?tag}"
SIGNING="${2:?signing status}"
DMG="${3:?dmg path}"
VERSION="${TAG#v}"
NAME="$(basename "$DMG")"
SHA="$(shasum -a 256 "$DMG" | cut -d' ' -f1)"
SIZE_MB="$(awk "BEGIN { printf \"%.1f\", $(stat -f %z "$DMG") / 1048576 }")"
PREVIOUS="$(git describe --tags --abbrev=0 --match 'v[0-9]*.[0-9]*.[0-9]*' "$TAG^" 2>/dev/null || true)"

# Read by the website to label the download; keep the format stable.
echo "<!-- kyomei:signing=$SIGNING -->"
echo "## 共鳴 Kyōmei $VERSION"
echo
echo "Native macOS control for Soundcore earbuds and headphones. Universal build for Apple silicon and Intel."
echo
echo "| | |"
echo "| --- | --- |"
echo "| Download | \`$NAME\` ($SIZE_MB MB) |"
echo "| SHA-256 | \`$SHA\` |"
case "$SIGNING" in
  notarized) echo "| Signature | Developer ID signed and notarized by Apple |" ;;
  signed)    echo "| Signature | Developer ID signed, **not notarized** |" ;;
  *)         echo "| Signature | **Unsigned** (ad hoc). Gatekeeper will ask before the first launch |" ;;
esac
echo "| Requires | macOS 14 Sonoma or later, Bluetooth, a paired supported Soundcore device |"
echo
echo "### Install"
echo
echo "1. Open the disk image and drag **Kyomei** onto **Applications**."
if [[ "$SIGNING" == "notarized" ]]; then
  echo "2. Open Kyōmei from Applications and allow Bluetooth access when asked."
else
  echo "2. Open Kyōmei from Applications. macOS blocks the first launch because the app is not notarized."
  echo "3. Open **System Settings → Privacy & Security**, scroll to the message about Kyōmei and click **Open Anyway** (or Control-click the app → Open). This allows Kyōmei only; do not turn Gatekeeper off."
  echo "4. Allow Bluetooth access when asked."
fi
echo
echo "Verify the download: \`shasum -a 256 -c $NAME.sha256\`"
echo
if [[ -n "$PREVIOUS" ]]; then
  echo "### Changes since $PREVIOUS"
  echo
  git log --no-merges --pretty='- %s (%h)' "$PREVIOUS..$TAG"
else
  echo "### Changes"
  echo
  git log --no-merges --pretty='- %s (%h)' -n 50 "$TAG"
fi
echo
echo "---"
echo "Kyōmei is an independent open-source project by [Kakushin](https://kakushin.dev). It is not affiliated with, endorsed by or sponsored by Anker Innovations or Soundcore."
