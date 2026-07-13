#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
VERSION="${1:-${PRESENCEFM_VERSION:-0.3.0}}"
APP="$ROOT/PresenceFM.app"
DMG="$ROOT/PresenceFM-${VERSION}.dmg"
WORK="$(mktemp -d)"
STAGING="$WORK/contents"
RW_DMG="$WORK/PresenceFM-rw.dmg"
mkdir -p "$STAGING"
trap 'rm -rf "$WORK"' EXIT

[[ -d "$APP" ]] || { echo "PresenceFM.app is missing; run scripts/package-app.sh first." >&2; exit 1; }

cp -R "$APP" "$STAGING/PresenceFM.app"
ln -s /Applications "$STAGING/Applications"
mkdir -p "$STAGING/.background"
cp "$ROOT/Sources/PresenceFM/Resources/Brand/dmg-background.png" "$STAGING/.background/background.png"

rm -f "$DMG"
hdiutil create -quiet -volname "PresenceFM" -srcfolder "$STAGING" -ov -format UDRW "$RW_DMG"
MOUNT_POINT="$(hdiutil attach -readwrite -noverify -noautoopen "$RW_DMG" | awk '/\/Volumes\// { sub(/^.*\/Volumes\//, "/Volumes/"); print; exit }')"
[[ -n "$MOUNT_POINT" ]] || { echo "Could not mount installer image." >&2; exit 1; }

osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "PresenceFM"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {120, 120, 780, 540}
    set theViewOptions to icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 96
    set background picture of theViewOptions to file ".background:background.png"
    set position of item "PresenceFM.app" of container window to {185, 220}
    set position of item "Applications" of container window to {475, 220}
    close
    open
    update without registering applications
    delay 1
  end tell
end tell
APPLESCRIPT

sync
hdiutil detach -quiet "$MOUNT_POINT"
hdiutil convert -quiet "$RW_DMG" -format UDZO -o "$DMG"
echo "Created $DMG"
