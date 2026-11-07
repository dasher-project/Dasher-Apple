#!/bin/bash
# RFC 0023 §1: the version source of truth is git tags. Emits
# xcodebuild-override lines derived from the nearest reachable v* tag,
# validated against the aligned scheme, so release builds never depend on
# hand-set project constants. The values checked into project.yml are the
# local-dev fallback this script falls back to; they are maintained by the
# release automation, never by hand.
#
# A qualifying tag matches the aligned scheme vMAJOR.MINOR.PATCH(-rc.N)?
# with MAJOR >= 6. Legacy tags (0.x, -mac-beta suffixes) are ignored for
# derivation and warn loudly, so they can't leak old versions into builds.
#
# Usage: eval "$(Scripts/version-from-tag.sh)"
#   MARKETING_VERSION        tag minus leading 'v' and any -rc.N suffix
#                            (v6.0.0-rc.1 -> 6.0.0). CFBundleShortVersionString
#                            must be numeric, so the rc counter lives in the
#                            tag/release name, not here.
#   CURRENT_PROJECT_VERSION  commit count (monotonic, stable ordering).
#                            CFBundleVersion — also what App Store Connect
#                            requires to only ever increase per platform.
set -eu

cd "$(dirname "$0")/.."

TAG=$(git describe --tags --match 'v*' --abbrev=0 2>/dev/null || true)

# Checked-in fallback (project.yml settings.base) — see header comment.
FALLBACK=$(sed -n 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"\([0-9][0-9.]*\)".*$/\1/p' project.yml 2>/dev/null | head -n 1 || true)
[ -n "$FALLBACK" ] || FALLBACK=6.0.0

MARKETING_VERSION=
if [ -n "$TAG" ] && printf '%s' "$TAG" | grep -Eq '^v(6|[7-9]|[1-9][0-9]+)\.[0-9]+\.[0-9]+(-rc\.[0-9]+)?$'; then
  MARKETING_VERSION=${TAG#v}
  MARKETING_VERSION=${MARKETING_VERSION%%-*}
else
  if [ -n "$TAG" ]; then
    echo "WARN: nearest tag '$TAG' predates the RFC 0023 §1 scheme (0.x / -mac-beta); stamping checked-in fallback $FALLBACK instead" >&2
  else
    echo "WARN: no v* tag reachable; stamping checked-in fallback $FALLBACK" >&2
  fi
  MARKETING_VERSION=$FALLBACK
fi

CURRENT_PROJECT_VERSION=$(git rev-list --count HEAD 2>/dev/null || true)
if [ -z "$CURRENT_PROJECT_VERSION" ]; then
  CURRENT_PROJECT_VERSION=$(sed -n 's/^[[:space:]]*CURRENT_PROJECT_VERSION:[[:space:]]*"\([0-9][0-9]*\)".*$/\1/p' project.yml 2>/dev/null | head -n 1 || true)
fi
[ -n "$CURRENT_PROJECT_VERSION" ] || CURRENT_PROJECT_VERSION=1

echo "MARKETING_VERSION=$MARKETING_VERSION"
echo "CURRENT_PROJECT_VERSION=$CURRENT_PROJECT_VERSION"
