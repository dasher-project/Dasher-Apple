#!/bin/sh
set -e

echo "=== Dasher CI Post-Clone ==="

cd "$CI_PRIMARY_REPOSITORY_PATH"

echo "Initializing DasherCore submodule..."
git submodule update --init --recursive

echo "Copying locale strings..."
mkdir -p DasherEngine/Resources/Data/Strings
cp -f DasherCore/Strings/*.json DasherEngine/Resources/Data/Strings/ 2>/dev/null || true

echo "Installing xcodegen..."
if ! command -v xcodegen >/dev/null 2>&1; then
    brew install xcodegen 2>/dev/null || {
        XCGEN_VER="2.45.4"
        curl -sL "https://github.com/yonaskolb/XcodeGen/releases/download/${XCGEN_VER}/xcodegen.zip" -o /tmp/xcodegen.zip
        unzip -o /tmp/xcodegen.zip -d /tmp/xcodegen
        chmod +x /tmp/xcodegen/xcodegen
        export PATH="/tmp/xcodegen:$PATH"
    }
fi

echo "Regenerating project from project.yml..."
xcodegen generate

echo "Restoring Package.resolved..."
mkdir -p Dasher.xcodeproj/project.xcworkspace/xcshareddata/swiftpm
cp -f Package.resolved Dasher.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved

echo "=== CI Post-Clone Complete ==="
