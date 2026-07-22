#!/bin/bash
set -euo pipefail

if [[ -n "${GITHUB_BASE_REF:-}" ]]; then
    git fetch --no-tags --depth=1 origin "${GITHUB_BASE_REF}"
    files="$(git diff --diff-filter=A --name-only "origin/${GITHUB_BASE_REF}"...HEAD -- '*.swift')"
else
    files="$(git diff-tree --root --no-commit-id --diff-filter=A --name-only -r HEAD -- '*.swift')"
fi

if [[ -z "$files" ]]; then
    echo "No newly added Swift files require format verification."
    exit 0
fi

while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    xcrun swift-format lint --strict --configuration .swift-format "$file"
done <<< "$files"
