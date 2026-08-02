#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
OUTPUT_DIRECTORY="${1:?usage: generate-app-intents-metadata.sh OUTPUT_DIRECTORY}"
DEVELOPER_DIR="$(xcode-select -p)"
TOOLCHAIN_DIR="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain"
SDK_ROOT="$(xcrun --sdk macosx --show-sdk-path)"
XCODE_BUILD="$(xcodebuild -version | sed -n '2s/Build version //p')"
ARCH="$(uname -m)"
SOURCE_LIST="$(mktemp /tmp/presencefm-intent-sources.XXXXXX)"
CONST_LIST="$(mktemp /tmp/presencefm-intent-constants.XXXXXX)"
trap 'rm -f "$SOURCE_LIST" "$CONST_LIST"' EXIT

find "$ROOT/Sources/PresenceFM" -name '*.swift' -type f -print | sort > "$SOURCE_LIST"
find "$ROOT/.build/out/Intermediates.noindex/PresenceFM.build/Release/PresenceFM-p.build/Objects-normal/$ARCH" \
    -name '*.swiftconstvalues' -type f -print | sort > "$CONST_LIST"

[[ -s "$CONST_LIST" ]] || {
    echo "Release App Intents constant metadata was not produced" >&2
    exit 1
}

rm -rf "$OUTPUT_DIRECTORY/Metadata.appintents"
xcrun appintentsmetadataprocessor \
    --output "$OUTPUT_DIRECTORY" \
    --toolchain-dir "$TOOLCHAIN_DIR" \
    --module-name PresenceFM \
    --sdk-root "$SDK_ROOT" \
    --xcode-version "$XCODE_BUILD" \
    --platform-family macOS \
    --deployment-target 15.0 \
    --target-triple "$ARCH-apple-macos15.0" \
    --source-file-list "$SOURCE_LIST" \
    --swift-const-vals-list "$CONST_LIST" \
    --deployment-aware-processing \
    --app-shortcuts-app-name-override \
    --force

[[ -d "$OUTPUT_DIRECTORY/Metadata.appintents" ]] || {
    echo "App Intents metadata bundle was not produced" >&2
    exit 1
}
