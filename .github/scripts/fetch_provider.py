#!/usr/bin/env python3
"""Mirrors an execution provider ONNX Runtime publishes itself.

Their asset layout is their own: a tarball on Linux, a zip on Windows, each
holding the provider library and a version marker. Ours is one flat archive per
target named the way the build hook looks for it, with a SHA-256 sidecar, the
same as everything else we publish. This turns one into the other.

Nothing is compiled. See .github/workflows/build-ep-cuda.yml for why.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import os
import pathlib
import subprocess
import sys
import tarfile
import tempfile
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import ep_matrix  # noqa: E402

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]


def sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


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
    if provider.source != ep_matrix.FETCH:
        raise SystemExit(f"{provider.name} is built here, not fetched")

    out = REPO_ROOT / "dist" / f"ep-{provider.name}"
    out.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory() as scratch:
        staging = pathlib.Path(scratch)
        for target, asset in provider.upstream_assets:
            print(f"{target}: {asset}")
            upstream = download(provider.upstream_tag, asset, staging)
            name, payload = library_in(upstream, provider.library_stem)

            # One flat archive, named for the target, holding the library under
            # the name the hook asks for.
            archive = out / f"{provider.name}-{target}.tar.gz"
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
