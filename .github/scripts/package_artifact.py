#!/usr/bin/env python3
"""Packages each built configuration into one release archive.

The build hook downloads exactly one archive for the target it is building and
verifies it against the sidecar written here, so hashing happens next to the
build rather than at release time where a mismatch would surface far from its
cause.

Headers are not included. They are identical across configurations and are
published once per release, so the archive a hook downloads holds only what it
needs to load.
"""

from __future__ import annotations

import hashlib
import os
import pathlib
import sys
import tarfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import ort_matrix  # noqa: E402

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
DIST = REPO_ROOT / "dist"

# What each platform's build produces and we ship. Windows also emits an import
# library, which downstream builds need in order to link.
ARTIFACT_PATTERNS = {
    "android": ["libonnxruntime.so"],
    "ios": ["libonnxruntime.dylib"],
    "macos": ["libonnxruntime.dylib"],
    "linux": ["libonnxruntime.so"],
    "windows": ["onnxruntime.dll", "onnxruntime.lib"],
    "web": ["ort-wasm*.wasm", "ort-wasm*.mjs"],
}


def sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> None:
    DIST.mkdir(parents=True, exist_ok=True)
    for config_id in os.environ["MATRIX_IDS"].split():
        package(ort_matrix.by_id(config_id))


def package(config: ort_matrix.Config) -> None:
    build_config = os.environ.get("ORT_BUILD_CONFIG", "Release")
    build_dir = REPO_ROOT / "build" / config.id / build_config
    if not build_dir.is_dir():
        raise SystemExit(f"{build_dir} does not exist; the build produced nothing")

    found: dict[str, pathlib.Path] = {}
    for pattern in ARTIFACT_PATTERNS[config.platform]:
        for source in sorted(build_dir.rglob(pattern)):
            # Skip CMake's intermediate copies and version symlinks.
            if "CMakeFiles" in source.parts or source.is_symlink():
                continue
            found.setdefault(source.name, source)

    if not found:
        raise SystemExit(
            f"no artifact matching {ARTIFACT_PATTERNS[config.platform]} "
            f"under {build_dir}"
        )

    # Flat archive: the hook looks up members by file name, not by path.
    archive = DIST / f"{config.id}.tar.gz"
    with tarfile.open(archive, "w:gz") as tar:
        for name, source in sorted(found.items()):
            tar.add(source, arcname=name)

    digest = sha256(archive)
    (DIST / f"{config.id}.tar.gz.sha256").write_text(
        f"{digest}  {archive.name}\n", encoding="utf-8"
    )

    size_mb = archive.stat().st_size / 1e6
    print(f"{config.id}: {', '.join(sorted(found))} -> {size_mb:.1f} MB")

    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as handle:
            handle.write(
                f"| `{config.id}.tar.gz` | {size_mb:.1f} MB | `{digest[:16]}…` |\n"
            )


if __name__ == "__main__":
    main()
