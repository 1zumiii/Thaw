#!/usr/bin/env bash
# Build the custom app and always replace ad-hoc signatures with the fixed key.
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
cd "$SCRIPT_DIR/.."
BUILD_DIR=${THAW_BUILD_DIR:-/tmp/thaw-custom-build}
export PATH="$HOME/.local/bin:$PATH"

# Fail before a long build if the persisted signing identity cannot be reused.
bash "$SCRIPT_DIR/setup-custom-signing.sh" > /dev/null
xcodebuild -project Thaw.xcodeproj -scheme Thaw -configuration Release \
    -destination 'platform=macOS' -derivedDataPath "$BUILD_DIR" \
    -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates \
    DISABLE_DIAMOND_PROBLEM_DIAGNOSTIC=YES CODE_SIGN_IDENTITY=- \
    CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=YES build
python3 "$SCRIPT_DIR/sign-custom-app.py" "$BUILD_DIR/Build/Products/Release/Thaw.app"
