#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"

required=(
  "README.md"
  "LICENSE"
  "Documentation/OPENAI-BUILD-WEEK.md"
  "Documentation/BUILD-WEEK-DEMO-SCRIPT.md"
  "Documentation/BUILD-WEEK-FINAL-SUBMISSION.md"
  "Sources/PresenceFM/DemoPlayback.swift"
)

for required_path in "${required[@]}"; do
  [[ -s "$required_path" ]] || { echo "Build Week verification failed: $required_path is missing or empty" >&2; exit 1; }
done

swift test -c release
./scripts/package-app.sh
./scripts/verify-package.sh
./scripts/verify-website.sh
git diff --check

echo "Build Week verification passed. Launch with: open PresenceFM.app --args --demo"
