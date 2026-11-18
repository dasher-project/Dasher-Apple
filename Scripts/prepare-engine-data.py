#!/usr/bin/env python3
"""Assemble full app language resources from the pinned engine and Apple additions."""

import argparse
import json
import shutil
import unicodedata
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent


def prepare(destination: Path) -> None:
    # Apple additions include the X-SAMPA alphabets and symbol images.
    shutil.copytree(ROOT / "DasherEngine/Resources/Data", destination, dirs_exist_ok=True)
    shutil.copytree(
        ROOT / "DasherCore/Data",
        destination,
        dirs_exist_ok=True,
        ignore=shutil.ignore_patterns("Makefile.am", "*.py", "__pycache__"),
    )
    shutil.copytree(ROOT / "DasherCore/Strings", destination / "Strings", dirs_exist_ok=True)

    training = destination / "training"
    index_path = destination / "alphabets/alphabet_index.json"
    index = json.loads(index_path.read_text(encoding="utf-8"))
    corpora = {}
    for alphabet in index["alphabets"]:
        language = alphabet.get("lang")
        script = alphabet.get("script")
        corpus = training / (alphabet.get("training") or "")
        if language and script and alphabet.get("conversion") == "none" and corpus.is_file():
            corpora.setdefault((language, script), corpus)

    # Keep legacy filenames so existing user training files continue to apply.
    for alphabet in index["alphabets"]:
        name = alphabet.get("training")
        if not name:
            continue
        corpus = training / name
        source = corpora.get((alphabet.get("lang"), alphabet.get("script")))
        if not corpus.exists() and source and alphabet.get("conversion") == "none":
            text = source.read_text(encoding="utf-8")
            form = "NFD" if "combining accents" in alphabet["id"].lower() else "NFC"
            corpus.write_text(unicodedata.normalize(form, text), encoding="utf-8")
        alphabet["training_available"] = corpus.is_file()
    index_path.write_text(json.dumps(index, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("destination", type=Path)
    prepare(parser.parse_args().destination)
