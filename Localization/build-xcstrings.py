#!/usr/bin/env python3
"""(Re)build Localizable.xcstrings from chrome-strings.jsonl, PRESERVING any
translations already merged into the catalog.

- keys still present in the JSONL keep their existing localizations.
- new keys are added with empty localizations.
- keys no longer in the JSONL are dropped (the string is gone from the UI).

Run after re-extracting:  python3 Localization/build-xcstrings.py
"""
import json, os

SRC = "Localization/chrome-strings.jsonl"
OUT = "Localization/Localizable.xcstrings"

# Fresh key set from the extraction.
fresh_keys = []
with open(SRC, encoding="utf-8") as f:
    for line in f:
        line = line.strip()
        if line:
            fresh_keys.append(json.loads(line)["key"])
fresh = set(fresh_keys)

# Preserve existing catalog (translations) where possible.
existing = {}
source_language = "en"
if os.path.exists(OUT):
    with open(OUT, encoding="utf-8") as f:
        prev = json.load(f)
    source_language = prev.get("sourceLanguage", "en")
    existing = prev.get("strings", {})

strings = {}
for key in fresh_keys:  # preserve jsonl order
    if key in existing:
        strings[key] = existing[key]            # keep merged localizations
    else:
        strings[key] = {"localizations": {}}    # new string

catalog = {"sourceLanguage": source_language, "strings": strings, "version": "1.0"}

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(catalog, f, indent=2, ensure_ascii=False)
    f.write("\n")

kept = sum(1 for k in strings if k in existing and existing[k].get("localizations"))
added = sum(1 for k in strings if k not in existing)
dropped = len(set(existing) - fresh)
print(f"wrote {OUT}: {len(strings)} keys "
      f"({added} new, {kept} with existing translations, {dropped} dropped)")
