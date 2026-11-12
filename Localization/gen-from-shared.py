#!/usr/bin/env python3
"""Generate Dasher-Apple `Localizable.xcstrings` from the shared UI catalogue.

RFC 0003 / Dasher-Apple#56:
1. Extracts all user-facing SwiftUI chrome strings across all 6 source directories
   (`DasherApp`, `DasherMac`, `DasherVision`, `DasherKeyboard`, `DasherShared`,
   `DasherSpeech`), refreshing `Localization/chrome-strings.jsonl` and
   `Localization/chrome-strings-formatted.jsonl`.
2. Maps extracted keys (static English strings and translatable Xcode format keys)
   against `SharedResources/ui-strings.json` (32 locales).
3. Emits a deterministic `Localization/Localizable.xcstrings` preserving any
   existing Apple-only translations for keys not yet in `ui-strings.json`.
4. Supports `--check` for CI and unit tests: verifies that `chrome-strings.jsonl`,
   `chrome-strings-formatted.jsonl`, and `Localizable.xcstrings` on disk match
   the generated output with zero drift.

Usage:
    python3 Localization/gen-from-shared.py           # regenerate files
    python3 Localization/gen-from-shared.py --check   # verify no drift (CI gate)
"""
import argparse
import importlib.util
import json
import sys
from pathlib import Path

sys.dont_write_bytecode = True

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
CATALOGUE = ROOT / "SharedResources" / "ui-strings.json"
XCSTRINGS = HERE / "Localizable.xcstrings"
STATIC_JSONL = HERE / "chrome-strings.jsonl"
INTERP_JSONL = HERE / "chrome-strings-formatted.jsonl"


