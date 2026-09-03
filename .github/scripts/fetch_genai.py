#!/usr/bin/env python3
"""Mirrors the ONNX Runtime GenAI release into ours.

Upstream publishes a library per target. This takes each archive, lifts the one
file the hook installs out of it, and repackages it under our own naming with a
checksum beside it, which is the same shape every other component we publish
has.

The architecture of each library is checked before it is packaged, for the same
reason it is checked everywhere else: a path is not evidence of what a file is,
and the mistake is invisible until something tries to load it.
"""

from __future__ import annotations

import hashlib
import os
import pathlib
import subprocess
import sys
import tarfile
import tempfile
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import binary_arch  # noqa: E402
import genai_matrix  # noqa: E402

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
DIST = REPO_ROOT / "dist" / genai_matrix.COMPONENT

#: Our target id -> the architecture its binaries must be.
ARCHITECTURE = {
    "linux-x64": "x86_64",
    "linux-arm64": "arm64",
    "macos-arm64": "arm64",
    "windows-x64": "x86_64",
    "windows-arm64": "arm64",
}


def download(target: str, into: pathlib.Path) -> pathlib.Path:
    asset = genai_matrix.upstream_asset(target)
    subprocess.run(
        (
            "gh", "release", "download", genai_matrix.upstream_tag(),
            "--repo", genai_matrix.UPSTREAM,
            "--pattern", asset,
            "--dir", str(into),
            "--clobber",
        ),
        check=True,
    )
    return into / asset


def extract(archive: pathlib.Path, wanted: str, into: pathlib.Path) -> pathlib.Path:
    """The one library out of [archive], wherever upstream put it."""
    into.mkdir(parents=True, exist_ok=True)

    if archive.suffix == ".zip":
        with zipfile.ZipFile(archive) as zf:
            names = [n for n in zf.namelist() if n.endswith(f"/{wanted}")]
            if not names:
                names = [n for n in zf.namelist() if n.endswith(wanted)]
            if not names:
                raise SystemExit(f"{archive.name} holds no {wanted}")
            with zf.open(names[0]) as source:
                out = into / wanted
                out.write_bytes(source.read())
            return out

    with tarfile.open(archive) as tf:
        members = [m for m in tf.getmembers() if m.name.endswith(f"/{wanted}")]
        if not members:
            members = [m for m in tf.getmembers() if m.name.endswith(wanted)]
        if not members:
            raise SystemExit(f"{archive.name} holds no {wanted}")
        source = tf.extractfile(members[0])
        if source is None:
            raise SystemExit(f"{archive.name}: {wanted} is not a file")
        out = into / wanted
        out.write_bytes(source.read())
        return out


def package(target: str, library: pathlib.Path) -> None:
    DIST.mkdir(parents=True, exist_ok=True)
    archive = DIST / genai_matrix.our_asset(target)

    with tarfile.open(archive, "w:gz") as tar:
        info = tar.gettarinfo(str(library), arcname=library.name)
        info.mode = 0o755
        with library.open("rb") as handle:
            tar.addfile(info, handle)

    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    (DIST / f"{archive.name}.sha256").write_text(
        f"{digest}  {archive.name}\n", encoding="utf-8"
    )
    size = archive.stat().st_size / 1e6
    print(f"  {target:16} {library.name} -> {archive.name} ({size:.1f} MB)")


def main() -> None:
    targets = sys.argv[1:] or genai_matrix.targets()
    print(
        f"mirroring {genai_matrix.COMPONENT} {genai_matrix.version()} "
        f"from {genai_matrix.UPSTREAM}"
    )
    with tempfile.TemporaryDirectory() as tmp:
        work = pathlib.Path(tmp)
        for target in targets:
            wanted = genai_matrix.library_for(target)
            archive = download(target, work / target)
            library = extract(archive, wanted, work / target / "lib")
            binary_arch.verify(library, ARCHITECTURE[target])
            package(target, library)


if __name__ == "__main__":
    main()
