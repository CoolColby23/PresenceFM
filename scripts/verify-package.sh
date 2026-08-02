#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP="${1:-$ROOT/PresenceFM.app}"
EXPECTED_VERSION="${PRESENCEFM_VERSION:-$(<"$ROOT/VERSION")}"
EXPECTED_BUILD="${PRESENCEFM_BUILD_NUMBER:-1}"
PLIST="$APP/Contents/Info.plist"

fail() { echo "Package verification failed: $*" >&2; exit 1; }

[[ -x "$APP/Contents/MacOS/PresenceFM" ]] || fail "executable is missing"
[[ -f "$PLIST" ]] || fail "Info.plist is missing"
[[ -f "$APP/Contents/Resources/PresenceFM.icns" ]] || fail "application icon is missing"
[[ -f "$APP/Contents/Frameworks/Sparkle.framework/Sparkle" ]] || fail "Sparkle framework is missing"
RESOURCE_BUNDLE="$APP/Contents/Resources/PresenceFM_PresenceFM.bundle"
[[ -d "$RESOURCE_BUNDLE" ]] || fail "SwiftPM resource bundle is missing"
RESOURCE_SYMBOL="$(find "$RESOURCE_BUNDLE" -type f -name 'presencefm-symbol.svg' -print -quit)"
[[ -n "$RESOURCE_SYMBOL" ]] || fail "SwiftPM resource bundle is missing its symbol"
INTENTS_METADATA="$APP/Contents/Resources/Metadata.appintents"
[[ -d "$INTENTS_METADATA" ]] || fail "App Intents metadata is missing"
grep -R -q "SetPresenceFMPrivateModeIntent" "$INTENTS_METADATA" || fail "Private Mode intent metadata is missing"
grep -R -q "OpenPresenceFMDashboardIntent" "$INTENTS_METADATA" || fail "dashboard intent metadata is missing"

[[ "$(plutil -extract CFBundleIdentifier raw "$PLIST")" == "fm.presence.PresenceFM" ]] || fail "bundle identifier is wrong"
[[ "$(plutil -extract CFBundleShortVersionString raw "$PLIST")" == "$EXPECTED_VERSION" ]] || fail "version is wrong"
[[ "$(plutil -extract CFBundleVersion raw "$PLIST")" == "$EXPECTED_BUILD" ]] || fail "build number is wrong"
[[ "$(plutil -extract LSMinimumSystemVersion raw "$PLIST")" == "15.0" ]] || fail "minimum macOS is wrong"
[[ -n "$(plutil -extract NSAppleEventsUsageDescription raw "$PLIST")" ]] || fail "Apple Events usage description is missing"
[[ -n "$(plutil -extract PRESENCEFM_DISCORD_APPLICATION_ID raw "$PLIST")" ]] || fail "Discord application ID is missing"
[[ "$(plutil -extract SUFeedURL raw "$PLIST")" == "https://github.com/CoolColby23/PresenceFM/releases/latest/download/appcast.xml" ]] || fail "update feed URL is wrong"
[[ -n "$(plutil -extract SUPublicEDKey raw "$PLIST")" ]] || fail "Sparkle public key is missing"
[[ "$(plutil -extract SUEnableAutomaticChecks raw "$PLIST")" == "true" ]] || fail "automatic update checks are not enabled"

otool -l "$APP/Contents/MacOS/PresenceFM" | grep -q "@executable_path/../Frameworks" || fail "framework runtime search path is missing"
otool -L "$APP/Contents/MacOS/PresenceFM" | grep -q "@rpath/Sparkle.framework" || fail "executable is not linked to Sparkle"

codesign --verify --deep --strict --verbose=2 "$APP"
ENTITLEMENTS="$(codesign -d --entitlements :- "$APP" 2>/dev/null)"
[[ "$ENTITLEMENTS" == *"com.apple.security.automation.apple-events"* ]] || fail "Apple Events entitlement is missing"

echo "Verified $APP ($EXPECTED_VERSION build $EXPECTED_BUILD)"
