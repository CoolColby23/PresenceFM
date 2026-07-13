#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
CANONICAL="$ROOT/brand"
APP_BRAND="$ROOT/Sources/PresenceFM/Resources/Brand"
WEB_BRAND="$ROOT/website/assets/brand"
BRAND_FILES=(
  PresenceFM.icns
  app-icon.svg
  presencefm-logo-dark.svg
  presencefm-logo-light.svg
  presencefm-symbol-mono.svg
  presencefm-symbol.svg
)

mkdir -p "$APP_BRAND" "$WEB_BRAND" "$APP_BRAND/AppIcon.iconset" "$APP_BRAND/Exports"
cp "$CANONICAL/BRAND-GUIDE.md" "$APP_BRAND/BRAND-GUIDE.md"

for file in $BRAND_FILES; do
  cp "$CANONICAL/$file" "$APP_BRAND/$file"
  cp "$CANONICAL/$file" "$WEB_BRAND/$file"
done

TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT
iconutil -c iconset "$CANONICAL/PresenceFM.icns" -o "$TEMP_DIR/PresenceFM.iconset"
MASTER_ICON="$TEMP_DIR/PresenceFM.iconset/icon_512x512@2x.png"

for spec in \
  icon_16x16.png:16 \
  icon_16x16@2x.png:32 \
  icon_32x32.png:32 \
  icon_32x32@2x.png:64 \
  icon_128x128.png:128 \
  icon_128x128@2x.png:256 \
  icon_256x256.png:256 \
  icon_256x256@2x.png:512 \
  icon_512x512.png:512 \
  icon_512x512@2x.png:1024
do
  name="${spec%%:*}"
  size="${spec##*:}"
  sips --resampleHeightWidth "$size" "$size" "$MASTER_ICON" --out "$APP_BRAND/AppIcon.iconset/$name" >/dev/null
done

cp "$MASTER_ICON" "$APP_BRAND/Exports/app-icon-1024.png"
for name in presencefm-logo-dark presencefm-logo-light presencefm-symbol-mono presencefm-symbol; do
  sips -s format png "$CANONICAL/$name.svg" --out "$TEMP_DIR/$name.png" >/dev/null
  if [[ "$name" == presencefm-logo-* ]]; then
    sips --resampleWidth 1024 "$TEMP_DIR/$name.png" --out "$APP_BRAND/Exports/$name.png" >/dev/null
  else
    sips --resampleHeightWidth 1024 1024 "$TEMP_DIR/$name.png" --out "$APP_BRAND/Exports/$name.png" >/dev/null
  fi
done

echo "Synced app and website assets from brand/."
