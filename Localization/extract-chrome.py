#!/usr/bin/env python3
"""Extract user-facing SwiftUI chrome strings from Dasher-Apple for translation.

Outputs JSONL (one record per unique string) keyed by the English source, which
is also the SwiftUI LocalizedStringKey. Format strings with `\\(...)`
interpolations are written to `chrome-strings-formatted.jsonl` along with their
derived Xcode String Catalog format key (`xcstrings_key`, e.g. `"Sending to %@"`).

Scans Text/Label/Button/Toggle/Picker/navigationTitle/help/confirmationDialog/
alert/Link/Section/menu first-string-argument literals across all app targets
and shared modules (including DasherSpeech).
"""
import glob
import json
import os
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DIRS = [
    "DasherApp/Sources",
    "DasherMac/Sources",
    "DasherVision/Sources",
    "DasherKeyboard/Sources",
    "DasherShared",
    "DasherSpeech",
]

CALL_START = re.compile(
    r'\b(?:Text|Label|LucideLabel|Button|Toggle|Picker|navigationTitle|help|confirmationDialog|'
    r'alert|Link|Section|menu)\(\s*"'
)

INT_EXPR_PATTERNS = re.compile(
    r'(\.count\b|^Int\s*\(|speedPercent\b|scanRateMs\b|'
    r'gamePhrasesCompleted\b|gameTargetLength\b|^correct$|getLongParameter\s*\()'
)


def mask_comments(text: str) -> str:
    """Mask single-line // comments and /* */ block comments with spaces/newlines,
    leaving string literals intact.
    """
    chars = list(text)
    n = len(chars)
    i = 0
    in_string = False
    while i < n:
        if in_string:
            if chars[i] == "\\":
                i += 2
                continue
            if chars[i] == '"':
                in_string = False
            i += 1
            continue

        if chars[i] == '"':
            in_string = True
            i += 1
            continue
        if i + 1 < n and chars[i] == "/" and chars[i + 1] == "/":
            j = i
            while j < n and chars[j] != "\n":
                chars[j] = " "
                j += 1
            i = j
            continue
        if i + 1 < n and chars[i] == "/" and chars[i + 1] == "*":
            j = i + 2
            chars[i] = " "
            chars[i + 1] = " "
            while j < n:
                if j + 1 < n and chars[j] == "*" and chars[j + 1] == "/":
                    chars[j] = " "
                    chars[j + 1] = " "
                    j += 2
                    break
                if chars[j] != "\n":
                    chars[j] = " "
                j += 1
            i = j
            continue
        i += 1
    return "".join(chars)


def parse_swift_string_literal(text: str, start_quote_idx: int):
    """Parse a Swift string literal starting at `start_quote_idx` (the opening `"`).

    Correctly handles nested `"..."` inside `\\(...)` string interpolations.
    Returns `(raw_contents, end_idx, interpolations)` or `None` if unterminated.
    """
    i = start_quote_idx + 1
    n = len(text)
    interpolations = []
    while i < n:
        ch = text[i]
        if ch == "\\":
            if i + 1 < n and text[i + 1] == "(":
                # Parse balanced parentheses for \(...), skipping nested strings
                interp_start = i + 2
                depth = 1
                j = interp_start
                while j < n and depth > 0:
                    c = text[j]
                    if c == "\\":
                        j += 2
                        continue
                    if c == '"':
                        # Skip nested string literal inside \(...)
                        j += 1
                        while j < n:
                            if text[j] == "\\":
                                j += 2
                            elif text[j] == '"':
                                j += 1
                                break
                            else:
                                j += 1
                        continue
                    if c == "(":
                        depth += 1
                    elif c == ")":
                        depth -= 1
                    j += 1
                expr = text[interp_start : j - 1].strip()
                interpolations.append((i - (start_quote_idx + 1), j - (start_quote_idx + 1), expr))
                i = j
                continue
            i += 2
            continue
        if ch == '"':
            raw = text[start_quote_idx + 1 : i]
            return raw, i + 1, interpolations
        i += 1
    return None


