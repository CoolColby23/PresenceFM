#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"
"$ROOT/scripts/sync-brand-assets.sh"
swift build -c release

VERSION="${PRESENCEFM_VERSION:-0.4.0}"
BUILD_NUMBER="${PRESENCEFM_BUILD_NUMBER:-1}"
DISCORD_APPLICATION_ID="${PRESENCEFM_DISCORD_APPLICATION_ID:-1525555974390153346}"

APP="$ROOT/PresenceFM.app"
CONTENTS="$APP/Contents"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$ROOT/.build/release/PresenceFM" "$CONTENTS/MacOS/PresenceFM"
cp "$ROOT/brand/PresenceFM.icns" "$CONTENTS/Resources/PresenceFM.icns"
RESOURCE_BUNDLE="$ROOT/.build/release/PresenceFM_PresenceFM.bundle"
if [[ -d "$RESOURCE_BUNDLE" ]]; then
  cp -R "$RESOURCE_BUNDLE" "$CONTENTS/Resources/PresenceFM_PresenceFM.bundle"
fi

plutil -create xml1 "$CONTENTS/Info.plist"
plutil -insert CFBundleName -string PresenceFM "$CONTENTS/Info.plist"
plutil -insert CFBundleDisplayName -string PresenceFM "$CONTENTS/Info.plist"
plutil -insert CFBundleIdentifier -string fm.presence.PresenceFM "$CONTENTS/Info.plist"
plutil -insert CFBundleExecutable -string PresenceFM "$CONTENTS/Info.plist"
plutil -insert CFBundlePackageType -string APPL "$CONTENTS/Info.plist"
plutil -insert CFBundleIconFile -string PresenceFM "$CONTENTS/Info.plist"
plutil -insert CFBundleShortVersionString -string "$VERSION" "$CONTENTS/Info.plist"
plutil -insert CFBundleVersion -string "$BUILD_NUMBER" "$CONTENTS/Info.plist"
plutil -insert LSMinimumSystemVersion -string 15.0 "$CONTENTS/Info.plist"
plutil -insert NSAppleEventsUsageDescription -string "PresenceFM reads the track currently playing in Apple Music. It does not control playback or modify your library." "$CONTENTS/Info.plist"
plutil -insert NSHumanReadableCopyright -string "PresenceFM contributors" "$CONTENTS/Info.plist"

plutil -insert PRESENCEFM_DISCORD_APPLICATION_ID -string "$DISCORD_APPLICATION_ID" "$CONTENTS/Info.plist"

if [[ "${PRESENCEFM_SKIP_SIGNING:-0}" != "1" ]]; then
  SIGNING_IDENTITY="${PRESENCEFM_SIGNING_IDENTITY:-}"
  if [[ -z "$SIGNING_IDENTITY" ]]; then
    SIGNING_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' | head -n 1)"
  fi
  if [[ -n "$SIGNING_IDENTITY" ]]; then
    codesign --force --options runtime --timestamp=none \
      --entitlements "$ROOT/Distribution.entitlements" \
      --sign "$SIGNING_IDENTITY" "$APP"
    codesign --verify --deep --strict --verbose=2 "$APP"
    echo "Signed with $SIGNING_IDENTITY"
  else
    codesign --force --sign - --entitlements "$ROOT/Distribution.entitlements" "$APP"
    codesign --verify --deep --strict --verbose=2 "$APP"
    echo "Ad-hoc signed (no paid Apple Developer account required)"
  fi
fi

echo "Created $APP"
