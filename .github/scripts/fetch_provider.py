#!/usr/bin/env python3
"""Mirrors an execution provider ONNX Runtime publishes itself.

Their asset layout is their own: a tarball on Linux, a zip on Windows, a Python
wheel on PyPI, each holding the provider library and whatever else it needs.
Ours is one flat archive per target named the way the build hook looks for it,
with a SHA-256 sidecar, the same as everything else we publish. This turns one
into the other.

Two shapes come out of that. CUDA needs its toolkit from the machine, so only
the plugin travels. QNN carries the Qualcomm runtime it dlopens, so the whole
set travels together and their library paths are rewritten to point beside
themselves rather than into a layout only Python would produce.

Nothing is compiled. See .github/workflows/build-ep-cuda.yml for why.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import elf_rpath  # noqa: E402
import ep_matrix  # noqa: E402

# Carried alongside the libraries because redistributing them is conditional on
# it. The Qualcomm runtime in the QNN wheel is licensed, not public domain.
LICENCE_FILES = ("LICENSE", "NOTICE", "ThirdPartyNotices.txt", "Privacy.md")

# Some wheels carry more than one architecture. The Windows x64 QNN wheel has
# libs/amd64 and libs/arm64ec, which flatten onto each other, so the target
# says which one it wants. arm64ec is an interop ABI, not what a native arm64
# build wants, and that comes from the win_arm64 wheel instead.
WHEEL_ARCH_DIRS = {
    "windows-x64": "amd64",
    "windows-arm64": "arm64",
}
LIBRARY_SUFFIXES = (".dll", ".dylib", ".pdb")

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]


def sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def is_library(name: str) -> bool:
    """Shared libraries, including the versioned `.so.1.0` names auditwheel
    produces, which a plain suffix test misses."""
    base = pathlib.PurePath(name).name
    return base.endswith(LIBRARY_SUFFIXES) or ".so" in base


def download_wheel(
    project: str, version: str, fragment: str, into: pathlib.Path
) -> pathlib.Path:
    """The wheel for one platform. The Python tag in the filename is noise
    here, since none of these are Python extension modules, so any wheel
    carrying the platform fragment will do and we take the first by name to
    stay reproducible."""
    into.mkdir(parents=True, exist_ok=True)
    url = f"https://pypi.org/pypi/{project}/{version}/json"
    with urllib.request.urlopen(url) as response:
        files = json.load(response)["urls"]

    matches = sorted(
        (f["filename"], f["url"]) for f in files if fragment in f["filename"]
    )
    if not matches:
        raise SystemExit(f"{project} {version} publishes no wheel matching {fragment}")

    filename, source = matches[0]
    destination = into / filename
    with urllib.request.urlopen(source) as response, destination.open("wb") as handle:
        shutil.copyfileobj(response, handle)
    return destination


def _arch_directories(names: list[str]) -> set[str]:
    """The `libs/<arch>/` directories a wheel is split across, if any."""
    found = set()
    for name in names:
        parts = pathlib.PurePath(name).parts
        if "libs" in parts:
            at = parts.index("libs")
            if at + 2 < len(parts):
                found.add(parts[at + 1])
    return found


def unpack_bundle(
    wheel: pathlib.Path, into: pathlib.Path, target: str = ""
) -> list[pathlib.Path]:
    """Every library and licence in a wheel, flattened into one directory.

    The wheel splits libraries across a package directory and an auditwheel
    sibling, and points the RPATHs across that gap. Flattening closes it, so
    the RPATHs are rewritten to match. Bundling steps downstream are free to
    move these files as a set, which they would not be otherwise."""
    into.mkdir(parents=True, exist_ok=True)
    written: list[pathlib.Path] = []

    with zipfile.ZipFile(wheel) as zipped:
        names = zipped.namelist()
        architectures = _arch_directories(names)
        wanted = ""
        if len(architectures) > 1:
            wanted = WHEEL_ARCH_DIRS.get(target, "")
            if wanted not in architectures:
                raise SystemExit(
                    f"{wheel.name} carries {', '.join(sorted(architectures))} "
                    f"and nothing says which {target} wants"
                )

        for entry in names:
            if wanted and f"/libs/{wanted}/" not in f"/{entry}":
                if f"/libs/" in f"/{entry}":
                    continue
            base = pathlib.PurePath(entry).name
            keep = is_library(entry) or base in LICENCE_FILES or base.endswith(".pdf")
            if entry.endswith("/") or ".dist-info/" in entry or not keep:
                continue
            destination = into / base
            if destination.exists():
                raise SystemExit(f"{wheel.name}: two entries named {base}")
            destination.write_bytes(zipped.read(entry))
            written.append(destination)

    for path in written:
        if is_library(path.name):
            was = elf_rpath.flatten(path)
            if was:
                print(f"    {path.name}: RPATH {was} -> $ORIGIN")
    return written


def download(tag: str, asset: str, into: pathlib.Path) -> pathlib.Path:
    """Takes one asset from an upstream release."""
    into.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        (
            "gh", "release", "download", tag,
            "--repo", "microsoft/onnxruntime",
            "--pattern", asset,
            "--dir", str(into),
            "--clobber",
        ),
        check=True,
    )
    downloaded = into / asset
    if not downloaded.is_file():
        raise SystemExit(f"{asset} is not in {tag}")
    return downloaded


def library_in(archive: pathlib.Path, stem: str) -> tuple[str, bytes]:
    """The provider library inside an upstream archive, whatever it is wrapped
    in and wherever they put it."""
    if archive.suffix == ".zip":
        with zipfile.ZipFile(archive) as zipped:
            for name in zipped.namelist():
                if stem in name and name.endswith((".dll", ".so", ".dylib")):
                    return pathlib.PurePath(name).name, zipped.read(name)
    else:
        with tarfile.open(archive) as tar:
            for member in tar.getmembers():
                if stem in member.name and member.name.endswith(
                    (".dll", ".so", ".dylib")
                ):
                    extracted = tar.extractfile(member)
                    if extracted is None:
                        continue
                    return pathlib.PurePath(member.name).name, extracted.read()
    raise SystemExit(f"{archive.name} holds no library matching {stem}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("provider", help="which provider to mirror")
    args = parser.parse_args()

    provider = ep_matrix.by_name(args.provider)
    if provider.source == ep_matrix.BUILD:
        raise SystemExit(f"{provider.name} is built here, not fetched")

    out = REPO_ROOT / "dist" / f"ep-{provider.name}"
    out.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory() as scratch:
        staging = pathlib.Path(scratch)
        for build, target, asset in provider.upstream_assets:
            print(f"{build or provider.name} {target}: {asset}")

            # One flat archive per build and target, holding the library under
            # the name the hook asks for. The build is in the archive name only
            # where the provider ships more than one, differing in what they
            # need from the machine rather than in what they do.
            archive = out / provider.asset_name(build, target)

            if provider.source == ep_matrix.PYPI:
                wheel = download_wheel(
                    provider.pypi_project, provider.version, asset, staging
                )
                unpacked = staging / f"{provider.name}-{target}"
                files = unpack_bundle(wheel, unpacked, target)
                if not any(provider.library_stem in f.name for f in files):
                    raise SystemExit(f"{wheel.name} holds no {provider.library_stem}")
                with tarfile.open(archive, "w:gz") as tar:
                    for path in sorted(files):
                        tar.add(path, arcname=path.name)
            else:
                upstream = download(provider.upstream_tag, asset, staging)
                name, payload = library_in(upstream, provider.library_stem)
                with tarfile.open(archive, "w:gz") as tar:
                    info = tarfile.TarInfo(name)
                    info.size = len(payload)
                    info.mode = 0o755
                    tar.addfile(info, io.BytesIO(payload))

            digest = sha256(archive)
            (out / f"{archive.name}.sha256").write_text(
                f"{digest}  {archive.name}\n", encoding="utf-8"
            )
            print(f"  -> {archive.name} ({archive.stat().st_size / 1e6:.1f} MB)")

    print(f"\n{provider.release_tag} staged in {out}")


if __name__ == "__main__":
    main()
