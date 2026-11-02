#!/usr/bin/env python3
"""Wrapper around `Localization/gen-from-shared.py` for backward compatibility."""
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent


def main() -> int:
    args = [a for a in sys.argv[1:] if a != "--force"]
    return subprocess.call([sys.executable, str(HERE / "gen-from-shared.py"), *args])


if __name__ == "__main__":
    raise SystemExit(main())
