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

    # The maintained Spanish definitions use the older corpus filenames.
    # Keep those names so existing user training files continue to apply.
    training = destination / "training"
    spanish = (training / "training_wa_es_Latn.txt").read_text(encoding="utf-8")
    for name, form in [
        ("training_spanish_ES.txt", "NFC"),
        ("training_spanishC_ES.txt", "NFD"),
    ]:
        (training / name).write_text(unicodedata.normalize(form, spanish), encoding="utf-8")

    index_path = destination / "alphabets/alphabet_index.json"
    index = json.loads(index_path.read_text(encoding="utf-8"))
    for alphabet in index["alphabets"]:
        corpus = alphabet.get("training")
        alphabet["training_available"] = bool(corpus and (training / corpus).is_file())
    index_path.write_text(json.dumps(index, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("destination", type=Path)
    prepare(parser.parse_args().destination)
