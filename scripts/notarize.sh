#!/bin/zsh
# Submits a signed disk image to Apple's notary service, waits, and staples the ticket.
#   scripts/notarize.sh path/to/Kyomei-X.Y.Z-macOS.dmg
# Requires APPLE_ID, APPLE_TEAM_ID and APPLE_APP_PASSWORD (an app-specific password).
# Only meaningful for images signed with a Developer ID Application certificate.
set -euo pipefail

DMG="${1:?usage: notarize.sh path/to/image.dmg}"
: "${APPLE_ID:?APPLE_ID is not set}"
: "${APPLE_TEAM_ID:?APPLE_TEAM_ID is not set}"
: "${APPLE_APP_PASSWORD:?APPLE_APP_PASSWORD is not set}"

codesign --verify --strict "$DMG" || { echo "✗ $DMG is not signed; notarization would be rejected" >&2; exit 1; }

echo "▸ Submitting to the notary service (this can take a few minutes)…"
RESULT="$(xcrun notarytool submit "$DMG" --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" \
  --password "$APPLE_APP_PASSWORD" --wait --output-format json)"
echo "$RESULT"
STATUS="$(print -r -- "$RESULT" | /usr/bin/plutil -extract status raw -o - - 2>/dev/null || true)"
if [[ "$STATUS" != "Accepted" ]]; then
  ID="$(print -r -- "$RESULT" | /usr/bin/plutil -extract id raw -o - - 2>/dev/null || true)"
  [[ -n "$ID" ]] && xcrun notarytool log "$ID" --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD" || true
  echo "✗ Notarization status: ${STATUS:-unknown}" >&2
  exit 1
fi

echo "▸ Stapling…"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
echo "✓ Notarized and stapled $DMG"
