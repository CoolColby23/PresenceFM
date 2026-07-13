#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP="${1:-$ROOT/PresenceFM.app}"
EXPECTED_VERSION="${PRESENCEFM_VERSION:-0.4.0}"
EXPECTED_BUILD="${PRESENCEFM_BUILD_NUMBER:-1}"
PLIST="$APP/Contents/Info.plist"

fail() { echo "Package verification failed: $*" >&2; exit 1; }

[[ -x "$APP/Contents/MacOS/PresenceFM" ]] || fail "executable is missing"
[[ -f "$PLIST" ]] || fail "Info.plist is missing"
[[ -f "$APP/Contents/Resources/PresenceFM.icns" ]] || fail "application icon is missing"
RESOURCE_BUNDLE="$APP/Contents/Resources/PresenceFM_PresenceFM.bundle"
[[ -d "$RESOURCE_BUNDLE" ]] || fail "SwiftPM resource bundle is missing"
RESOURCE_SYMBOL="$(find "$RESOURCE_BUNDLE" -type f -name 'presencefm-symbol.svg' -print -quit)"
[[ -n "$RESOURCE_SYMBOL" ]] || fail "SwiftPM resource bundle is missing its symbol"

[[ "$(plutil -extract CFBundleIdentifier raw "$PLIST")" == "fm.presence.PresenceFM" ]] || fail "bundle identifier is wrong"
[[ "$(plutil -extract CFBundleShortVersionString raw "$PLIST")" == "$EXPECTED_VERSION" ]] || fail "version is wrong"
[[ "$(plutil -extract CFBundleVersion raw "$PLIST")" == "$EXPECTED_BUILD" ]] || fail "build number is wrong"
[[ "$(plutil -extract LSMinimumSystemVersion raw "$PLIST")" == "15.0" ]] || fail "minimum macOS is wrong"
[[ -n "$(plutil -extract NSAppleEventsUsageDescription raw "$PLIST")" ]] || fail "Apple Events usage description is missing"
[[ -n "$(plutil -extract PRESENCEFM_DISCORD_APPLICATION_ID raw "$PLIST")" ]] || fail "Discord application ID is missing"

codesign --verify --deep --strict --verbose=2 "$APP"
ENTITLEMENTS="$(codesign -d --entitlements :- "$APP" 2>/dev/null)"
[[ "$ENTITLEMENTS" == *"com.apple.security.automation.apple-events"* ]] || fail "Apple Events entitlement is missing"

echo "Verified $APP ($EXPECTED_VERSION build $EXPECTED_BUILD)"
