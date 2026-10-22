#!/bin/zsh
# Checks a built Kyomei.app before it is packaged or published.
#   scripts/verify-app.sh [path/to/Kyomei.app] [expected-version]
# Exits non-zero on the first problem, printing what was wrong.
set -euo pipefail

APP="${1:-build/Kyomei.app}"
EXPECTED_VERSION="${2:-}"
PLIST="$APP/Contents/Info.plist"
WIDGET="$APP/Contents/PlugIns/KyomeiWidget.appex"
fail() { echo "✗ $*" >&2; exit 1; }
read_key() { /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null || true; }

[[ -d "$APP" ]] || fail "$APP does not exist"
[[ -f "$PLIST" ]] || fail "missing Info.plist"
plutil -lint "$PLIST" >/dev/null || fail "Info.plist is malformed"

EXE="$APP/Contents/MacOS/$(read_key "$PLIST" CFBundleExecutable)"
[[ -x "$EXE" ]] || fail "executable $EXE missing or not executable"

[[ "$(read_key "$PLIST" CFBundleIdentifier)" == "dev.kakushin.kyomei" ]] || fail "unexpected bundle identifier"
[[ "$(read_key "$PLIST" CFBundlePackageType)" == "APPL" ]] || fail "not an application bundle"
[[ -n "$(read_key "$PLIST" NSBluetoothAlwaysUsageDescription)" ]] || fail "missing Bluetooth usage description (the app would be killed by TCC)"

VERSION="$(read_key "$PLIST" CFBundleShortVersionString)"
[[ "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || fail "version '$VERSION' is not SemVer"
if [[ -n "$EXPECTED_VERSION" && "$VERSION" != "$EXPECTED_VERSION" ]]; then
  fail "bundle version $VERSION does not match expected $EXPECTED_VERSION"
fi
MIN_OS="$(read_key "$PLIST" LSMinimumSystemVersion)"
[[ -n "$MIN_OS" ]] || fail "missing LSMinimumSystemVersion"

ARCHS="$(lipo -archs "$EXE")"
[[ -n "$ARCHS" ]] || fail "could not read architectures"

[[ -f "$APP/Contents/Resources/AppIcon.icns" ]] || fail "missing app icon"
[[ -d "$WIDGET" ]] || fail "missing widget extension"
[[ "$(read_key "$WIDGET/Contents/Info.plist" NSExtension:NSExtensionPointIdentifier)" == "com.apple.widgetkit-extension" ]] \
  || fail "widget extension point is wrong"
WIDGET_EXE="$WIDGET/Contents/MacOS/$(read_key "$WIDGET/Contents/Info.plist" CFBundleExecutable)"
[[ -x "$WIDGET_EXE" ]] || fail "widget executable missing"
[[ "$(lipo -archs "$WIDGET_EXE")" == "$ARCHS" ]] || fail "widget and app architectures differ"
# The widget must start in NSExtensionMain (see Package.swift); a plain main crashes on launch.
# (Output is captured first: grep -q exiting early would SIGPIPE the producer under pipefail.)
LOAD_COMMANDS="$(otool -l "$WIDGET_EXE")"
[[ "$LOAD_COMMANDS" == *LC_MAIN* ]] || fail "widget has no entry point"
WIDGET_ENTITLEMENTS="$(codesign -d --entitlements - "$WIDGET" 2>/dev/null || true)"
[[ "$WIDGET_ENTITLEMENTS" == *com.apple.security.app-sandbox* ]] || fail "widget is not sandboxed; WidgetKit will not load it"

# Only system frameworks and the Swift runtime may be linked.
# Dependency lines are indented; universal binaries add an unindented header per architecture.
for line in "${(@f)$(otool -L "$EXE")}"; do
  [[ "$line" == [[:space:]]* ]] || continue
  lib="${${(z)line}[1]}"
  [[ "$lib" == /System/Library/* || "$lib" == /usr/lib/* ]] || fail "unexpected dynamic dependency: $lib"
done

codesign --verify --strict "$APP" || fail "code signature invalid"
SIGNING_INFO="$(codesign -dv "$APP" 2>&1 || true)"
SIGNATURE=""
for line in "${(@f)SIGNING_INFO}"; do
  case "$line" in Signature=*|Authority=*) SIGNATURE="${line#*=}"; break ;; esac
done

echo "✓ $APP"
echo "  version      $VERSION ($(read_key "$PLIST" CFBundleVersion))"
echo "  minimum OS   macOS $MIN_OS"
echo "  archs        $ARCHS"
echo "  signature    ${SIGNATURE:-unknown}"
