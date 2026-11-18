#!/usr/bin/env python3
"""Assemble full app language resources from the pinned engine and Apple additions."""

import argparse
import shutil
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


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("destination", type=Path)
    prepare(parser.parse_args().destination)
