#!/bin/bash
set -euo pipefail

source_dir=$(cd "$(dirname "$0")" && pwd)
output_dir=${1:-"$source_dir/../../build/input-method-probe"}
app="$output_dir/Dasher IME Probe.app"

mkdir -p "$app/Contents/MacOS"
plutil -lint "$source_dir/Info.plist"
cp "$source_dir/Info.plist" "$app/Contents/Info.plist"
xcrun clang -fobjc-arc -Wall -Wextra -Werror -mmacosx-version-min=14.0 \
    -framework AppKit -framework Carbon -framework CoreGraphics -framework InputMethodKit \
    "$source_dir/main.m" "$source_dir/ProbeText.m" -o "$app/Contents/MacOS/DasherInputMethodProbe"
codesign --force --sign - "$app"
codesign --verify --strict "$app"
xcrun clang -fobjc-arc -Wall -Wextra -Werror -mmacosx-version-min=14.0 \
    -framework Foundation "$source_dir/ProbeText.m" "$source_dir/ProbeTextTests.m" \
    -o "$output_dir/probe-text-tests"
"$output_dir/probe-text-tests"
printf 'Built %s\n' "$app"
