# Contributing to Dasher-Apple

Thank you for your interest in improving Dasher for Apple platforms! This guide
covers the specifics of this repository. For project-wide conventions (code of
conduct, security, RFCs), see the
[organisation CONTRIBUTING](https://github.com/dasher-project/.github/blob/main/CONTRIBUTING.md).

## Quick start

```bash
git clone --recurse-submodules https://github.com/dasher-project/Dasher-Apple.git
cd Dasher-Apple
brew install xcodegen swiftlint
xcodegen generate
open Dasher.xcodeproj
```

## What lives where

| Directory          | Purpose                                                        |
| :----------------- | :------------------------------------------------------------ |
| `DasherApp/`       | iOS app (SwiftUI)                                             |
| `DasherKeyboard/`  | iOS custom keyboard extension (memory-constrained, standalone) |
| `DasherMac/`       | macOS app (SwiftUI + AppKit)                                  |
| `DasherVision/`    | visionOS app (SwiftUI + RealityKit)                           |
| `DasherShared/`    | Shared Swift library — access config, input methods, UI       |
| `DasherSpeech/`    | Shared TTS wrapper (swift-tts-wrapper)                        |
| `DasherEngine/`    | Resource bundle (DasherCore data files)                          |
| `DasherCore/`      | **Submodule** — the C++ engine (do not edit here; PR upstream) |
| `Scripts/`         | Build/release helpers (CAPI gate, version stamping)            |

## Code style

- **SwiftLint** (`.swiftlint.yml`) runs as a build phase — fix all warnings
  before submitting a PR.
- 2-space indentation for Swift; no trailing whitespace.
- Use `// MARK: -` to organise sections within large files.
- Platform-specific code uses `#if os(iOS)` / `#elseif os(macOS)` /
  `#elseif os(visionOS)`.

## DasherCore changes

DasherCore is a git submodule pointing to
[dasher-project/DasherCore](https://github.com/dasher-project/DasherCore).
**Do not modify it inside this repo.** If you need an engine change, open a PR
against DasherCore directly, then bump the submodule pin here once merged.

### Submodule pinning policy

DasherCore is pinned to **release tags** (e.g. `v0.1.5`), not arbitrary `main`
commits. This ensures Xcode Cloud and other CI systems can always resolve the
submodule. To update:

```bash
cd DasherCore
git fetch --tags
git checkout v0.1.X          # latest release tag
cd ..
git add DasherCore
git commit -s -m "Bump DasherCore to v0.1.X"
```

Never commit a DasherCore pointer to a local-only commit — CI will fail with
"Failed to find commit in submodule."

### Engine CAPI gate (RFC 0023 item 3)

The build **fails** if the pinned DasherCore's `DASHER_CAPI_VERSION`
(`DasherCore/src/dasher.h`) is below the minimum this frontend requires,
declared once as `REQUIRED_DASHER_CAPI_VERSION` in `project.yml`
(`settings.base`). The check runs in CI (`Scripts/check-capi.sh`) and as an
Xcode build phase on every target that links the engine — same contract as
Dasher-Windows' `check-capi.ps1`. If the gate fires, bump the submodule via
the `shared-deps-bump` PR (or manually, per above). The RFC's belt-and-braces
runtime assert at engine-create lives engine-side in DasherCore, not here.

## Releases & versioning (RFC 0023 §1)

- **Version source of truth is git tags**, via
  `Scripts/version-from-tag.sh` (`git describe --tags --match 'v*'`,
  validated against the scheme above — legacy `0.x`/`-mac-beta` tags are
  ignored with a loud warning, never silently stamped). The
  `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` values in `project.yml` are
  the local-dev fallback — the release automation (macOS release workflow,
  Xcode Cloud `ci_post_clone`) derives them from the tag and never edits them
  by hand.
- **Tag format**: `vMAJOR.MINOR.PATCH` (e.g. `v6.0.1`, per-platform PATCH).
  Prereleases are `vMAJOR.MINOR.PATCH-rc.N` (e.g. `v6.0.0-rc.1`).
  **The `-mac-beta` suffix is retired** — the release workflow rejects such
  tags. `CURRENT_PROJECT_VERSION` is the commit count, so it only ever rises.
- **Cutting a macOS release**: tag the commit and push —

  ```bash
  git tag v6.0.0-rc.1 && git push origin v6.0.0-rc.1
  ```

  Pushing any `v*` tag triggers the GitHub release workflow: archive, sign,
  notarize, DMG, GitHub Release. Verify the stamped version in the built
  app's About window if unsure.
- **iOS/visionOS/keyboard/watch** ride Xcode Cloud (TestFlight); versions are
  stamped from tags in `ci_scripts/ci_post_clone.sh`.

## Definition of Done

- [ ] SwiftLint passes (zero warnings)
- [ ] Builds on all relevant target platforms
- [ ] Commits are signed off (DCO) — `git commit -s`
- [ ] If you changed a user-visible capability, update the
      [feature status matrix](https://dasher.at/status/) (`website` repo:
      `src/data/feature-status.json`) — the PR template has a checkbox for this
- [ ] If you changed UX/hardware interaction across platforms, check whether an
      [RFC](https://github.com/dasher-project/governance/tree/main/rfcs) is needed

## Pull request process

1. Fork and branch from `main`.
2. Run `xcodegen generate` if you added/removed files (the `.xcodeproj` is
   not committed).
3. Open a PR — the org-level PR template will prompt you on parity, RFCs, and
   the feature matrix.
