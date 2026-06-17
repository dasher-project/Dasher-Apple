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
| `DasherEngine/`    | Resource bundle (DasherCore data files)                       |
| `DasherCore/`      | **Submodule** — the C++ engine (do not edit here; PR upstream) |
| `docs/`            | Design documents (input system, access settings)              |

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
