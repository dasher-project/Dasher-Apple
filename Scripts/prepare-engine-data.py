#!/usr/bin/env python3
"""Assemble full app language resources from the pinned engine and Apple additions."""

import argparse
import shutil
import tempfile
import unicodedata
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent


def normalize_resource_names(root: Path) -> None:
    # Finder decomposes Unicode filenames when copying an app. Use that
    # form before signing so installation preserves the resource seal.
    for path in sorted(root.rglob("*"), key=lambda p: len(p.parts), reverse=True):
        name = unicodedata.normalize("NFD", path.name)
        if name == path.name:
            continue
        target = path.with_name(name)
        if target.exists() and not path.samefile(target):
            raise FileExistsError(f"Resource filenames collide: {path} and {target}")
        # A direct rename can be a no-op on normalization-insensitive APFS.
        with tempfile.TemporaryDirectory(prefix=".dasher-nfd-", dir=path.parent) as staging:
            staged = Path(staging) / "resource"
            path.rename(staged)
            try:
                staged.rename(target)
            except OSError:
                staged.rename(path)
                raise


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
    normalize_resource_names(destination)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("destination", type=Path)
    prepare(parser.parse_args().destination)
