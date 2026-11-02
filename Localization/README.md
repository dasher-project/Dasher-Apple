# Dasher-Apple chrome localisation (RFC 0003)

This directory holds the strings that need translation and the tooling to turn
translations back into an Xcode String Catalog. The goal is described in
[RFC 0003](https://github.com/dasher-project/governance/blob/main/rfcs/0003-multilingual-ui.md).

The engine layer (parameter labels) is already localised through DasherCore's
`dasher_set_locale` + 33 locale files. This work covers the **frontend chrome** —
the SwiftUI toolbar, settings tabs, buttons, onboarding, and dialog text.

## What's here

| File | Purpose |
| --- | --- |
| `gen-from-shared.py` | **Primary generator & CI gate.** Extracts SwiftUI strings across all 6 source directories (`DasherApp`, `DasherMac`, `DasherVision`, `DasherKeyboard`, `DasherShared`, `DasherSpeech`), maps static and format keys against `SharedResources/ui-strings.json`, and emits `Localizable.xcstrings`. Supports `--check` for CI. |
| `chrome-strings.jsonl` | Extracted static UI strings (one JSON record per line). |
| `chrome-strings-formatted.jsonl` | Extracted `\(...)` interpolated strings with their derived Xcode format keys (`%@` / `%lld`) and `"translatable"` flag. |
| `Localizable.xcstrings` | The Xcode String Catalog (English source). Wired into every app target. |
| `extract-chrome.py` | Extracts `chrome-strings.jsonl` and `chrome-strings-formatted.jsonl` from the Swift sources. |
| `build-xcstrings.py` | Rebuilds the English scaffold `Localizable.xcstrings` from the JSONL files. |
| `merge-translations.py` | Merges a standalone locale JSON map into `Localizable.xcstrings`. |
| `generate-from-catalogue.py` | Backwards-compatible wrapper around `gen-from-shared.py`. |

## Shared UI string catalogue (RFC 0003)

The `SharedResources/` submodule points at
[dasher-shared-resources](https://github.com/dasher-project/dasher-shared-resources),
which holds the canonical cross-frontend `ui-strings.json` (332 English source
strings × 32 locales). Our catalog keys are the English source strings, so
`gen-from-shared.py` maps catalogue entries onto our keys directly:

```sh
git submodule update --init --remote SharedResources   # pull latest catalogue
python3 Localization/gen-from-shared.py                # extract + sync Localizable.xcstrings
python3 Localization/gen-from-shared.py --check        # CI gate: verify zero drift
```
