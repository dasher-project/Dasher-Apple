#!/usr/bin/env python3
"""Merge translated strings into Localizable.xcstrings.

Usage:
    python3 Localization/merge-translations.py <locale> <translations.json>

<translations.json> is a flat map of English source -> translated string, e.g.:
    {
      "Speed": "Geschwindigkeit",
      "Alphabet": "Alphabet",
      "Accept hover/pointer events as Dasher input. ...": "..."
    }

Keys that aren't in the catalog are reported and skipped. Existing translations
for the same locale are overwritten. The catalog's English source keys and its
sourceLanguage are never modified.
"""
import json, os, sys

CATALOG = "Localization/Localizable.xcstrings"


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(2)
    locale, trans_path = sys.argv[1], sys.argv[2]
    with open(CATALOG, encoding="utf-8") as f:
        catalog = json.load(f)
    with open(trans_path, encoding="utf-8") as f:
        translations = json.load(f)

    strings = catalog["strings"]
    added = 0
    missing = [k for k in translations if k not in strings]
    for src, value in translations.items():
        if src not in strings:
            continue
        strings[src].setdefault("localizations", {})[locale] = {
            "stringUnit": {"state": "translated", "value": value}
        }
        added += 1

    with open(CATALOG, "w", encoding="utf-8") as f:
        json.dump(catalog, f, indent=2, ensure_ascii=False)
        f.write("\n")

    print(f"merged {added} translations for '{locale}' into {CATALOG}")
    if missing:
        print(f"  WARNING: {len(missing)} translation key(s) not in catalog (skipped):")
        for k in missing[:10]:
            print(f"    - {k[:70]}")
        if len(missing) > 10:
            print(f"    ... and {len(missing) - 10} more")


if __name__ == "__main__":
    main()
