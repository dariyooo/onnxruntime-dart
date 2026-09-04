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
    "android-arm64-v8a": "arm64-v8a",
    "android-x86_64": "x86_64",
    "ios-device-arm64": "arm64",
    "ios-sim-arm64": "arm64",
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


def extract_many(
    archive: pathlib.Path,
    target: str,
    into: pathlib.Path,
) -> list[pathlib.Path]:
    """Every library [target] needs, out of an archive that holds many targets.

    Android and iOS each come as one archive covering several of ours, so the
    slice matters as much as the file name. Android also needs a companion
    library that ships in the same .aar and nowhere else.
    """
    into.mkdir(parents=True, exist_ok=True)
    out: list[pathlib.Path] = []

    with zipfile.ZipFile(archive) as zf:
        if target in genai_matrix.ANDROID:
            abi = genai_matrix.ANDROID[target]
            wanted = ["libonnxruntime-genai.so", *genai_matrix.ANDROID_COMPANIONS]
            for name in wanted:
                inside = f"jni/{abi}/{name}"
                if inside not in zf.namelist():
                    raise SystemExit(f"{archive.name} holds no {inside}")
                written = into / name
                written.write_bytes(zf.read(inside))
                out.append(written)
            return out

        slice_ = genai_matrix.IOS[target]
        inside = (
            f"onnxruntime-genai.xcframework/{slice_}/"
            f"onnxruntime-genai.framework/onnxruntime-genai"
        )
        if inside not in zf.namelist():
            raise SystemExit(f"{archive.name} holds no {inside}")
        written = into / "onnxruntime-genai"
        written.write_bytes(zf.read(inside))
        out.append(written)
        return out


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


def package(target: str, libraries: list[pathlib.Path]) -> None:
    DIST.mkdir(parents=True, exist_ok=True)
    archive = DIST / genai_matrix.our_asset(target)

    with tarfile.open(archive, "w:gz") as tar:
        for library in libraries:
            info = tar.gettarinfo(str(library), arcname=library.name)
            info.mode = 0o755
            with library.open("rb") as handle:
                tar.addfile(info, handle)

    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    (DIST / f"{archive.name}.sha256").write_text(
        f"{digest}  {archive.name}\n", encoding="utf-8"
    )
    size = archive.stat().st_size / 1e6
    names = ", ".join(library.name for library in libraries)
    print(f"  {target:18} {names} -> {archive.name} ({size:.1f} MB)")


def main() -> None:
    targets = sys.argv[1:] or genai_matrix.targets()
    print(
        f"mirroring {genai_matrix.COMPONENT} {genai_matrix.version()} "
        f"from {genai_matrix.UPSTREAM}"
    )
    with tempfile.TemporaryDirectory() as tmp:
        work = pathlib.Path(tmp)
        for target in targets:
            archive = download(target, work / target)
            if target in genai_matrix.ANDROID or target in genai_matrix.IOS:
                libraries = extract_many(target=target, archive=archive,
                                         into=work / target / "lib")
            else:
                libraries = [
                    extract(archive, genai_matrix.library_for(target),
                            work / target / "lib")
                ]
            for library in libraries:
                binary_arch.verify(library, ARCHITECTURE[target])
                if target in genai_matrix.ANDROID:
                    binary_arch.verify_android_dependencies(
                        library,
                        alongside=tuple(l.name for l in libraries),
                    )
            package(target, libraries)


if __name__ == "__main__":
    main()
