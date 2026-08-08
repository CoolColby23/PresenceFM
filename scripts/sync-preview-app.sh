#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"

"$ROOT/scripts/package-app.sh"

TARGET_APP="/Applications/PresenceFM.app"
rm -rf "$TARGET_APP"
cp -R "$ROOT/PresenceFM.app" "$TARGET_APP"

echo "Installed $TARGET_APP from $ROOT/PresenceFM.app"
