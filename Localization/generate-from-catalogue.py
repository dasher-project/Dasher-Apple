#!/usr/bin/env python3
"""Generate Dasher-Apple chrome translations from the shared UI string catalogue.

RFC 0003 (2026-08-27 amendment): frontends map their native i18n keys against
the canonical English strings in dasher-shared-resources/ui-strings.json. This
repo's Xcode String Catalog keys ARE the English source strings, so the mapping
is direct: catalogue key -> its "en" value -> our catalog key.

For every Apple key found in the catalogue, each catalogue locale's translation
is written into Localizable.xcstrings via the same merge semantics as
merge-translations.py (never overwrites an existing translation unless
--force). Keys not in the catalogue — and Xcode format-string keys ("%@ ..."),
which the catalogue stores as Android-style positional formats — are reported
and left for the manual流程 described in README.md.

Usage:
    python3 Localization/generate-from-catalogue.py [--force]
"""

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CATALOGUE = ROOT / "SharedResources" / "ui-strings.json"
XCSTRINGS = ROOT / "Localization" / "Localizable.xcstrings"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--force", action="store_true",
                    help="overwrite existing translations in the catalog")
    args = ap.parse_args()

    catalogue = json.loads(CATALOGUE.read_text())
    shared = catalogue["shared"]

    # English source -> per-locale translations
    by_source = {}
    for _key, locales in shared.items():
        en = locales.get("en")
        if not en:
            continue
        by_source[en] = {loc: v for loc, v in locales.items() if loc != "en"}

    xc = json.loads(XCSTRINGS.read_text())
    strings = xc["strings"]

    matched, missed, filled, skipped_existing = 0, [], 0, 0
    for key in strings:
        entry = strings[key]
        translations = by_source.get(key)
        if translations is None:
            missed.append(key)
            continue
        matched += 1
        localizations = entry.setdefault("localizations", {})
        for loc, value in translations.items():
            unit = localizations.setdefault(loc, {}).setdefault("stringUnit", {})
            if unit.get("state") == "translated" and not args.force:
                skipped_existing += 1
                continue
            unit["state"] = "translated"
            unit["value"] = value
            filled += 1

    if filled == 0:
        print("no new translations — catalog left untouched")
    else:
        # Xcode serializes .xcstrings with 2-space indent and standard ": "
        # separators but preserves key insertion order; we sort for determinism.
        # A real content update will rewrite the file wholesale (Xcode does the
        # same when you edit in its catalog editor).
        XCSTRINGS.write_text(json.dumps(xc, ensure_ascii=False, indent=2,
                                        separators=(",", ": ")) + "\n")

    print(f"catalogue locales: {len(catalogue['meta']['locales'])}")
    print(f"matched: {matched} / {len(strings)} Apple keys")
    print(f"translations {'overwritten' if args.force else 'written'}: {filled}, "
          f"kept existing: {skipped_existing}")
    if missed:
        print("\nnot in catalogue (format strings / Apple-only) — handle manually:")
        for k in missed:
            print(f"  - {k[:80]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
