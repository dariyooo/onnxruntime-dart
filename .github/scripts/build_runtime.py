#!/usr/bin/env python3
"""Builds one ONNX Runtime configuration from the pinned submodule.

Thin on purpose. Resolves paths, enforces the complete-build invariant, and hands
off to ORT's own build.py. Anything more is a second build system to keep in sync.
"""

from __future__ import annotations

import os
import pathlib
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import ort_matrix  # noqa: E402

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
ORT_ROOT = REPO_ROOT / "third_party" / "onnxruntime"
BUILD_DIR = REPO_ROOT / "build"

# cmake/deps.txt vendors ~40 dependencies. A stable FetchContent directory lets
# actions/cache reuse them between runs.
DEPS_CACHE = (
    pathlib.Path("C:/deps") if sys.platform == "win32"
    else pathlib.Path.home() / ".onnxruntime_deps"
)


def main() -> None:
    for config_id in os.environ["MATRIX_IDS"].split():
        build(ort_matrix.by_id(config_id))


def build(config: ort_matrix.Config) -> None:
    print(f"\n=== building {config.id} ===", flush=True)
    build_py = ORT_ROOT / "tools" / "ci_build" / "build.py"
    if not build_py.is_file():
        raise SystemExit(
            f"{build_py} is missing. The submodule is not checked out; "
            "the workflow needs actions/checkout with submodules: true."
        )

    args = list(config.build_args())
    ort_matrix.assert_complete_build(args)

    DEPS_CACHE.mkdir(parents=True, exist_ok=True)

    command = [
        sys.executable,
        str(build_py),
        # Each configuration gets its own build directory so grouped
        # configurations do not overwrite one another's output.
        "--build_dir", str(BUILD_DIR / config.id),
        "--config", os.environ.get("ORT_BUILD_CONFIG", "Release"),
        "--cmake_extra_defines", f"FETCHCONTENT_BASE_DIR={DEPS_CACHE}",
        # CMake 4 refuses projects declaring cmake_minimum_required below 3.5.
        # Several vendored dependencies still do, psimd among them. ORT applies
        # the same override in its own build images.
        "--cmake_extra_defines", "CMAKE_POLICY_VERSION_MINIMUM=3.5",
        *args,
    ]

    if config.platform == "android":
        ndk = os.environ.get("ANDROID_NDK_HOME") or os.environ.get("ANDROID_NDK_ROOT")
        sdk = os.environ.get("ANDROID_SDK_ROOT") or os.environ.get("ANDROID_HOME")
        if not ndk:
            raise SystemExit("ANDROID_NDK_HOME is unset; the NDK setup step did not run")
        command += ["--android_ndk_path", ndk]
        if sdk:
            command += ["--android_sdk_path", sdk]

    print(f"$ {' '.join(command)}", flush=True)
    result = subprocess.run(command, cwd=ORT_ROOT, check=False)
    if result.returncode != 0:
        note = (
            "\nThis configuration is marked unproven in ort_matrix.py. Failures "
            "are expected until it converges. Stop and report rather than "
            "iterating blindly."
            if config.unproven else ""
        )
        raise SystemExit(f"build failed for {config.id} (exit {result.returncode}){note}")


if __name__ == "__main__":
    main()