def load_extractor():
    spec = importlib.util.spec_from_file_location("extract_chrome", HERE / "extract-chrome.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def build_shared_lookup(shared: dict) -> dict:
    """Map English source string -> {locale: translated_value}."""
    by_source = {}
    for _key, locales in shared.items():
        if not isinstance(locales, dict):
            continue
        en = locales.get("en")
        if not en:
            continue
        translations = {
            loc: val
            for loc, val in locales.items()
            if loc != "en" and isinstance(val, str) and val.strip()
        }
        if en not in by_source or len(translations) > len(by_source[en]):
            by_source[en] = translations

    # Convert named placeholders in shared formats to Xcode's format syntax.
    if "typing_rate_format" in shared and isinstance(shared["typing_rate_format"], dict):
        fmt_trans = {}
        for loc, val in shared["typing_rate_format"].items():
            if loc != "en" and isinstance(val, str) and "{cps}" in val and "{wpm}" in val:
                fmt_trans[loc] = val.replace("{cps}", "%1$@").replace("{wpm}", "%2$lld")
        if fmt_trans:
            by_source["%@ cps · %lld wpm"] = fmt_trans

    sending_to_app = by_source.get("Sending to {app}", {})
    if sending_to_app:
        by_source["Sending to %@"] = {
            locale: value.replace("{app}", "%@")
            for locale, value in sending_to_app.items()
            if value.count("{app}") == 1
        }

    return by_source


def generate_all(root: Path = ROOT, force: bool = True):
    extractor = load_extractor()
    static_records, interp_records = extractor.extract_all(root)

    static_jsonl_text = "".join(
        json.dumps(r, ensure_ascii=False) + "\n" for r in static_records
    )
    interp_jsonl_text = "".join(
        json.dumps(r, ensure_ascii=False) + "\n" for r in interp_records
    )

    catalogue = json.loads((root / "SharedResources" / "ui-strings.json").read_text(encoding="utf-8"))
    shared = catalogue["shared"]
    by_source = build_shared_lookup(shared)

    existing_strings = {}
    source_language = "en"
    xc_path = root / "Localization" / "Localizable.xcstrings"
    if xc_path.exists():
        prev = json.loads(xc_path.read_text(encoding="utf-8"))
        source_language = prev.get("sourceLanguage", "en")
        existing_strings = prev.get("strings", {})

    # Collect all active keys in deterministic order: static keys + translatable format keys
    active_keys = []
    seen = set()
    for r in static_records:
        k = r["key"]
        if k not in seen:
            seen.add(k)
            active_keys.append(k)
    for r in interp_records:
        if r.get("translatable"):
            k = r["key"]
            if k not in seen:
                seen.add(k)
                active_keys.append(k)
    active_keys.sort(key=lambda s: (s.lower(), s))

    out_strings = {}
    matched_count = 0
    translated_units = 0

    for key in active_keys:
        prev_entry = existing_strings.get(key, {})
        prev_locs = prev_entry.get("localizations", {})
        new_locs = {}

        shared_trans = by_source.get(key)
        if shared_trans is not None:
            matched_count += 1

        # Merge existing localizations + shared catalogue localizations
        all_locales = sorted(set(prev_locs.keys()) | set((shared_trans or {}).keys()))
        for loc in all_locales:
            existing_unit = prev_locs.get(loc, {}).get("stringUnit", {})
            shared_val = (shared_trans or {}).get(loc)
            if shared_val and (force or existing_unit.get("state") != "translated"):
                new_locs[loc] = {
                    "stringUnit": {
                        "state": "translated",
                        "value": shared_val,
                    }
                }
                translated_units += 1
            elif existing_unit:
                new_locs[loc] = {"stringUnit": existing_unit}
                if existing_unit.get("state") == "translated":
                    translated_units += 1

        out_strings[key] = {"localizations": new_locs}

    xc_obj = {
        "sourceLanguage": source_language,
        "strings": out_strings,
        "version": "1.0",
    }
    xc_text = json.dumps(xc_obj, ensure_ascii=False, indent=2, separators=(",", ": ")) + "\n"
    stats = {
        "static_count": len(static_records),
        "interp_count": len(interp_records),
        "translatable_interp_count": sum(1 for r in interp_records if r.get("translatable")),
        "total_xc_keys": len(out_strings),
        "matched_shared_keys": matched_count,
        "translated_units": translated_units,
    }
    return static_jsonl_text, interp_jsonl_text, xc_text, stats


def main() -> int:
    ap = argparse.ArgumentParser(description="Generate Localizable.xcstrings from SharedResources/ui-strings.json")
    ap.add_argument("--check", action="store_true", help="verify generated files match disk without writing")
    ap.add_argument("--no-force", action="store_true", help="do not overwrite existing translations with shared catalogue")
    args = ap.parse_args()

    static_text, interp_text, xc_text, stats = generate_all(ROOT, force=not args.no_force)

    if args.check:
        drifted = []
        for path, expected in [
            (STATIC_JSONL, static_text),
            (INTERP_JSONL, interp_text),
            (XCSTRINGS, xc_text),
        ]:
            if not path.exists() or path.read_text(encoding="utf-8") != expected:
                drifted.append(path.relative_to(ROOT).as_posix())
        if drifted:
            print(
                f"ERROR: localization files out of sync: {', '.join(drifted)}\n"
                "Run `python3 Localization/gen-from-shared.py` and commit the updated files.",
                file=sys.stderr,
            )
            return 1
        print(
            f"OK: Localization files in sync ({stats['total_xc_keys']} keys, "
            f"{stats['matched_shared_keys']} matched in shared catalogue, "
            f"{stats['translated_units']} translated string units)."
        )
        return 0

    STATIC_JSONL.write_text(static_text, encoding="utf-8")
    INTERP_JSONL.write_text(interp_text, encoding="utf-8")
    XCSTRINGS.write_text(xc_text, encoding="utf-8")
    print(
        f"wrote Localization/chrome-strings.jsonl ({stats['static_count']} static), "
        f"chrome-strings-formatted.jsonl ({stats['interp_count']} formatted, "
        f"{stats['translatable_interp_count']} translatable)"
    )
    print(
        f"wrote Localization/Localizable.xcstrings: {stats['total_xc_keys']} keys "
        f"({stats['matched_shared_keys']} matched in SharedResources/ui-strings.json, "
        f"{stats['translated_units']} translated units)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
