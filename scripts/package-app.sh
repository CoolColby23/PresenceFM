#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"
"$ROOT/scripts/sync-brand-assets.sh"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

VERSION="${PRESENCEFM_VERSION:-$(<"$ROOT/VERSION")}"
BUILD_NUMBER="${PRESENCEFM_BUILD_NUMBER:-1}"
DISCORD_APPLICATION_ID="${PRESENCEFM_DISCORD_APPLICATION_ID:-1525555974390153346}"

APP="$ROOT/PresenceFM.app"
CONTENTS="$APP/Contents"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" "$CONTENTS/Frameworks"
cp "$BIN_DIR/PresenceFM" "$CONTENTS/MacOS/PresenceFM"
cp -R "$BIN_DIR/Sparkle.framework" "$CONTENTS/Frameworks/Sparkle.framework"
# SwiftPM may already embed this rpath; only add it when missing.
if ! otool -l "$CONTENTS/MacOS/PresenceFM" | grep -q '@executable_path/../Frameworks'; then
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$CONTENTS/MacOS/PresenceFM"
fi
cp "$ROOT/brand/PresenceFM.icns" "$CONTENTS/Resources/PresenceFM.icns"
RESOURCE_BUNDLE="$BIN_DIR/PresenceFM_PresenceFM.bundle"
[[ -n "$RESOURCE_BUNDLE" && -d "$RESOURCE_BUNDLE" ]] || {
  echo "SwiftPM resource bundle was not produced" >&2
  exit 1
}
cp -R "$RESOURCE_BUNDLE" "$CONTENTS/Resources/PresenceFM_PresenceFM.bundle"
"$ROOT/scripts/generate-app-intents-metadata.sh" "$CONTENTS/Resources"

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
plutil -insert SUFeedURL -string "https://github.com/CoolColby23/PresenceFM/releases/latest/download/appcast.xml" "$CONTENTS/Info.plist"
plutil -insert SUPublicEDKey -string "NAio4ba6lGI+Or7NZiCwfkF0NXkixmZjkAvesHK2zGY=" "$CONTENTS/Info.plist"
plutil -insert SUEnableAutomaticChecks -bool true "$CONTENTS/Info.plist"
plutil -insert SUAllowsAutomaticUpdates -bool true "$CONTENTS/Info.plist"

plutil -insert PRESENCEFM_DISCORD_APPLICATION_ID -string "$DISCORD_APPLICATION_ID" "$CONTENTS/Info.plist"

if [[ "${PRESENCEFM_SKIP_SIGNING:-0}" != "1" ]]; then
  SIGNING_IDENTITY="${PRESENCEFM_SIGNING_IDENTITY:-}"
  if [[ -z "$SIGNING_IDENTITY" ]]; then
    SIGNING_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' | head -n 1 || true)"
  fi

  ENTITLEMENTS_FILE="$(mktemp -t presencefm-entitlements).plist"
  cp "$ROOT/Distribution.entitlements" "$ENTITLEMENTS_FILE"
  trap 'rm -f "$ENTITLEMENTS_FILE"' EXIT

  # Explicit ad-hoc: "-" or empty. CI always uses ad-hoc.
  if [[ -z "$SIGNING_IDENTITY" || "$SIGNING_IDENTITY" == "-" ]]; then
    # Ad-hoc signatures cannot use an iCloud key-value-store entitlement.
    /usr/libexec/PlistBuddy -c "Delete :com.apple.developer.ubiquity-kvstore-identifier" "$ENTITLEMENTS_FILE" 2>/dev/null || true
    codesign --force --deep --sign - "$CONTENTS/Frameworks/Sparkle.framework"
    codesign --force --sign - --entitlements "$ENTITLEMENTS_FILE" "$APP"
    codesign --verify --deep --strict --verbose=2 "$APP"
    echo "Ad-hoc signed (no paid Apple Developer account required)"
  else
    TEAM_IDENTIFIER="$(security find-certificate -c "$SIGNING_IDENTITY" -p 2>/dev/null | openssl x509 -noout -subject -nameopt RFC2253 2>/dev/null | sed -n 's/.*OU=\([^,]*\).*/\1/p' | head -n 1 || true)"
    if [[ -n "$TEAM_IDENTIFIER" && "${PRESENCEFM_ENABLE_ICLOUD_SYNC:-0}" == "1" ]]; then
      /usr/libexec/PlistBuddy -c \
        "Set :com.apple.developer.ubiquity-kvstore-identifier $TEAM_IDENTIFIER.fm.presence.PresenceFM" \
        "$ENTITLEMENTS_FILE"
    else
      /usr/libexec/PlistBuddy -c "Delete :com.apple.developer.ubiquity-kvstore-identifier" "$ENTITLEMENTS_FILE" 2>/dev/null || true
    fi
    codesign --force --deep --options runtime --timestamp=none \
      --sign "$SIGNING_IDENTITY" "$CONTENTS/Frameworks/Sparkle.framework"
    codesign --force --options runtime --timestamp=none \
      --entitlements "$ENTITLEMENTS_FILE" \
      --sign "$SIGNING_IDENTITY" "$APP"
    codesign --verify --deep --strict --verbose=2 "$APP"
    echo "Signed with $SIGNING_IDENTITY"
  fi
  rm -f "$ENTITLEMENTS_FILE"
  trap - EXIT
fi

echo "Created $APP"
