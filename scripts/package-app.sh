#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"
swift build -c release

VERSION="${PRESENCEFM_VERSION:-0.3.0}"
BUILD_NUMBER="${PRESENCEFM_BUILD_NUMBER:-3}"
DISCORD_APPLICATION_ID="${PRESENCEFM_DISCORD_APPLICATION_ID:-1525555974390153346}"

APP="$ROOT/PresenceFM.app"
CONTENTS="$APP/Contents"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$ROOT/.build/release/PresenceFM" "$CONTENTS/MacOS/PresenceFM"
cp "$ROOT/Sources/PresenceFM/Resources/Brand/PresenceFM.icns" "$CONTENTS/Resources/PresenceFM.icns"

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

echo "Created $APP"
