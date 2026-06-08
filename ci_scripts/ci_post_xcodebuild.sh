#!/bin/sh
set -e

echo "=== Dasher CI Post-Xcodebuild ==="
echo "Scheme: $CI_XCODE_SCHEME"
echo "Platform: $CI_PLATFORM"

if [ "$CI_XCODEBUILD_RESULT" = "success" ]; then
    echo "Build succeeded — artifacts should be in $CI_DERIVED_DATA_PATH"
else
    echo "Build failed — skipping post-build steps"
    exit 0
fi
