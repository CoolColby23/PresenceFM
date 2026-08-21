#!/bin/zsh
set -euo pipefail

if [[ "${PRESENCEFM_REQUIRE_LOCAL_CONFIG:-YES}" != "YES" ]]; then
  exit 0
fi

missing=()
for name in DEVELOPMENT_TEAM PRESENCEFM_IOS_BUNDLE_ID; do
  value="${(P)name:-}"
  if [[ -z "$value" || "$value" == YOUR_* ]]; then missing+=("$name"); fi
done

if (( ${#missing[@]} )); then
  echo "error: PresenceFM local configuration is incomplete: ${missing[*]}" >&2
  echo "error: Copy Config/Local.xcconfig.example to Config/Local.xcconfig and fill in personal values." >&2
  exit 1
fi
