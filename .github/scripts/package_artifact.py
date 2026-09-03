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

import binary_arch  # noqa: E402
import ort_matrix  # noqa: E402

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
DIST = REPO_ROOT / "dist"

# Canonical archive member -> the patterns that may match it on disk.
#
# Builds emit versioned files with an unversioned symlink beside them, and the
# symlink is not always present in what CMake leaves behind. Archives therefore
# carry the real bytes under the unversioned name the loader asks for, which is
# also the name the build hook looks up.
ARTIFACT_PATTERNS = {
    "android": {
        ort_matrix.RUNTIME: {
            "libonnxruntime.so": ["libonnxruntime.so", "libonnxruntime.so.*"],
        },
        ort_matrix.EP_WEBGPU: {
            "libonnxruntime_providers_webgpu.so": [
                "libonnxruntime_providers_webgpu.so",
                "libonnxruntime_providers_webgpu.so.*",
            ],
        },
    },
    "ios": {
        ort_matrix.RUNTIME: {
            "libonnxruntime.dylib": ["libonnxruntime.dylib", "libonnxruntime.*.dylib"],
        },
        ort_matrix.EP_WEBGPU: {
            "libonnxruntime_providers_webgpu.dylib": [
                "libonnxruntime_providers_webgpu.dylib",
                "libonnxruntime_providers_webgpu.*.dylib",
            ],
        },
    },
    "macos": {
        ort_matrix.RUNTIME: {
            "libonnxruntime.dylib": ["libonnxruntime.dylib", "libonnxruntime.*.dylib"],
        },
        ort_matrix.EP_WEBGPU: {
            "libonnxruntime_providers_webgpu.dylib": [
                "libonnxruntime_providers_webgpu.dylib",
                "libonnxruntime_providers_webgpu.*.dylib",
            ],
        },
    },
    "linux": {
        ort_matrix.RUNTIME: {
            "libonnxruntime.so": ["libonnxruntime.so", "libonnxruntime.so.*"],
        },
        ort_matrix.EP_WEBGPU: {
            "libonnxruntime_providers_webgpu.so": [
                "libonnxruntime_providers_webgpu.so",
                "libonnxruntime_providers_webgpu.so.*",
            ],
        },
    },
    # Windows does not version file names. The import library is needed by
    # downstream builds that link against us.
    "windows": {
        ort_matrix.RUNTIME: {
            "onnxruntime.dll": ["onnxruntime.dll"],
            "onnxruntime.lib": ["onnxruntime.lib"],
        },
        ort_matrix.EP_WEBGPU: {
            "onnxruntime_providers_webgpu.dll": ["onnxruntime_providers_webgpu.dll"],
        },
    },
    "web": {
        ort_matrix.RUNTIME: {
            # The full variant enables the training APIs, and ORT puts that in
            # the file name: ort-training-wasm-... rather than ort-wasm-...
            # (cmake/onnxruntime_webassembly.cmake builds the name from the
            # features that are on). So the glob cannot anchor on "ort-wasm".
            "*": ["ort-*wasm*.wasm", "ort-*wasm*.mjs"],
        },
    },
}


def sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> None:
    DIST.mkdir(parents=True, exist_ok=True)
    package(ort_matrix.by_id(os.environ["MATRIX_ID"]))


def package(config: ort_matrix.Config) -> None:
    build_config = os.environ.get("ORT_BUILD_CONFIG", "Release")
    build_dir = REPO_ROOT / "build" / config.id / build_config
    if not build_dir.is_dir():
        raise SystemExit(f"{build_dir} does not exist; the build produced nothing")

    # One configuration, one component. Nothing here is optional: a build that
    # produced no artifact for the thing it was run to produce is a failure,
    # not an absence, and letting it through publishes a release with a hole
    # that 404s at install time.
    patterns = ARTIFACT_PATTERNS[config.platform]
    members = patterns.get(config.component)
    if members is None:
        raise SystemExit(
            f"{config.id} builds {config.component}, but nothing collects that "
            f"on {config.platform}. Add a pattern or drop the configuration."
        )

    found = _find(build_dir, members)
    if not found:
        raise SystemExit(
            f"no artifact matching {members} under {build_dir}, so "
            f"{config.id} produced no {config.component}"
        )
    _archive(config, config.component, found)


def _find(
    build_dir: pathlib.Path,
    members: dict[str, list[str]],
) -> dict[str, pathlib.Path]:
    """Maps each canonical archive name to the real file that provides it."""
    found: dict[str, pathlib.Path] = {}
    for canonical, patterns in members.items():
        for pattern in patterns:
            for source in sorted(build_dir.rglob(pattern)):
                # Skip CMake's intermediate copies and the unversioned symlinks
                # pointing at the file we are already taking.
                if "CMakeFiles" in source.parts or source.is_symlink():
                    continue
                # A literal "*" means keep whatever names the build produced,
                # which is how the wasm outputs are shipped.
                name = source.name if canonical == "*" else canonical
                found.setdefault(name, source)
    return found


def _archive(
    config: ort_matrix.Config,
    component: str,
    found: dict[str, pathlib.Path],
) -> None:
    # One directory per release stream, so the release job can publish each
    # without picking artifacts apart.
    out = DIST / component
    out.mkdir(parents=True, exist_ok=True)

    # Flat archive: the hook looks members up by file name, not by path.
    archive = out / f"{config.id}.tar.gz"
    with tarfile.open(archive, "w:gz") as tar:
        for name, source in sorted(found.items()):
            # Before it goes in, because a cross-compilation that produced the
            # wrong architecture is invisible until something tries to load
            # it, and for the targets we have no hardware to load-test on that
            # would be in a user's application.
            binary_arch.verify(source, config.arch)
            tar.add(source, arcname=name)

    digest = sha256(archive)
    (out / f"{config.id}.tar.gz.sha256").write_text(
        f"{digest}  {archive.name}\n", encoding="utf-8"
    )

    size_mb = archive.stat().st_size / 1e6
    print(f"{component}/{config.id}: {', '.join(sorted(found))} -> {size_mb:.1f} MB")

    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as handle:
            handle.write(
                f"| `{component}/{config.id}.tar.gz` | {size_mb:.1f} MB "
                f"| `{digest[:16]}…` |\n"
            )


if __name__ == "__main__":
    main()
