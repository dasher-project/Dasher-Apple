# Dasher for Apple Platforms

Dasher is a zooming predictive text-entry system designed for accessibility and
augmentative communication. This repository contains the **native Apple
frontends** — iOS, macOS, and visionOS — built on the shared
[DasherCore](https://github.com/dasher-project/DasherCore) engine.

## Targets

| Target          | Platform | Description                                    |
| :-------------- | :------- | :--------------------------------------------- |
| **DasherApp**   | iOS 17+  | Flagship iPhone/iPad app                       |
| **DasherKeyboard** | iOS 17+ | System-wide custom keyboard extension       |
| **DasherMac**   | macOS 14+ | Mac app with direct-mode (accessibility API) |
| **DasherVision** | visionOS 1.0+ | Apple Vision Pro app with hand-tracking |

Shared code lives in `DasherShared/` (access/input configuration, shared UI)
and `DasherSpeech/` (TTS via [swift-tts-wrapper](https://github.com/aactools/swift-tts-wrapper)),
managed as local Swift Package Manager targets.

## Architecture

Each frontend calls DasherCore exclusively through its flat C API
([`dasher.h`](https://github.com/dasher-project/DasherCore/blob/main/src/dasher.h))
via per-target bridging headers. The frontend owns input capture, canvas
rendering (Metal/CoreGraphics), and platform UI (SwiftUI).

See the [architecture overview](https://dasher.at/developers/architecture/) for
the full engine-frontend contract.

## Requirements

- **Xcode 16+**
- **XcodeGen** — `brew install xcodegen`
- Swift 5.9+

## Build

```bash
git clone --recurse-submodules https://github.com/dasher-project/Dasher-Apple.git
cd Dasher-Apple
xcodegen generate          # produces Dasher.xcodeproj
open Dasher.xcodeproj
```

Select a scheme (`DasherApp`, `DasherKeyboard`, `DasherMac`, or
`DasherVision`) and build.

> The `.xcodeproj` is **not committed** — it is regenerated from `project.yml`
> by XcodeGen on every clone. Xcode Cloud runs this automatically via
> `ci_scripts/ci_post_clone.sh`.

## Code style

[SwiftLint](https://github.com/realm/SwiftLint) is configured in
`.swiftlint.yml` and runs as a build phase. Install it with
`brew install swiftlint`.

## Documentation

- [Developer handbook](https://dasher.at/developers/) — architecture, build
  guides, contributing, RFCs
- [Feature status matrix](https://dasher.at/status/) — what's supported where
- [Input system design](docs/INPUT_SYSTEM.md) — input device + filter model
- [Access settings redesign](docs/ACCESS_SETTINGS_REDESIGN.md) — access/selection method architecture

## License

DasherCore is MIT-licensed (Copyright Ace Centre). This frontend inherits the
same license terms. See the
[DasherCore LICENSE](https://github.com/dasher-project/DasherCore/blob/main/LICENSE).
