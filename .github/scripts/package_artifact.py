#!/usr/bin/env python3
"""Collects a built configuration into `dist/` with SHA-256 sidecars.

Sidecars are produced next to the build rather than at release time, so a
mismatch surfaces near its cause. The build hook verifies them after download.

Headers ship alongside the library because downstream packages link
libonnxruntime and need them to build.
"""

from __future__ import annotations

import hashlib
import os
import pathlib
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import ort_matrix  # noqa: E402

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
ORT_ROOT = REPO_ROOT / "third_party" / "onnxruntime"
DIST = REPO_ROOT / "dist"

# Windows also emits an import library, which downstream builds need to link.
LIBRARY_PATTERNS = {
    "android": ["libonnxruntime.so"],
    "ios": ["libonnxruntime.dylib", "libonnxruntime.*.dylib"],
    "macos": ["libonnxruntime.dylib", "libonnxruntime.*.dylib"],
    "linux": ["libonnxruntime.so", "libonnxruntime.so.*"],
    "windows": ["onnxruntime.dll", "onnxruntime.lib"],
    "web": ["ort-wasm*.wasm", "ort-wasm*.mjs", "ort-wasm*.js"],
}


def sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> None:
    config_id = os.environ["MATRIX_ID"]
    config = ort_matrix.by_id(config_id)
    build_config = os.environ.get("ORT_BUILD_CONFIG", "Release")
    build_dir = REPO_ROOT / "build" / build_config

    if not build_dir.is_dir():
        raise SystemExit(f"{build_dir} does not exist; the build step did not produce output")

    out = DIST / config_id
    (out / "lib").mkdir(parents=True, exist_ok=True)

    found: list[pathlib.Path] = []
    for pattern in LIBRARY_PATTERNS[config.platform]:
        for source in build_dir.rglob(pattern):
            # Skip CMake's intermediate copies.
            if "CMakeFiles" in source.parts or source.is_symlink():
                continue
            destination = out / "lib" / source.name
            if destination.exists():
                continue
            shutil.copy2(source, destination)
            found.append(destination)

    if not found:
        raise SystemExit(
            f"no library matching {LIBRARY_PATTERNS[config.platform]} under {build_dir}"
        )

    headers = out / "include"
    shutil.copytree(
        ORT_ROOT / "include" / "onnxruntime" / "core" / "session",
        headers,
        dirs_exist_ok=True,
        ignore=shutil.ignore_patterns("*.dox", "*.inc"),
    )

    version = (ORT_ROOT / "VERSION_NUMBER").read_text(encoding="utf-8").strip()
    (out / "VERSION").write_text(f"{version}\n", encoding="utf-8")

    # One sidecar per file, so the hook verifies each download independently
    # rather than trusting an archive-level hash.
    lines = []
    for path in sorted(out.rglob("*")):
        if path.is_file() and path.suffix != ".sha256":
            digest = sha256(path)
            path.with_suffix(path.suffix + ".sha256").write_text(
                f"{digest}  {path.name}\n", encoding="utf-8"
            )
            lines.append(f"| `{path.relative_to(out)}` | {path.stat().st_size / 1e6:.1f} MB | `{digest[:16]}…` |")

    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as handle:
            handle.write(f"\n#### `{config_id}` ORT {version}\n\n")
            handle.write("| file | size | sha256 |\n|---|---|---|\n")
            handle.write("\n".join(lines) + "\n")

    print(f"packaged {len(lines)} files into {out}")


if __name__ == "__main__":
    main()
