#!/usr/bin/env python3
"""Packages the public C headers once per release.

They come from the pinned submodule and are identical for every configuration,
so they ship as a single asset rather than inside each platform archive.
Downstream packages that link libonnxruntime need them; the build hook does not.
"""

from __future__ import annotations

import hashlib
import pathlib
import tarfile

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
HEADERS = REPO_ROOT / "third_party" / "onnxruntime" / "include" / "onnxruntime"
DIST = REPO_ROOT / "dist"


def main() -> None:
    if not HEADERS.is_dir():
        raise SystemExit(f"{HEADERS} does not exist; the submodule is not checked out")

    DIST.mkdir(parents=True, exist_ok=True)
    archive = DIST / "headers.tar.gz"
    with tarfile.open(archive, "w:gz") as tar:
        for header in sorted(HEADERS.rglob("*.h")):
            tar.add(header, arcname=str(header.relative_to(HEADERS)))

    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    (DIST / "headers.tar.gz.sha256").write_text(
        f"{digest}  {archive.name}\n", encoding="utf-8"
    )
    print(f"headers.tar.gz: {archive.stat().st_size / 1e6:.1f} MB  {digest[:16]}")


if __name__ == "__main__":
    main()
