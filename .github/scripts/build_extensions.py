#!/usr/bin/env python3
"""Builds the onnxruntime-extensions operator library for one target.

Upstream ships build.sh, build.android and build.ios_xcframework, none of which
produce what we want: one shared library per target, named the way the build
hook looks for it. They wrap the same CMake project, so this drives it directly
and the configuration lives in extensions_matrix.py where it can be read.
"""

from __future__ import annotations

import argparse
import os
import pathlib
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import extensions_matrix  # noqa: E402

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCE = REPO_ROOT / "third_party" / "onnxruntime-extensions"

# The real file, not the symlinks beside it. The build leaves
# libortextensions.dylib -> libortextensions.0.dylib -> libortextensions.<v>.dylib
# and only the last one has content.
PATTERNS = {
    "windows": ("ortextensions.dll",),
    "macos": ("libortextensions.*.dylib", "libortextensions.dylib"),
    "ios": ("libortextensions.*.dylib", "libortextensions.dylib"),
}
DEFAULT_PATTERNS = ("libortextensions.so.*", "libortextensions.so")


def find_library(build_dir: pathlib.Path, platform: str) -> pathlib.Path:
    for pattern in PATTERNS.get(platform, DEFAULT_PATTERNS):
        for found in sorted(build_dir.rglob(pattern)):
            if found.is_file() and not found.is_symlink():
                return found
    raise SystemExit(f"no extensions library under {build_dir}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("target", help="which target to build")
    args = parser.parse_args()

    build = extensions_matrix.by_id(args.target)
    build_dir = REPO_ROOT / "build" / f"extensions-{build.id}"

    subprocess.run(
        ("cmake", "-S", str(SOURCE), "-B", str(build_dir), *build.cmake_args()),
        check=True,
        cwd=SOURCE,
    )
    subprocess.run(
        (
            "cmake", "--build", str(build_dir),
            "--config", "Release",
            "--target", "extensions_shared",
            "--parallel",
        ),
        check=True,
    )

    library = find_library(build_dir, build.platform)

    # Under the name the hook asks for, without the version the soname carries.
    out = REPO_ROOT / "dist" / extensions_matrix.COMPONENT
    out.mkdir(parents=True, exist_ok=True)
    suffix = {"windows": ".dll", "macos": ".dylib", "ios": ".dylib"}.get(
        build.platform, ".so"
    )
    stem = "ortextensions" if build.platform == "windows" else "libortextensions"
    staged = out / f"{stem}{suffix}"
    shutil.copy2(library, staged)

    print(f"{build.id}: {library.name} -> {staged.name} "
          f"({staged.stat().st_size / 1e6:.1f} MB)")


if __name__ == "__main__":
    main()
