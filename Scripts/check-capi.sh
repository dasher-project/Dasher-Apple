#!/bin/bash
# RFC 0023 item 3: CAPI compatibility gate.
# Fails the build when the pinned DasherCore's dasher.h exposes a
# DASHER_CAPI_VERSION below this frontend's declared minimum.
# (Apple twin of Dasher-Windows' Scripts/check-capi.ps1 + Directory.Build.props:
# "can I bump the engine?" becomes a build check, not archaeology.)
#
# Usage: check-capi.sh [header-path] [required-version]
#   header-path      Defaults to $SRCROOT/DasherCore/src/dasher.h when run as an
#                    Xcode build phase, else <repo-root>/DasherCore/src/dasher.h.
#   required-version Defaults to $REQUIRED_DASHER_CAPI_VERSION (declared in
#                    project.yml settings.base, propagated into build-phase
#                    script env), then re-read from project.yml, then 3.
set -eu

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HEADER="${1:-${SRCROOT:-$REPO_ROOT}/DasherCore/src/dasher.h}"
REQUIRED="${2:-${REQUIRED_DASHER_CAPI_VERSION:-}}"

if [ -z "$REQUIRED" ]; then
  REQUIRED=$(sed -n 's/^[[:space:]]*REQUIRED_DASHER_CAPI_VERSION:[[:space:]]*"\{0,1\}\([0-9][0-9]*\)"\{0,1\}[[:space:]]*$/\1/p' "$REPO_ROOT/project.yml" 2>/dev/null | head -n 1 || true)
fi
[ -n "$REQUIRED" ] || REQUIRED=3

if [ ! -f "$HEADER" ]; then
  echo "CAPI gate: header not found: $HEADER" >&2
  exit 1
fi

# Match '#define DASHER_CAPI_VERSION <n>' (same regex as the Windows ps1).
PINNED=$(sed -n 's/^[[:space:]]*#define[[:space:]][[:space:]]*DASHER_CAPI_VERSION[[:space:]][[:space:]]*\([0-9][0-9]*\).*/\1/p' "$HEADER" | head -n 1 || true)

if [ -z "$PINNED" ]; then
  echo "CAPI gate: DASHER_CAPI_VERSION not found in $HEADER" >&2
  exit 1
fi

if [ "$PINNED" -lt "$REQUIRED" ]; then
  echo "CAPI gate: pinned DasherCore exposes CAPI version $PINNED, this frontend requires >= $REQUIRED. Bump the DasherCore submodule (see .github/workflows/shared-deps-bump.yml)." >&2
  exit 1
fi

echo "CAPI gate: pinned DasherCore CAPI version $PINNED (required >= $REQUIRED) - OK"
