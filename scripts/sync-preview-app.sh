#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"

"$ROOT/scripts/package-app.sh"

TARGET_APP="/Applications/PresenceFM.app"
if pgrep -x PresenceFM >/dev/null; then
  pkill -x PresenceFM
  for _ in {1..30}; do
    pgrep -x PresenceFM >/dev/null || break
    sleep 0.1
  done
fi
rm -rf "$TARGET_APP"
cp -R "$ROOT/PresenceFM.app" "$TARGET_APP"

echo "Installed $TARGET_APP from $ROOT/PresenceFM.app"
