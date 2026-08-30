#!/usr/bin/env python3
"""Points the test suite at a shared library from our own build.

Sets ONNXRUNTIME_LIB, which `test/src/ort_library.dart` reads. Fails loudly when
the artifact holds no library, because the ABI tests skip when none is found and
a silent skip would let the job pass while proving nothing.
"""

from __future__ import annotations

import os
import pathlib
import sys

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
LIBRARY_NAMES = ("libonnxruntime.so", "libonnxruntime.dylib", "onnxruntime.dll")


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: locate_library.py <artifact-directory-name>")

    root = REPO_ROOT / ".local" / "ort" / sys.argv[1]
    if not root.is_dir():
        raise SystemExit(f"{root} does not exist; the artifact was not downloaded")

    library = next(
        (p for p in sorted(root.rglob("*")) if p.name in LIBRARY_NAMES and p.is_file()),
        None,
    )
    if library is None:
        found = sorted(p.name for p in root.rglob("*") if p.is_file())
        raise SystemExit(
            f"no library named one of {LIBRARY_NAMES} under {root}. Found: {found}"
        )

    print(f"ONNXRUNTIME_LIB={library}")
    if env_file := os.environ.get("GITHUB_ENV"):
        with open(env_file, "a", encoding="utf-8") as handle:
            handle.write(f"ONNXRUNTIME_LIB={library}\n")


if __name__ == "__main__":
    main()
