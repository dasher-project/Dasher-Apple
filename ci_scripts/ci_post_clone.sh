#!/bin/sh
set -eu

echo "=== Dasher CI Post-Clone ==="

cd "$CI_PRIMARY_REPOSITORY_PATH"

echo "Initializing DasherCore submodule..."
git submodule update --init --recursive

echo "Stamping tag-derived versions into project.yml (RFC 0023 §1)..."
if ! git fetch --tags origin 2>/dev/null; then
    echo "WARNING: could not fetch tags — versions may fall back to the project.yml constants" >&2
fi
eval "$(Scripts/version-from-tag.sh)"
if [ -z "${MARKETING_VERSION:-}" ] || [ -z "${CURRENT_PROJECT_VERSION:-}" ]; then
    echo "ERROR: Scripts/version-from-tag.sh emitted no version — refusing to stamp empty values" >&2
    exit 1
fi
sed -i '' "s/MARKETING_VERSION: \".*\"/MARKETING_VERSION: \"$MARKETING_VERSION\"/g" project.yml
sed -i '' "s/CURRENT_PROJECT_VERSION: \".*\"/CURRENT_PROJECT_VERSION: \"$CURRENT_PROJECT_VERSION\"/g" project.yml
if ! grep -q "MARKETING_VERSION: \"$MARKETING_VERSION\"" project.yml; then
    echo "ERROR: MARKETING_VERSION stamp into project.yml did not apply" >&2
    exit 1
fi
if ! grep -q "CURRENT_PROJECT_VERSION: \"$CURRENT_PROJECT_VERSION\"" project.yml; then
    echo "ERROR: CURRENT_PROJECT_VERSION stamp into project.yml did not apply" >&2
    exit 1
fi
echo "Version: $MARKETING_VERSION ($CURRENT_PROJECT_VERSION)"

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
