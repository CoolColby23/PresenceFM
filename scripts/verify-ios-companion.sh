#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="${TMPDIR:-/tmp}/PresenceFM-iOS-Verification"
ICON="$ROOT/iOS/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"

plutil -lint "$ROOT/iOS/Info.plist" >/dev/null
jq empty "$ROOT/iOS/Assets.xcassets/AppIcon.appiconset/Contents.json"
jq empty "$ROOT/iOS/Assets.xcassets/AccentColor.colorset/Contents.json"

dimensions="$(sips -g pixelWidth -g pixelHeight "$ICON" 2>/dev/null)"
grep -q 'pixelWidth: 1024' <<< "$dimensions"
grep -q 'pixelHeight: 1024' <<< "$dimensions"
grep -q 'presencefm' "$ROOT/iOS/Info.plist"
grep -q 'lastfm-auth' "$ROOT/iOS/CompanionLastFMClient.swift"
grep -q 'presence-fm.vercel.app/lastfm-callback.html' "$ROOT/iOS/CompanionLastFMClient.swift"

if rg -n '\.pink|FF2D55|magenta' "$ROOT/iOS" --glob '*.swift' --glob '*.json'; then
    echo "Retired pink/magenta branding remains in the iOS app."
    exit 1
fi

rm -rf "$DERIVED_DATA"
xcodebuild \
    -project "$ROOT/PresenceFMiOS.xcodeproj" \
    -scheme PresenceFMiOS \
    -configuration Debug \
    -sdk iphonesimulator \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$DERIVED_DATA" \
    ARCHS="$(uname -m)" \
    ONLY_ACTIVE_ARCH=YES \
    build >/dev/null

echo "iOS companion branding, callback registration, assets, and simulator build verified."
