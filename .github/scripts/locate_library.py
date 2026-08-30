#!/usr/bin/env python3
"""Unpacks our own build and points the test suite at it.

Sets ONNXRUNTIME_LIB, and ONNXRUNTIME_EP_WEBGPU when the plugin was built. Fails
loudly when the runtime archive is missing, because the tests that need it skip
when it is absent and a silent skip would let the job pass while proving nothing.
"""

from __future__ import annotations

import os
import pathlib
import sys
import tarfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import ort_matrix  # noqa: E402

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
LIBRARY_NAMES = ("libonnxruntime.so", "libonnxruntime.dylib", "onnxruntime.dll")
PLUGIN_NAMES = (
    "libonnxruntime_providers_webgpu.so",
    "libonnxruntime_providers_webgpu.dylib",
    "onnxruntime_providers_webgpu.dll",
)


def extract(archive: pathlib.Path, into: pathlib.Path) -> list[pathlib.Path]:
    into.mkdir(parents=True, exist_ok=True)
    with tarfile.open(archive) as tar:
        tar.extractall(into, filter="data")
    return [p for p in into.rglob("*") if p.is_file()]


def find(files: list[pathlib.Path], names: tuple[str, ...]) -> pathlib.Path | None:
    return next((p for p in sorted(files) if p.name in names), None)


def export(key: str, value: pathlib.Path) -> None:
    print(f"{key}={value}")
    if env_file := os.environ.get("GITHUB_ENV"):
        with open(env_file, "a", encoding="utf-8") as handle:
            handle.write(f"{key}={value}\n")


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: locate_library.py <configuration-id>")

    config_id = sys.argv[1]
    downloaded = REPO_ROOT / ".local" / "artifacts"
    unpacked = REPO_ROOT / ".local" / "ort" / config_id

    runtime = downloaded / "runtime" / f"{config_id}.tar.gz"
    if not runtime.is_file():
        available = sorted(p.name for p in downloaded.rglob("*.tar.gz"))
        raise SystemExit(f"{runtime} is missing. Downloaded: {available}")

    library = find(extract(runtime, unpacked / "runtime"), LIBRARY_NAMES)
    if library is None:
        raise SystemExit(f"{runtime} holds no library named one of {LIBRARY_NAMES}")
    export("ONNXRUNTIME_LIB", library)

    # Optional: only platforms with a WebGPU shared_lib build produce this.
    plugin_archive = downloaded / "ep-webgpu" / f"{config_id}.tar.gz"
    if plugin_archive.is_file():
        plugin = find(extract(plugin_archive, unpacked / "ep-webgpu"), PLUGIN_NAMES)
        if plugin is None:
            raise SystemExit(f"{plugin_archive} holds no WebGPU plugin")
        export("ONNXRUNTIME_EP_WEBGPU", plugin)
    elif "shared_lib" in ort_matrix.by_id(config_id).build_args():
        # The configuration asked for a loadable WebGPU EP, so its absence is a
        # packaging failure. Letting it through would silently skip the only
        # tests that exercise plugin loading.
        raise SystemExit(
            f"{config_id} is built with --use_webgpu shared_lib but "
            f"{plugin_archive} does not exist"
        )
    else:
        print(f"no WebGPU plugin for {config_id}; those tests will skip")


if __name__ == "__main__":
    main()
