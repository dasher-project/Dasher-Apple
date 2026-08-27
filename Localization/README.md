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
| `chrome-strings.jsonl` | **Translate this.** 123 static UI strings, one JSON record per line. |
| `chrome-strings-formatted.jsonl` | 18 strings with `\(...)` interpolation. Translate case-by-case (keep the interpolation). |
| `Localizable.xcstrings` | The Xcode String Catalog (English source). Wired into every app target. |
| `extract-chrome.py` | Re-extracts the JSONL from the Swift sources. |
| `build-xcstrings.py` | Rebuilds the English scaffold `Localizable.xcstrings` from the JSONL. |
| `merge-translations.py` | Merges a locale's translations into `Localizable.xcstrings`. |
| `generate-from-catalogue.py` | Syncs translations from the shared UI string catalogue (see below). |

## Shared UI string catalogue (RFC 0003, 2026-08-27 amendment)

The `SharedResources/` submodule points at
[dasher-shared-resources](https://github.com/dasher-project/dasher-shared-resources),
which holds the canonical cross-frontend `ui-strings.json` (223 English source
strings × 33 locales). Our catalog keys are the English source strings, so the
generator maps catalogue entries onto our keys directly:

```sh
git submodule update --init --remote SharedResources   # pull latest catalogue
python3 Localization/generate-from-catalogue.py        # sync (--force to overwrite)
```

State as of first wiring: 123 of 123 static keys matched; Apple's catalog was
one of the catalogue's sources and already carries the translations, so the
first run is a no-op. Future runs pick up catalogue improvements (e.g.
hand-reviewed locales) and new strings other frontends contribute. The six
Xcode format-string keys (`"%@ ..."`) are Android-style positional formats in
the catalogue and stay manual (see Notes).

## How to translate

`chrome-strings.jsonl` is one record per line:

```json
{"key": "Speed", "source": "Speed", "context": "DasherApp/Sources/ContentView.swift:477"}
```

- `key` / `source` — the English string (also the SwiftUI `LocalizedStringKey`). Don't change it.
- `context` — where it appears, to help translators. Not used by the merge.

Produce a **flat JSON map** of `source → translation` for each locale, e.g.
`translations/de.json`:

```json
{
  "Speed": "Geschwindigkeit",
  "Alphabet": "Alphabet"
}
```

Then merge it into the catalog:

```sh
python3 Localization/merge-translations.py de translations/de.json
```

Repeat for each locale. `Localizable.xcstrings` already ships in every app
target, so the translations take effect on the next build (English still shows
English until a locale is filled in).

## When new UI strings are added

Re-extract and rebuild the scaffold, then re-merge your translations:

```sh
python3 Localization/extract-chrome.py     # refreshes the .jsonl files
python3 Localization/build-xcstrings.py     # rebuilds the catalog (keeps existing translations)
```

`build-xcstrings.py` preserves any translations already merged into
`Localizable.xcstrings` for keys that still exist.

## Notes

- The 18 `chrome-strings-formatted.jsonl` entries (e.g. `"\(count) wpm"`) need
  format-string-aware keys that Xcode derives; translate them manually and add
  by hand in Xcode's String Catalog editor, or handle in a follow-up.
- The engine locale picker is a separate concern (binding it to DasherCore's
  `locales.json`, RFC 0003) and is not covered by these chrome strings.
