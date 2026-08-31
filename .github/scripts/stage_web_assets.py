#!/usr/bin/env python3
"""Puts the built WebAssembly runtime into the Flutter package that serves it.

Flutter bundles what is in a package's `assets/` when the package is published,
and a build hook cannot put it there: data assets from hooks are behind a
Flutter flag that is master-only. So the files are staged here, at release
time, and the directory is otherwise empty and gitignored.

One package per build, because two of the three builds produce the same file
name with different contents, and because Flutter bundles every declared asset:
a single package holding all three would serve every browser three runtimes.
"""

from __future__ import annotations

import argparse
import os
import pathlib
import sys
import tarfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]

# Build id -> the package that serves it.
PACKAGES = {
    "web-wasm": "onnxruntime_web",
    "web-wasm-webgpu": "onnxruntime_web_webgpu",
    "web-wasm-webgpu-webnn": "onnxruntime_web_webgpu_webnn",
}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("build", choices=sorted(PACKAGES))
    parser.add_argument(
        "--archive",
        type=pathlib.Path,
        help="the built artifact; defaults to where the matrix leaves it",
    )
    args = parser.parse_args()

    archive = args.archive or (
        REPO_ROOT / "dist" / "runtime" / f"{args.build}.tar.gz"
    )
    if not archive.is_file():
        raise SystemExit(f"{archive} does not exist")

    assets = REPO_ROOT / "packages" / PACKAGES[args.build] / "assets"
    assets.mkdir(parents=True, exist_ok=True)

    with tarfile.open(archive) as tar:
        members = [
            m for m in tar.getmembers() if m.name.endswith((".wasm", ".mjs"))
        ]
        if not members:
            raise SystemExit(f"{archive.name} holds no wasm or loader")
        for member in members:
            # Flat: the package serves them side by side. Written directly
            # rather than extracted, so nothing in the archive can decide where
            # a file lands, and so this works on older Pythons that have no
            # extraction filter.
            payload = tar.extractfile(member)
            if payload is None:
                continue
            name = pathlib.PurePath(member.name).name
            (assets / name).write_bytes(payload.read())
            size = (assets / name).stat().st_size
            print(f"  {name}  {size / 1e6:.1f} MB")

    print(f"staged into packages/{PACKAGES[args.build]}/assets")


if __name__ == "__main__":
    main()
