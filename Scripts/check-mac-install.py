#!/usr/bin/env python3
"""Check that a Mac app's resource seal survives a Finder-style copy."""

import argparse
import os
import shutil
import subprocess
import tempfile
import unicodedata
from pathlib import Path


def copy_decomposed(source: Path, destination: Path) -> None:
    destination.mkdir()
    for path in source.iterdir():
        target = destination / unicodedata.normalize("NFD", path.name)
        if path.is_symlink():
            target.symlink_to(os.readlink(path))
        elif path.is_dir():
            copy_decomposed(path, target)
        else:
            shutil.copy2(path, target)
    shutil.copystat(source, destination)


def check(app: Path) -> None:
    with tempfile.TemporaryDirectory(prefix="DasherInstallCheck-") as temporary:
        root = Path(temporary)
        source = root / "Source.app"
        installed = root / "Installed.app"
        shutil.copytree(app, source, symlinks=True)
        # CI builds without distribution credentials. Sign only this scratch
        # copy ad hoc; the original build and its signature stay untouched.
        subprocess.run(
            ["codesign", "--force", "--deep", "--sign", "-", "--timestamp=none", str(source)], check=True
        )
        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(source)], check=True)
        copy_decomposed(source, installed)
        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(installed)], check=True)
        print("Installed-copy resource seal verified.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    args = parser.parse_args()
    if not args.app.is_dir() or args.app.suffix != ".app":
        parser.error("app must be an existing .app bundle")
    check(args.app)
