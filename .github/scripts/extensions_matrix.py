#!/usr/bin/env python3
"""The onnxruntime-extensions builds, and how each is configured.

Extensions is its own CMake project, not a flag on an ONNX Runtime build, so it
does not go through ort_matrix. What it shares is the target names: an operator
library is only useful beside a runtime for the same target, so the two lists
are checked against each other by test_matrix.py.

Not the web. Under Emscripten the upstream CMake refuses a shared library
(`_ORTX_SHARED_BUILD_SUPPORTED`), because there the operators have to be
compiled into the runtime rather than loaded beside it.
"""

from __future__ import annotations

import dataclasses
import os
import pathlib
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import ort_matrix  # noqa: E402

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
SUBMODULE = REPO_ROOT / "third_party" / "onnxruntime-extensions"

COMPONENT = "extensions"

# Every operator set the upstream defaults enable, which is what makes the
# library worth shipping: tokenizers, text, math, vision and audio. The only
# thing turned off is the test suite.
COMMON = (
    "-DCMAKE_BUILD_TYPE=Release",
    "-DOCOS_BUILD_SHARED_LIB=ON",
    "-DOCOS_ENABLE_CTEST=OFF",
    # Upstream and its dependencies declare cmake_minimum_required values that
    # CMake 4 rejects outright. Same flag the runtime build passes.
    "-DCMAKE_POLICY_VERSION_MINIMUM=3.5",
)


@dataclasses.dataclass(frozen=True)
class Build:
    """One extensions library."""

    id: str
    platform: str
    arch: str
    runner: str
    args: tuple[str, ...] = ()

    def cmake_args(self) -> tuple[str, ...]:
        """Configuration for this target, with environment references resolved.

        These reach CMake through subprocess rather than a shell, so anything
        of the form $NAME has to be expanded here or it arrives verbatim.
        """
        return COMMON + tuple(os.path.expandvars(a) for a in self.args)


def version() -> str:
    """What the library reports in its soname.

    From version.txt rather than the tag: upstream tags v0.14.0 on a commit
    whose version.txt already says 0.15.0, and the built library follows the
    file.
    """
    return (SUBMODULE / "version.txt").read_text(encoding="utf-8").strip()


def release_tag() -> str:
    return f"{COMPONENT}-v{version()}"


def _android(abi: str) -> Build:
    return Build(
        id=f"android-{abi}",
        platform="android",
        arch=abi,
        runner="ubuntu-24.04",
        args=(
            "-DCMAKE_TOOLCHAIN_FILE="
            "$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake",
            f"-DANDROID_ABI={abi}",
            "-DANDROID_PLATFORM=android-24",
        ),
    )


def _ios(name: str, sysroot: str, arch: str) -> Build:
    return Build(
        id=f"ios-{name}",
        platform="ios",
        arch=arch,
        runner="macos-15",
        args=(
            "-DCMAKE_TOOLCHAIN_FILE=cmake/ortext_ios.toolchain.cmake",
            f"-DCMAKE_OSX_SYSROOT={sysroot}",
            f"-DCMAKE_OSX_ARCHITECTURES={arch}",
            "-DCMAKE_OSX_DEPLOYMENT_TARGET=15.1",
            "-GXcode",
        ),
    )


BUILDS: tuple[Build, ...] = (
    _android("arm64-v8a"),
    _android("armeabi-v7a"),
    _android("x86_64"),
    _android("x86"),
    _ios("device-arm64", "iphoneos", "arm64"),
    _ios("sim-arm64", "iphonesimulator", "arm64"),
    _ios("sim-x86_64", "iphonesimulator", "x86_64"),
    Build(
        id="macos-arm64",
        platform="macos",
        arch="arm64",
        runner="macos-15",
        args=("-DCMAKE_OSX_ARCHITECTURES=arm64",),
    ),
    Build(
        id="macos-x86_64",
        platform="macos",
        arch="x86_64",
        runner="macos-15-intel",
        args=("-DCMAKE_OSX_ARCHITECTURES=x86_64",),
    ),
    Build(id="linux-x64", platform="linux", arch="x86_64", runner="ubuntu-24.04"),
    Build(
        id="linux-arm64", platform="linux", arch="arm64", runner="ubuntu-24.04-arm"
    ),
    Build(
        id="windows-x64", platform="windows", arch="x86_64", runner="windows-2022"
    ),
    Build(
        id="windows-arm64",
        platform="windows",
        arch="arm64",
        runner="windows-11-arm",
    ),
)


def by_id(build_id: str) -> Build:
    for build in BUILDS:
        if build.id == build_id:
            return build
    raise SystemExit(f"unknown extensions build {build_id!r}")


def targets() -> list[str]:
    return [b.id for b in BUILDS]


def runtime_targets() -> list[str]:
    """The native targets the runtime is built for, which this must match."""
    return [
        c.id
        for c in ort_matrix.all_configurations()
        if c.component == ort_matrix.RUNTIME
        and c.variant == ort_matrix.BASE
        and c.platform != "web"
    ]
