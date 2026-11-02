#!/usr/bin/env python3
"""(Re)build Localizable.xcstrings from chrome-strings.jsonl + chrome-strings-formatted.jsonl,
PRESERVING any translations already merged into the catalog.

Prefer running `python3 Localization/gen-from-shared.py` which runs extraction,
rebuilds `Localizable.xcstrings`, and merges all translations from
`SharedResources/ui-strings.json` in one deterministic step.
"""
import json
import os

SRC_STATIC = "Localization/chrome-strings.jsonl"
SRC_INTERP = "Localization/chrome-strings-formatted.jsonl"
OUT = "Localization/Localizable.xcstrings"

fresh_keys = []
seen = set()
for src in (SRC_STATIC, SRC_INTERP):
    if not os.path.exists(src):
        continue
    with open(src, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            rec = json.loads(line)
            if src == SRC_INTERP and not rec.get("translatable", False):
                continue
            k = rec["key"]
            if k not in seen:
                seen.add(k)
                fresh_keys.append(k)

fresh_keys.sort(key=lambda s: (s.lower(), s))
fresh = set(fresh_keys)

existing = {}
source_language = "en"
if os.path.exists(OUT):
    with open(OUT, encoding="utf-8") as f:
        prev = json.load(f)
    source_language = prev.get("sourceLanguage", "en")
    existing = prev.get("strings", {})

strings = {}
for key in fresh_keys:
    if key in existing:
        strings[key] = existing[key]
    else:
        strings[key] = {"localizations": {}}

catalog = {"sourceLanguage": source_language, "strings": strings, "version": "1.0"}

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(catalog, f, indent=2, ensure_ascii=False, separators=(",", ": "))
    f.write("\n")

kept = sum(1 for k in strings if k in existing and existing[k].get("localizations"))
added = sum(1 for k in strings if k not in existing)
dropped = len(set(existing) - fresh)
print(
    f"wrote {OUT}: {len(strings)} keys "
    f"({added} new, {kept} with existing translations, {dropped} dropped)"
)
