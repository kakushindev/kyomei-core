#!/bin/zsh
# Builds "Kyomei.app" (Kyōmei) with its desktop widget into ./build.
#
#   scripts/build-app.sh            build only
#   scripts/build-app.sh --install  build and copy to /Applications
#
# Environment (all optional):
#   KYOMEI_VERSION     marketing version; defaults to the VERSION file
#   KYOMEI_BUILD       CFBundleVersion build number; defaults to 1
#   KYOMEI_ARCHS       "arm64 x86_64" (default, universal) or a single arch
#   CODESIGN_IDENTITY  e.g. "Developer ID Application: Name (TEAMID)"; ad hoc when unset
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"

APP_NAME="Kyomei"
DISPLAY_NAME="Kyōmei"
BUNDLE_ID="dev.kakushin.kyomei"
WIDGET_ID="$BUNDLE_ID.widget"
LEGACY_BUNDLE_ID="dev.local.soundcore-macos"
VERSION="${KYOMEI_VERSION:-$(tr -d '[:space:]' < VERSION)}"
BUILD_NUMBER="${KYOMEI_BUILD:-1}"
ARCHS=(${=KYOMEI_ARCHS:-arm64 x86_64})
SIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/$APP_NAME.app"
APPEX="$APP/Contents/PlugIns/KyomeiWidget.appex"

if [[ ! "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
  echo "✗ Version '$VERSION' is not MAJOR.MINOR.PATCH" >&2
  exit 1
fi

ARCH_FLAGS=()
for arch in $ARCHS; do ARCH_FLAGS+=(--arch "$arch"); done

echo "▸ Compiling $DISPLAY_NAME $VERSION ($BUILD_NUMBER) for ${ARCHS[*]}…"
swift build -c release $ARCH_FLAGS --product SoundcoreMac
swift build -c release $ARCH_FLAGS --product SoundcoreWidget
BIN_DIR="$(swift build -c release $ARCH_FLAGS --show-bin-path)"

echo "▸ Assembling $APP_NAME.app…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APPEX/Contents/MacOS"
cp "$BIN_DIR/SoundcoreMac" "$APP/Contents/MacOS/$APP_NAME"
cp "$BIN_DIR/SoundcoreWidget" "$APPEX/Contents/MacOS/KyomeiWidget"

ICONSET="$BUILD_DIR/AppIcon.iconset"
if [[ ! -f "$BUILD_DIR/AppIcon.icns" || scripts/make-icon.swift -nt "$BUILD_DIR/AppIcon.icns" ]]; then
  echo "▸ Rendering icon…"
  rm -rf "$ICONSET" && mkdir -p "$ICONSET"
  swift scripts/make-icon.swift "$BUILD_DIR/icon-1024.png"
  for s in 16 32 128 256 512; do
    sips -z $s $s "$BUILD_DIR/icon-1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) "$BUILD_DIR/icon-1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$BUILD_DIR/AppIcon.icns"
fi
cp "$BUILD_DIR/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleDisplayName</key><string>$DISPLAY_NAME</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key><string>$BUNDLE_ID</string>
      <key>CFBundleURLSchemes</key><array><string>kyomei</string><string>soundcore-mac</string></array>
    </dict>
  </array>
  <key>LSApplicationCategoryType</key><string>public.app-category.music</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Kyōmei by Kakushin. Open source. Not affiliated with Anker or Soundcore.</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSBluetoothAlwaysUsageDescription</key>
  <string>Kyōmei connects to your headphones over Bluetooth to read battery levels and change noise cancelling, equalizer and other settings.</string>
</dict>
</plist>
PLIST

cat > "$APPEX/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleDisplayName</key><string>$DISPLAY_NAME</string>
  <key>CFBundleExecutable</key><string>KyomeiWidget</string>
  <key>CFBundleIdentifier</key><string>$WIDGET_ID</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>KyomeiWidget</string>
  <key>CFBundlePackageType</key><string>XPC!</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSExtension</key>
  <dict>
    <key>NSExtensionPointIdentifier</key><string>com.apple.widgetkit-extension</string>
  </dict>
</dict>
</plist>
PLIST

# Widget extensions must be sandboxed; this one may only read the snapshot the app writes.
ENTITLEMENTS="$BUILD_DIR/KyomeiWidget.entitlements"
cat > "$ENTITLEMENTS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.app-sandbox</key><true/>
  <key>com.apple.security.temporary-exception.files.home-relative-path.read-only</key>
  <array><string>/Library/Application Support/Kyomei/</string></array>
</dict>
</plist>
PLIST

# Inside-out: the extension first (with its entitlements), then the app. No --deep, which
# would re-sign the extension without its sandbox entitlements.
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  echo "▸ Signing (ad hoc; not for distribution through Gatekeeper)…"
  codesign --force --options runtime --entitlements "$ENTITLEMENTS" --sign - "$APPEX"
  codesign --force --options runtime --sign - "$APP"
else
  echo "▸ Signing with $SIGN_IDENTITY…"
  codesign --force --options runtime --timestamp --entitlements "$ENTITLEMENTS" --sign "$SIGN_IDENTITY" "$APPEX"
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
fi
codesign --verify --strict --verbose=1 "$APP"

if [[ "${1:-}" == "--install" ]]; then
  echo "▸ Installing to /Applications…"
  pkill -x "$APP_NAME" 2>/dev/null || true
  # Remove the pre-rebrand build, but only if it really is ours.
  LEGACY="/Applications/Soundcore.app"
  if [[ -d "$LEGACY" ]] && [[ "$(defaults read "$LEGACY/Contents/Info" CFBundleIdentifier 2>/dev/null)" == "$LEGACY_BUNDLE_ID" ]]; then
    pkill -x Soundcore 2>/dev/null || true
    rm -rf "$LEGACY"
    echo "  removed pre-rebrand $LEGACY"
  fi
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$APP" /Applications/
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/$APP_NAME.app" || true
  echo "✓ Installed /Applications/$APP_NAME.app"
else
  echo "✓ Built $APP"
fi
