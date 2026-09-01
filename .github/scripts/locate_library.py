#!/usr/bin/env python3
"""Unpacks our own build and points the test suite at it.

Sets ONNXRUNTIME_LIB, and ONNXRUNTIME_EP_<PROVIDER> for each plugin built. Fails
loudly when the runtime archive is missing, because the tests that need it skip
when it is absent and a silent skip would let the job pass while proving nothing.
"""

from __future__ import annotations

import os
import pathlib
import sys
import tarfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import ep_matrix  # noqa: E402
import ort_matrix  # noqa: E402

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
PROVIDER_VARIABLES = {
    "webgpu": "ONNXRUNTIME_EP_WEBGPU",
    "cuda": "ONNXRUNTIME_EP_CUDA",
    "qnn": "ONNXRUNTIME_EP_QNN",
}

LIBRARY_NAMES = ("libonnxruntime.so", "libonnxruntime.dylib", "onnxruntime.dll")
PLUGIN_NAMES = (
    "libonnxruntime_providers_webgpu.so",
    "libonnxruntime_providers_webgpu.dylib",
    "onnxruntime_providers_webgpu.dll",
)

EXTENSIONS_NAMES = (
    "libortextensions.so",
    "libortextensions.dylib",
    "ortextensions.dll",
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

    # Each provider is built by its own pipeline, into its own configuration
    # named after this one, so it arrives as a separate artifact.
    for provider, variable in PROVIDER_VARIABLES.items():
        archive = downloaded / f"ep-{provider}" / f"{config_id}-{provider}.tar.gz"
        if archive.is_file():
            plugin = find(extract(archive, unpacked / f"ep-{provider}"), PLUGIN_NAMES)
            if plugin is None:
                raise SystemExit(f"{archive} holds no {provider} plugin")
            export(variable, plugin)
        elif config_id in ep_matrix.by_name(provider).targets:
            # Published for this target, so a missing plugin is a packaging or
            # artifact failure. Letting it through would silently skip the only
            # tests that load a real provider.
            raise SystemExit(
                f"{provider} is published for {config_id} but {archive} does "
                f"not exist"
            )
        else:
            print(f"no {provider} plugin for {config_id}; those tests will skip")

    # The operator library, unpacked by the job before this runs. Optional in
    # the same way: without it the extensions tests skip rather than fail.
    extensions = REPO_ROOT / ".local" / "ort-extensions"
    if extensions.is_dir():
        found = find(extensions, EXTENSIONS_NAMES)
        if found is None:
            raise SystemExit(f"{extensions} holds no extensions library")
        export("ONNXRUNTIME_EXTENSIONS_LIB", found)
    else:
        print("no extensions library; those tests will skip")


if __name__ == "__main__":
    main()
