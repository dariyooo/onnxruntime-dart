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
#
# One directory per configuration, never one per job. FetchContent puts compiled
# archives here, not only downloaded sources, so sharing it between the four
# Android ABIs links x86_64 objects into the 32-bit x86 build.
DEPS_CACHE = (
    pathlib.Path("C:/deps") if sys.platform == "win32"
    else pathlib.Path.home() / ".onnxruntime_deps"
)


# build.py picks a Visual Studio generator from the OS alone, and it picks the
# one that was current when that code was written. GitHub moved the
# windows-11-arm image from VS 2022 to VS 2026 in October 2026, and every arm64
# build stopped at `project()` with "could not find any instance of Visual
# Studio" fifteen seconds in.
#
# So ask the machine instead of assuming. vswhere ships with every VS installer
# and reports what is actually there, which keeps this working through the next
# image bump in either direction.
_VS_GENERATORS = {
    "17": "Visual Studio 17 2022",
    "18": "Visual Studio 18 2026",
}


def _windows_generator() -> str:
    """The generator for the Visual Studio this machine actually has."""
    vswhere = (
        pathlib.Path(os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)"))
        / "Microsoft Visual Studio" / "Installer" / "vswhere.exe"
    )
    if not vswhere.is_file():
        raise SystemExit(
            f"{vswhere} is missing, so which Visual Studio is installed cannot "
            "be determined. It ships with every Visual Studio installer, so a "
            "runner without it has no Visual Studio either."
        )
    found = subprocess.run(
        [str(vswhere), "-latest", "-property", "installationVersion"],
        capture_output=True, text=True, check=True,
    ).stdout.strip()
    major = found.split(".")[0]
    generator = _VS_GENERATORS.get(major)
    if generator is None:
        raise SystemExit(
            f"Visual Studio {found} is installed, and build.py accepts only "
            f"{sorted(_VS_GENERATORS.values())}. Add the new generator here and "
            "check the pinned submodule's build_args.py accepts it."
        )
    print(f"  Visual Studio {found} -> {generator}", flush=True)
    return generator


def main() -> None:
    build(ort_matrix.by_id(os.environ["MATRIX_ID"]))


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

    (DEPS_CACHE / config.id).mkdir(parents=True, exist_ok=True)

    command = [
        sys.executable,
        str(build_py),
        # Each configuration gets its own build directory so grouped
        # configurations do not overwrite one another's output.
        "--build_dir", str(BUILD_DIR / config.id),
        "--config", os.environ.get("ORT_BUILD_CONFIG", "Release"),
        "--cmake_extra_defines", f"FETCHCONTENT_BASE_DIR={DEPS_CACHE / config.id}",
        # CMake 4 refuses projects declaring cmake_minimum_required below 3.5.
        # Several vendored dependencies still do, psimd among them. ORT applies
        # the same override in its own build images.
        "--cmake_extra_defines", "CMAKE_POLICY_VERSION_MINIMUM=3.5",
        *args,
    ]

    if config.platform == "windows":
        command += ["--cmake_generator", _windows_generator()]

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
