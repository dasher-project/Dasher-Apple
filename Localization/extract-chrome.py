#!/usr/bin/env python3
"""Extract user-facing SwiftUI chrome strings from Dasher-Apple for translation.

Outputs JSONL (one record per unique string) keyed by the English source, which
is also the SwiftUI LocalizedStringKey. The user translates `source`; a merge
script writes the results back into Localizable.xcstrings.

Scans Text/Label/Button/Toggle/navigationTitle/help/confirmationDialog/alert/
Link/Section/menu first-string-argument literals across all targets + shared.
"""
import glob, json, os, re, sys

ROOT = "."
DIRS = ["DasherApp/Sources", "DasherMac/Sources", "DasherVision/Sources",
        "DasherKeyboard/Sources", "DasherShared"]

# First string argument of these SwiftUI calls is user-facing chrome.
PATTERN = re.compile(
    r'\b(?:Text|Label|Button|Toggle|navigationTitle|help|confirmationDialog|'
    r'alert|Link|Section|menu)\(\s*"((?:[^"\\]|\\.)*)"'
)
STR_LIT = re.compile(r'"((?:[^"\\]|\\.)*)"')
INTERP = re.compile(r'\\\(')  # Swift string interpolation

def unescape(s: str) -> str:
    return s.replace('\\"', '"').replace('\\n', '\n').replace('\\t', '\t').replace('\\\\', '\\')

seen = {}  # source -> (file, line, interpolated)
for d in DIRS:
    for path in glob.glob(os.path.join(d, "**", "*.swift"), recursive=True):
        with open(path, encoding="utf-8") as f:
            text = f.read()
        # Build a line index for offset->line lookup.
        for m in PATTERN.finditer(text):
            raw = m.group(1)
            src = unescape(raw)
            if not src.strip():
                continue
            # Skip pure symbols / single non-alphanumeric (e.g. "+", "·", "–").
            if not re.search(r'[A-Za-zÀ-ÿ]', src):
                continue
            line = text.count("\n", 0, m.start()) + 1
            rel = os.path.relpath(path, ROOT)
            interp = bool(INTERP.search(raw))
            if src not in seen:
                seen[src] = {"source": src, "interpolated": interp,
                             "context": f"{rel}:{line}"}

records = sorted(seen.values(), key=lambda r: r["source"].lower())
static = [r for r in records if not r["interpolated"]]
interp = [r for r in records if r["interpolated"]]

os.makedirs("Localization", exist_ok=True)

# 1) The translate list: clean static strings only (key = English source).
out = "Localization/chrome-strings.jsonl"
with open(out, "w", encoding="utf-8") as f:
    for r in static:
        f.write(json.dumps({"key": r["source"], "source": r["source"],
                            "context": r["context"]}, ensure_ascii=False) + "\n")

# 2) Format strings (interpolation) — need manual, format-aware translation.
with open("Localization/chrome-strings-formatted.jsonl", "w", encoding="utf-8") as f:
    for r in interp:
        f.write(json.dumps({"key": r["source"], "source": r["source"],
                            "context": r["context"],
                            "note": "Contains \\(...) interpolation; keep the "
                                    "\\(...) segments and surrounding format when translating."},
                           ensure_ascii=False) + "\n")

print(f"wrote {out}: {len(static)} static strings to translate")
print(f"wrote Localization/chrome-strings-formatted.jsonl: "
      f"{len(interp)} format strings (manual handling)")