def unescape_segment(s: str) -> str:
    def repl(m):
        c = m.group(1)
        if c == "n":
            return "\n"
        if c == "t":
            return "\t"
        if c == '"':
            return '"'
        if c == "\\":
            return "\\"
        return c

    return re.sub(r'\\(["nt\\])', repl, s)


def specifier_for_expr(expr: str) -> str:
    if INT_EXPR_PATTERNS.search(expr):
        return "%lld"
    return "%@"


def build_xcstrings_format_key(raw: str, interpolations: list) -> str:
    """Convert a raw Swift interpolated literal into its Xcode String Catalog key."""
    parts = []
    last = 0
    for start, end, expr in interpolations:
        parts.append(unescape_segment(raw[last:start]))
        parts.append(specifier_for_expr(expr))
        last = end
    parts.append(unescape_segment(raw[last:]))
    return "".join(parts)


def is_translatable_format_key(xc_key: str) -> bool:
    """Return True if the format key contains translatable prose or labels,
    not just bare format specifiers / punctuation (e.g. `%@`, `%lld%%`, `%lld/%lld`).
    """
    stripped = re.sub(r"%(?:lld|@)", "", xc_key)
    return bool(re.search(r"[A-Za-zÀ-ÿ]{2,}", stripped))


def extract_all(root: Path = ROOT):
    seen_static = {}
    seen_interp = {}

    for d in DIRS:
        dir_path = root / d
        for path_str in sorted(glob.glob(str(dir_path / "**" / "*.swift"), recursive=True)):
            path = Path(path_str)
            text = mask_comments(path.read_text(encoding="utf-8"))
            rel = path.relative_to(root).as_posix()
            for m in CALL_START.finditer(text):
                quote_idx = m.end() - 1
                parsed = parse_swift_string_literal(text, quote_idx)
                if not parsed:
                    continue
                raw, _, interpolations = parsed
                line = text.count("\n", 0, m.start()) + 1
                if not interpolations:
                    src = unescape_segment(raw)
                    if not src.strip() or not re.search(r"[A-Za-zÀ-ÿ]", src):
                        continue
                    if src not in seen_static:
                        seen_static[src] = {
                            "key": src,
                            "source": src,
                            "context": f"{rel}:{line}",
                        }
                else:
                    xc_key = build_xcstrings_format_key(raw, interpolations)
                    translatable = is_translatable_format_key(xc_key)
                    if raw not in seen_interp:
                        seen_interp[raw] = {
                            "key": xc_key,
                            "source": raw,
                            "context": f"{rel}:{line}",
                            "translatable": translatable,
                            "note": (
                                "Contains \\(...) interpolation; mapped to Xcode format key "
                                f"{xc_key!r} in Localizable.xcstrings."
                            ),
                        }

    static_records = sorted(seen_static.values(), key=lambda r: (r["source"].lower(), r["source"]))
    interp_records = sorted(seen_interp.values(), key=lambda r: (r["source"].lower(), r["source"]))
    return static_records, interp_records


def write_extraction_files(root: Path = ROOT):
    static_records, interp_records = extract_all(root)
    loc_dir = root / "Localization"
    loc_dir.mkdir(exist_ok=True)

    static_out = loc_dir / "chrome-strings.jsonl"
    with open(static_out, "w", encoding="utf-8") as f:
        for r in static_records:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")

    interp_out = loc_dir / "chrome-strings-formatted.jsonl"
    with open(interp_out, "w", encoding="utf-8") as f:
        for r in interp_records:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")

    return static_records, interp_records


def main() -> int:
    static_records, interp_records = write_extraction_files(ROOT)
    translatable_interp = sum(1 for r in interp_records if r["translatable"])
    print(f"wrote Localization/chrome-strings.jsonl: {len(static_records)} static strings")
    print(
        f"wrote Localization/chrome-strings-formatted.jsonl: "
        f"{len(interp_records)} format strings ({translatable_interp} translatable)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
