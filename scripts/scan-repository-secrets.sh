#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"

tracked="$(git ls-files)"
for forbidden in 'Config/Local.xcconfig' '*.mobileprovision' '*.provisionprofile' '*.p12' '*.pfx' '*.key' '*.pem'; do
  pattern="^$(print -r -- "$forbidden" | sed -e 's/[.]/\\&/g' -e 's/\*/.*/g')$"
  if print -r -- "$tracked" | grep -E "$pattern" >/dev/null; then
    echo "Tracked private configuration matched $forbidden" >&2
    exit 1
  fi
done

if git grep -nE -- '-----BEGIN ([A-Z0-9 ]+ )?PRIVATE KEY-----' >/dev/null; then
  echo "Private key material is tracked in the repository" >&2
  exit 1
fi

if git grep -nEI '(lastFMSessionKey|LASTFM_SHARED_SECRET)[[:space:]]*=[[:space:]]*[A-Fa-f0-9]{16,}' -- ':!Tests/**' ':!Config/Local.xcconfig.example' >/dev/null; then
  echo "Possible Last.fm credential committed to the repository" >&2
  exit 1
fi

if git grep -nE 'iCloud\.(com|net|org)\.[A-Za-z0-9.-]+' -- ':!Config/Local.xcconfig.example' ':!Documentation/**' >/dev/null; then
  echo "Possible personal iCloud container committed to the repository" >&2
  exit 1
fi

echo "Repository credential scan passed"
