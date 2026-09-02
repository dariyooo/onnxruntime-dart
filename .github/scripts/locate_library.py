#!/usr/bin/env python3
"""Unpacks our own build and points the test suite at it.

Sets ONNXRUNTIME_LIB, and ONNXRUNTIME_EP_<PROVIDER> for each plugin built. Fails
loudly when the runtime archive is missing, because the tests that need it skip
when it is absent and a silent skip would let the job pass while proving nothing.
"""

from __future__ import annotations

import os
import pathlib
import re
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
def plugin_names(provider: str) -> tuple[str, ...]:
    """What the shared library for [provider] is called, per platform.

    The stem comes from ep_matrix, which is what the mirror script already
    searches upstream archives by, so there is one answer rather than two that
    can drift. This was a fixed tuple naming the WebGPU library, from when that
    was the only provider we shipped, so CUDA and QNN archives were searched
    for a file that could not be in them.
    """
    stem = ep_matrix.by_name(provider).library_stem
    return (f"lib{stem}.so", f"lib{stem}.dylib", f"{stem}.dll")

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


def provider_archive(
    directory: pathlib.Path, provider: str, config_id: str
) -> pathlib.Path | None:
    """The archive holding [provider]'s plugin for [config_id], however named.

    A provider built through the runtime pipeline is named for the
    configuration, `linux-x64-webgpu.tar.gz`, because its configuration ids
    already end in the provider name. A mirrored one is named for itself,
    `qnn-linux-x64.tar.gz`, and CUDA puts its toolkit in the middle,
    `cuda-cuda12-linux-x64.tar.gz`. Matched rather than spelled out, so a new
    provider needs nothing here.
    """
    if not directory.is_dir():
        return None

    candidates = [
        path
        # Walked, not globbed: an artifact may unpack with its own folder
        # inside, and a plugin one level down is still the plugin.
        for path in sorted(directory.rglob("*.tar.gz"))
        if config_id in path.name and provider in path.name
    ]
    return candidates[0] if candidates else None


def find(files: list[pathlib.Path], names: tuple[str, ...]) -> pathlib.Path | None:
    return next((p for p in sorted(files) if p.name in names), None)


def point_hook_at(directory: pathlib.Path) -> None:
    """Points the build hook at the runtime this job downloaded.

    Setting ONNXRUNTIME_LIB is enough for the tests that open the library
    themselves, and not for anything that goes through the ordinary API: the
    generated bindings resolve their symbols from a native asset, which the
    build hook supplies. Without one every session-level test skips, which is
    how a job can report success having exercised almost nothing.

    The hook takes a directory from `user_defines`, which come from the
    pubspec, so the pubspec is what has to say it. Rewritten here rather than
    committed, because the path is whatever this runner unpacked to. Mutating a
    tracked file is fine in a checkout that exists for one job.
    """
    pubspec = REPO_ROOT / "pubspec.yaml"
    text = pubspec.read_text(encoding="utf-8")
    updated = re.sub(
        r"^(\s*local_build:).*$",
        lambda m: f"{m.group(1)} {directory}",
        text,
        count=1,
        flags=re.MULTILINE,
    )
    if updated == text:
        raise SystemExit(
            f"{pubspec} has no local_build line for the hook to be pointed at"
        )
    pubspec.write_text(updated, encoding="utf-8")
    print(f"hook local_build={directory}")


def export(key: str, value: pathlib.Path) -> None:
    print(f"{key}={value}")
    if env_file := os.environ.get("GITHUB_ENV"):
        with open(env_file, "a", encoding="utf-8") as handle:
            handle.write(f"{key}={value}\n")


def main() -> None:
    """Exports the paths the tests look for.

    Which providers must be present is the caller's to say, because a job
    stages only what it downloaded: requiring every provider published for the
    target would fail a job that deliberately fetched one of them.
    """
    if len(sys.argv) < 2:
        raise SystemExit(
            "usage: locate_library.py <configuration-id> [provider ...]"
        )

    config_id = sys.argv[1]
    # The providers the caller staged, and so the ones whose absence is a
    # failure rather than a reason for those tests to skip.
    required = set(sys.argv[2:])
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
    point_hook_at(library.parent)

    # Each provider is built by its own pipeline, into its own configuration
    # named after this one, so it arrives as a separate artifact.
    for provider, variable in PROVIDER_VARIABLES.items():
        archive = provider_archive(downloaded / f"ep-{provider}", provider, config_id)
        if archive is not None:
            plugin = find(
                extract(archive, unpacked / f"ep-{provider}"),
                plugin_names(provider),
            )
            if plugin is None:
                raise SystemExit(f"{archive} holds no {provider} plugin")
            export(variable, plugin)
        elif provider in required and config_id in ep_matrix.by_name(provider).targets:
            # The caller said it staged this one, so a missing archive is a
            # packaging or artifact failure. Letting it through would silently
            # skip the only tests that load a real provider.
            raise SystemExit(
                f"{provider} is published for {config_id} but no archive for "
                f"it was staged in {downloaded / f'ep-{provider}'}"
            )
        else:
            print(f"no {provider} plugin for {config_id}; those tests will skip")

    # The operator library, unpacked by the job before this runs. Optional in
    # the same way: without it the extensions tests skip rather than fail.
    extensions = REPO_ROOT / ".local" / "ort-extensions"
    if extensions.is_dir():
        # Walked rather than handed over: `find` takes the files, and this
        # is the directory the job unpacked them into.
        found = find(list(extensions.rglob("*")), EXTENSIONS_NAMES)
        if found is None:
            raise SystemExit(f"{extensions} holds no extensions library")
        export("ONNXRUNTIME_EXTENSIONS_LIB", found)
    else:
        print("no extensions library; those tests will skip")


if __name__ == "__main__":
    main()
